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
/// **B6: a mixed library has no single global [MediaKind], so it may not be
/// excluded from either catalog by one.** [MediaLibrary.kind] reads
/// [MediaKind.unknown] for exactly this case — Jellyfin's own "Mixed
/// content" `CollectionType`, or a Plex section this codebase's own
/// [MediaKind.fromString] does not recognise — and such a library is
/// therefore eligible for *every* [kind], never excluded by this check.
/// That is safe, not a guess: [UnifiedCatalogService] always asks each
/// participating library for one concrete [kind] on the wire (Plex's
/// `type=`, Jellyfin's `IncludeItemTypes`), so the server itself does the
/// item-level classification a mixed library needs — a movie surfaces only
/// under the Films query, a show only under Series, and a genre this library
/// holds neither of (music, photos) simply answers empty rather than
/// guessed. A concrete, *non-matching* kind (a music library's `artist`, when
/// [kind] is `movie`) is excluded exactly as before — only [MediaKind.unknown]
/// gets this treatment, because only it means "we cannot say", not "we can
/// say, and it is something else."
///
/// Pure and headless on purpose: this is the k-way merge engine's own input,
/// not the reactive `LibrariesProvider`/`MultiServerProvider` wiring that
/// `unified_catalog_provider.dart` (also fase 3) does. Every input here is a
/// plain value, so this is testable without a widget tree or `ChangeNotifier`, and
/// the provider can call it directly once it exists.
List<CatalogLibrary> eligibleCatalogLibraries({
  required List<MediaLibrary> libraries,
  required MediaKind kind,
  required bool Function(ServerId serverId) isServerVisible,
  required Set<String> hiddenLibraryKeys,
}) {
  final result = <CatalogLibrary>[];
  for (final library in libraries) {
    if (library.kind != kind && library.kind != MediaKind.unknown) continue;
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

  /// True once this library has reported every item it has. A cursor never
  /// fetches again once this is set.
  ///
  /// Decided from the concrete page protocol (E8) — an empty page, a page
  /// shorter than requested, or [lastFetchedItemKeys] catching a stalled
  /// offset — never from [sourceTotal] alone.
  bool exhausted = false;

  /// The library's own reported total, once a page has answered. Null before
  /// the first successful fetch — hoofdstuk 12's DoD forbids claiming an
  /// exact catalog total before every cursor has reported one.
  ///
  /// **Advisory only (E8).** A backend's `totalCount` can rise, fall or be
  /// briefly inconsistent while a library changes underneath the merge —
  /// nothing here treats it as ground truth. It still feeds progress copy and
  /// diagnostics; [exhausted] is decided from the concrete page protocol
  /// instead (see [UnifiedCatalogService]'s own fetch loop): an empty page, a
  /// short page, or [lastFetchedItemKeys] catching a page that never actually
  /// advanced.
  int? sourceTotal;

  /// The `globalKey`s [UnifiedCatalogService] fetched on this cursor's most
  /// recent successful page, in order — E8's no-progress guard.
  ///
  /// Offset paging assumes the server honours the offset it was given.
  /// `sourceTotal` lying was one way that assumption could go wrong;
  /// `offset` being silently ignored is the other, and it does not show up as
  /// an empty or short page — the backend keeps answering with a full page,
  /// just always the *same* one. Comparing this against the next page's own
  /// keys is what turns that into a page nobody can silently loop on forever,
  /// without needing `sourceTotal` at all.
  List<String>? lastFetchedItemKeys;

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

  /// The in-flight fetch itself, so a caller that has *nothing else to show*
  /// can wait for it rather than reporting an empty catalog over a library
  /// that is merely slow. [fetchInFlight] stays the authority on whether
  /// anything is running; this is only how to await it.
  Future<void>? pending;

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
