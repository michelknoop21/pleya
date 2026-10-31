/// Carries a settled play to the other sources of its title (besluit 3 of
/// DEC-XXX "Eén titel over servers heen", hoofdstuk 4.6 and 13.2 of
/// docs/tvos-unified-experience.md).
library;

import 'dart:async';
import 'dart:math' as math;

import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/unified/unified_watch_state.dart';
import '../../utils/app_logger.dart';
import '../../utils/watch_state_notifier.dart';
import '../offline_watch_sync_service.dart';
import 'unified_title_playback.dart';

/// Writes what [playing] reported to every copy on another server.
///
/// Everything lands in the existing watch queue, also for a server that is up:
/// that is what makes a late or refusing second server harmless. The source
/// that plays is written by the tracker, before this runs, and nothing here
/// waits on it or reaches it. Copies whose runtime differs too much keep their
/// own state (G7): a position on one cut means nothing on another.
class UnifiedProgressMirror {
  UnifiedProgressMirror({this.known, this.find, required this.playing, required this.queue})
    : _notifier = WatchStateNotifier();

  /// The sources the play came with. Written first, so a lookup nobody waits
  /// for cannot hold them up.
  final UnifiedTitlePlayback? known;

  /// Finds what [known] does not hold: a card can show one source of three.
  /// Runs when the play settles and answers once; null means nothing more.
  final Future<UnifiedTitlePlayback?> Function()? find;

  final MediaItem playing;
  final OfflineWatchSyncService queue;
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
    // Who watched, before anything waits on a server.
    final profileId = queue.activeProfileId;
    final reached = {playing.globalKey};
    final title = known;
    if (title != null) await _writeTo(title, reached, profileId, position, duration, watched: watched);
    final lookup = find;
    final found = lookup == null ? null : await (_found ??= lookup());
    if (found != null) await _writeTo(found, reached, profileId, position, duration, watched: watched);
  }

  Future<void> _writeTo(
    UnifiedTitlePlayback title,
    Set<String> reached,
    String? profileId,
    Duration position,
    Duration duration, {
    required bool watched,
  }) async {
    final copies = await title.copiesOf(playing);
    final played = playing.copyWith(durationMs: duration.inMilliseconds);
    var written = 0;
    for (final copy in copies) {
      final serverId = copy.serverId;
      if (serverId == null || !reached.add(copy.globalKey) || !runtimesAreComparable(played, copy)) continue;
      final ownDuration = copy.durationMs ?? duration.inMilliseconds;
      final offset = math.min(position.inMilliseconds, ownDuration);
      final held = await queue.queueMirroredProgress(
        serverId: ServerId(serverId),
        itemId: copy.id,
        viewOffset: offset,
        duration: ownDuration,
        watched: watched,
        profileId: profileId,
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
