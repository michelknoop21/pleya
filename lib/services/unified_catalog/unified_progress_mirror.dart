/// Carries a settled play to the other sources of its title (besluit 3 of
/// DEC-XXX "Eén titel over servers heen", hoofdstuk 4.6 and 13.2 of
/// docs/tvos-unified-experience.md).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/unified/unified_watch_state.dart';
import '../../utils/app_logger.dart';
import '../../utils/watch_state_notifier.dart';
import '../offline_watch_sync_service.dart';
import '../playback_progress_tracker.dart';
import 'unified_title_discovery.dart';
import 'unified_title_playback.dart';
import 'watch_mark_order.dart';

/// Writes what [playing] reported to every copy on another server.
///
/// Everything lands in the existing watch queue, also for a server that is up:
/// that is what makes a late or refusing second server harmless. The source
/// that plays is written by the tracker, before this runs, and nothing here
/// waits on it or reaches it. Copies whose runtime differs too much keep their
/// own state (G7): a position on one cut means nothing on another.
class UnifiedProgressMirror {
  UnifiedProgressMirror({this.known, this.find, required this.playing, required this.queue})
    : _profileId = queue.activeProfileId,
      _notifier = WatchStateNotifier();

  /// The sources the play came with. Written first, so a lookup nobody waits
  /// for cannot hold them up.
  final UnifiedTitlePlayback? known;

  /// Finds what [known] does not hold: a card can show one source of three.
  /// Runs when the play settles and answers once; null means nothing more.
  final Future<UnifiedTitlePlayback?> Function()? find;

  final MediaItem playing;
  final OfflineWatchSyncService queue;

  /// Who watched, read when the play started. The stop of a play can arrive
  /// after a profile switch tore the player down: by then the active profile
  /// is someone else, whose account this viewing has nothing to do with.
  final String? _profileId;

  final WatchStateNotifier _notifier;
  Future<UnifiedTitlePlayback?>? _found;

  /// A [PlaybackSettledCallback]. Never throws and never blocks.
  void report(Duration position, Duration duration, {required bool watched}) {
    unawaited(
      write(position, duration, watched: watched).catchError((Object e, StackTrace st) {
        appLogger.w('Could not carry ${playing.globalKey} to its other sources', error: e, stackTrace: st);
      }),
    );
  }

  Future<void> write(Duration position, Duration duration, {required bool watched}) async {
    final stamp = WatchMarkOrder.now;
    final reached = {playing.globalKey};
    final title = known;
    if (title != null) await _writeTo(title, reached, stamp, position, duration, watched: watched);
    final lookup = find;
    final found = lookup == null ? null : await (_found ??= lookup());
    if (found != null) await _writeTo(found, reached, stamp, position, duration, watched: watched);
  }

  Future<void> _writeTo(
    UnifiedTitlePlayback title,
    Set<String> reached,
    int stamp,
    Duration position,
    Duration duration, {
    required bool watched,
  }) async {
    if (queue.activeProfileId != _profileId) return;
    final copies = await title.copiesOf(playing);
    final played = playing.copyWith(durationMs: duration.inMilliseconds);
    var written = 0;
    for (final copy in copies) {
      final serverId = copy.serverId;
      if (serverId == null || !reached.add(copy.globalKey) || !runtimesAreComparable(played, copy)) continue;
      // A mark made since says what the viewer wants now.
      if (WatchMarkOrder.markedAfter(playing.globalKey, stamp) || WatchMarkOrder.markedAfter(copy.globalKey, stamp)) {
        continue;
      }
      final ownMs = copy.durationMs ?? 0;
      final ownDuration = ownMs > 0 ? ownMs : duration.inMilliseconds;
      final offset = math.min(position.inMilliseconds, ownDuration);
      // A play only moves a copy forward. Eight seconds on one server must not
      // cost an hour on another; only finishing it may.
      if (!watched && (copy.viewOffsetMs ?? 0) >= offset) continue;
      final held = await queue.queueMirroredProgress(
        serverId: ServerId(serverId),
        itemId: copy.id,
        viewOffset: offset,
        duration: ownDuration,
        watched: watched,
        profileId: _profileId,
      );
      if (!held) return;
      // A progress event and never a watched one: the page and the rails need
      // to see this copy move, but Trakt counts watched events per viewing.
      _notifier.notifyProgress(
        item: copy,
        viewOffset: offset,
        duration: ownDuration,
        watchedThreshold: watched ? 0 : queue.getWatchedThreshold(ServerId(serverId)),
      );
      written++;
    }
    if (written > 0) await queue.syncPendingItems(queueIfBusy: true);
  }
}

/// What a tracker reports its settled play to. A card can show one source of
/// three, so what the play came with is not all there is: the rest is looked
/// up when it settles. Nothing waits for that, and no answer leaves it on the
/// sources already known. Null when there is nothing to reach.
PlaybackSettledCallback? unifiedSettledCallback({
  required MediaItem metadata,
  required OfflineWatchSyncService? queue,
  required UnifiedTitlePlayback? title,
  required UnifiedTitleDiscovery? discovery,
}) {
  if (queue == null) return null;
  final known = title != null && title.holds(metadata) ? title : null;
  if (known != null) unawaited(known.prime());
  if (known == null && discovery == null) return null;
  return UnifiedProgressMirror(
    known: known,
    find: discovery == null ? null : () => discovery.titleOf(metadata),
    playing: metadata,
    queue: queue,
  ).report;
}

/// A play that ran offline reaches its copies once its own server took it: no
/// player is left by then to tell them. [context] sits inside the profile
/// session, where the hidden libraries of this profile are. Answers how to undo
/// it when that session ends.
VoidCallback bindOwnPlayMirror(BuildContext context, OfflineWatchSyncService queue) {
  void mirror(MediaItem item, Duration position, Duration duration, {required bool watched}) {
    if (!context.mounted) return;
    final discovery = UnifiedTitleDiscovery.of(context);
    if (discovery == null) return;
    UnifiedProgressMirror(
      find: () => discovery.titleOf(item),
      playing: item,
      queue: queue,
    ).report(position, duration, watched: watched);
  }

  queue.onOwnPlayReplayed = mirror;
  return () {
    if (queue.onOwnPlayReplayed == mirror) queue.onOwnPlayReplayed = null;
  };
}
