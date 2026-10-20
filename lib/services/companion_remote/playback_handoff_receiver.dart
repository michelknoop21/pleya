import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../models/companion_remote/remote_command.dart';
import '../../providers/companion_remote_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../utils/app_logger.dart';
import '../../utils/formatters.dart';
import '../../utils/video_player_navigation.dart';
import '../../widgets/notice/notice.dart';
import '../../widgets/notice/notice_controller.dart';
import 'companion_remote_receiver.dart';
import 'playback_handoff.dart';

/// Apple TV side of a Playback Handoff (A-23): open the item the phone named,
/// at the position it named, and report back once it plays.
///
/// A handoff is a deliberate press on the phone, so it replaces whatever this
/// device is doing without asking. Any failure is reported to the phone, which
/// then keeps playing.
///
/// After a profile switch (A-23b) the phone gives up at a fixed time, so the
/// caller passes [mayStart] and [startWithin]: the time left until the last
/// start time. The player is never opened after it, and a fetch that hangs
/// past it neither keeps the receiver busy nor starts anything when it ends.
/// Both null (the plain path) means no deadline.
Future<void> receivePlaybackHandoff(
  BuildContext context,
  PlaybackHandoffRequest request, {
  bool Function()? mayStart,
  Duration? startWithin,
}) async {
  // One handoff at a time while it fetches and clears the old player: a second
  // arriving now would close and push in parallel.
  if (_receiving) return;
  _receiving = true;
  var released = false;
  void release() {
    if (released) return;
    released = true;
    _receiving = false;
  }

  final attempt = _HandoffAttempt(mayStart);
  Timer? timer;
  final expired = Completer<void>();
  if (startWithin != null) {
    timer = Timer(startWithin < Duration.zero ? Duration.zero : startWithin, () {
      if (attempt.opened) return;
      attempt.expired = true;
      appLogger.w('Playback handoff ${request.id} failed: past its start window');
      reportPlaybackHandoff(context.read<CompanionRemoteProvider>(), request.id, PlaybackHandoffOutcome.failed);
      release();
      expired.complete();
    });
  }
  try {
    await Future.any([_receive(context, request, release, attempt), expired.future]);
  } finally {
    timer?.cancel();
    release();
  }
}

/// One start under a deadline: [expired] is set by the timer, and everything
/// that comes after it (a late fetch, a late player) stands down.
class _HandoffAttempt {
  _HandoffAttempt(this._mayStart);

  final bool Function()? _mayStart;
  bool expired = false;

  /// The player is being opened; the deadline no longer applies.
  bool opened = false;

  bool get late => expired || (_mayStart != null && !_mayStart());
}

bool _receiving = false;
final Set<String> _cancelled = {};
String? _activeHandoffId;

/// The phone gave up on [id]. Skips a start that has not happened yet, and
/// closes the player if it already did.
void cancelPlaybackHandoff(String id) {
  _cancelled.add(id);
  // Bounded: ids arrive from the network and are only removed when they match a start.
  while (_cancelled.length > 16) {
    _cancelled.remove(_cancelled.first);
  }
  if (_activeHandoffId == id) CompanionRemoteReceiver.instance.onStop?.call();
}

/// Tells the phone how handoff [id] ended, and keeps the answer for a phone that
/// is still reconnecting after a profile switch and asks later (A-23b).
void reportPlaybackHandoff(CompanionRemoteProvider provider, String id, PlaybackHandoffOutcome outcome) {
  playbackHandoffLedger.record(id, outcome);
  provider.sendCommand(RemoteCommandType.syncState, data: handoffOutcomeData(id, outcome));
}

/// Whether the phone gave up on [id]. The player asks this when it starts, so a
/// cancel that arrived while the player was still opening is not lost.
bool isPlaybackHandoffCancelled(String id) => _cancelled.contains(id);

Future<void> _receive(
  BuildContext context,
  PlaybackHandoffRequest request,
  VoidCallback release,
  _HandoffAttempt attempt,
) async {
  final provider = context.read<CompanionRemoteProvider>();
  void fail(String reason) {
    // The timer already told the phone.
    if (attempt.expired) return;
    appLogger.w('Playback handoff ${request.id} failed: $reason');
    reportPlaybackHandoff(provider, request.id, PlaybackHandoffOutcome.failed);
  }

  final serverId = ServerId.tryParse(request.serverId);
  final client = serverId == null ? null : context.read<MultiServerProvider>().getClientForServer(serverId);
  if (client == null) return fail('server ${request.serverId} not available');

  MediaItem? item;
  try {
    item = await client.fetchItem(request.itemId);
  } catch (e) {
    appLogger.d('Playback handoff item fetch failed', error: e);
  }
  if (!context.mounted || attempt.expired) return;
  if (item == null || (item.kind != MediaKind.movie && item.kind != MediaKind.episode)) {
    return fail('item ${request.itemId} not playable');
  }

  // The phone may have given up while this was fetching: do not close what plays for nothing.
  if (_cancelled.remove(request.id)) return;
  if (attempt.late) return fail('past its start window');

  // A player that is already open is closed first; two players must never stack.
  final closePlayer = CompanionRemoteReceiver.instance.onStop;
  if (closePlayer != null) {
    closePlayer();
    // The player unregisters its Stop when it is gone; wait for that, not a guess.
    for (var i = 0; i < 20 && CompanionRemoteReceiver.instance.onStop != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!context.mounted || attempt.expired) return;
    if (CompanionRemoteReceiver.instance.onStop != null) return fail('previous player did not close');
  }
  if (_cancelled.remove(request.id)) return;
  if (attempt.late) return fail('past its start window');

  noticeController.show(
    Notice(
      level: NoticeLevel.info,
      title: t.playbackHandoff.received(from: request.from),
      body: t.playbackHandoff.receivedBody(
        title: item.displayTitle,
        time: formatDurationTimestamp(Duration(milliseconds: request.positionMs)),
      ),
      groupKey: 'playback-handoff:${request.id}',
    ),
  );

  attempt.opened = true;
  _activeHandoffId = request.id;
  // The guard covers fetching and clearing the old player; once the player is
  // pushed, a new handoff may replace it.
  release();
  await navigateToVideoPlayer(
    context,
    metadata: itemAtHandoffPosition(item, request),
    // The sender's position is the intent; a refetch or a cached offset must not compete with it.
    resolveWatchState: false,
    startPosition: Duration(milliseconds: request.positionMs),
    handoffId: request.id,
    onPlaybackInitFailed: () => fail('player did not start'),
  );
  if (_activeHandoffId == request.id) _activeHandoffId = null;
}
