import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';
import 'local_library_store_test.dart' show film, library;
import 'local_library_sync_test.dart' show Client;

void main() {
  late Directory root;
  late LocalLibraryStore store;
  late DateTime now;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-artwork-test-');
    store = LocalLibraryStore(root);
    await store.load();
    now = DateTime.utc(2026, 1, 1);
  });
  tearDown(() async => root.delete(recursive: true));

  test('same ID validates over HTTP: changed bytes replace identity; 304 performs no image write', () async {
    final item = film('a');
    await store.saveLibrary(library, [item], complete: true);
    var version = 1;
    var requests = 0;
    var bodyBytes = 0;
    final httpClient = MockClient((request) async {
      requests++;
      expect(request.headers['Cache-Control'], 'no-cache');
      if (request.headers['If-None-Match'] == '"$version"') {
        return http.Response('', 304, headers: {'etag': '"$version"'});
      }
      bodyBytes += 3;
      return http.Response.bytes([version, 2, 3], 200, headers: {'etag': '"$version"'});
    });
    Future<void> sync() => LocalLibrarySync(
      store: store,
      clock: () => now,
      posterRevalidator: (_, _, validators) =>
          revalidateLocalPoster('https://fixture.invalid/artwork/same?width=720', validators, transport: httpClient),
    ).syncPosters([item], (_) => Client(), isCurrent: () => true);
    await sync();
    final first = store.posterPath('one', item.thumbPath!)!;
    now = now.add(const Duration(minutes: 10));
    version = 2;
    await sync();
    final second = store.posterPath('one', item.thumbPath!)!;
    expect(second, isNot(first));
    expect(await File(second).readAsBytes(), [2, 2, 3]);
    final stat = await File(second).stat();
    now = now.add(const Duration(minutes: 10));
    await sync();
    expect(store.posterPath('one', item.thumbPath!), second);
    expect((await File(second).stat()).modified, stat.modified);
    expect(requests, 3);
    expect(bodyBytes, 6);
    expect(
      await Directory('${root.path}/posters').list().length,
      2,
      reason: '304 creates no third image; old version is retired by the existing complete-scan prune',
    );
    print('TASK4 same-ID: requests=$requests 200_body_bytes=$bodyBytes image_writes=2 304_writes=0');
  });

  test('HTTP fallback validators, variant changes, errors and oversized bodies', () async {
    const url = 'https://fixture.invalid/art?width=720&api_key=secret';
    final fresh = await revalidateLocalPoster(
      url,
      {},
      transport: MockClient((request) async {
        expect(request.headers['If-None-Match'], isNull);
        return http.Response.bytes([1], 200, headers: {'last-modified': 'Wed, 01 Jan 2025 00:00:00 GMT'});
      }),
    );
    expect(fresh.variant, isNot(contains('secret')));
    await revalidateLocalPoster(
      url,
      {'variant': fresh.variant, 'lastModified': fresh.lastModified},
      transport: MockClient((request) async {
        expect(request.headers['If-Modified-Since'], fresh.lastModified);
        return http.Response('', 304);
      }),
    );
    await revalidateLocalPoster(
      'https://fixture.invalid/art?width=960',
      {'variant': fresh.variant, 'etag': 'old'},
      transport: MockClient((request) async {
        expect(request.headers['If-None-Match'], isNull);
        return http.Response.bytes([2], 200);
      }),
    );
    for (final status in [304, 401, 404, 429, 500]) {
      await expectLater(
        revalidateLocalPoster(url, {}, transport: MockClient((_) async => http.Response('', status))),
        throwsStateError,
      );
    }
    await expectLater(
      revalidateLocalPoster(url, {}, transport: MockClient((_) async => http.Response('', 200))),
      throwsStateError,
    );
    await expectLater(
      revalidateLocalPoster(
        url,
        {},
        transport: MockClient((_) async => http.Response.bytes(Uint8List(12 * 1024 * 1024 + 1), 200)),
      ),
      throwsStateError,
    );
  });

  test('missing file drops validators; offline error keeps last valid bytes and successful timestamp', () async {
    final item = film('a');
    var error = false;
    var validations = 0;
    Future<void> sync() => LocalLibrarySync(
      store: store,
      clock: () => now,
      posterRevalidator: (_, _, validators) async {
        validations++;
        if (error) throw const SocketException('synthetic offline');
        expect(validators['etag'], isNull);
        return LocalPosterResult(bytes: Uint8List.fromList([1]), variant: 'v', etag: 'e');
      },
    ).syncPosters([item], (_) => Client(), isCurrent: () => true);
    await sync();
    final old = store.posterPath('one', item.thumbPath!)!;
    final validated = store.posterFreshness('one', item.thumbPath!)['validated'];
    error = true;
    now = now.add(const Duration(minutes: 10));
    await sync();
    expect(store.posterPath('one', item.thumbPath!), old);
    expect(store.posterFreshness('one', item.thumbPath!)['validated'], validated);
    await sync();
    expect(validations, 2, reason: 'failure cannot occupy this interval again');
    await File(old).delete();
    now = now.add(const Duration(minutes: 10));
    error = false;
    await sync();
    expect(store.posterPath('one', item.thumbPath!), isNotNull);
  });

  test('pilot is fair beyond 60 with repeated priority, persistent failure and restart', () async {
    final items = [for (var i = 0; i < 121; i++) film('$i').copyWith(thumbPath: '/poster/$i')];
    await store.saveLibrary(library, items, complete: true);
    final touched = <String>{};
    var active = 0;
    var maxActive = 0;
    var requests = 0;
    var bodyBytes = 0;
    for (var round = 0; round < 5; round++) {
      for (final i in items.take(20)) store.prioritizePoster('one', i.thumbPath!);
      final before = requests;
      final sync = LocalLibrarySync(
        store: store,
        clock: () => now,
        posterRevalidator: (_, item, state) async {
          requests++;
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(Duration.zero);
          active--;
          touched.add(item.id);
          if (item.id == '0') throw const SocketException('persistent fixture failure');
          if (state['etag'] != null) return LocalPosterResult(variant: item.thumbPath!, etag: 'e');
          bodyBytes += 4;
          return LocalPosterResult(bytes: Uint8List.fromList([1, 2, 3, 4]), variant: item.thumbPath!, etag: 'e');
        },
      );
      await sync.syncPosters(items, (_) => Client(), isCurrent: () => true);
      expect(requests - before, lessThanOrEqualTo(60));
      final after = requests;
      store = LocalLibraryStore(root);
      await store.load();
      await LocalLibrarySync(
        store: store,
        clock: () => now,
        posterRevalidator: (_, _, _) async {
          throw StateError('must not repeat after reopening');
        },
      ).syncPosters(items, (_) => Client(), isCurrent: () => true);
      expect(requests, after);
      now = now.add(const Duration(minutes: 10));
    }
    expect(touched, hasLength(121));
    expect(maxActive, 1);
    expect(bodyBytes, 120 * 4);
    expect(await Directory('${root.path}/posters').list().length, 120);
    print(
      'TASK4 pilot: items=121 rounds=5 requests=$requests 200_body_bytes=$bodyBytes image_writes=120 max_inflight=$maxActive',
    );
  });

  for (final boundary in ['clear', 'revoke', 'profile', 'provider']) {
    test('$boundary rejects late artwork response and validation state', () async {
      final item = film('a');
      final entered = Completer<void>();
      final gate = Completer<LocalPosterResult>();
      var current = true;
      final pending = LocalLibrarySync(
        store: store,
        clock: () => now,
        posterRevalidator: (_, _, _) {
          entered.complete();
          return gate.future;
        },
      ).syncPosters([item], (_) => Client(), isCurrent: () => current);
      await entered.future;
      current = false;
      if (boundary == 'clear') await store.clear();
      gate.complete(LocalPosterResult(bytes: Uint8List.fromList([99]), variant: 'v', etag: 'new'));
      await expectLater(pending, throwsA(isA<LocalLibraryPaused>()));
      expect(store.posterPath('one', item.thumbPath!), isNull);
      expect(store.posterFreshness('one', item.thumbPath!)['validated'], isNull);
      expect(await root.list(recursive: true).where((f) => f.path.endsWith('.pending')).isEmpty, isTrue);
    });
  }

  test('staggered syncs retain the rolling ten-minute priority and oldest budgets after restart', () async {
    final items = [for (var i = 0; i < 120; i++) film('$i').copyWith(thumbPath: '/poster/$i')];
    var calls = 0;
    Future<void> sync() => LocalLibrarySync(
      store: store,
      clock: () => now,
      posterRevalidator: (_, item, _) async {
        calls++;
        return LocalPosterResult(bytes: Uint8List.fromList([1]), variant: item.thumbPath!);
      },
    ).syncPosters(items, (_) => Client(), isCurrent: () => true);
    await sync();
    expect(calls, 40);
    now = now.add(const Duration(minutes: 9));
    for (final item in items.skip(40).take(20)) store.prioritizePoster('one', item.thumbPath!);
    await sync();
    expect(calls, 60);
    store = LocalLibraryStore(root);
    await store.load();
    now = now.add(const Duration(minutes: 1));
    for (final item in items.skip(60).take(20)) store.prioritizePoster('one', item.thumbPath!);
    await sync();
    expect(calls, 100, reason: 'only the 40 old slots expired; priority stays capped until minute 19');
    expect(store.posterBudget(now).total, 60);
  });

  test('revalidation ceiling is three across retiring and new profile callers', () async {
    final gates = [for (var i = 0; i < 4; i++) Completer<void>()];
    var entered = 0;
    var active = 0;
    var maxActive = 0;
    final client = MockClient((_) async {
      final index = entered++;
      active++;
      if (active > maxActive) maxActive = active;
      await gates[index].future;
      active--;
      return http.Response.bytes([1], 200);
    });
    final pending = [
      for (var i = 0; i < 4; i++) revalidateLocalPoster('https://fixture.invalid/$i', {}, transport: client),
    ];
    try {
      for (var spin = 0; entered < 3 && spin < 100; spin++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(entered, 3);
      expect(maxActive, 3);
      for (final gate in gates.take(3)) {
        gate.complete();
      }
      for (var spin = 0; entered < 4 && spin < 100; spin++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(entered, 4);
      gates.last.complete();
      await Future.wait(pending);
      expect(maxActive, 3);
    } finally {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future.wait(pending);
    }
  });

  test('policy denial starts no artwork request', () async {
    var calls = 0;
    await expectLater(
      LocalLibrarySync(
        store: store,
        mayContinue: () async => false,
        posterRevalidator: (_, _, _) async {
          calls++;
          return const LocalPosterResult(variant: 'v');
        },
      ).syncPosters([film('a')], (_) => Client(), isCurrent: () => true),
      throwsA(isA<LocalLibraryPaused>()),
    );
    expect(calls, 0);
  });
}
