/// What a saved Home row ([HomeCustomRow]) actually contains, and the one
/// place that asks the catalog for it (ROW1,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100)).
///
/// ## Why this is not a page of the Films catalog
///
/// A row is the *front* of a filter, not a browse session. It wants the first
/// handful of cards and a count, once, and then it is done; the catalog
/// provider is built for the opposite — a long-lived merge that keeps its
/// paging position, its remembered sources and its restart-on-dependency-change
/// behaviour while a grid scrolls. Reusing it would mean a Home with four
/// custom rows holding four full merges open for as long as the app runs, each
/// one restarting whenever a server blinks.
///
/// So this drives [UnifiedCatalogService] directly, with `groupsPerPage` set to
/// what a row can show, and calls `loadMore` exactly once. It is the same merge
/// engine, the same identity pipeline and the same neutral query the catalog
/// uses — hoofdstuk 12's "geen tweede projectie-architectuur" holds — just
/// asked one question instead of kept open.
///
/// ## The count is the one from 10.7, not a total
///
/// [HomeCustomRowContent.isExact] is `UnifiedCatalogSnapshot.isComplete`, which
/// is true only when every participating library reported itself exhausted. A
/// row over a large library therefore says "N geladen" and not "N titels", and
/// that is the honest answer: the merge deduplicates across servers, so the sum
/// of the libraries' own totals is not the number of cards this row would have.
library;

import '../../media/ids.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import 'catalog_service.dart';
import 'home_custom_row.dart';
import 'source_cursor.dart';
import 'unified_catalog_filters.dart';

class HomeCustomRowContent {
  /// The row's cards, in the saved sort.
  final List<UnifiedMediaGroup> groups;

  /// Whether [groups] is everything this filter yields (hoofdstuk 10.7).
  final bool isExact;

  /// A participating library did not answer. The row still shows what it has
  /// (hoofdstuk 21.4), and says its coverage is partial.
  final bool isPartial;

  const HomeCustomRowContent({this.groups = const [], this.isExact = false, this.isPartial = false});

  /// Nothing participates: no visible library of this kind survives the row's
  /// own source restriction. Distinct from a filter that matched nothing, and
  /// treated the same way on Home — an empty row is not drawn — but the panel
  /// tells the two apart.
  static const empty = HomeCustomRowContent(isExact: true);

  bool get isEmpty => groups.isEmpty;
  int get loadedCount => groups.length;
}

abstract class HomeCustomRowLoader {
  /// The first [limit] cards this row's filter yields, plus whether that is
  /// all of them.
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit});
}

class CatalogHomeCustomRowLoader implements HomeCustomRowLoader {
  CatalogHomeCustomRowLoader({
    required List<MediaLibrary> Function() libraries,
    required bool Function(ServerId serverId) isServerVisible,
    required Set<String> Function() hiddenLibraryKeys,
    required MediaServerClient? Function(ServerId serverId) clientFor,
  }) : _libraries = libraries,
       _isServerVisible = isServerVisible,
       _hiddenLibraryKeys = hiddenLibraryKeys,
       _clientFor = clientFor;

  final List<MediaLibrary> Function() _libraries;
  final bool Function(ServerId serverId) _isServerVisible;
  final Set<String> Function() _hiddenLibraryKeys;
  final MediaServerClient? Function(ServerId serverId) _clientFor;

  @override
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit}) async {
    // The source predicates run by leaving a cursor out of the merge, exactly
    // as the catalog executes them (`UnifiedCatalogFilterSelection.selects`).
    // Filtering after the merge would be both wasteful and wrong here: a row
    // asked for twelve cards would show three.
    final participating = eligibleCatalogLibraries(
      libraries: _libraries(),
      kind: row.kind,
      isServerVisible: _isServerVisible,
      hiddenLibraryKeys: _hiddenLibraryKeys(),
    ).where(row.filters.selects).toList();
    if (participating.isEmpty) return HomeCustomRowContent.empty;

    // Capabilities follow the *participating* set, so a row restricted to the
    // Plex and Jellyfin libraries keeps its genre filter even while a Pleya
    // Server library exists elsewhere in the catalog.
    final query = buildUnifiedCatalogQuery(
      kind: row.kind,
      preferences: row.preferences,
      capabilities: unifiedFilterCapabilitiesFor(participating.map((library) => library.backend)),
    );
    final service = UnifiedCatalogService(
      query: query,
      libraries: participating,
      clientFor: _clientFor,
      groupsPerPage: limit,
    );
    try {
      final snapshot = await service.loadMore();
      return HomeCustomRowContent(
        groups: snapshot.groups,
        isExact: snapshot.isComplete,
        isPartial: snapshot.failedLibraryIds.isNotEmpty,
      );
    } finally {
      // One question asked and answered. A cursor still inside its
      // progressive-loading grace has nobody left to report to, and leaving it
      // running would keep a request alive for a row that already drew.
      service.cancelInFlight();
    }
  }
}
