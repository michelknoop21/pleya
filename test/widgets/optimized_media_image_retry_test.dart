import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image_ce/cached_network_image.dart' show HttpExceptionWithStatus;
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/widgets/optimized_media_image.dart';

/// An image that fails its first [failures] loads and then decodes.
///
/// Evicts itself on error, as the real network provider does: Flutter's image
/// cache otherwise hands every later resolve the same failed load.
class _FlakyImage extends ImageProvider<_FlakyImage> {
  _FlakyImage({required this.failures, this.error, this.gate});

  final int failures;
  final Object? error;

  /// When set, a successful load waits for it, like a download in progress.
  final Completer<void>? gate;

  /// When set, the load with this number waits for it and then fails.
  ({int load, Completer<void> until})? hangingFailure;
  int loads = 0;

  @override
  Future<_FlakyImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<_FlakyImage>(this);

  @override
  ImageStreamCompleter loadImage(_FlakyImage key, ImageDecoderCallback decode) {
    loads++;
    final attempt = loads;
    if (hangingFailure case (:final load, :final until) when load == attempt) {
      return OneFrameImageStreamCompleter(
        until.future.then<ImageInfo>((_) {
          scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
          throw const _Dropped();
        }),
      );
    }
    if (attempt <= failures) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      return OneFrameImageStreamCompleter(Future<ImageInfo>.error(error ?? const _Dropped()));
    }
    final ready = gate?.future ?? Future<void>.value();
    return OneFrameImageStreamCompleter(ready.then((_) => ImageInfo(image: pixel!.clone())));
  }

  /// Decoded once per test, outside the fake clock.
  static ui.Image? pixel;

  static Future<ui.Image> decodePixel() {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(const [255, 0, 0, 255]),
      1,
      1,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

class _Dropped implements Exception {
  const _Dropped();
}

void main() {
  late _FlakyImage image;

  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    artworkRetryDelays = const [Duration(seconds: 2), Duration(seconds: 10)];
  });
  tearDown(() => OptimizedMediaImage.debugNetworkProviderBuilder = null);

  Future<void> settleLoad(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpPoster(WidgetTester tester) async {
    _FlakyImage.pixel = await tester.runAsync(_FlakyImage.decodePixel);
    OptimizedMediaImage.debugNetworkProviderBuilder = (_, _) => image;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: OptimizedMediaImage(
            client: null,
            imagePath: 'https://example.invalid/poster.jpg',
            width: 96,
            height: 144,
            errorWidget: (_, _, _) => const Text('failed'),
          ),
        ),
      ),
    );
    await settleLoad(tester);
  }

  testWidgets('a poster whose download dropped once is fetched again by itself', (tester) async {
    image = _FlakyImage(failures: 1);
    await pumpPoster(tester);
    expect(find.text('failed'), findsOneWidget);
    expect(image.loads, 1);

    await tester.pump(const Duration(seconds: 2));
    await settleLoad(tester);

    expect(image.loads, 2);
    expect(find.text('failed'), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  testWidgets('after two failed retries the tile waits, and a reconnect tries again', (tester) async {
    image = _FlakyImage(failures: 3);
    await pumpPoster(tester);

    await tester.pump(const Duration(seconds: 2));
    await settleLoad(tester);
    await tester.pump(const Duration(seconds: 10));
    await settleLoad(tester);
    expect(image.loads, 3);
    expect(find.text('failed'), findsOneWidget);

    await tester.pump(const Duration(minutes: 5));
    await settleLoad(tester);
    expect(image.loads, 3, reason: 'no third automatic attempt');

    ArtworkReloadSignal.instance.requestReload();
    await tester.pump();
    await settleLoad(tester);

    expect(image.loads, 4);
    expect(find.text('failed'), findsNothing);
  });

  testWidgets('a picture the server says it does not have is not asked for again', (tester) async {
    image = _FlakyImage(failures: 99, error: HttpExceptionWithStatus(404, 'Invalid statusCode: 404'));
    await pumpPoster(tester);

    await tester.pump(const Duration(minutes: 1));
    await settleLoad(tester);

    expect(image.loads, 1);
    expect(find.text('failed'), findsOneWidget);
  });

  testWidgets('a loaded poster ignores the reload signal', (tester) async {
    image = _FlakyImage(failures: 0);
    await pumpPoster(tester);
    expect(image.loads, 1);

    ArtworkReloadSignal.instance.requestReload();
    await tester.pump();
    await settleLoad(tester);

    expect(image.loads, 1);
  });

  testWidgets('what the tile shows instead stays until the retry has the picture', (tester) async {
    // UnifiedMediaImage draws another server's poster as the error widget. A
    // retry that swapped the image first would trade that poster for a
    // placeholder for as long as the download took.
    final gate = Completer<void>();
    image = _FlakyImage(failures: 1, gate: gate);
    await pumpPoster(tester);
    expect(find.text('failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await settleLoad(tester);
    expect(image.loads, 2, reason: 'the retry is under way');
    expect(find.text('failed'), findsOneWidget, reason: 'the stand-in is still on screen');

    gate.complete();
    await settleLoad(tester);
    await tester.pump();

    expect(find.text('failed'), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  testWidgets('a reload signal during the last retry gives the tile its attempts back', (tester) async {
    // A resume aborts the running download and sends the signal in one call.
    // Ignoring the signal left the tile failed until the next one.
    final abort = Completer<void>();
    image = _FlakyImage(failures: 2)..hangingFailure = (load: 3, until: abort);
    await pumpPoster(tester);
    await tester.pump(const Duration(seconds: 2));
    await settleLoad(tester);
    await tester.pump(const Duration(seconds: 10));
    await settleLoad(tester);
    expect(image.loads, 3, reason: 'the last automatic retry hangs');

    ArtworkReloadSignal.instance.requestReload();
    abort.complete();
    await settleLoad(tester);
    await tester.pump(const Duration(seconds: 2));
    await settleLoad(tester);
    await tester.pump();

    expect(image.loads, 4);
    expect(find.text('failed'), findsNothing);
  });
}
