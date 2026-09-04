/// Covers [UnifiedMediaGroup.withUpdatedSourceItem] — the incremental refresh
/// I19's player-return wiring is built on: swap one membership's state in
/// place, without touching identity or the representative source's ranking.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';

MediaItem _item(String serverId, {int? viewOffsetMs, int? durationMs, int? lastViewedAt}) => MediaItem(
  id: 'sintel',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  serverId: serverId,
  serverName: serverId,
  viewOffsetMs: viewOffsetMs,
  durationMs: durationMs,
  lastViewedAt: lastViewedAt,
);

UnifiedMediaGroup _group(List<MediaItem> items, {String? representativeServerId}) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  final representative = representativeServerId == null ? sources.first.sourceKey : '$representativeServerId:sintel';
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
    sources: sources,
    representativeSourceKey: representative,
    watchState: UnifiedWatchState(representativeSourceKey: representative),
  );
}

void main() {
  group('withUpdatedSourceItem', () {
    test('re-reads the named source and recomputes watch state from it', () {
      final group = _group([_item('a'), _item('b')]);

      final updated = group.withUpdatedSourceItem(
        _item('a', viewOffsetMs: 60000, durationMs: 6000000, lastViewedAt: 1756000000),
      );

      final source = updated.sources.singleWhere((s) => s.serverId.value == 'a');
      expect(source.item.viewOffsetMs, 60000);
      expect(updated.watchState.hasActiveProgress, isTrue);
      expect(updated.watchState.representativeSourceKey, 'a:sintel');
    });

    test('an item naming no membership of this group leaves it unchanged', () {
      final group = _group([_item('a')]);

      final result = group.withUpdatedSourceItem(_item('c', viewOffsetMs: 5000, durationMs: 6000000));

      expect(identical(result, group), isTrue);
    });

    test('identity, groupId and the untouched sources survive the swap', () {
      final group = _group([_item('a'), _item('b')]);

      final updated = group.withUpdatedSourceItem(_item('a', viewOffsetMs: 1000, durationMs: 6000000));

      expect(updated.groupId, group.groupId);
      expect(updated.identity, group.identity);
      expect(updated.sources, hasLength(2));
      expect(updated.sources.singleWhere((s) => s.serverId.value == 'b').item.viewOffsetMs, isNull);
    });

    test('the representative source is not re-ranked by a state-only update', () {
      // A watch-state refresh must not rearrange the card as a side effect
      // of the very viewing that triggered it. The representative here is
      // pinned to 'a', updating 'b' must not silently move it even though
      // 4.7 ranking would now prefer 'b' on richer metadata.
      final group = _group([
        _item('a'),
        MediaItem(
          id: 'sintel',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: 'Sintel',
          year: 2010,
          serverId: 'b',
          serverName: 'b',
          summary: 'A much richer summary than a has',
        ),
      ], representativeServerId: 'a');

      final updated = group.withUpdatedSourceItem(_item('b', viewOffsetMs: 1000, durationMs: 6000000));

      expect(updated.representativeSourceKey, 'a:sintel');
    });

    test('a preferred source key still reaches tier 4 through the swap', () {
      final group = _group([
        _item('a', viewOffsetMs: 20000, durationMs: 6000000, lastViewedAt: 1756000000),
        _item('b', viewOffsetMs: 20000, durationMs: 6000000, lastViewedAt: 1756000000),
      ]);

      final updated = group.withUpdatedSourceItem(
        _item('a', viewOffsetMs: 20000, durationMs: 6000000, lastViewedAt: 1756000000),
        preferredSourceKey: 'b:sintel',
      );

      expect(updated.watchState.representativeSourceKey, 'b:sintel');
    });
  });
}
