import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../media/unified/unified_media_source.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import '../utils/provider_extensions.dart';

/// Writes one title's rating to every membership except the one the sheet is
/// bound to and has already written itself.
///
/// Hoofdstuk 13.8 and [DEC-075](../../docs/DECISIONS.md#dec-075): a rating
/// describes the title, not the copy. The same film on two servers had two
/// different numbers, and which one a user saw depended on which card they
/// happened to open, which is the same incoherence DEC-071 removed from watch
/// state.
///
/// **Why this is a class and not a static.** Three pieces of state have to
/// survive between callbacks: the latest value (the sheet reports one per
/// debounce tick, and they have to be coalesced), the accumulated failures,
/// and the resolved clients. The last one is the load-bearing part: the sheet
/// flushes a pending rating from `dispose()`
/// (`rating_bottom_sheet.dart:_flushPendingAutoSavesOnDispose`), so the final
/// write of an interaction happens *after* the `BuildContext` that opened the
/// sheet is gone. A seam that resolved clients at write time would drop
/// exactly that write, which is the one carrying the value the user settled on.
///
/// **Why not on `WatchActions`.** That class states its remit in four parts:
/// route offline marks to the queue, online marks to the client, emit the
/// single `WatchStateNotifier` event, fire trackers. Rating has none of them.
/// It has no queue (a rating has no offline action type and the queue has no
/// column for a value), no notifier analogue, and the trackers are the rating
/// sheet's own separate axis. Adding a rating entry point there would make
/// that class's own doc comment false.
class RatingMirror {
  RatingMirror._(this._targets, {required int unreachableCount}) : _unreachableCount = unreachableCount;

  /// Testable core: no `BuildContext`, no providers, no widget tree.
  @visibleForTesting
  factory RatingMirror.withTargets(List<RatingMirrorTarget> targets, {int unreachableCount = 0}) =>
      RatingMirror._(List.unmodifiable(targets), unreachableCount: unreachableCount);

  /// Siblings named as `serverId:itemId` global keys — the shape
  /// [UnifiedMediaSource.sourceKey] and
  /// `UnifiedMediaRouteContext.availableSourceKeys` already carry.
  ///
  /// A key whose server has no client is counted as unreachable and never
  /// written to. That is also how a stale `availableSourceKeys` (captured when
  /// the route opened, session-scoped by design) resolves itself: a server
  /// that has since gone away simply fails to produce a client.
  ///
  /// [additionalUnreachable] is for a caller that already knows some
  /// memberships are unreachable and has deliberately left them out of
  /// [sourceKeys] — the TV menu, which reads live server health rather than a
  /// client lookup. They belong in the denominator all the same.
  static RatingMirror fromSourceKeys(
    BuildContext context, {
    required Iterable<String> sourceKeys,
    required String originSourceKey,
    int additionalUnreachable = 0,
  }) {
    final targets = <RatingMirrorTarget>[];
    var unreachable = additionalUnreachable;

    // Deduped before anything else: two memberships can resolve to the same
    // `serverId:itemId` (a server reachable through two connections, an A18
    // re-add), and writing twice would both PUT twice and inflate the
    // denominator the user is shown.
    for (final key in sourceKeys.toSet()) {
      if (key == originSourceKey) continue;
      final parsed = parseGlobalKey(key);
      if (parsed == null) continue;

      // The strict lookup, never `getMediaClientWithFallback`: that one falls
      // back to the first online server, and a Plex rating key is a per-server
      // integer. A fallback here would write this title's rating onto whatever
      // unrelated title happens to hold that key elsewhere — silently, and
      // permanently, because a write leaves no trace to notice.
      final client = context.tryGetMediaClientForServer(parsed.serverId);
      if (client == null) {
        unreachable++;
        continue;
      }
      // A backend that cannot take a rating is not a membership that quietly
      // stops existing: it is one this rating set out to reach and did not.
      // Dropping it left `done == intendedTargetCount`, which both callers
      // read as "everything landed" and therefore say nothing about — so
      // DEC-075's "reaches everything it can and reports the rest" reported
      // nothing. It is unreachable in the sense that matters here: no retry
      // exists for it either.
      if (!client.capabilities.userRating) {
        unreachable++;
        continue;
      }

      targets.add(RatingMirrorTarget(sourceKey: key, client: client, item: _writeItem(client, parsed)));
    }

    return RatingMirror._(List.unmodifiable(targets), unreachableCount: unreachable);
  }

