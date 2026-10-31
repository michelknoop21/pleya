/// What a live Plex server lists decides what the menus offer.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/media/library_menu_definition.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/services/unified_catalog/library_menu_support.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';

class _Plex implements MediaServerClient {
  _Plex({this.sorts = const [], this.filters = const [], this.listed = const [], this.fails = false});

  final List<String> sorts;

  /// Boolean filters by `filter` value, the short way to write a fixture.
  final List<String> filters;

  /// Filters as the wire gives them, for the cases that need a type or title.
  final List<Map<String, dynamic>> listed;
  final bool fails;

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async {
    if (fails) throw StateError('offline');
    return [for (final key in sorts) MediaSort(key: key, title: key)];
  }

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult(
    filters: [
      for (final key in filters) MediaFilter(filter: key, filterType: 'boolean', key: '', title: key, type: 'filter'),
      for (final json in listed) MediaFilter.fromJson(json),
    ],
    cachedValues: const {},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

CatalogLibrary _library(String server, MediaBackend backend) =>
    (serverId: ServerId(server), serverName: server, libraryId: 'lib', backend: backend, libraryTitle: 'lib');

Future<LibraryMenuSupport?> _load(Map<String, _Plex> servers, List<CatalogLibrary> libraries) =>
    loadLibraryMenuSupport(libraries: libraries, kind: MediaKind.movie, clientFor: (id) => servers[id.value]);

void main() {
  test('without a Plex library the static table stands', () async {
    expect(await _load(const {}, [_library('j', MediaBackend.jellyfin)]), isNull);
  });

  test('a sort beyond the first four needs the key on the server', () async {
    final support = await _load(
      {
        'p': _Plex(sorts: ['titleSort', 'rating', 'mediaHeight']),
      },
      [_library('p', MediaBackend.plex)],
    );
    expect(
      support!.sortFields,
      containsAll([UnifiedCatalogSortField.criticRating, UnifiedCatalogSortField.resolution]),
    );
    expect(support.sortFields, isNot(contains(UnifiedCatalogSortField.audienceRating)));
    expect(support.sortFields, contains(UnifiedCatalogSortField.addedAt));
  });

  test('two Plex libraries: only what both list', () async {
    final support = await _load(
      {
        'a': _Plex(sorts: ['rating', 'duration'], filters: ['hdr', 'unmatched']),
        'b': _Plex(sorts: ['rating'], filters: ['hdr']),
      },
      [_library('a', MediaBackend.plex), _library('b', MediaBackend.plex)],
    );
    expect(support!.sortFields, isNot(contains(UnifiedCatalogSortField.duration)));
    expect(support.mediaFilters, {LibraryQuickFilter.hdr});
  });

  test('a media filter disappears as soon as a non-Plex library takes part', () async {
    final support = await _load(
      {
        'p': _Plex(filters: ['hdr', 'duplicate']),
      },
      [_library('p', MediaBackend.plex), _library('j', MediaBackend.jellyfin)],
    );
    expect(support!.mediaFilters, isEmpty);
  });

  // `/library/sections/{id}/filters` as a server can answer it: every known
  // boolean, spellings that differ from ours, one the definition has no row
  // for, the five categories of the definition and two it has none for.
  final fixture = <Map<String, dynamic>>[
    {'filter': 'hdr', 'filterType': 'boolean', 'key': '/library/sections/1/hdr', 'title': 'HDR', 'type': 'filter'},
    {'filter': 'DolbyVision', 'filterType': 'boolean', 'key': '/library/sections/1/dv', 'title': 'Dolby Vision'},
    {'filter': 'hdr10Plus', 'filterType': 'boolean', 'key': '/library/sections/1/h', 'title': 'HDR10+'},
    {'filter': 'dolbyAtmos', 'filterType': 'boolean', 'key': '/library/sections/1/a', 'title': 'Atmos'},
    {'filter': 'unwatched', 'filterType': 'boolean', 'key': '/library/sections/1/u', 'title': 'Unplayed'},
    {'filter': 'inProgress', 'filterType': 'boolean', 'key': '/library/sections/1/i', 'title': 'In Progress'},
    {'filter': 'unmatched', 'filterType': 'boolean', 'key': '/library/sections/1/m', 'title': 'Unmatched'},
    {'filter': 'duplicate', 'filterType': 'boolean', 'key': '/library/sections/1/d', 'title': 'Duplicates'},
    {'filter': 'hasSubtitles', 'filterType': 'boolean', 'key': '/library/sections/1/s', 'title': 'Has subtitles'},
    {'filter': 'genre', 'filterType': 'string', 'key': '/library/sections/1/genre', 'title': 'Genre'},
    {'filter': 'year', 'filterType': 'integer', 'key': '/library/sections/1/year', 'title': 'Year'},
    {'filter': 'decade', 'filterType': 'integer', 'key': '/library/sections/1/decade', 'title': 'Decade'},
    {'filter': 'contentRating', 'filterType': 'string', 'key': '/library/sections/1/cr', 'title': 'Content Rating'},
    {'filter': 'audioLanguage', 'filterType': 'string', 'key': '/library/sections/1/al', 'title': 'Audio Language'},
    {'filter': 'studio', 'filterType': 'string', 'key': '/library/sections/1/studio', 'title': 'Studio'},
    {'filter': 'country', 'filterType': 'string', 'key': '/library/sections/1/country', 'title': 'Land'},
  ];

  test('the server decides what exists: aliases land on the known rows, with the server spelling', () async {
    final support = await _load({'p': _Plex(listed: fixture)}, [_library('p', MediaBackend.plex)]);
    expect(support!.mediaFilterKeys, {
      LibraryQuickFilter.hdr: 'hdr',
      LibraryQuickFilter.dolbyVision: 'DolbyVision',
      LibraryQuickFilter.hdr10Plus: 'hdr10Plus',
      LibraryQuickFilter.atmos: 'dolbyAtmos',
      LibraryQuickFilter.unmatched: 'unmatched',
      LibraryQuickFilter.duplicates: 'duplicate',
    });
  });

  test('an unknown boolean goes to the bottom with the label of the server, watch states add nothing', () async {
    final support = await _load({'p': _Plex(listed: fixture)}, [_library('p', MediaBackend.plex)]);
    expect(support!.extraFilters, [const LibraryServerFilter(key: 'hasSubtitles', label: 'Has subtitles')]);
  });

  test('non-booleans beyond the five of the definition become categories in serverlabel', () async {
    final support = await _load({'p': _Plex(listed: fixture)}, [_library('p', MediaBackend.plex)]);
    expect(support!.serverCategories, [
      const LibraryServerFilter(key: 'studio', label: 'Studio'),
      const LibraryServerFilter(key: 'country', label: 'Land'),
    ]);
  });

  test('an option the server does not list does not appear', () async {
    final support = await _load(
      {
        'p': _Plex(filters: ['hdr']),
      },
      [_library('p', MediaBackend.plex)],
    );
    expect(support!.mediaFilterKeys.keys, [LibraryQuickFilter.hdr]);
    expect(support.extraFilters, isEmpty);
    expect(support.serverCategories, isEmpty);
  });

  test('two libraries: only what both list, and under one spelling', () async {
    final support = await _load(
      {
        'a': _Plex(filters: ['hdr10Plus', 'hasSubtitles', 'dovi']),
        'b': _Plex(filters: ['hdr10plus', 'hasSubtitles', 'dovi']),
      },
      [_library('a', MediaBackend.plex), _library('b', MediaBackend.plex)],
    );
    expect(support!.mediaFilterKeys, {LibraryQuickFilter.dolbyVision: 'dovi'});
    expect(support.extraFilters.map((e) => e.key), ['hasSubtitles']);
  });

  test('extras and categories disappear as soon as a non-Plex library takes part', () async {
    final support = await _load(
      {'p': _Plex(listed: fixture)},
      [_library('p', MediaBackend.plex), _library('j', MediaBackend.jellyfin)],
    );
    expect(support!.extraFilters, isEmpty);
    expect(support.serverCategories, isEmpty);
  });

  test('a server that does not answer keeps the first four and offers nothing new', () async {
    final support = await _load({'p': _Plex(fails: true)}, [_library('p', MediaBackend.plex)]);
    expect(support!.sortFields, {
      UnifiedCatalogSortField.title,
      UnifiedCatalogSortField.addedAt,
      UnifiedCatalogSortField.releaseDate,
      UnifiedCatalogSortField.recentlyWatched,
    });
    expect(support.mediaFilters, isEmpty);
  });
}
