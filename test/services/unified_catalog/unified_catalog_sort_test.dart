/// Every sort field: its key per backend, its comparator with titles without a
/// value, which backend combinations offer it, and what a change of sources does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/library_menu_definition.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/services/library_query_translator.dart';
import 'package:pleya/services/unified_catalog/library_menu_support.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';

typedef _F = UnifiedCatalogSortField;

LibraryQuery _queryFor(_F field) =>
    UnifiedCatalogQuery(kind: MediaKind.movie, sortField: field).toLibraryQuery(offset: 0, limit: 10);

String _plex(_F field) =>
    const PlexLibraryQueryTranslator().toQueryParameters(_queryFor(field))['sort']!.split(':').first;

String _jellyfin(_F field) =>
    (const JellyfinLibraryQueryTranslator(userId: 'u', fields: 'f').toQueryParameters(_queryFor(field))['SortBy']
            as String)
        .split(',')
        .first;

MediaItem _plexItem(String title, {double? rating, double? audience, double? user, int? year}) => PlexMediaItem(
  id: title,
  kind: MediaKind.movie,
  title: title,
  rating: rating,
  audienceRating: audience,
  userRating: user,
  year: year,
);

/// One item per field that has [value] for it, or nothing at all.
MediaItem _withValue(_F field, String title, num? value) {
  final v = value?.toInt();
  return switch (field) {
    _F.title => PlexMediaItem(id: title, kind: MediaKind.movie, title: value == null ? '' : title),
    _F.year => PlexMediaItem(id: title, kind: MediaKind.movie, title: title, year: v),
    _F.releaseDate => PlexMediaItem(
      id: title,
      kind: MediaKind.movie,
      title: title,
      originallyAvailableAt: v == null ? null : '$v-01-01',
    ),
    _F.criticRating => _plexItem(title, rating: value?.toDouble()),
    _F.audienceRating => _plexItem(title, audience: value?.toDouble()),
    _F.userRating => _plexItem(title, user: value?.toDouble()),
    _F.contentRating => PlexMediaItem(
      id: title,
      kind: MediaKind.movie,
      title: title,
      contentRating: v == null ? null : '$v',
    ),
    _F.duration => PlexMediaItem(id: title, kind: MediaKind.movie, title: title, durationMs: v),
    _F.progress => PlexMediaItem(id: title, kind: MediaKind.movie, title: title, viewOffsetMs: v),
    _F.plays => PlexMediaItem(id: title, kind: MediaKind.movie, title: title, viewCount: v),
    _F.addedAt => PlexMediaItem(id: title, kind: MediaKind.movie, title: title, addedAt: v),
    _F.recentlyWatched => PlexMediaItem(id: title, kind: MediaKind.movie, title: title, lastViewedAt: v),
    _F.resolution => PlexMediaItem(
      id: title,
      kind: MediaKind.movie,
      title: title,
      mediaVersions: v == null ? null : [MediaVersion(id: 'v', height: v)],
    ),
  };
}

List<String?> _ordered(_F field, LibrarySortDirection direction, List<MediaItem> items) =>
    [...items].toList().sorted(field, direction);

extension on List<MediaItem> {
  List<String?> sorted(_F field, LibrarySortDirection direction) {
    sort(unifiedCatalogSortComparator(field, direction));
    return [for (final item in this) item.id];
  }
}

