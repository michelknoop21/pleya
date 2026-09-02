/// The prefetcher's contract, proven without a byte of network traffic: the
/// precache call is injected, so every test asserts on the URLs that *would*
/// have been warmed, in the order they would have gone out.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/unified_artwork_prefetcher.dart';
import 'package:pleya/utils/media_image_helper.dart' show ImageType;
import 'package:pleya/widgets/optimized_media_image.dart';

/// A Jellyfin-shaped self-contained artwork URL. `getOptimizedImageUrl` sizes
/// these without needing a client at all, which keeps the fixtures honest:
/// the URLs under test come out of the real helper, not out of the test.
String _thumb(int index) => 'https://jf.test/Items/$index/Images/Primary?api_key=secret';

UnifiedMediaGroup _group(int index, {String? thumbPath = _unset, String serverId = 's1'}) {
  final item = MediaItem(
    id: 'i$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Title $index',
    thumbPath: identical(thumbPath, _unset) ? _thumb(index) : thumbPath,
    serverId: serverId,
    serverName: serverId,
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'g$index',
    identity: CanonicalMediaIdentity.movie(title: 'Title $index', year: 2010),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
  );
}

/// Sentinel so `thumbPath: null` means "this title has no artwork" and an
/// omitted argument means "the usual one".
const String _unset = '__unset__';

List<UnifiedMediaGroup> _groups(int count) => [for (var i = 0; i < count; i++) _group(i)];

/// Records what would have been warmed, and hands each call's completion back
/// to the test so the in-flight cap is observable.
class _RecordingPrecache {
  final List<ArtworkPrefetchRequest> requests = [];
  final List<Completer<void>> completers = [];

  /// When false, calls complete immediately instead of parking on a completer.
  final bool park;

  /// Throws synchronously out of the precache call.
  final bool throwSync;

  /// Returns an already-failed future.
  final bool failAsync;

  _RecordingPrecache({this.park = false, this.throwSync = false, this.failAsync = false});

  /// Which groups were warmed, in dispatch order.
  List<String> get groupIds => [for (final request in requests) request.groupId];

  Future<void> call(ArtworkPrefetchRequest request, BuildContext context) {
    requests.add(request);
    if (throwSync) throw StateError('precache exploded');
    if (failAsync) return Future<void>.error(StateError('server went away'));
    if (!park) return Future<void>.value();
    final completer = Completer<void>();
    completers.add(completer);
    return completer.future;
  }
}

/// Pumps a bare tree and hands back a context with a pinned device pixel
/// ratio, so the sized URLs the helper produces are deterministic.
Future<BuildContext> _context(WidgetTester tester, {double devicePixelRatio = 2.0}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: devicePixelRatio),
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

const Size _poster = Size(200, 300);
const Size _wide = Size(340, 190);

/// A group carrying *both* artworks — the discovery case, where the 2:3 poster
/// and the 16:9 frame are different assets and not two crops of one.
UnifiedMediaGroup _groupWithWide(int index) {
  final item = MediaItem(
    id: 'i$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Title $index',
    thumbPath: _thumb(index),
    artPath: 'https://jf.test/Items/$index/Images/Backdrop?api_key=secret',
    serverId: 's1',
    serverName: 's1',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'g$index',
    identity: CanonicalMediaIdentity.movie(title: 'Title $index', year: 2010),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey),
  );
}

List<UnifiedMediaGroup> _wideGroups(int count) => [for (var i = 0; i < count; i++) _groupWithWide(i)];

UnifiedArtworkVariant _backdropVariant({int lookaheadItems = UnifiedArtworkVariant.defaultWideLookaheadItems}) =>
    UnifiedArtworkVariant(
      pathOf: (item) => item.artPath,
      imageTypeOf: (_) => ImageType.art,
      lookaheadItems: lookaheadItems,
    );

