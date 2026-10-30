/// What the live Plex servers behind a catalog say they can do.
///
/// The static table in `unified_catalog_capabilities.dart` holds what a backend
/// can do by its API. Plex is the one backend that answers per library, and only
/// its own lists prove a key for this library type on this server version:
/// `/library/sections/{id}/sorts` and `/filters`. So a sort beyond the first
/// four, and every media quick filter, shows only once each Plex library in the
/// catalog has named it.
library;

import 'dart:async';

import '../../media/ids.dart';
import '../../media/library_menu_definition.dart';
import '../../media/media_backend.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import 'source_cursor.dart';
import 'unified_catalog_query.dart';

/// Sorts the catalog has always run on Plex, kept when `/sorts` fails: a server
/// that is briefly unreachable must not take away Recently Added.
const Set<UnifiedCatalogSortField> _unconditionalPlexSorts = {
  UnifiedCatalogSortField.title,
  UnifiedCatalogSortField.addedAt,
  UnifiedCatalogSortField.releaseDate,
  UnifiedCatalogSortField.recentlyWatched,
};

class LibraryMenuSupport {
  const LibraryMenuSupport({
    required this.sortFields,
    this.mediaFilterKeys = const {},
    this.extraFilters = const [],
    this.serverCategories = const [],
  });

  /// The sort fields every Plex library listed.
  final Set<UnifiedCatalogSortField> sortFields;

  /// The known media quick filters every library listed, with the `filter`
  /// value they are listed under. A filter the libraries spell differently is
  /// absent: one query cannot ask two spellings. Empty as soon as a non-Plex
  /// library takes part, since none of them runs on another backend.
  final Map<LibraryQuickFilter, String> mediaFilterKeys;

  /// Booleans every library listed that the definition has no row for.
  final List<LibraryServerFilter> extraFilters;

  /// Non-boolean categories every library listed, beyond the five of the
  /// definition.
  final List<LibraryServerFilter> serverCategories;

  Set<LibraryQuickFilter> get mediaFilters => mediaFilterKeys.keys.toSet();
}

/// Asks every Plex library in [libraries]. Null when there is none, which
/// leaves the static table as the whole answer.
Future<LibraryMenuSupport?> loadLibraryMenuSupport({
  required List<CatalogLibrary> libraries,
  required MediaKind kind,
  required MediaServerClient? Function(ServerId serverId) clientFor,
}) async {
  final plex = libraries.where((library) => library.backend == MediaBackend.plex).toList();
  if (plex.isEmpty) return null;
  final answers = await Future.wait([for (final library in plex) _ask(library, kind, clientFor)]);

  var sortFields = UnifiedCatalogSortField.values.toSet();
  var keys = answers.first.mediaFilterKeys;
  var extras = answers.first.extraFilters;
  var categories = answers.first.serverCategories;
  for (final answer in answers) {
    sortFields = sortFields.intersection(answer.sortFields);
    keys = {
      for (final entry in keys.entries)
        if (answer.mediaFilterKeys[entry.key] == entry.value) entry.key: entry.value,
    };
    extras = [
      for (final extra in extras)
        if (answer.extraFilters.any((e) => e.key == extra.key)) extra,
    ];
    categories = [
      for (final category in categories)
        if (answer.serverCategories.any((c) => c.key == category.key)) category,
    ];
  }
  final allPlex = plex.length == libraries.length;
  return LibraryMenuSupport(
    sortFields: sortFields,
    mediaFilterKeys: allPlex ? keys : const {},
    extraFilters: allPlex ? extras : const [],
    serverCategories: allPlex ? categories : const [],
  );
}

Future<LibraryMenuSupport> _ask(
  CatalogLibrary library,
  MediaKind kind,
  MediaServerClient? Function(ServerId serverId) clientFor,
) async {
  final client = clientFor(library.serverId);
  var sortKeys = const <String>{};
  var server = const LibraryServerFilters();
  if (client != null) {
    try {
      final (sorts, filters) = await (
        client.fetchSortOptions(library.libraryId, libraryType: kind.id),
        client.fetchLibraryFiltersWithValues(library.libraryId),
      ).wait;
      sortKeys = {for (final sort in sorts) sort.key};
      server = classifyServerFilters(filters.filters);
    } catch (e) {
      appLogger.d('Library menu support failed for ${library.libraryTitle}: $e');
    }
  }
  return LibraryMenuSupport(
    sortFields: {
      for (final field in UnifiedCatalogSortField.values)
        if (_unconditionalPlexSorts.contains(field) || sortKeys.contains(plexSortKeyFor(field))) field,
    },
    mediaFilterKeys: server.known,
    extraFilters: server.extras,
    serverCategories: server.categories,
  );
}
