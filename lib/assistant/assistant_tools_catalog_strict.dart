part of 'assistant_tools.dart';

// search_catalog's strict filters: runtime, exclusions, subtitles and audio,
// checked on each candidate's own detail read.

Future<({List<UnifiedMediaGroup> groups, Map<String, Object?> coverage, bool failed, bool sampled})>
_strictCatalogMatches(
  AssistantToolContext ctx,
  List<UnifiedMediaGroup> groups,
  AssistantStrictFilters filters,
  bool unwatched,
  bool inProgress,
  void Function() checkCurrent, {
  Set<String> genreAlternatives = const {},
}) async {
  final matched = <MediaItem>[];
  var checked = 0;
  var unavailable = 0;
  var excluded = 0;
  final sources = groups.expand((g) => g.sources).toList();
  // The metadata reads have their own cap: merged titles may contain many
  // copies, and mixed-kind searches may have loaded 100 of each kind.
  for (final source in sources.take(100)) {
    checkCurrent();
    if (ctx.catalog!.rowLoader case final CatalogHomeCustomRowLoader loader) {
      if (!loader
          .librariesFor(source.item.kind)
          .any((library) => library.serverId == source.serverId && library.libraryId == source.libraryId)) {
        unavailable++;
        continue;
      }
    }
    final client = ctx.userClient(source.serverId);
    if (client == null) {
      unavailable++;
      continue;
    }
    checked++;
    MediaItem? item;
    try {
      item = await client.fetchItem(source.item.id);
    } catch (_) {
      // The unavailable count is incremented once below, for null or failure.
    }
    checkCurrent();
    if (!identical(ctx.userClient(source.serverId), client)) throw const AssistantToolError('catalog_changed');
    if (item == null) {
      unavailable++;
      continue;
    }
    // Jellyfin's ParentId can be a nested folder; the catalog already proved
    // the root via its recursive ParentId query. Only an explicit root on the
    // detail DTO may contradict that proof.
    final detailLibrary = item.backend == MediaBackend.jellyfin ? (item.raw?['ParentLibraryId']) : item.libraryId;
    final malformedLibrary =
        item.backend == MediaBackend.jellyfin &&
        (item.raw?.containsKey('ParentLibraryId') ?? false) &&
        (detailLibrary is! String || detailLibrary.isEmpty);
    if (item.id != source.item.id ||
        item.kind != source.item.kind ||
        item.backend != source.backend ||
        (item.serverId != null && item.serverId != source.serverId.value) ||
        malformedLibrary ||
        (detailLibrary != null && detailLibrary != source.libraryId)) {
      unavailable++;
      continue;
    }
    item = item.copyWith(serverId: source.serverId.value, libraryId: source.libraryId);
    final watchKnown =
        item.backend != MediaBackend.jellyfin ||
        item.raw?['UserData'] is Map && (item.raw!['UserData'] as Map)['Played'] is bool;
    final genreMatches =
        genreAlternatives.isEmpty ||
        (item.genres?.any((genre) => genreAlternatives.contains(genre.trim().toLowerCase())) ?? false);
    if (!genreMatches ||
        (unwatched && !watchKnown) ||
        !filters.matches(item) ||
        (unwatched && item.isWatched) ||
        (inProgress && !item.hasActiveProgress)) {
      excluded++;
      continue;
    }
    matched.add(item);
  }
  final merged = await _merge(ctx, matched);
  checkCurrent();
  return (
    groups: merged,
    failed: unavailable > 0,
    sampled: sources.length > 100,
    coverage: {
      'candidates_checked': checked,
      'excluded_metadata_or_watch': excluded,
      'unavailable_metadata': unavailable,
      'candidate_limit': 100,
    },
  );
}