void main() {
  group('window', () {
    testWidgets('warms the visible range plus the documented margin, and nothing else', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(200),
        firstVisibleIndex: 20,
        lastVisibleIndex: 25,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.groupIds, [
        // Visible first: those are the placeholders on screen right now.
        for (var i = 20; i <= 25; i++) 'g$i',
        // Then forward, the direction of travel.
        for (var i = 26; i <= 37; i++) 'g$i',
        // Then backward, nearest first.
        for (var i = 19; i >= 8; i--) 'g$i',
      ]);
      expect(precache.requests.length, 6 + UnifiedArtworkPrefetcher.defaultLookaheadItems * 2);
    });

    testWidgets('never warms the whole catalog, even when the caller reports it all as visible', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(5000),
        firstVisibleIndex: 0,
        lastVisibleIndex: 4999,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.requests.length, UnifiedArtworkPrefetcher.maxWindowItems);
      expect(precache.groupIds.first, 'g0');
      expect(precache.groupIds.last, 'g${UnifiedArtworkPrefetcher.maxWindowItems - 1}');
    });

    testWidgets('clamps a range that ran past the end of a shortened list', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(3),
        firstVisibleIndex: 40,
        lastVisibleIndex: 60,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.groupIds, ['g2', 'g1', 'g0']);
    });

    testWidgets('an empty list and a degenerate poster size are no-ops', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: const [],
        firstVisibleIndex: 0,
        lastVisibleIndex: 0,
        posterSize: _poster,
      );
      prefetcher.prefetchAround(
        context: context,
        groups: _groups(4),
        firstVisibleIndex: 0,
        lastVisibleIndex: 3,
        posterSize: Size.zero,
      );
      prefetcher.prefetchAround(
        context: context,
        groups: _groups(4),
        firstVisibleIndex: 0,
        lastVisibleIndex: 3,
        posterSize: const Size(double.infinity, 300),
      );
      await tester.pump();

      expect(precache.requests, isEmpty);
    });
  });

  group('the existing artwork pipeline', () {
    testWidgets('URLs are the sized ones MediaImageHelper builds for a poster', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(1),
        firstVisibleIndex: 0,
        lastVisibleIndex: 0,
        posterSize: _poster,
      );
      await tester.pump();

      final request = precache.requests.single;
      // 200×300 logical at DPR 2 buckets to 400×600 — the poster branch of
      // calculateOptimalDimensions, not a size this test invented.
      expect(request.url, contains('maxWidth=400'));
      expect(request.url, contains('maxHeight=600'));
      expect(request.url, startsWith('https://jf.test/Items/0/Images/Primary?'));
      expect(request.provider, isA<ResizeImage>());
    });

    testWidgets('the cache key is the token-free one the image widget stores under', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(1),
        firstVisibleIndex: 0,
        lastVisibleIndex: 0,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.requests.single.cacheKey, startsWith('plex_optimized_'));
      // A rotated token must not invalidate the entry: same image, same key.
      expect(
        OptimizedMediaImage.artworkCacheKey('https://jf.test/Items/0/Images/Primary?api_key=one&maxWidth=400'),
        OptimizedMediaImage.artworkCacheKey('https://jf.test/Items/0/Images/Primary?api_key=two&maxWidth=400'),
      );
      expect(
        OptimizedMediaImage.artworkCacheKey('https://plex.test/photo?url=%2Fthumb&X-Plex-Token=aaa'),
        OptimizedMediaImage.artworkCacheKey('https://plex.test/photo?url=%2Fthumb&X-Plex-Token=bbb'),
      );
    });
  });

  group('de-duplication', () {
    testWidgets('a repeated call over an unchanged window warms nothing new', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      final groups = _groups(50);
      for (var call = 0; call < 5; call++) {
        prefetcher.prefetchAround(
          context: context,
          groups: groups,
          firstVisibleIndex: 0,
          lastVisibleIndex: 5,
          posterSize: _poster,
        );
        await tester.pump();
      }

      expect(precache.requests.length, 18);
    });

    testWidgets('scrolling on only warms what the previous window did not cover', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(50),
        firstVisibleIndex: 0,
        lastVisibleIndex: 5,
        posterSize: _poster,
      );
      await tester.pump();
      precache.requests.clear();

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(50),
        firstVisibleIndex: 6,
        lastVisibleIndex: 11,
        posterSize: _poster,
      );
      await tester.pump();

      // 0–17 were already warmed by the first window; only the new tail goes out.
      expect(precache.groupIds, ['g18', 'g19', 'g20', 'g21', 'g22', 'g23']);
    });
  });

  group('bounded in flight', () {
    testWidgets('never exceeds maxConcurrent, and drains as calls settle', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache(park: true);
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 3);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(10),
        firstVisibleIndex: 0,
        lastVisibleIndex: 9,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.requests.length, 3);
      expect(prefetcher.inFlightCount, 3);
      expect(prefetcher.pendingCount, 7);

      precache.completers.first.complete();
      await tester.pump();

      expect(precache.requests.length, 4);
      expect(prefetcher.inFlightCount, 3);
      expect(prefetcher.pendingCount, 6);
      expect(precache.groupIds, ['g0', 'g1', 'g2', 'g3']);
    });
  });

  group('never throws into the caller', () {
    testWidgets('a server with no client is skipped, not an error', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      // A relative path with no client cannot be signed at all.
      final groups = [
        _group(0),
        _group(1, thumbPath: '/library/metadata/1/thumb'),
        _group(2, thumbPath: null),
        _group(3, thumbPath: ''),
        _group(4),
      ];
      prefetcher.prefetchAround(
        context: context,
        groups: groups,
        firstVisibleIndex: 0,
        lastVisibleIndex: 4,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.groupIds, ['g0', 'g4']);
    });

    testWidgets('a resolver that throws costs one poster, not the scroll', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(
        clientFor: (serverId) => throw StateError('server $serverId is gone'),
        precache: precache.call,
        maxConcurrent: 64,
      );
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: [
          _group(0, thumbPath: '/library/metadata/0/thumb'),
          _group(1),
        ],
        firstVisibleIndex: 0,
        lastVisibleIndex: 1,
        posterSize: _poster,
      );
      await tester.pump();

      // The absolute URL still resolves without a client; the relative one is
      // simply skipped. Neither path let the throw escape.
      expect(precache.groupIds, ['g1']);
    });

    testWidgets('a failing precache releases its slot instead of wedging the queue', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache(failAsync: true);
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 2);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(6),
        firstVisibleIndex: 0,
        lastVisibleIndex: 5,
        posterSize: _poster,
      );
      await tester.pump();
      await tester.pump();

      expect(precache.requests.length, 6);
      expect(prefetcher.inFlightCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a precache that throws synchronously does the same', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache(throwSync: true);
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 2);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(6),
        firstVisibleIndex: 0,
        lastVisibleIndex: 5,
        posterSize: _poster,
      );
      await tester.pump();

      expect(precache.requests.length, 6);
      expect(prefetcher.inFlightCount, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('dispose', () {
    testWidgets('drops the queue and dispatches nothing further', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache(park: true);
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 2);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(20),
        firstVisibleIndex: 0,
        lastVisibleIndex: 9,
        posterSize: _poster,
      );
      await tester.pump();
      expect(precache.requests.length, 2);

      prefetcher.dispose();
      expect(prefetcher.isDisposed, isTrue);
      expect(prefetcher.pendingCount, 0);

      // An in-flight call landing after dispose must not restart the queue.
      precache.completers.first.complete();
      await tester.pump();
      expect(precache.requests.length, 2);

      // And a late scroll callback is inert.
      prefetcher.prefetchAround(
        context: context,
        groups: _groups(20),
        firstVisibleIndex: 10,
        lastVisibleIndex: 15,
        posterSize: _poster,
      );
      await tester.pump();
      expect(precache.requests.length, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a queued entry whose context is gone is skipped', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache(park: true);
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 2);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _groups(10),
        firstVisibleIndex: 0,
        lastVisibleIndex: 9,
        posterSize: _poster,
      );
      await tester.pump();
      expect(precache.requests.length, 2);
      expect(prefetcher.pendingCount, 8);

      // The grid leaves the tree while the queue is still draining.
      await tester.pumpWidget(const SizedBox());
      precache.completers.first.complete();
      await tester.pump();

      expect(precache.requests.length, 2);
      expect(prefetcher.pendingCount, 0);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // P8: a second variant, on the same budget
  // ---------------------------------------------------------------------------

  group('a second variant', () {
    testWidgets('is not warmed at all unless a caller asks for one', (tester) async {
      // The whole compatibility claim: the catalog grid's call site and every
      // test above it must behave byte-for-byte as before.
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _wideGroups(10),
        firstVisibleIndex: 0,
        lastVisibleIndex: 2,
        posterSize: _poster,
        // A size but no variant: nothing to warm it with.
        secondarySize: _wide,
      );
      await tester.pump();

      expect(precache.requests.every((r) => r.url.contains('Primary')), isTrue);
    });

    testWidgets('warms both assets for the visible range, on one queue', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(
        clientFor: (_) => null,
        precache: precache.call,
        maxConcurrent: 64,
        secondary: _backdropVariant(),
      );
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _wideGroups(20),
        firstVisibleIndex: 5,
        lastVisibleIndex: 5,
        posterSize: _poster,
        secondarySize: _wide,
      );
      await tester.pump();

      final backdrops = precache.requests.where((r) => r.url.contains('Backdrop')).toList();
      final posters = precache.requests.where((r) => r.url.contains('Primary')).toList();
      expect(backdrops, isNotEmpty);
      expect(posters, isNotEmpty);
      // The focused item's wide frame goes out before the poster lookahead:
      // it is the artwork the tile is about to draw, and everything else is a
      // guess about where the remote goes next.
      expect(precache.requests.first.url, contains('Backdrop'));
      expect(precache.requests.first.groupId, 'g5');
    });

    testWidgets('holds the wide variant to four items either side, against the posters twelve', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(
        clientFor: (_) => null,
        precache: precache.call,
        maxConcurrent: 64,
        secondary: _backdropVariant(),
      );
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _wideGroups(60),
        firstVisibleIndex: 30,
        lastVisibleIndex: 30,
        posterSize: _poster,
        secondarySize: _wide,
      );
      await tester.pump();

      int indexOf(ArtworkPrefetchRequest r) => int.parse(r.groupId.substring(1));
      final wide = precache.requests.where((r) => r.url.contains('Backdrop')).map(indexOf).toSet();
      final poster = precache.requests.where((r) => r.url.contains('Primary')).map(indexOf).toSet();

      expect(wide, {26, 27, 28, 29, 30, 31, 32, 33, 34});
      expect(
        poster.length,
        greaterThan(wide.length),
        reason: 'a 16:9 frame is ~2.7x the pixels of a poster and only one is ever on screen',
      );
      expect(poster, contains(42), reason: 'posters keep their twelve');
      expect(wide, isNot(contains(42)));
    });

    testWidgets('shares one in-flight budget rather than opening a second one', (tester) async {
      // The failure mode this rules out: two prefetchers of three each, which
      // together can occupy all six permits `image_cache_service.dart` grants
      // artwork globally and starve the tile actually on screen.
      final context = await _context(tester);
      final precache = _RecordingPrecache(park: true);
      final prefetcher = UnifiedArtworkPrefetcher(
        clientFor: (_) => null,
        precache: precache.call,
        secondary: _backdropVariant(),
      );
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _wideGroups(40),
        firstVisibleIndex: 10,
        lastVisibleIndex: 14,
        posterSize: _poster,
        secondarySize: _wide,
      );
      await tester.pump();

      expect(prefetcher.inFlightCount, UnifiedArtworkPrefetcher.defaultMaxConcurrent);
      expect(
        precache.requests,
        hasLength(UnifiedArtworkPrefetcher.defaultMaxConcurrent),
        reason: 'three in the air across *both* variants, not three each',
      );
      expect(UnifiedArtworkPrefetcher.defaultMaxConcurrent, lessThan(6), reason: 'and still under the global limit');

      for (final completer in precache.completers) {
        completer.complete();
      }
      await tester.pump();
      expect(precache.requests.length, greaterThan(UnifiedArtworkPrefetcher.defaultMaxConcurrent));
    });

    testWidgets('the LRU is not quietly enlarged to pay for the second variant', (tester) async {
      // Doubling the remembered-URL budget would have been the easy answer and
      // there is no evidence it is needed: falling off the end of the LRU costs
      // at most one repeat request, which the disk cache answers.
      expect(UnifiedArtworkPrefetcher.defaultMaxRememberedUrls, 512);
    });

    testWidgets('an item with no wide artwork is skipped, not padded with its poster', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(
        clientFor: (_) => null,
        precache: precache.call,
        maxConcurrent: 64,
        secondary: _backdropVariant(),
      );
      addTearDown(prefetcher.dispose);

      // `_group` carries a poster and no `artPath`.
      prefetcher.prefetchAround(
        context: context,
        groups: _groups(5),
        firstVisibleIndex: 0,
        lastVisibleIndex: 4,
        posterSize: _poster,
        secondarySize: _wide,
      );
      await tester.pump();

      expect(precache.requests.every((r) => r.url.contains('Primary')), isTrue);
      expect(precache.groupIds.toSet(), hasLength(5), reason: 'the posters still all go out');
    });

    testWidgets('the two variants land on different URLs, so neither shadows the other', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final prefetcher = UnifiedArtworkPrefetcher(
        clientFor: (_) => null,
        precache: precache.call,
        maxConcurrent: 64,
        secondary: _backdropVariant(),
      );
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: _wideGroups(3),
        firstVisibleIndex: 1,
        lastVisibleIndex: 1,
        posterSize: _poster,
        secondarySize: _wide,
      );
      await tester.pump();

      final forG1 = precache.requests.where((r) => r.groupId == 'g1').toList();
      expect(forG1, hasLength(2));
      expect(forG1.map((r) => r.url).toSet(), hasLength(2));
      expect(forG1.map((r) => r.cacheKey).toSet(), hasLength(2), reason: 'one cache entry each, or one overwrites');
    });
  });

  group('resolver', () {
    testWidgets('is asked for the representative source’s server', (tester) async {
      final context = await _context(tester);
      final precache = _RecordingPrecache();
      final asked = <String>[];
      MediaServerClient? clientFor(String serverId) {
        asked.add(serverId);
        return null;
      }

      final prefetcher = UnifiedArtworkPrefetcher(clientFor: clientFor, precache: precache.call, maxConcurrent: 64);
      addTearDown(prefetcher.dispose);

      prefetcher.prefetchAround(
        context: context,
        groups: [
          _group(0, serverId: 'nas'),
          _group(1, serverId: 'laptop'),
        ],
        firstVisibleIndex: 0,
        lastVisibleIndex: 1,
        posterSize: _poster,
      );
      await tester.pump();

      expect(asked, ['nas', 'laptop']);
    });
  });
}
