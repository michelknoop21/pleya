/// Covers hoofdstuk 9.5's selection rules: films and series only, unique
/// groups, no unreleased title, and an exactly reproducible list for a given
/// input — fase 8 has to be able to reason about which slide is which.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/featured_selector.dart';

final _asOf = DateTime.utc(2026, 8, 30);

MediaItem _item(
  String id, {
  required MediaKind kind,
  String? title = 'Dune',
  int? year = 2021,
  String? originallyAvailableAt,
  String serverId = 'server-a',
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  title: title,
  year: year,
  originallyAvailableAt: originallyAvailableAt,
  grandparentTitle: kind == MediaKind.episode ? 'Severance' : null,
  parentIndex: kind == MediaKind.episode ? 1 : null,
  index: kind == MediaKind.episode ? 3 : null,
  serverId: serverId,
);

UnifiedMediaGroup _groupOf(List<MediaItem> items, {String? groupId}) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  return UnifiedMediaGroup(
    groupId: groupId ?? 'group:${items.first.globalKey}',
    identity: canonicalIdentityOf(items.first) ?? CanonicalMediaIdentity.opaque(),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: selectRepresentativeWatchState({for (final s in sources) s.sourceKey: s.item}),
  );
}

UnifiedMediaHub _hub(String slug, List<UnifiedMediaGroup> groups) =>
    UnifiedMediaHub.synthesized(slug: slug, title: slug, kind: UnifiedHubKind.mixed, groups: groups);

UnifiedMediaGroup _movie(String id, {String title = 'Dune', int? year = 2021, String serverId = 'server-a'}) =>
    _groupOf([_item(id, kind: MediaKind.movie, title: title, year: year, serverId: serverId)]);

void main() {
  group('FeaturedSelector', () {
    test('picks candidates in the order the caller ranked them', () {
      final hubs = [
        _hub('topPicks', [_movie('1', title: 'Dune'), _movie('2', title: 'Arrival', year: 2016)]),
        _hub('recentFilms', [_movie('3', title: 'Sicario', year: 2015)]),
      ];

      final selected = const FeaturedSelector().select(hubs, now: _asOf);

      expect([for (final group in selected) group.representativeSource.item.title], ['Dune', 'Arrival', 'Sicario']);
    });

    test('is exactly reproducible for the same input', () {
      final hubs = [
        _hub('topPicks', [_movie('1', title: 'Dune'), _movie('2', title: 'Arrival', year: 2016)]),
        _hub('recentSeries', [
          _groupOf([_item('4', kind: MediaKind.show, title: 'Severance', year: 2022)]),
        ]),
      ];

      final first = const FeaturedSelector().select(hubs, now: _asOf);
      final second = const FeaturedSelector().select(hubs, now: _asOf);

      expect([for (final g in first) g.groupId], [for (final g in second) g.groupId]);
      expect([for (final g in first) g.groupId], ['group:server-a:1', 'group:server-a:2', 'group:server-a:4']);
    });

    test('caps the carousel at hoofdstuk 9.5\'s upper bound', () {
      final hubs = [
        _hub('topPicks', [for (var i = 0; i < 20; i++) _movie('$i', title: 'Film $i', year: 2000 + i)]),
      ];

      expect(const FeaturedSelector().select(hubs, now: _asOf), hasLength(8));
      expect(const FeaturedSelector(maxCount: 5).select(hubs, now: _asOf), hasLength(5));
    });

    test('returns fewer than five rather than inventing slides', () {
      final hubs = [
        _hub('topPicks', [_movie('1', title: 'Dune'), _movie('2', title: 'Arrival', year: 2016)]),
      ];

      expect(const FeaturedSelector().select(hubs, now: _asOf), hasLength(2));
    });

    test('the same group reaching the selector from two rows is one slide', () {
      final dune = _movie('1');
      final hubs = [
        _hub('topPicks', [dune]),
        _hub('recentFilms', [dune]),
      ];

      expect(const FeaturedSelector().select(hubs, now: _asOf), hasLength(1));
    });

    test('two groups that share a concrete source are one slide', () {
      final shared = _item('1', kind: MediaKind.movie);
      final other = _item('2', kind: MediaKind.movie, title: 'Dune', serverId: 'server-b');
      final hubs = [
        _hub('topPicks', [
          _groupOf([shared], groupId: 'group:one'),
        ]),
        _hub('recentFilms', [
          _groupOf([other, shared], groupId: 'group:two'),
        ]),
      ];

      final selected = const FeaturedSelector().select(hubs, now: _asOf);

      expect(selected, hasLength(1));
      expect(selected.single.groupId, 'group:one');
    });

    test('two groups the pipeline could not prove equal still yield one slide per title', () {
      final hubs = [
        _hub('topPicks', [_movie('1', title: 'Dune', year: 2021)]),
        _hub('recentFilms', [_movie('2', title: 'Dune', year: 2021, serverId: 'server-b')]),
      ];

      expect(const FeaturedSelector().select(hubs, now: _asOf), hasLength(1));
    });

    test('a loose episode is never a hero slide', () {
      final hubs = [
        _hub('continueWatching', [
          _groupOf([_item('e1', kind: MediaKind.episode, title: 'Episode 3', year: null)]),
          _movie('1'),
        ]),
      ];

      final selected = const FeaturedSelector().select(hubs, now: _asOf);

      expect(selected, hasLength(1));
      expect(selected.single.representativeSource.item.kind, MediaKind.movie);
    });

    test('a title with a future release date is not featured', () {
      final hubs = [
        _hub('topPicks', [
          _groupOf([
            _item(
              '1',
              kind: MediaKind.movie,
              title: 'Dune Part Three',
              year: 2026,
              originallyAvailableAt: '2026-12-18',
            ),
          ]),
          _movie('2', title: 'Arrival', year: 2016),
        ]),
      ];

      final selected = const FeaturedSelector().select(hubs, now: _asOf);

      expect([for (final g in selected) g.representativeSource.item.title], ['Arrival']);
    });

    test('a release year beyond the current one is caught even without a date', () {
      final hubs = [
        _hub('topPicks', [_movie('1', title: 'Ghost Release', year: 2031), _movie('2', title: 'Arrival', year: 2016)]),
      ];

      final selected = const FeaturedSelector().select(hubs, now: _asOf);

      expect([for (final g in selected) g.representativeSource.item.title], ['Arrival']);
    });

    test('a title released earlier this year is still featured', () {
      final hubs = [
        _hub('topPicks', [
          _groupOf([
            _item('1', kind: MediaKind.movie, title: 'Recent', year: 2026, originallyAvailableAt: '2026-02-01'),
          ]),
        ]),
      ];

      expect(const FeaturedSelector().select(hubs, now: _asOf), hasLength(1));
    });

    test('an item without a usable title is skipped', () {
      final hubs = [
        _hub('topPicks', [
          _groupOf([_item('1', kind: MediaKind.movie, title: '   ', year: 2021)]),
          _movie('2', title: 'Arrival', year: 2016),
        ]),
      ];

      final selected = const FeaturedSelector().select(hubs, now: _asOf);

      expect([for (final g in selected) g.representativeSource.item.title], ['Arrival']);
    });

    test('no candidates at all yields no slides', () {
      expect(const FeaturedSelector().select(const [], now: _asOf), isEmpty);
      expect(const FeaturedSelector().select([_hub('topPicks', const [])], now: _asOf), isEmpty);
    });
  });
}
