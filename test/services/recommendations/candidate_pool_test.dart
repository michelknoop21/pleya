import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/recommendations/candidate_pool.dart';
import 'package:pleya/utils/media_server_http_client.dart';

const _nowMs = 1700000000000;

MediaItem _item(String id) => MediaItem.plex(id: id, kind: MediaKind.movie, serverId: 'srv', title: id);

class _FakeClient implements MediaServerClient {
  _FakeClient({
    this.libraries = const [],
    this.recent = const [],
    this.total = 1000,
    this.failLibraries = false,
    this.failRecent = false,
    this.failPages = false,
  });

  List<MediaLibrary> libraries;
  List<MediaItem> recent;
  int total;
  bool failLibraries;
  bool failRecent;
  bool failPages;

  /// Library ids whose pages fail, for the half-failed case that a single
  /// `failPages` flag cannot express.
  Set<String> failPagesFor = const {};

  /// Delay per page call, so overlapping work is observable rather than assumed.
  Duration pageDelay = Duration.zero;
  int pagesInFlight = 0;
  int peakPagesInFlight = 0;

  int recentCalls = 0;
  int libraryCalls = 0;
  final List<({String id, LibraryQuery query, MediaKind? kind})> pageCalls = [];

  @override
  ServerId get serverId => ServerId('srv');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 20}) async {
    recentCalls++;
    if (failRecent) throw Exception('no');
    return recent;
  }

  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    libraryCalls++;
    if (failLibraries) throw Exception('no');
    return libraries;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    pageCalls.add((id: libraryId, query: query, kind: libraryKind));
    pagesInFlight++;
    if (pagesInFlight > peakPagesInFlight) peakPagesInFlight = pagesInFlight;
    try {
      if (pageDelay > Duration.zero) await Future<void>.delayed(pageDelay);
    } finally {
      pagesInFlight--;
    }
    if (failPages || failPagesFor.contains(libraryId)) throw Exception('no');
    final sort = query.sort?.field ?? 'none';
    return LibraryPage(
      items: [for (var i = 0; i < 3; i++) _item('$libraryId-$sort-${query.offset}-$i')],
      totalCount: total,
      offset: query.offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String id, {MediaKind kind = MediaKind.movie, bool hidden = false}) =>
    MediaLibrary(id: id, backend: MediaBackend.plex, title: id, kind: kind, hidden: hidden);

/// A pool whose clock the test can move, for everything about expiry.
class _MovableClockPool {
  int now = _nowMs;
  late final CandidatePool pool = CandidatePool(clock: () => now);
}

