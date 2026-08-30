/// One participating library's position in the unified catalog's k-way merge
/// (hoofdstuk 12.1 of docs/tvos-unified-experience.md). Mutable — owned
/// exclusively by [UnifiedCatalogService] (`catalog_service.dart`), one per
/// library for the lifetime of one query.
library;

import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/media_server_http_client.dart';

/// A library eligible to participate in a unified catalog session — already
/// server- and library-visibility-filtered by the caller (hoofdstuk 22:
/// "vóór grouping" — see [eligibleCatalogLibraries]).
typedef CatalogLibrary = ({
  ServerId serverId,
  String serverName,
  String libraryId,
  String libraryTitle,
  MediaBackend backend,
});

/// Which of [libraries] a unified catalog session for [kind] may use.
///
/// Applies hoofdstuk 22's visibility boundary at both levels it names —
/// "actief profiel; zichtbare servers; zichtbare libraries" — before any
/// item from these libraries can reach the k-way merge or the identity
/// pipeline: [isServerVisible] is the same predicate
/// `DataAggregationService._clientsFor` and fase 2's [SourceAllResolver]
/// already enforce for server visibility, and [hiddenLibraryKeys] is the
/// existing client-side per-library hide list (`HiddenLibrariesProvider`,
/// already used the same way by `DataAggregationService.getOnDeckFromAllServers`
/// and friends). A library outside either set never becomes a
/// [CatalogLibrary] — hoofdstuk 31 rule 13 forbids counting a hidden library
/// at all, not just hiding it after the fact.
///
/// Pure and headless on purpose: hoofdstuk 27 fase 3 is the k-way merge
/// engine, not the reactive `LibrariesProvider`/`MultiServerProvider` wiring
/// (`unified_catalog_provider.dart`, deferred). Every input here is a plain
/// value, so this is testable without a widget tree or `ChangeNotifier`, and
/// the provider can call it directly once it exists.
List<CatalogLibrary> eligibleCatalogLibraries({
  required List<MediaLibrary> libraries,
  required MediaKind kind,
  required bool Function(ServerId serverId) isServerVisible,
  required Set<String> hiddenLibraryKeys,
}) {
  final result = <CatalogLibrary>[];
  for (final library in libraries) {
    if (library.kind != kind) continue;
    final rawServerId = library.serverId;
    if (rawServerId == null || rawServerId.isEmpty) continue;
    final serverId = ServerId(rawServerId);
    if (!isServerVisible(serverId)) continue;
    if (library.hidden) continue;
    if (hiddenLibraryKeys.contains(library.globalKey)) continue;
    result.add((
      serverId: serverId,
      serverName: library.serverName ?? rawServerId,
      libraryId: library.id,
      libraryTitle: library.title,
      backend: library.backend,
    ));
  }
  return result;
}

class UnifiedSourceCursor {
  UnifiedSourceCursor(this.library);

  final CatalogLibrary library;

  /// `serverId:libraryId` — this cursor's stable identity, distinct from any
  /// single item's own key.
  String get libraryGlobalKey => buildGlobalKey(library.serverId, library.libraryId);

  int offset = 0;

  /// Items fetched but not yet popped by the merge. Bounded to at most one
  /// page (hoofdstuk 12.7's buffercap) — a cursor never holds more than the
  /// page it most recently fetched.
  final List<MediaItem> buffer = [];

  /// True once this library has reported every item it has — [offset] has
  /// reached its last known [sourceTotal]. A cursor never fetches again once
  /// this is set.
  bool exhausted = false;

  /// The library's own reported total, once a page has answered. Null before
  /// the first successful fetch — hoofdstuk 12's DoD forbids claiming an
  /// exact catalog total before every cursor has reported one.
  int? sourceTotal;

  /// The most recent fetch failure, if any. Cleared on the next successful
  /// fetch. A cursor with a [lastError] is retried on the *next*
  /// `UnifiedCatalogService.loadMore` call rather than being marked
  /// [exhausted] — hoofdstuk 12.6: one failure never permanently drops a
  /// library from the merge.
  Object? lastError;

  /// True while a page fetch for this cursor is in flight, so
  /// `UnifiedCatalogService` never dispatches two concurrent fetches for the
  /// same library.
  bool fetchInFlight = false;

  /// Cancels this cursor's in-flight fetch, if any (hoofdstuk 12.7: a
  /// query/filter change abandons old requests via generation IDs and abort
  /// controllers — this is the abort-controller half; the service's own
  /// generation counter is the other).
  AbortController? inFlight;

  bool get hasBufferedItem => buffer.isNotEmpty;

  MediaItem get head => buffer.first;

  MediaItem popHead() => buffer.removeAt(0);

  /// Worth asking for another page: not exhausted, and no fetch already in
  /// flight for it.
  bool get isFetchable => !exhausted && !fetchInFlight;
}