void main() {
  group('the key of every field per backend', () {
    test('Plex', () {
      expect(
        {for (final f in _F.values) f: _plex(f)},
        {
          _F.title: 'title',
          _F.year: 'year',
          _F.releaseDate: 'originallyAvailableAt',
          _F.criticRating: 'rating',
          _F.audienceRating: 'audienceRating',
          _F.userRating: 'userRating',
          _F.contentRating: 'contentRating',
          _F.duration: 'duration',
          _F.progress: 'viewOffset',
          _F.plays: 'viewCount',
          _F.addedAt: 'addedAt',
          _F.recentlyWatched: 'lastViewedAt',
          _F.resolution: 'mediaHeight',
        },
      );
    });

    test('Jellyfin, for what it can run', () {
      final offered = unifiedFilterCapabilitiesFor([MediaBackend.jellyfin]).sortFields;
      expect(
        {for (final f in offered) f: _jellyfin(f)},
        {
          _F.title: 'SortName',
          _F.year: 'ProductionYear',
          _F.releaseDate: 'PremiereDate',
          _F.criticRating: 'CriticRating',
          _F.audienceRating: 'CommunityRating',
          _F.contentRating: 'OfficialRating',
          _F.duration: 'Runtime',
          _F.plays: 'PlayCount',
          _F.addedAt: 'DateCreated',
          _F.recentlyWatched: 'DatePlayed',
        },
      );
    });

    test('Jellyfin keeps rating as the community score for saved browse sorts', () {
      final params = const JellyfinLibraryQueryTranslator(userId: 'u', fields: 'f').toQueryParameters(
        const LibraryQuery(
          sort: LibrarySort(field: 'rating', direction: LibrarySortDirection.descending),
        ),
      );
      expect(params['SortBy'], 'CommunityRating,SortName');
    });
  });

  group('the comparator of every field', () {
    for (final field in _F.values.where((f) => f != _F.title)) {
      test('${field.name}: both directions, titles without a value last', () {
        List<MediaItem> items() => [
          _withValue(field, 'none', null),
          _withValue(field, 'low', field == _F.releaseDate || field == _F.year ? 1990 : 3),
          _withValue(field, 'high', field == _F.releaseDate || field == _F.year ? 2020 : 9),
        ];
        expect(_ordered(field, LibrarySortDirection.ascending, items()), ['low', 'high', 'none']);
        expect(_ordered(field, LibrarySortDirection.descending, items()), ['high', 'low', 'none']);
      });
    }

    test('equal values read in title order in both directions, as in 04.png', () {
      List<MediaItem> items() => [
        _plexItem('Backrooms', year: 2026),
        _plexItem('Animals', year: 2026),
        _plexItem('Apex', year: 2026),
      ];
      expect(_ordered(_F.year, LibrarySortDirection.descending, items()), ['Animals', 'Apex', 'Backrooms']);
      expect(_ordered(_F.year, LibrarySortDirection.ascending, items()), ['Animals', 'Apex', 'Backrooms']);
    });

    test('Plex 9.1 and Jellyfin 91 are the same score, Jellyfin 88 sits below', () {
      const jellyfin91 = JellyfinMediaItem(
        id: 'j91',
        kind: MediaKind.movie,
        title: 'B',
        externalRatings: [ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 91)],
      );
      const jellyfin88 = JellyfinMediaItem(
        id: 'j88',
        kind: MediaKind.movie,
        title: 'C',
        externalRatings: [ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 88)],
      );
      final items = [jellyfin88, _plexItem('A', rating: 9.1), jellyfin91];
      expect(_ordered(_F.criticRating, LibrarySortDirection.descending, items), ['A', 'j91', 'j88']);
    });

    test('age ratings sort as the Leeftijd filter lists them, country prefix or not', () {
      List<MediaItem> items() => [
        const PlexMediaItem(id: 'pg', kind: MediaKind.movie, title: 'x', contentRating: 'PG-13'),
        const PlexMediaItem(id: 'gb12', kind: MediaKind.movie, title: 'x', contentRating: 'gb/12'),
        const PlexMediaItem(id: '6', kind: MediaKind.movie, title: 'x', contentRating: '6'),
      ];
      expect(_ordered(_F.contentRating, LibrarySortDirection.ascending, items()), ['6', 'gb12', 'pg']);
    });

    test('zero plays and zero progress are no value', () {
      final item = _withValue(_F.plays, 'x', 0);
      expect(unifiedCatalogHasSortValue(item, _F.plays), isFalse);
      expect(unifiedCatalogHasSortValue(_withValue(_F.progress, 'x', 0), _F.progress), isFalse);
    });

    test('resolution reads the tallest version', () {
      final item = PlexMediaItem(
        id: 'x',
        kind: MediaKind.movie,
        mediaVersions: [
          MediaVersion(id: 'a', height: 1080),
          MediaVersion(id: 'b', height: 2160),
        ],
      );
      final lower = _withValue(_F.resolution, 'y', 1600);
      expect(unifiedCatalogSortComparator(_F.resolution, LibrarySortDirection.descending)(item, lower), lessThan(0));
    });
  });

  group('what a combination of backends can sort on', () {
    Set<_F> fields(List<MediaBackend> backends, {MediaKind kind = MediaKind.movie}) =>
        unifiedFilterCapabilitiesFor(backends, kind: kind).sortFields;

    test('Plex alone offers everything on films', () {
      expect(fields([MediaBackend.plex]), _F.values.toSet());
    });

    test('a Plex show has no runtime, position or resolution of its own', () {
      expect(_F.values.toSet().difference(fields([MediaBackend.plex], kind: MediaKind.show)), {
        _F.duration,
        _F.progress,
        _F.resolution,
      });
    });

    test('Jellyfin has no sort on user rating, position or resolution', () {
      expect(_F.values.toSet().difference(fields([MediaBackend.jellyfin])), {
        _F.userRating,
        _F.progress,
        _F.resolution,
      });
    });

    test('Pleya Server takes exactly its five fields', () {
      expect(fields([MediaBackend.pleyaServer]), {_F.title, _F.addedAt, _F.year, _F.recentlyWatched, _F.duration});
    });

    test('Plex and Jellyfin: the intersection, scores included, Leeftijd not: it cannot be merged', () {
      expect(
        fields([MediaBackend.plex, MediaBackend.jellyfin]),
        fields([MediaBackend.jellyfin]).difference({_F.contentRating}),
      );
    });

    test('Plex and Pleya Server: no scores', () {
      expect(fields([MediaBackend.plex, MediaBackend.pleyaServer]), fields([MediaBackend.pleyaServer]));
    });

    test('Jellyfin and Pleya Server: no scores', () {
      expect(fields([MediaBackend.jellyfin, MediaBackend.pleyaServer]), fields([MediaBackend.pleyaServer]));
    });

    test('all three: the five of Pleya Server', () {
      expect(
        fields([MediaBackend.plex, MediaBackend.jellyfin, MediaBackend.pleyaServer]),
        fields([MediaBackend.pleyaServer]),
      );
    });

    test('a local folder takes what its client sorts on', () {
      expect(fields([MediaBackend.local]), {_F.title, _F.year, _F.plays, _F.addedAt, _F.recentlyWatched});
    });

    test('nothing participating promises title alone', () {
      expect(UnifiedFilterCapabilities.none.sortFields, {_F.title});
    });
  });

  group('a change of sources', () {
    const stored = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.criticHighest);
    final jellyfin = unifiedFilterCapabilitiesFor([MediaBackend.jellyfin]);
    final mixed = unifiedFilterCapabilitiesFor([MediaBackend.jellyfin, MediaBackend.pleyaServer]);

    test('a sort that falls away reads title, and the query asks for title', () {
      expect(stored.effectiveSort(mixed), UnifiedCatalogSort.titleAsc);
      final query = buildUnifiedCatalogQuery(kind: MediaKind.movie, preferences: stored, capabilities: mixed);
      expect(query.sortField, _F.title);
      expect(query.sortDirection, LibrarySortDirection.ascending);
    });

    test('the stored sort survives and returns with the sources', () {
      stored.effectiveSort(mixed);
      expect(stored.sort, UnifiedCatalogSort.criticHighest);
      expect(stored.effectiveSort(jellyfin), UnifiedCatalogSort.criticHighest);
    });

    group('Pleya Server has no date, only a year', () {
      final pleya = unifiedFilterCapabilitiesFor([MediaBackend.pleyaServer]);

      test('a stored release sort runs on the year, both ways round', () {
        const newest = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease);
        const oldest = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.oldestRelease);
        expect(newest.effectiveSort(pleya), UnifiedCatalogSort.yearNewest);
        expect(oldest.effectiveSort(pleya), UnifiedCatalogSort.yearOldest);
      });

      test('the query asks for the year, so it never reads A to Z', () {
        final query = buildUnifiedCatalogQuery(
          kind: MediaKind.movie,
          preferences: const UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease),
          capabilities: pleya,
        );
        expect(query.sortField, _F.year);
        expect(query.sortDirection, LibrarySortDirection.descending);
      });

      test('a backend with the date keeps the date, and the stored sort is never rewritten', () {
        const newest = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease);
        expect(newest.effectiveSort(jellyfin), UnifiedCatalogSort.newestRelease);
        newest.effectiveSort(pleya);
        expect(newest.sort, UnifiedCatalogSort.newestRelease);
      });

      test('without a year either it is title', () {
        const newest = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease);
        expect(newest.effectiveSort(UnifiedFilterCapabilities.none), UnifiedCatalogSort.titleAsc);
      });

      test('the named list keeps a date sort on it, so the phone and the TV rail have one', () {
        final offered = UnifiedCatalogSort.named.where((sort) => pleya.supportsSort(sort.field));
        expect(offered, containsAll([UnifiedCatalogSort.yearNewest, UnifiedCatalogSort.yearOldest]));
      });
    });

    test('a stored name from this list round-trips, an unknown one falls to title', () {
      expect(UnifiedCatalogPreferences.fromJson(stored.toJson()).sort, UnifiedCatalogSort.criticHighest);
      expect(UnifiedCatalogPreferences.fromJson({'sort': 'gone'}).sort, UnifiedCatalogSort.titleAsc);
    });

    test('every field except Bekeken has both directions', () {
      for (final field in _F.values.where((f) => f != _F.recentlyWatched)) {
        final directions = UnifiedCatalogSort.values.where((s) => s.field == field).map((s) => s.direction).toSet();
        expect(directions, hasLength(2), reason: field.name);
      }
    });
  });

  group('the live answer of Plex', () {
    final plex = unifiedFilterCapabilitiesFor([MediaBackend.plex]);

    test('narrows the table and is the only way to a media filter', () {
      expect(plex.supportsQuickFilter(LibraryQuickFilter.hdr), isFalse);
      final narrowed = plex.narrowedTo(
        const LibraryMenuSupport(
          sortFields: {_F.title, _F.criticRating},
          mediaFilterKeys: {LibraryQuickFilter.hdr: 'hdr'},
        ),
      );
      expect(narrowed.sortFields, {_F.title, _F.criticRating});
      expect(narrowed.supportsQuickFilter(LibraryQuickFilter.hdr), isTrue);
      expect(narrowed.supportsQuickFilter(LibraryQuickFilter.duplicates), isFalse);
    });

    test('a quick choice reaches Plex as its boolean filter, and only there', () {
      final narrowed = plex.narrowedTo(
        LibraryMenuSupport(
          sortFields: _F.values.toSet(),
          mediaFilterKeys: const {LibraryQuickFilter.duplicates: 'duplicate'},
        ),
      );
      const preferences = UnifiedCatalogPreferences(
        filters: UnifiedCatalogFilterSelection(mediaFilter: LibraryQuickFilter.duplicates),
      );
      final query = buildUnifiedCatalogQuery(kind: MediaKind.movie, preferences: preferences, capabilities: narrowed);
      expect(query.toLibraryQuery(offset: 0, limit: 1).filters.single.field, 'duplicate');

      final without = buildUnifiedCatalogQuery(kind: MediaKind.movie, preferences: preferences, capabilities: plex);
      expect(without.filters, isEmpty);
    });
  });

  group('the quick choice and the decade', () {
    test('one quick choice at a time, Alles clears both kinds', () {
      const start = UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched, genres: {'Drama'});
      final hdr = start.withQuickFilter(LibraryQuickFilter.hdr);
      expect(hdr.quickFilter, LibraryQuickFilter.hdr);
      expect(hdr.watchState, UnifiedWatchFilter.all);
      expect(hdr.genres, {'Drama'});
      final watched = hdr.withQuickFilter(LibraryQuickFilter.watched);
      expect(watched.mediaFilter, isNull);
      expect(watched.quickFilter, LibraryQuickFilter.watched);
      expect(watched.withQuickFilter(LibraryQuickFilter.all).activeCount, 1);
    });

    test('a decade runs as its ten years on every backend that filters on year', () {
      final caps = unifiedFilterCapabilitiesFor([MediaBackend.jellyfin, MediaBackend.pleyaServer]);
      const preferences = UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(decades: {1990}));
      final query = buildUnifiedCatalogQuery(kind: MediaKind.movie, preferences: preferences, capabilities: caps);
      expect(query.years, [for (var y = 1990; y < 2000; y++) y]);
    });

    test('a year and a decade are AND-ed, and two that exclude each other find nothing', () {
      final caps = unifiedFilterCapabilitiesFor([MediaBackend.plex]);
      List<int>? years(UnifiedCatalogFilterSelection filters) => buildUnifiedCatalogQuery(
        kind: MediaKind.movie,
        preferences: UnifiedCatalogPreferences(filters: filters),
        capabilities: caps,
      ).years;
      expect(years(const UnifiedCatalogFilterSelection(decades: {1990}, years: {1994, 2001})), [1994]);
      expect(years(const UnifiedCatalogFilterSelection(decades: {1990}, years: {2001})), [0]);
    });

    test('both survive storage', () {
      const preferences = UnifiedCatalogPreferences(
        filters: UnifiedCatalogFilterSelection(decades: {1990}, mediaFilter: LibraryQuickFilter.hdr),
      );
      expect(UnifiedCatalogPreferences.fromJson(preferences.toJson()), preferences);
    });
  });
}
