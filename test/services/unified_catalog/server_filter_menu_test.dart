/// The filters a server names reach the request under the server's own
/// `filter` value, and a selection of them survives storage.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_menu_definition.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/library_query_translator.dart';
import 'package:pleya/services/unified_catalog/library_menu_support.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_capabilities.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';

MediaFilter _f(String filter, String type, String title) =>
    MediaFilter(filter: filter, filterType: type, key: '/k/$filter', title: title, type: 'filter');

final _server = classifyServerFilters([
  _f('DolbyVision', 'boolean', 'Dolby Vision'),
  _f('hasSubtitles', 'boolean', 'Has subtitles'),
  _f('unwatched', 'boolean', 'Unplayed'),
  _f('genre', 'string', 'Genre'),
  _f('studio', 'string', 'Studio'),
]);

UnifiedFilterCapabilities _capabilities() => unifiedFilterCapabilitiesFor([MediaBackend.plex]).narrowedTo(
  LibraryMenuSupport(
    sortFields: UnifiedCatalogSortField.values.toSet(),
    mediaFilterKeys: _server.known,
    extraFilters: _server.extras,
    serverCategories: _server.categories,
  ),
);

Map<String, dynamic> _request(UnifiedCatalogFilterSelection selection) {
  final query = buildUnifiedCatalogQuery(
    kind: MediaKind.movie,
    preferences: UnifiedCatalogPreferences(filters: selection),
    capabilities: _capabilities(),
  );
  return const PlexLibraryQueryTranslator().toQueryParameters(query.toLibraryQuery(offset: 0, limit: 10));
}

void main() {
  test('a known row asks Plex under the value the server listed, with 1', () {
    final request = _request(const UnifiedCatalogFilterSelection(mediaFilter: LibraryQuickFilter.dolbyVision));
    expect(request['DolbyVision'], '1');
    expect(request.containsKey('dolbyVision'), isFalse);
  });

  test('an unknown boolean asks under its own filter value', () {
    final request = _request(const UnifiedCatalogFilterSelection(extraFilter: 'hasSubtitles'));
    expect(request['hasSubtitles'], '1');
  });

  test('a server category asks under its filter value with the chosen values', () {
    final request = _request(
      const UnifiedCatalogFilterSelection(
        serverFilters: {
          'studio': {'B', 'A'},
        },
      ),
    );
    expect(request['studio'], 'A,B');
  });

  test('a filter the server does not list never reaches the request', () {
    final request = _request(
      const UnifiedCatalogFilterSelection(
        mediaFilter: LibraryQuickFilter.atmos,
        extraFilter: 'neverListed',
        serverFilters: {
          'neverListed': {'x'},
        },
      ),
    );
    expect(request.keys, isNot(containsAll(['atmos', 'neverListed'])));
    expect(request.containsKey('neverListed'), isFalse);
  });

  test('the quick choices take one slot, and the selection round-trips through storage', () {
    const start = UnifiedCatalogFilterSelection(
      serverFilters: {
        'studio': {'A'},
      },
    );
    final extra = start.withExtraFilter('hasSubtitles');
    expect(extra.withQuickFilter(LibraryQuickFilter.hdr).extraFilter, isNull);
    expect(extra.withQuickFilter(LibraryQuickFilter.hdr).serverFilters, start.serverFilters);
    expect(extra.activeCount, 2);

    final restored = UnifiedCatalogPreferences.fromJson(UnifiedCatalogPreferences(filters: extra).toJson()).filters;
    expect(restored, extra);
    expect(restored.extraFilter, 'hasSubtitles');
  });

  test('unified: a library that cannot run a server filter takes it away', () {
    final narrowed = unifiedFilterCapabilitiesFor([MediaBackend.plex, MediaBackend.jellyfin]).narrowedTo(
      LibraryMenuSupport(
        sortFields: UnifiedCatalogSortField.values.toSet(),
        extraFilters: const [],
        serverCategories: const [],
      ),
    );
    const selection = UnifiedCatalogFilterSelection(
      extraFilter: 'hasSubtitles',
      serverFilters: {
        'studio': {'A'},
      },
    );
    final effective = selection.constrainedTo(narrowed);
    expect(effective.extraFilter, isNull);
    expect(effective.serverFilters, isEmpty);
  });
}
