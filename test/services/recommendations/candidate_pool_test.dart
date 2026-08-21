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
    if (failPages) throw Exception('no');
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