  /// Same, for a caller that already holds the live sources (the TV menu).
  static RatingMirror fromSources(
    BuildContext context, {
    required List<UnifiedMediaSource> sources,
    required String originSourceKey,
    int additionalUnreachable = 0,
  }) => fromSourceKeys(
    context,
    sourceKeys: sources.map((source) => source.sourceKey),
    originSourceKey: originSourceKey,
    additionalUnreachable: additionalUnreachable,
  );

  /// The write item both backends need, built exactly as the offline sync
  /// service builds its replay items: `rate` reads `item.id` and nothing else
  /// on Plex, Jellyfin and Pleya Server alike.
  static MediaItem _writeItem(MediaServerClient client, ({ServerId serverId, String ratingKey}) parsed) => MediaItem(
    id: parsed.ratingKey,
    backend: client.backend,
    kind: MediaKind.unknown,
    serverId: parsed.serverId.value,
  );

  final List<RatingMirrorTarget> _targets;
  final int _unreachableCount;
  final Set<String> _failed = {};
  final Set<String> _succeeded = {};

  double? _latest;
  double? _written;
  Future<void>? _inFlight;

  /// How many memberships this rating set out to reach: the origin the sheet
  /// wrote itself, the siblings that can be written to, and the ones that are
  /// currently unreachable.
  ///
  /// The unreachable ones are counted rather than quietly dropped for the same
  /// reason hoofdstuk 13.4 point 5 counts them: "klaar op alle 2" while a third
  /// membership was never touched is the sentence that rule exists to forbid.
  /// Rating holds nothing back for later, so being counted here is the *only*
  /// thing that happens to them.
  int get intendedTargetCount => 1 + _targets.length + _unreachableCount;

  /// The origin, plus every sibling that took the write.
  ///
  /// The origin counts as done because the caller only ever hands values to
  /// [write] from `RatingBottomSheet.onServerRatingWritten`, which fires inside
  /// the awaited body after `client.rate` returned. A throw takes the sheet's
  /// catch arm and the callback never fires, so a mirror that ran at all is a
  /// mirror whose origin landed.
  int get doneCount => 1 + _succeeded.length;

  /// Which siblings refused the write. Never retried, never rolled back.
  Set<String> get failedSourceKeys => Set.unmodifiable(_failed);

  /// Whether there is any sibling to write to at all. A mirror with nothing to
  /// do still counts an unreachable membership, so this is not the same as
  /// `intendedTargetCount == 1`.
  bool get hasTargets => _targets.isNotEmpty;

  /// The in-flight chain, so the caller can report once after the sheet closes.
  Future<void> get settled => _inFlight ?? Future<void>.value();

  /// Records [rating] as the value every sibling should end on, and writes it.
  ///
  /// Latest-wins, and safe to call on every change the sheet reports.
  /// Intermediate values are dropped rather than queued, which is **not** an
  /// optimisation: two concurrent PUTs of 6 and then 8 to the same server can
  /// land in either order and leave it on 6. Serialising and coalescing is what
  /// makes "the last value the user chose" the value that survives.
  ///
  /// [rating] is the raw value handed to `MediaServerClient.rate`, including
  /// the `-1` clear sentinel. It is deliberately not the value
  /// `onServerRatingChanged` reports: that one flattens `-1` to `0` for
  /// display, and `0` is a real rating on Plex, so mirroring it would turn
  /// every "clear my rating" into a zero on every other server.
  void write(double rating) {
    _latest = rating;
    if (_targets.isEmpty) return;
    _inFlight ??= _drain();
  }

  Future<void> _drain() async {
    while (_latest != _written) {
      final value = _latest!;
      for (final target in _targets) {
        try {
          await target.client.rate(target.item, value);
          _succeeded.add(target.sourceKey);
          _failed.remove(target.sourceKey);
        } catch (e, st) {
          // Collected, not thrown: one refusing server must not stop the
          // others, and the caller reports the subset afterwards.
          _succeeded.remove(target.sourceKey);
          _failed.add(target.sourceKey);
          appLogger.w('Mirroring rating to ${target.sourceKey} failed', error: e, stackTrace: st);
        }
      }
      _written = value;
    }
    _inFlight = null;
  }
}

/// One sibling membership plus everything needed to write to it, resolved
/// while a `BuildContext` still existed.
@immutable
class RatingMirrorTarget {
  const RatingMirrorTarget({required this.sourceKey, required this.client, required this.item});

  final String sourceKey;
  final MediaServerClient client;
  final MediaItem item;
}
