import '../../media/ids.dart';
import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';

/// Items pulled per layer, per library.
const int kRecentlyAddedLimit = 100;
const int kPerLibraryLimit = 40;

/// Libraries consulted per server. A media server with more than a handful of
/// movie and show libraries is unusual, and the cap keeps the call budget
/// provable.
const int kMaxLibraries = 6;

/// Upper bound on catalogue calls per server per [_deepTtl] window:
/// one library listing plus a top-rated and a rotating page for each library.
const int kMaxCatalogueCallsPerServer = 1 + 2 * kMaxLibraries;

/// Supplies a bounded pool of catalogue items for personalized-row scoring,
/// cached in memory per server so warm home loads issue zero extra fetches.
///
/// Four layers, because one was not enough to answer the questions the rows
/// ask. Recently-added alone can never fill a row that wants titles older than
/// ninety days, so "Hidden Gems" was structurally starved: a source problem
/// rather than something to tune. Top-rated brings quality depth, and a
/// deterministic rotating slice of the oldest additions brings the rest of the
/// catalogue into view a little at a time.
class CandidatePool {
  static const Duration _ttl = Duration(hours: 12);
  static const Duration _deepTtl = Duration(hours: 24);

  final int Function() _nowMs;

  CandidatePool({int Function()? clock}) : _nowMs = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Map<String, _Entry> _byServer = {};
  final Map<String, _Entry> _deepByServer = {};

  /// Fetches (or returns cached) candidate items across [clients], plus any
  /// [extra] items already loaded elsewhere (e.g. the discover hubs) for free.
  Future<List<MediaItem>> candidates(List<MediaServerClient> clients, {List<MediaItem> extra = const []}) async {
    final now = _nowMs();
    final recent = await Future.wait([for (final client in clients) _recentlyAdded(client, now)]);
    final deep = await Future.wait([for (final client in clients) _deepCatalogue(client, now)]);

    // Layer order is the dedup order, and it is deliberate: free items first,
    // then the cheapest fetch, then depth. A title present in two layers keeps
    // the copy from the earliest one, so the merge is stable across runs.
    final seen = <String>{};
    final merged = <MediaItem>[];
    for (final item in [...extra, ...recent.expand((r) => r), ...deep.expand((r) => r)]) {
      if (seen.add(item.globalKey)) merged.add(item);
    }
    return merged;
  }

  Future<List<MediaItem>> _recentlyAdded(MediaServerClient client, int now) async {
    final key = client.serverId.toString();
    final cached = _byServer[key];
    if (cached != null && now - cached.fetchedAtMs < _ttl.inMilliseconds) {
      return cached.items;
    }
    try {
      final items = await client.fetchRecentlyAdded(limit: kRecentlyAddedLimit);
      _byServer[key] = _Entry(items: items, fetchedAtMs: now);
      return items;
    } catch (e, s) {
      appLogger.w('CandidatePool: fetchRecentlyAdded failed for $key', error: e, stackTrace: s);
      return cached?.items ?? const <MediaItem>[];
    }
  }

  /// Top-rated plus a rotating slice of the oldest additions, per library.
  ///
  /// Every layer swallows its own failure into an empty list: a server that
  /// cannot list libraries should cost the rows depth, never the whole feed.
  Future<List<MediaItem>> _deepCatalogue(MediaServerClient client, int now) async {
    final key = client.serverId.toString();
    final cached = _deepByServer[key];
    if (cached != null && now - cached.fetchedAtMs < _deepTtl.inMilliseconds) {
      return cached.items;
    }

    List<MediaLibrary> libraries;
    try {
      libraries = await client.fetchLibraries();
    } catch (e, s) {
      appLogger.w('CandidatePool: fetchLibraries failed for $key', error: e, stackTrace: s);
      return cached?.items ?? const <MediaItem>[];
    }

    final usable = libraries
        .where((l) => !l.hidden && (l.kind == MediaKind.movie || l.kind == MediaKind.show))
        .take(kMaxLibraries)
        .toList();

    final items = <MediaItem>[];
    var calls = 1; // fetchLibraries
    for (final library in usable) {
      // The top-rated page already reports totalCount, so the rotating slice
      // gets its offset for free instead of spending a probe call on it. That
      // is what keeps the budget at exactly two calls per library.
      final top = await _topRated(client, library);
      items.addAll(top.items);
      items.addAll(await _rotatingOldest(client, library, now, totalCount: top.totalCount));
      calls += 2;
    }
    // The budget is a real contract, not a comment: this layer runs behind the
    // discover feed and a regression here would quietly multiply catalogue
    // traffic on every server.
    assert(
      calls <= kMaxCatalogueCallsPerServer,
      'CandidatePool spent $calls catalogue calls on one server, over the '
      'budget of $kMaxCatalogueCallsPerServer',
    );
    _deepByServer[key] = _Entry(items: items, fetchedAtMs: now);
    return items;
  }

  Future<({List<MediaItem> items, int totalCount})> _topRated(MediaServerClient client, MediaLibrary library) async {
    try {
      final page = await client.fetchLibraryPagedContent(
        library.id,
        query: const LibraryQuery(
          limit: kPerLibraryLimit,
          sort: LibrarySort(field: 'rating', direction: LibrarySortDirection.descending),
        ),
        libraryKind: library.kind,
      );
      return (items: page.items, totalCount: page.totalCount);
    } catch (e) {
      appLogger.w('CandidatePool: top-rated page failed for library ${library.id}', error: e);
      return (items: const <MediaItem>[], totalCount: 0);
    }
  }

  /// A window into the *oldest* additions, moved along one page per day.
  ///
  /// Ascending on `addedAt` is what makes this useful: it surfaces the back of
  /// the catalogue, which is exactly what a "hidden gems" row is looking for
  /// and precisely what a recently-added feed can never contain. The offset is
  /// derived from the day bucket, so it is stable within a day (and therefore
  /// testable) while still rotating over time.
  Future<List<MediaItem>> _rotatingOldest(
    MediaServerClient client,
    MediaLibrary library,
    int now, {
    required int totalCount,
  }) async {
    final span = totalCount - kPerLibraryLimit;
    final offset = span <= 0 ? 0 : (now ~/ Duration.millisecondsPerDay * kPerLibraryLimit) % span;
    try {
      final page = await client.fetchLibraryPagedContent(
        library.id,
        query: LibraryQuery(
          offset: offset,
          limit: kPerLibraryLimit,
          sort: const LibrarySort(field: 'addedAt', direction: LibrarySortDirection.ascending),
        ),
        libraryKind: library.kind,
      );
      return page.items;
    } catch (e) {
      appLogger.w('CandidatePool: rotating page failed for library ${library.id}', error: e);
      return const [];
    }
  }

  void invalidate([ServerId? serverId]) {
    if (serverId == null) {
      _byServer.clear();
      _deepByServer.clear();
    } else {
      _byServer.remove(serverId.toString());
      _deepByServer.remove(serverId.toString());
    }
  }
}

class _Entry {
  final List<MediaItem> items;
  final int fetchedAtMs;
  const _Entry({required this.items, required this.fetchedAtMs});
}
