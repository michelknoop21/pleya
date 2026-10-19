import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../models/companion_remote/remote_command.dart';
import '../../providers/companion_remote_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../utils/app_logger.dart';
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
Future<void> receivePlaybackHandoff(
  BuildContext context,
  PlaybackHandoffRequest request, {
  String? switchedToProfile,
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

  try {
    await _receive(context, request, release, switchedToProfile);
  } finally {
    release();
  }
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

/// Whether the phone gave up on [id]. The player asks this when it starts, so a
/// cancel that arrived while the player was still opening is not lost.
bool isPlaybackHandoffCancelled(String id) => _cancelled.contains(id);

Future<void> _receive(
  BuildContext context,
  PlaybackHandoffRequest request,
  VoidCallback release,
  String? switchedToProfile,
) async {
  final provider = context.read<CompanionRemoteProvider>();
  void fail(String reason) {
    appLogger.w('Playback handoff ${request.id} failed: $reason');
    provider.sendCommand(RemoteCommandType.syncState, data: {handoffFailedKey: request.id});
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
  if (!context.mounted) return;
  if (item == null || (item.kind != MediaKind.movie && item.kind != MediaKind.episode)) {
    return fail('item ${request.itemId} not playable');
  }

  // The phone may have given up while this was fetching: do not close what plays for nothing.
  if (_cancelled.remove(request.id)) return;

  // A player that is already open is closed first; two players must never stack.
  final closePlayer = CompanionRemoteReceiver.instance.onStop;
  if (closePlayer != null) {
    closePlayer();
    // The player unregisters its Stop when it is gone; wait for that, not a guess.
    for (var i = 0; i < 20 && CompanionRemoteReceiver.instance.onStop != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!context.mounted) return;
    if (CompanionRemoteReceiver.instance.onStop != null) return fail('previous player did not close');
  }
  if (_cancelled.remove(request.id)) return;

  noticeController.show(
    Notice(
      level: NoticeLevel.info,
      title: t.playbackHandoff.received(from: request.from),
      body: switchedToProfile == null
          ? item.displayTitle
          : '${item.displayTitle} · ${t.playbackHandoff.switchedTo(name: switchedToProfile)}',
      groupKey: 'playback-handoff:${request.id}',
    ),
  );

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

/// A handoff waiting for the profile switch it asked for. Switching rebuilds the
/// whole profile session, including the screen that received the request, so
/// the new session picks it up once the switch has settled (see
/// [takePendingPlaybackHandoff]).
class _PendingHandoff {
  _PendingHandoff(this.request, this.profileId, this.profileName);

  final PlaybackHandoffRequest request;
  final String profileId;
  final String profileName;

  /// Set when the profile is active and its servers are bound; before that the
  /// previous profile's clients are still the ones that would play.
  DateTime? settledAt;
}

_PendingHandoff? _pending;

/// Tells the screen of the new session that a pending handoff became ready.
final ValueNotifier<int> pendingPlaybackHandoffChanged = ValueNotifier<int>(0);

/// The handoff that waits for its profile switch to settle.
abstract final class PendingHandoff {
  /// Taken once, by the session of the profile the handoff switched to, and only
  /// when the switch has settled. A request that waited more than two minutes
  /// after that is dropped: the phone has long given up.
  static ({PlaybackHandoffRequest request, String profileName})? take({required String activeProfileId}) {
    final pending = _pending;
    final settledAt = pending?.settledAt;
    if (pending == null || settledAt == null || pending.profileId != activeProfileId) return null;
    _pending = null;
    if (DateTime.now().difference(settledAt) > const Duration(minutes: 2)) return null;
    return (request: pending.request, profileName: pending.profileName);
  }

  @visibleForTesting
  static void debugSet(PlaybackHandoffRequest request, String profileId, {DateTime? settledAt}) {
    _pending = _PendingHandoff(request, profileId, 'Test')..settledAt = settledAt;
  }
}

/// A phone of another user of the Home hands over: switch this device to that
/// user's profile first, so playback and progress belong to the right account.
/// Refused (the phone keeps playing) when that user has no profile here, when a
/// switch is already under way, or when the switch fails; a failed switch goes
/// back to the profile that was active.
Future<void> receivePlaybackHandoffFromOtherUser(
  BuildContext context,
  PlaybackHandoffRequest request,
  String clientUserUuid,
) async {
  final provider = context.read<CompanionRemoteProvider>();
  final active = context.read<ActiveProfileProvider>();
  final binder = context.read<ActiveProfileBinder>();
  void fail(String reason) {
    appLogger.w('Playback handoff ${request.id} refused: $reason');
    provider.sendCommand(RemoteCommandType.syncState, data: {handoffFailedKey: request.id});
  }

  if (_pending != null) return fail('another switch is under way');
  final target = profileForHandoffUser(active.profiles, clientUserUuid);
  if (target == null) return fail('no switchable profile for the sender');

  final previous = active.active;
  final pending = _pending = _PendingHandoff(request, target.id, target.displayName);
  binder.markUserInitiatedActivation(target.id);
  // A PIN prompt on this device is part of the binding, so settling can take a while.
  final switched =
      await active.activate(target) && await active.awaitBindingSettle(timeout: const Duration(seconds: 80));
  if (switched && active.activeId == target.id) {
    pending.settledAt = DateTime.now();
    pendingPlaybackHandoffChanged.value++;
    return;
  }
  if (identical(_pending, pending)) _pending = null;
  fail('switching to ${target.displayName} failed');
  if (previous != null && active.activeId != previous.id) {
    binder.markUserInitiatedActivation(previous.id);
    await active.activate(previous);
  }
}