void main() {
  CandidatePool pool({int? now}) => CandidatePool(clock: () => now ?? _nowMs);

  test('recently added alone still works', () async {
    final client = _FakeClient(recent: [_item('r1'), _item('r2')]);
    final items = await pool().candidates([client]);
    expect(items.map((i) => i.id), containsAll(['r1', 'r2']));
    expect(client.recentCalls, 1);
  });

  test('older catalogue depth reaches the pool', () async {
    // The point of the widening: a hidden-gems row wants titles the
    // recently-added feed structurally cannot contain.
    final client = _FakeClient(libraries: [_library('1')], recent: [_item('r1')]);
    final items = await pool().candidates([client]);

    final sorts = client.pageCalls.map((c) => c.query.sort!).toList();
    expect(sorts.map((s) => s.field), containsAll(['rating', 'addedAt']));
    final oldest = sorts.firstWhere((s) => s.field == 'addedAt');
    expect(oldest.direction, LibrarySortDirection.ascending, reason: 'ascending on addedAt is the *oldest* titles');
    expect(items.any((i) => i.id.contains('addedAt')), isTrue);
  });

  test('the library kind is passed through for Jellyfin show libraries', () async {
    final client = _FakeClient(libraries: [_library('1', kind: MediaKind.show)]);
    await pool().candidates([client]);
    expect(client.pageCalls.every((c) => c.kind == MediaKind.show), isTrue);
  });

  test('hidden and non-video libraries are left alone', () async {
    final client = _FakeClient(
      libraries: [
        _library('movies'),
        _library('hidden', hidden: true),
        _library('music', kind: MediaKind.unknown),
      ],
    );
    await pool().candidates([client]);
    expect(client.pageCalls.map((c) => c.id).toSet(), {'movies'});
  });

  test('the call budget holds even with many libraries', () async {
    final client = _FakeClient(libraries: [for (var i = 0; i < 20; i++) _library('lib$i')]);
    await pool().candidates([client]);
    final total = client.recentCalls + client.libraryCalls + client.pageCalls.length;
    expect(total, lessThanOrEqualTo(kMaxCatalogueCallsPerServer + 1), reason: 'plus one recently-added');
    expect(client.pageCalls.length, kMaxLibraries * 2);
  });

  test('a warm cache issues no further calls', () async {
    final client = _FakeClient(libraries: [_library('1')], recent: [_item('r1')]);
    final p = pool();
    await p.candidates([client]);
    final after = client.recentCalls + client.libraryCalls + client.pageCalls.length;
    await p.candidates([client]);
    expect(client.recentCalls + client.libraryCalls + client.pageCalls.length, after);
  });

  test('the rotating offset is stable within a day and moves the next day', () async {
    final client = _FakeClient(libraries: [_library('1')], total: 1000);
    await pool(now: _nowMs).candidates([client]);
    final first = client.pageCalls.firstWhere((c) => c.query.sort!.field == 'addedAt').query.offset;

    final again = _FakeClient(libraries: [_library('1')], total: 1000);
    await pool(now: _nowMs + 1000).candidates([again]);
    expect(again.pageCalls.firstWhere((c) => c.query.sort!.field == 'addedAt').query.offset, first);

    final tomorrow = _FakeClient(libraries: [_library('1')], total: 1000);
    await pool(now: _nowMs + Duration.millisecondsPerDay).candidates([tomorrow]);
    expect(tomorrow.pageCalls.firstWhere((c) => c.query.sort!.field == 'addedAt').query.offset, isNot(first));
  });

  test('a small library is not offset past its end', () async {
    final client = _FakeClient(libraries: [_library('1')], total: 5);
    await pool().candidates([client]);
    expect(client.pageCalls.firstWhere((c) => c.query.sort!.field == 'addedAt').query.offset, 0);
  });

  group('a failing layer stays contained', () {
    test('failing libraries still yields recently added', () async {
      final client = _FakeClient(failLibraries: true, recent: [_item('r1')]);
      expect((await pool().candidates([client])).map((i) => i.id), ['r1']);
    });

    test('failing pages still yields recently added', () async {
      final client = _FakeClient(libraries: [_library('1')], recent: [_item('r1')], failPages: true);
      expect((await pool().candidates([client])).map((i) => i.id), ['r1']);
    });

    test('failing recently added still yields catalogue depth', () async {
      final client = _FakeClient(libraries: [_library('1')], failRecent: true);
      expect(await pool().candidates([client]), isNotEmpty);
    });

    test('everything failing yields an empty pool, never an exception', () async {
      final client = _FakeClient(failLibraries: true, failRecent: true);
      expect(await pool().candidates([client]), isEmpty);
    });
  });

  group('an incomplete answer is not cached like a good one', () {
    // The failure this is about: one bad minute used to cost a full day of
    // catalogue depth. A page times out, the thin result is written with a
    // 24-hour stamp, and the rows never ask again even though the server came
    // back a minute later.
    test('a complete deep pass holds for the day; a half-failed one does not', () async {
      final healthy = _FakeClient(libraries: [_library('a'), _library('b')]);
      final healthyPool = _MovableClockPool();
      await healthyPool.pool.candidates([healthy]);
      final afterComplete = healthy.pageCalls.length;
      healthyPool.now += const Duration(hours: 1).inMilliseconds;
      await healthyPool.pool.candidates([healthy]);
      expect(healthy.pageCalls.length, afterComplete, reason: 'a complete answer is good for the full window');

      final flaky = _FakeClient(libraries: [_library('a'), _library('b')])..failPagesFor = {'b'};
      final flakyPool = _MovableClockPool();
      await flakyPool.pool.candidates([flaky]);
      final afterThin = flaky.pageCalls.length;
      flakyPool.now += const Duration(hours: 1).inMilliseconds;
      await flakyPool.pool.candidates([flaky]);
      expect(flaky.pageCalls.length, greaterThan(afterThin), reason: 'an incomplete answer is retried within the hour');
    });

    test('a recovered server replaces the thin pool with the full one', () async {
      final flaky = _FakeClient(libraries: [_library('a'), _library('b')])..failPagesFor = {'b'};
      final harness = _MovableClockPool();
      final thin = await harness.pool.candidates([flaky]);

      flaky.failPagesFor = const {};
      harness.now += const Duration(hours: 1).inMilliseconds;
      final full = await harness.pool.candidates([flaky]);

      expect(full.length, greaterThan(thin.length));
    });

    test('a thin answer never displaces a richer complete one', () async {
      final client = _FakeClient(libraries: [_library('a'), _library('b')]);
      final harness = _MovableClockPool();
      final complete = await harness.pool.candidates([client]);

      // A day on the entry has expired, and this time half the server is down.
      client.failPagesFor = {'a', 'b'};
      harness.now += const Duration(hours: 25).inMilliseconds;
      final degraded = await harness.pool.candidates([client]);

      expect(degraded.length, complete.length, reason: 'the richer previous answer is kept, not overwritten');
    });

    test('a failed recently-added pass keeps serving the previous items', () async {
      final client = _FakeClient(recent: [_item('r1'), _item('r2')]);
      final harness = _MovableClockPool();
      expect((await harness.pool.candidates([client])).length, 2);

      client.failRecent = true;
      harness.now += const Duration(hours: 13).inMilliseconds;
      expect((await harness.pool.candidates([client])).map((i) => i.id), ['r1', 'r2']);

      // …and does not hammer the server while it stays down.
      final callsAfterFailure = client.recentCalls;
      await harness.pool.candidates([client]);
      expect(client.recentCalls, callsAfterFailure, reason: 'the stale answer holds for the retry window');
    });
  });

  group('stale data eventually retires', () {
    // The trap this closes: re-stamping the whole entry on every failed retry
    // makes a two-day-old pool look fresh forever, so a title deleted from the
    // server keeps being recommended for as long as the server stays down.
    test('a server that stays down stops contributing instead of ageing forever', () async {
      final client = _FakeClient(recent: [_item('r1')], libraries: [_library('a')]);
      final harness = _MovableClockPool();
      expect(await harness.pool.candidates([client]), isNotEmpty);

      client
        ..failRecent = true
        ..failLibraries = true;

      // A day in, the previous answer is still the best there is.
      harness.now += const Duration(hours: 24).inMilliseconds;
      expect(await harness.pool.candidates([client]), isNotEmpty);

      // Two days in, it is simply too old to keep passing off as a catalogue.
      harness.now += const Duration(hours: 25).inMilliseconds;
      expect(await harness.pool.candidates([client]), isEmpty);
    });

    test('failed retries throttle without making the data look younger', () async {
      final client = _FakeClient(recent: [_item('r1')]);
      final harness = _MovableClockPool();
      await harness.pool.candidates([client]);
      client.failRecent = true;

      // Well past the normal window, so every pass from here is a retry.
      harness.now += const Duration(hours: 13).inMilliseconds;
      var attempts = 0;
      for (var i = 0; i < 8; i++) {
        harness.now += const Duration(minutes: 20).inMilliseconds;
        final before = client.recentCalls;
        await harness.pool.candidates([client]);
        if (client.recentCalls > before) attempts++;
      }
      expect(attempts, 8, reason: 'one retry per window, not one per home load');

      // …and the data still ages out on its own clock despite all those retries.
      harness.now += const Duration(hours: 48).inMilliseconds;
      expect(await harness.pool.candidates([client]), isEmpty);
    });
  });

  group('libraries are fetched side by side', () {
    test('within the same call budget', () async {
      final client = _FakeClient(libraries: [for (var i = 0; i < 6; i++) _library('lib$i')])
        ..pageDelay = const Duration(milliseconds: 5);
      await pool().candidates([client]);

      expect(client.pageCalls.length, kMaxLibraries * 2, reason: 'still exactly two calls per library');
      expect(client.peakPagesInFlight, greaterThan(1), reason: 'the libraries genuinely overlap');
      expect(
        client.peakPagesInFlight,
        lessThanOrEqualTo(kLibraryConcurrency),
        reason: 'bounded: one page per library at a time, at most kLibraryConcurrency libraries',
      );
    });

    test('one failing library does not hold up or empty the others', () async {
      final client = _FakeClient(libraries: [_library('a'), _library('b'), _library('c')])..failPagesFor = {'b'};
      final items = await pool().candidates([client]);

      expect(items.any((i) => i.id.startsWith('a-')), isTrue);
      expect(items.any((i) => i.id.startsWith('c-')), isTrue);
      expect(items.any((i) => i.id.startsWith('b-')), isFalse);
    });

    test('the merged order follows the library listing, not who answered first', () async {
      final client = _FakeClient(libraries: [_library('a'), _library('b'), _library('c')]);
      final items = await pool().candidates([client]);
      int firstOf(String lib) => items.indexWhere((i) => i.id.startsWith('$lib-'));
      expect(firstOf('a'), isNonNegative);
      expect(firstOf('a'), lessThan(firstOf('b')));
      expect(firstOf('b'), lessThan(firstOf('c')));
    });
  });

  test('extras come first and deduplication is stable', () async {
    final shared = _item('shared');
    final client = _FakeClient(libraries: [_library('1')], recent: [shared, _item('r1')]);
    final items = await pool().candidates([client], extra: [shared, _item('e1')]);
    expect(items.map((i) => i.id).take(2), ['shared', 'e1']);
    expect(items.where((i) => i.id == 'shared'), hasLength(1));
  });

  test('invalidate clears every layer', () async {
    final client = _FakeClient(libraries: [_library('1')], recent: [_item('r1')]);
    final p = pool();
    await p.candidates([client]);
    p.invalidate();
    await p.candidates([client]);
    expect(client.recentCalls, 2);
    expect(client.libraryCalls, 2);
  });
}
