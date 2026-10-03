import '../../../assistant/assistant_tool_context.dart';
import '../../../navigation/tv/tv_destination.dart';
import '../../../providers/unified_catalogs.dart';
import '../../../services/unified_catalog/source_cursor.dart';
import '../../../utils/global_key_utils.dart';

/// The route id `TvLibrariesScreen._openInCatalog` gives one library's catalog.
const tvLibraryCatalogRoutePrefix = 'tvLibraryCatalog_';

/// What the summoned Big P sees behind him: "deze bibliotheek" on a catalog
/// that shows one library, "deze server" when every source is on one server,
/// nothing anywhere else. Read from what the shell already knows; nothing is
/// loaded for it.
AssistantScreenContext? tvAssistantSummonContext({
  required TvDestinationId active,
  String? nestedRouteId,
  UnifiedCatalogs? catalogs,
}) {
  if (nestedRouteId != null) {
    if (!nestedRouteId.startsWith(tvLibraryCatalogRoutePrefix)) return null;
    final key = parseGlobalKey(nestedRouteId.substring(tvLibraryCatalogRoutePrefix.length));
    return key == null ? null : AssistantScreenContext(serverId: key.serverId, libraryId: key.ratingKey);
  }
  final List<CatalogLibrary>? libraries = switch (active) {
    TvDestinationId.movies => catalogs?.movies.participatingLibraries,
    TvDestinationId.series => catalogs?.shows.participatingLibraries,
    _ => null,
  };
  if (libraries == null || libraries.isEmpty) return null;
  if (libraries.length == 1) {
    return AssistantScreenContext(serverId: libraries.single.serverId, libraryId: libraries.single.libraryId);
  }
  final servers = {for (final l in libraries) l.serverId};
  return servers.length == 1 ? AssistantScreenContext(serverId: servers.single) : null;
}
