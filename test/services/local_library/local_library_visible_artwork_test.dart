import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image_ce/cached_network_image.dart';
// ignore: implementation_imports
import 'package:cached_network_image_ce/src/cache/default_cache_manager.dart' as ce;
import 'package:file/file.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pleya/services/unified_catalog/unified_artwork_prefetcher.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/providers/local_library_provider.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'local_library_default_loader_test.dart' show ThumbnailClient;
import 'local_library_store_test.dart' show library, film;

class Cache extends ce.DefaultCacheManager {
  Cache(Directory root) : super(cacheDirectoryProvider: () async => root);
  bool fail = false;
  Completer<void>? gate;
  Completer<void>? entered;
  int writes = 0;
  String? lastWrittenKey;
  @override
  Future<fs.File> putFile(
    String url,
    List<int> bytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    if (fail) throw const FileSystemException('synthetic write failure');
    writes++;
    lastWrittenKey = key;
    final saved = await super.putFile(url, bytes, key: key, eTag: eTag, maxAge: maxAge, fileExtension: fileExtension);
    if (entered != null && !entered!.isCompleted) entered!.complete();
    await gate?.future;
    return saved;
  }
}

Future<void> until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('fixture did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Cache cache;
  late LocalLibraryProvider provider;
  late ChangeNotifier changes;
  late ThumbnailClient client;
  late DateTime now;
  var colorArtwork = false;
  final colorBodies = {
    1: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
    ),
    2: base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEElEQVR4nGNgYPj/H4KhDAA/0gf5tBJPzQAAAABJRU5ErkJggg==',
    ),
  };
  var allowed = true;
  var includeUnrelated = false;
  var unrelatedHidden = false;
  var wifi = true;
  var version = 1;
  var status = 200;
  var requests = 0;
  var bodyBytes = 0;
  late Map<String, dynamic> validators;
  const url = 'https://fixture.invalid/poster?width=720';
  late String base;
  VisibleArtworkRequest request([String address = url]) => VisibleArtworkRequest(
    client: client,
    path: '/shared-poster',
    url: address,
    baseKey: OptimizedMediaImage.artworkCacheKey(address),
  );
  String key() => provider.artworkCacheKey('one', url, base);
  Future<LocalPosterResult> validate(String address, Map<String, dynamic> state) {
    validators = state;
    return revalidateLocalPoster(
      address,
      state,
      transport: MockClient((r) async {
        requests++;
        if (status != 200) return http.Response('', status);
        if (r.headers['If-None-Match'] == '"$version"') return http.Response('', 304, headers: {'etag': '"$version"'});
        final body = colorArtwork ? colorBodies[version]! : Uint8List.fromList([version]);
        bodyBytes += body.length;
        return http.Response.bytes(body, 200, headers: {'etag': '"$version"'});
      }),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-visible-artwork-');
    cache = Cache(Directory('${root.path}/ce'));
    changes = ChangeNotifier();
    client = ThumbnailClient();
    allowed = true;
    colorArtwork = false;
    includeUnrelated = false;
    unrelatedHidden = false;
    wifi = true;
    version = 1;
    status = 200;
    requests = 0;
    bodyBytes = 0;
    now = DateTime.utc(2026, 2, 1);
    validators = {};
    base = OptimizedMediaImage.artworkCacheKey(url);
    provider = LocalLibraryProvider(
      profileId: 'synthetic',
      directory: Directory('${root.path}/local'),
      librariesForSync: () => [
        library,
        if (includeUnrelated) library.copyWith(id: 'unrelated', hidden: unrelatedHidden),
      ],
      clientFor: (_) => client,
      mayReadServer: (_) => allowed,
      mayReadLibrary: (_) => allowed,
      networkConnected: () => true,
      wifiConnected: () => wifi,
      changes: changes,
      availableBytes: () async => 1024 * 1024 * 1024,
      artworkCache: cache,
      artworkClock: () => now,
      artworkRevalidator: validate,
      posterRevalidator: (_, _, state) => validate(url, state),
    );
    await provider.ready;
    await cache.putFile(url, Uint8List.fromList([0]), key: base);
    cache.writes = 0;
  });
  tearDown(() async {
    OptimizedMediaImage.debugResetMissingImages();
    if (!provider.isDisposed) provider.dispose();
    await provider.pendingStoreWrites;
    changes.dispose();
    await cache.dispose();
    await root.delete(recursive: true);
  });
  Object? bootstrapLease;
  Future<void> first() async {
    bootstrapLease = Object();
    provider.registerVisibleArtwork(bootstrapLease!, request());
    await until(() => key() != base && !provider.artworkRevalidationRunning);
  }

  test('fill off: same-ID HTTP200 publishes immutable CE key, 304 writes nothing, error retains bytes', () async {
    await first();
    expect(provider.enabled, isFalse);
    expect(provider.items, isEmpty);
    expect(await Directory('${root.path}/local/posters').exists(), isFalse);
    final one = key();
    expect(await (await cache.getFileFromCache(one))!.file.readAsBytes(), [1]);
    now = now.add(const Duration(minutes: 10));
    version = 2;
    await provider.revalidateVisibleArtwork();
    final two = key();
    expect(two, isNot(one));
    expect(await (await cache.getFileFromCache(one))!.file.readAsBytes(), [1]);
    expect(await (await cache.getFileFromCache(two))!.file.readAsBytes(), [2]);
    now = now.add(const Duration(minutes: 10));
    await provider.revalidateVisibleArtwork();
    expect(key(), two);
    expect(cache.writes, 2);
    now = now.add(const Duration(minutes: 10));
    status = 500;
    await provider.revalidateVisibleArtwork();
    expect(key(), two);
    expect(cache.writes, 2);
    expect(requests, 4);
    expect(bodyBytes, 2);
    final text = await File('${root.path}/local/options.json').readAsString();
    expect(text, isNot(contains('api_key')));
    print('TASK4B fill-off: starts=$requests body_bytes=$bodyBytes image_writes=${cache.writes} 304_writes=0');
  });

  test('failed CE write keeps published and decoded identity', () async {
    await first();
    final before = key();
    now = now.add(const Duration(minutes: 10));
    version = 2;
    cache.fail = true;
    await provider.revalidateVisibleArtwork();
    expect(key(), before);
    expect(await (await cache.getFileFromCache(before))!.file.readAsBytes(), [1]);
    await provider.revalidateVisibleArtwork();
    expect(requests, 2);
  });

  test('missing CE file drops the validator and repairs without permanent fill', () async {
    await first();
    await cache.removeFile(key());
    now = now.add(const Duration(minutes: 10));
    await provider.revalidateVisibleArtwork();
    expect(validators, isEmpty);
    expect(await (await cache.getFileFromCache(key()))!.file.readAsBytes(), [1]);
    expect(cache.writes, 2);
  });

  test('bounded mounted leases, duplicate rebuilds, shared budget and disconnect recovery', () async {
    wifi = false;
    changes.notifyListeners();
    final lease = Object();
    for (var i = 0; i < 100; i++) provider.registerVisibleArtwork(lease, request());
    expect(provider.visibleArtworkCount, 1);
    final leases = [for (var i = 0; i < 80; i++) Object()];
    for (var i = 0; i < leases.length; i++) {
      provider.registerVisibleArtwork(leases[i], request('https://fixture.invalid/art/$i?api_key=secret'));
    }
    expect(provider.visibleArtworkCount, 60);
    wifi = true;
    changes.notifyListeners();
    await until(() => requests == 20);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await provider.revalidateVisibleArtwork();
    expect(requests, 20);
    expect(provider.items, isEmpty);
    now = now.add(const Duration(minutes: 10));
    await provider.revalidateVisibleArtwork();
    expect(requests, 40);
    now = now.add(const Duration(minutes: 10));
    await provider.revalidateVisibleArtwork();
    expect(requests, 60);
    for (final lease in leases) provider.unregisterVisibleArtwork(lease);
    expect(provider.visibleArtworkCount, 0);
    final options = jsonDecode(await File('${root.path}/local/options.json').readAsString()) as Map;
    expect(options['artworkVariants'], hasLength(60));
    expect(options['posterAttempts'], hasLength(20));
    expect(options['artworkVariants'].toString(), isNot(contains('secret')));
    print('TASK4B mounted60/ever80: 3 intervals starts=$requests retained_variants=60 mounted_after_dispose=0');
  });

  test('duplicate mounted variants coalesce one HTTP start', () async {
    final leases = [for (var i = 0; i < 60; i++) Object()];
    for (final lease in leases) provider.registerVisibleArtwork(lease, request());
    await until(() => key() != base && !provider.artworkRevalidationRunning);
    expect(requests, 1);
    expect(cache.writes, 1);
    for (final lease in leases) provider.unregisterVisibleArtwork(lease);
    expect(provider.visibleArtworkCount, 0);
  });

  test('visible20 plus oldest40 share the persisted rolling start budget', () async {
    for (var i = 0; i < 60; i++) {
      provider.registerVisibleArtwork(Object(), request('https://fixture.invalid/visible/$i'));
    }
    await until(() => requests == 20 && !provider.artworkRevalidationRunning);
    final store = LocalLibraryStore(Directory('${root.path}/local'));
    await store.load();
    var oldStarts = 0;
    await LocalLibrarySync(
      store: store,
      clock: () => now,
      posterLoader: (_, _) async {
        oldStarts++;
        return Uint8List.fromList([1]);
      },
    ).syncPosters(
      [for (var i = 0; i < 100; i++) film('$i').copyWith(thumbPath: '/old/$i')],
      (_) => client,
      isCurrent: () => true,
    );
    expect(oldStarts, 40);
    expect(store.posterBudget(now).total, 60);
    expect(store.posterBudget(now).priority, 20);
    print('TASK4B shared rolling budget: visible=$requests oldest=$oldStarts total=60');
  });

  test('old writer cleanup cannot delete a new provider publication of the same bytes', () async {
    cache.entered = Completer<void>();
    final oldGate = Completer<void>();
    cache.gate = oldGate;
    provider.registerVisibleArtwork(Object(), request());
    await cache.entered!.future;
    final oldCandidate = cache.lastWrittenKey!;
    provider.dispose();
    cache.gate = null;
    now = now.add(const Duration(minutes: 10));
    final newer = LocalLibraryProvider(
      profileId: 'synthetic',
      directory: Directory('${root.path}/local'),
      librariesForSync: () => [library],
      clientFor: (_) => client,
      mayReadServer: (_) => true,
      mayReadLibrary: (_) => true,
      networkConnected: () => true,
      wifiConnected: () => true,
      changes: changes,
      availableBytes: () async => 1024 * 1024 * 1024,
      artworkCache: cache,
      artworkClock: () => now,
      artworkRevalidator: (_, _) async => LocalPosterResult(bytes: Uint8List.fromList([1]), variant: url, etag: '"1"'),
    );
    try {
      await newer.ready;
      newer.registerVisibleArtwork(Object(), request());
      await until(() => newer.artworkCacheKey('one', url, base) != base && !newer.artworkRevalidationRunning);
      final published = newer.artworkCacheKey('one', url, base);
      expect(published, isNot(oldCandidate), reason: 'each provider owns its unpublished candidate');
      oldGate.complete();
      await until(() => !provider.artworkRevalidationRunning);
      expect(await cache.getFileFromCache(oldCandidate), isNull);
      expect(await (await cache.getFileFromCache(published))!.file.readAsBytes(), [1]);
    } finally {
      if (!oldGate.isCompleted) oldGate.complete();
      newer.dispose();
    }
  });

  testWidgets('a known missing poster retains its visible revalidation lease', (tester) async {
    wifi = false;
    Widget tree() => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: OptimizedMediaImage.poster(client: client, imagePath: '/shared-poster', width: 200, height: 300),
      ),
    );
    await tester.pumpWidget(tree());
    expect(provider.visibleArtworkCount, 1);
    tester.widget<Image>(find.byType(Image)).errorBuilder!(
      tester.element(find.byType(Image)),
      const HttpExceptionWithStatus(404, 'missing'),
      StackTrace.empty,
    );
    await tester.pumpWidget(tree());
    expect(find.byType(Image), findsNothing);
    expect(provider.visibleArtworkCount, 1, reason: 'the fallback must remain eligible for background revalidation');
    wifi = true;
    colorArtwork = true;
    await tester.runAsync(provider.revalidateVisibleArtwork);
    await tester.pump();
    expect(key(), isNot(base));
    expect(find.byType(Image), findsOneWidget, reason: 'successful revalidation must replace the mounted fallback');
    expect(provider.visibleArtworkCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(provider.visibleArtworkCount, 0);
  });

  testWidgets('widget and prefetch use the same changed decoded key; leases survive rebuild and unregister', (
    tester,
  ) async {
    await tester.runAsync(first);
    provider.unregisterVisibleArtwork(bootstrapLease!);
    late BuildContext context;
    Widget tree() => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1),
          child: Builder(
            builder: (c) {
              context = c;
              return OptimizedMediaImage.poster(client: client, imagePath: '/shared-poster', width: 200, height: 300);
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(tree());
    expect(provider.visibleArtworkCount, 1);
    await tester.pumpWidget(tree());
    expect(provider.visibleArtworkCount, 1);
    final source = UnifiedMediaSource.fromItem(film('a'));
    final groups = [
      UnifiedMediaGroup(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'a'),
        sources: [source],
        representativeSourceKey: source.sourceKey,
        watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
      ),
    ];
    final warmed = <ArtworkPrefetchRequest>[];
    final prefetcher = UnifiedArtworkPrefetcher(
      clientFor: (_) => client,
      precache: (r, _) async {
        warmed.add(r);
      },
    );
    void warm() => prefetcher.prefetchAround(
      context: context,
      groups: groups,
      firstVisibleIndex: 0,
      lastVisibleIndex: 0,
      posterSize: const Size(200, 300),
    );
    try {
      warm();
      await tester.pump();
      expect(warmed.single.cacheKey, key());
      final firstProvider = tester.widget<Image>(find.byType(Image).first).image;
      expect(
        await firstProvider.obtainKey(ImageConfiguration.empty),
        await warmed.single.provider.obtainKey(ImageConfiguration.empty),
      );
      final oldKey = key();
      now = now.add(const Duration(minutes: 10));
      version = 2;
      await tester.runAsync(provider.revalidateVisibleArtwork);
      await tester.pump();
      warm();
      await tester.pump();
      expect(key(), isNot(oldKey));
      expect(warmed, hasLength(2), reason: 'same viewport must warm a newly published content key');
      final changed = tester.widget<Image>(find.byType(Image).first).image;
      expect(
        await changed.obtainKey(ImageConfiguration.empty),
        await warmed.last.provider.obtainKey(ImageConfiguration.empty),
      );
      expect(changed, isNot(firstProvider));
      await tester.pumpWidget(const SizedBox());
      expect(provider.visibleArtworkCount, 0);
    } finally {
      prefetcher.dispose();
    }
  });

  testWidgets('review I1: filled permanent poster stays fresh with fill off and same mounted widget', (tester) async {
    colorArtwork = true;
    await tester.runAsync(() async {
      await provider.setEnabled(true);
      await until(() => provider.state == LocalLibraryState.ready && !provider.artworkRevalidationRunning);
    });
    final v1 = provider.posterPath('one', '/shared-poster')!;
    expect(await tester.runAsync(() => File(v1).readAsBytes()), colorBodies[1]);
    Widget tree() => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: OptimizedMediaImage.poster(client: client, imagePath: '/shared-poster', width: 200, height: 300),
      ),
    );
    Future<void> expectRenderedColor(List<int> expected) async {
      List<int>? actual;
      for (var spin = 0; spin < 1000; spin++) {
        final image = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .map((w) => w.image)
            .whereType<dynamic>()
            .firstOrNull;
        if (image != null) {
          final bytes = await tester.runAsync(() => image.toByteData());
          actual = bytes?.buffer.asUint8List().take(4).toList().cast<int>();
          if (listEquals(actual, expected)) break;
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
        await tester.pump();
      }
      expect(actual, expected, reason: 'the mounted RawImage must decode the selected poster bytes');
    }

    await tester.pumpWidget(tree());
    await expectRenderedColor([255, 0, 0, 255]);
    expect(provider.visibleArtworkCount, 1);
    final mounted = tester.state(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VisibleArtworkRegistration'),
    );
    final oldImage = tester.widget<Image>(find.byType(Image).first).image;
    await tester.runAsync(() => provider.setEnabled(false));
    now = now.add(const Duration(minutes: 10));
    version = 2;
    await tester.runAsync(provider.revalidateVisibleArtwork);
    await tester.pump();
    await expectRenderedColor([0, 0, 255, 255]);
    final v2 = provider.posterPath('one', '/shared-poster')!;
    expect(v2, isNot(v1));
    expect(
      await tester.runAsync(() => File(v1).exists()),
      isFalse,
      reason: 'fill-off maintenance retires only its superseded image version',
    );
    expect(await tester.runAsync(() => File(v2).readAsBytes()), colorBodies[2]);
    expect(tester.widget<Image>(find.byType(Image).first).image, isNot(oldImage));
    expect(
      tester.state(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VisibleArtworkRegistration')),
      same(mounted),
    );
    now = now.add(const Duration(minutes: 10));
    await tester.runAsync(provider.revalidateVisibleArtwork);
    await tester.pump();
    expect(provider.posterPath('one', '/shared-poster'), v2, reason: '304 keeps file and decode identity');
    now = now.add(const Duration(minutes: 10));
    status = 503;
    await tester.runAsync(provider.revalidateVisibleArtwork);
    await tester.pump();
    expect(provider.posterPath('one', '/shared-poster'), v2);
    expect(await tester.runAsync(() => File(v2).readAsBytes()), colorBodies[2]);
    expect(provider.enabled, isFalse);
    expect(provider.items, hasLength(2));
    expect(requests, 4);
    expect(bodyBytes, colorBodies[1]!.length + colorBodies[2]!.length);
    expect(cache.writes, 0);
    await tester.pumpWidget(const SizedBox());
    expect(provider.visibleArtworkCount, 0);
  });

  testWidgets('review I2: allowed mounted lease recovers after unrelated access and clear; revoke stays closed', (
    tester,
  ) async {
    includeUnrelated = true;
    wifi = false;
    await tester.runAsync(() async {
      changes.notifyListeners();
      await provider.pendingStoreWrites;
    });
    Widget tree() => ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: OptimizedMediaImage.poster(client: client, imagePath: '/shared-poster', width: 200, height: 300),
      ),
    );
    await tester.pumpWidget(tree());
    final mounted = tester.state(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VisibleArtworkRegistration'),
    );
    await tester.pumpWidget(tree());
    expect(provider.visibleArtworkCount, 1);
    // No selected path/cache-key change can rebuild this image: only its
    // registration-epoch subscription observes this unrelated boundary.
    expect(key(), base);
    unrelatedHidden = true;
    await tester.runAsync(() async {
      changes.notifyListeners();
      await provider.pendingStoreWrites;
    });
    expect(provider.visibleArtworkCount, 0);
    await tester.pump();
    expect(provider.visibleArtworkCount, 1);
    expect(key(), base);
    expect(requests, 0);
    expect(
      tester.state(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VisibleArtworkRegistration')),
      same(mounted),
    );
    Future<void> settle() async {
      for (var spin = 0; spin < 1000 && (key() == base || provider.artworkRevalidationRunning); spin++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
        await tester.pump();
      }
      expect(key(), isNot(base));
      expect(provider.artworkRevalidationRunning, isFalse);
    }

    wifi = true;
    await tester.runAsync(() async {
      changes.notifyListeners();
    });
    await tester.pump();
    await settle();
    expect(requests, 1);
    now = now.add(const Duration(minutes: 10));
    version = 2;
    unrelatedHidden = false;
    await tester.runAsync(() async {
      changes.notifyListeners();
      await provider.pendingStoreWrites;
    });
    expect(key(), base, reason: 'boundary withdraws prior publication');
    await tester.pump();
    expect(provider.visibleArtworkCount, 1, reason: 'notify renews same allowed mounted widget without replacement');
    await settle();
    expect(requests, 2);
    expect(
      tester.state(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VisibleArtworkRegistration')),
      same(mounted),
    );
    now = now.add(const Duration(minutes: 10));
    version = 3;
    await tester.runAsync(provider.clear);
    await tester.pump();
    expect(provider.visibleArtworkCount, 1);
    await settle();
    expect(requests, 3);
    expect(provider.enabled, isFalse);
    expect(
      tester.state(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VisibleArtworkRegistration')),
      same(mounted),
    );
    allowed = false;
    await tester.runAsync(() async {
      changes.notifyListeners();
      await provider.pendingStoreWrites;
    });
    await tester.pump();
    await tester.runAsync(provider.revalidateVisibleArtwork);
    expect(provider.visibleArtworkCount, 0);
    expect(requests, 3);
    await tester.pumpWidget(const SizedBox());
    // CE's public putFile returns before Hive's metadata write future.
    // Complete that real close while this widget's fake timers/microtasks can
    // still advance; teardown outside this zone cannot flush those callbacks.
    var cacheClosed = false;
    final closing = cache.dispose().whenComplete(() => cacheClosed = true);
    for (var spin = 0; spin < 1000 && !cacheClosed; spin++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(cacheClosed, isTrue);
    await closing;
  });

  for (final boundary in ['clear', 'revoke', 'profile', 'client', 'unregister']) {
    test('$boundary during CE write rejects publication and removes new candidate', () async {
      cache.entered = Completer<void>();
      cache.gate = Completer<void>();
      final lease = Object();
      provider.registerVisibleArtwork(lease, request());
      await cache.entered!.future;
      if (boundary == 'clear') await provider.clear();
      if (boundary == 'revoke') {
        allowed = false;
        changes.notifyListeners();
      }
      if (boundary == 'profile') provider.dispose();
      if (boundary == 'client') {
        client = ThumbnailClient();
        changes.notifyListeners();
      }
      if (boundary == 'unregister') provider.unregisterVisibleArtwork(lease);
      cache.gate!.complete();
      await until(() => provider.visibleArtworkCount == 0);
      await until(() => !provider.artworkRevalidationRunning);
      expect(await cache.getFileFromCache(cache.lastWrittenKey!), isNull);
      expect(key(), base);
      expect(await cache.getFileFromCache(base), isNotNull);
      final local = LocalLibraryStore(Directory('${root.path}/local'));
      await local.load();
      expect(local.artworkVariant(request().identity)['key'], isNull);
    });
  }
}
