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

/// Libraries fetched at once, **per server**. The per-library work is two
/// dependent calls (the second needs the first's `totalCount`), so the
/// parallelism has to sit across libraries rather than inside one.
///
/// Bounded, but be honest about what it bounds: [CandidatePool.candidates]
/// already fans out over every online client at once, so the ceiling is this
/// number times the server count, not this number. Three keeps a single server
/// from opening six sockets behind a screen that is already drawn; a global
/// cap would have to live in `candidates` and is not what this is.
const int kLibraryConcurrency = 3;

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

  /// How long to wait before trying again after an incomplete answer.
  ///
  /// A failed or half-failed fetch used to be cached exactly like a good one,
  /// so one bad minute cost a full day of catalogue depth: three libraries time
  /// out, the thin result is written with a 24-hour stamp, and the rows never
  /// ask again even though the server came back a minute later. Something is
  /// still cached, because re-fetching on every home load while a server is
  /// down is the other way to get this wrong.
  static const Duration _retryTtl = Duration(minutes: 15);

  /// How old the *data* may get, no matter how often a refresh has failed.
  ///
  /// The retry stamp and the data stamp have to be separate fields or this goes
  /// wrong in a way that is easy to miss: re-stamping the whole entry on every
  /// failed retry makes a two-day-old pool look fresh forever, and titles that
  /// were deleted from the server keep being recommended. Past this age the
  /// entry is dropped and the layer contributes nothing, which is the honest
  /// answer for a server nobody has been able to reach in two days.
  static const Duration _maxStaleAge = Duration(hours: 48);

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
    if (_isFresh(cached, now, _ttl)) return cached!.items;
    try {
      final items = await client.fetchRecentlyAdded(limit: kRecentlyAddedLimit);
      _byServer[key] = _Entry(items: items, fetchedAtMs: now, lastAttemptMs: now, complete: true);
      return items;
    } catch (e, s) {
      appLogger.w('CandidatePool: fetchRecentlyAdded failed for $key', error: e, stackTrace: s);
      return _keepStale(_byServer, key, cached, now);
    }
  }

  /// Serve what was cached before, under the short retry window.
  ///
  /// Two failure modes to avoid at once. Writing the failure as a fresh entry
  /// hides a recovered server for the full TTL; writing nothing re-fetches on
  /// every single home load for as long as the server stays down. Re-stamping
  /// only the *attempt* time does neither, and leaving the data's own timestamp
  /// alone is what lets [_maxStaleAge] eventually retire it. With nothing
  /// cached there is nothing to stamp and the next load simply tries again.
  static List<MediaItem> _keepStale(Map<String, _Entry> into, String key, _Entry? cached, int now) {
    if (cached == null) return const <MediaItem>[];
    if (now - cached.fetchedAtMs >= _maxStaleAge.inMilliseconds) {
      into.remove(key);
      return const <MediaItem>[];
    }
    into[key] = _Entry(items: cached.items, fetchedAtMs: cached.fetchedAtMs, lastAttemptMs: now, complete: false);
    return cached.items;
  }

  /// Whether a cached answer may be served without asking again.
  ///
  /// Two clocks, deliberately. [_Entry.fetchedAtMs] is how old the items are
  /// and never moves once they are cached; [_Entry.lastAttemptMs] is when a
  /// refresh was last attempted and is what throttles retries. A complete entry
  /// stands for its full [ttl]; an incomplete one only until the next retry is
  /// due, and never past [_maxStaleAge] whatever happens.
  static bool _isFresh(_Entry? entry, int now, Duration ttl) {
    if (entry == null) return false;
    if (now - entry.fetchedAtMs >= _maxStaleAge.inMilliseconds) return false;
    if (entry.complete) return now - entry.fetchedAtMs < ttl.inMilliseconds;
    return now - entry.lastAttemptMs < _retryTtl.inMilliseconds;
  }

  /// Top-rated plus a rotating slice of the oldest additions, per library.
  ///
  /// Every layer swallows its own failure into an empty list: a server that
  /// cannot list libraries should cost the rows depth, never the whole feed.
  Future<List<MediaItem>> _deepCatalogue(MediaServerClient client, int now) async {
    final key = client.serverId.toString();
    final cached = _deepByServer[key];
    if (_isFresh(cached, now, _deepTtl)) return cached!.items;

    List<MediaLibrary> libraries;
    try {
      libraries = await client.fetchLibraries();
    } catch (e, s) {
      appLogger.w('CandidatePool: fetchLibraries failed for $key', error: e, stackTrace: s);
      return _keepStale(_deepByServer, key, cached, now);
    }

    final usable = libraries
        .where((l) => !l.hidden && (l.kind == MediaKind.movie || l.kind == MediaKind.show))
        .take(kMaxLibraries)
        .toList();

    // Libraries in bounded parallel, the two calls within one library still in
    // order: the top-rated page reports totalCount, so the rotating slice gets
    // its offset from it for free instead of spending a probe call. That is
    // what keeps the budget at exactly two calls per library, and running the
    // libraries side by side does not spend a single call more.
    final perLibrary = <_LibraryResult>[];
    var calls = 1; // fetchLibraries
    for (var i = 0; i < usable.length; i += kLibraryConcurrency) {
      final slice = usable.skip(i).take(kLibraryConcurrency).toList();
      perLibrary.addAll(await Future.wait([for (final library in slice) _forLibrary(client, library, now)]));
      calls += 2 * slice.length;
    }
    // The budget is a real contract, not a comment: this layer runs behind the
    // discover feed and a regression here would quietly multiply catalogue
    // traffic on every server.
    assert(
      calls <= kMaxCatalogueCallsPerServer,
      'CandidatePool spent $calls catalogue calls on one server, over the '
      'budget of $kMaxCatalogueCallsPerServer',
    );

    // Order is stable regardless of which library answered first, because the
    // results are consumed in the order the libraries were listed.
    final items = [for (final result in perLibrary) ...result.items];
    final complete = perLibrary.every((r) => r.complete);
    if (!complete) {
      appLogger.w(
        'CandidatePool: ${perLibrary.where((r) => !r.complete).length} of ${perLibrary.length} libraries on $key '
        'answered incompletely, keeping the thin pool for $_retryTtl only',
      );
      // A previous complete answer beats a fresh thin one, so it is kept —
      // re-stamped as incomplete, which is what puts it on the short window.
      if (cached != null && cached.complete && items.length < cached.items.length) {
        return _keepStale(_deepByServer, key, cached, now);
      }
    }
    _deepByServer[key] = _Entry(items: items, fetchedAtMs: now, lastAttemptMs: now, complete: complete);
    return items;
  }

  /// Both calls for one library, and whether they both actually answered.
  Future<_LibraryResult> _forLibrary(MediaServerClient client, MediaLibrary library, int now) async {
    final top = await _topRated(client, library);
    final rotating = await _rotatingOldest(client, library, now, totalCount: top.totalCount);
    return _LibraryResult(items: [...top.items, ...rotating.items], complete: top.ok && rotating.ok);
  }

  Future<({List<MediaItem> items, int totalCount, bool ok})> _topRated(
    MediaServerClient client,
    MediaLibrary library,
  ) async {
    try {
      final page = await client.fetchLibraryPagedContent(
        library.id,
        query: const LibraryQuery(
          limit: kPerLibraryLimit,
          sort: LibrarySort(field: 'rating', direction: LibrarySortDirection.descending),
        ),
        libraryKind: library.kind,
      );
      return (items: page.items, totalCount: page.totalCount, ok: true);
    } catch (e) {
      appLogger.w('CandidatePool: top-rated page failed for library ${library.id}', error: e);
      return (items: const <MediaItem>[], totalCount: 0, ok: false);
    }
  }

  /// A window into the *oldest* additions, moved along one page per day.
  ///
  /// Ascending on `addedAt` is what makes this useful: it surfaces the back of
  /// the catalogue, which is exactly what a "hidden gems" row is looking for
  /// and precisely what a recently-added feed can never contain. The offset is
  /// derived from the day bucket, so it is stable within a day (and therefore
  /// testable) while still rotating over time.
  Future<({List<MediaItem> items, bool ok})> _rotatingOldest(
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
      return (items: page.items, ok: true);
    } catch (e) {
      appLogger.w('CandidatePool: rotating page failed for library ${library.id}', error: e);
      return (items: const <MediaItem>[], ok: false);
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

  /// When these items came off the server. Never moved by a failed retry, so
  /// it stays an honest age for the data.
  final int fetchedAtMs;

  /// When a refresh was last attempted, which is what throttles retries.
  final int lastAttemptMs;

  /// Whether every call behind these items actually answered. An incomplete
  /// entry is still served, but expires far sooner.
  final bool complete;

  const _Entry({required this.items, required this.fetchedAtMs, required this.lastAttemptMs, required this.complete});
}

class _LibraryResult {
  final List<MediaItem> items;
  final bool complete;
  const _LibraryResult({required this.items, required this.complete});
}
