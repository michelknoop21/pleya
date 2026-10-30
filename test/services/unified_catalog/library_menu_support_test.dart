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
  _Plex({this.sorts = const [], this.filters = const [], this.fails = false});

  final List<String> sorts;
  final List<String> filters;
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

  test('no key is ever guessed for Dolby Vision, HDR10+ or Atmos', () async {
    final support = await _load(
      {
        'p': _Plex(filters: ['hdr', 'unmatched', 'duplicate', 'dolbyVision', 'hdr10Plus', 'atmos']),
      },
      [_library('p', MediaBackend.plex)],
    );
    expect(support!.mediaFilters, {
      LibraryQuickFilter.hdr,
      LibraryQuickFilter.unmatched,
      LibraryQuickFilter.duplicates,
    });
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
