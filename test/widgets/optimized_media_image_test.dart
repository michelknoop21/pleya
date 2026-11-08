import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/utils/media_image_helper.dart';
import 'package:pleya/widgets/optimized_media_image.dart';

void main() {
  testWidgets('network images use decode resize without disk cache resize', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 160,
          height: 90,
          child: OptimizedMediaImage.thumb(
            imagePath: 'https://example.invalid/episode-thumb.jpg',
            width: 160,
            height: 90,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resizeProvider = image.image as ResizeImage;
    final cachedProvider = resizeProvider.imageProvider as CachedNetworkImageProvider;

    expect(resizeProvider.height, isNotNull);
    expect(cachedProvider.maxHeight, isNull);
    expect(cachedProvider.maxWidth, isNull);
  });

  testWidgets('failed image placeholders keep explicit dimensions in loose layouts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OptimizedMediaImage(
                  client: null,
                  imagePath: 'https://example.invalid/broken-actor-image.jpg',
                  width: 96,
                  height: 96,
                  imageType: ImageType.avatar,
                  fallbackIcon: Symbols.person_rounded,
                ),
                const SizedBox(height: 8),
                const Text('Actor Name'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Symbols.person_rounded), findsOneWidget);

    final placeholder = find.descendant(of: find.byType(OptimizedMediaImage), matching: find.byType(Container));
    expect(placeholder, findsOneWidget);
    expect(tester.getSize(placeholder), const Size(96, 96));
  });

  group('images the server answered 404 for', () {
    tearDown(OptimizedMediaImage.debugResetMissingImages);

    Widget poster(String path, {String? cacheKey}) => MaterialApp(
      home: SizedBox(
        width: 160,
        height: 90,
        child: OptimizedMediaImage.thumb(imagePath: path, cacheKey: cacheKey, width: 160, height: 90),
      ),
    );

    testWidgets('are not requested again once the server said 404', (tester) async {
      await tester.pumpWidget(poster('https://example.invalid/missing-cast.jpg'));
      final provider =
          (tester.widget<Image>(find.byType(Image)).image as ResizeImage).imageProvider as CachedNetworkImageProvider;

      expect(
        rememberMissingImage(
          provider.url,
          HttpExceptionWithStatus(404, 'Invalid statusCode: 404', uri: Uri.parse(provider.url)),
        ),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(poster('https://example.invalid/missing-cast.jpg'));
      expect(find.byType(Image), findsNothing, reason: 'a known-missing URL must not build a network image');
    });

    testWidgets('an explicit artwork revision retries the same previously missing URL', (tester) async {
      const url = 'https://example.invalid/revalidated.jpg';
      await tester.pumpWidget(poster(url, cacheKey: 'revision-1'));
      final image = tester.widget<Image>(find.byType(Image));
      image.errorBuilder!(
        tester.element(find.byType(Image)),
        const HttpExceptionWithStatus(404, 'missing'),
        StackTrace.empty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(poster(url, cacheKey: 'revision-1'));
      expect(find.byType(Image), findsNothing, reason: 'the unchanged failed revision stays suppressed');

      await tester.pumpWidget(poster(url, cacheKey: 'revision-2'));
      expect(find.byType(Image), findsOneWidget, reason: 'an explicit artwork revision must allow a new request');
      final retried =
          (tester.widget<Image>(find.byType(Image)).image as ResizeImage).imageProvider as CachedNetworkImageProvider;
      expect(retried.cacheKey, 'revision-2');
    });

    testWidgets('a missing image does not suppress another authenticated URL with the same custom key', (tester) async {
      const first = 'https://example.invalid/poster?auth=first';
      const second = 'https://example.invalid/poster?auth=second';
      await tester.pumpWidget(poster(first, cacheKey: 'cover'));
      tester.widget<Image>(find.byType(Image)).errorBuilder!(
        tester.element(find.byType(Image)),
        const HttpExceptionWithStatus(404, 'missing'),
        StackTrace.empty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(poster(second, cacheKey: 'cover'));
      expect(find.byType(Image), findsOneWidget);
      final provider =
          (tester.widget<Image>(find.byType(Image)).image as ResizeImage).imageProvider as CachedNetworkImageProvider;
      expect(provider.url, second);
    });

    test('only a 404 marks an image missing', () {
      const url = 'https://example.invalid/photo';
      expect(rememberMissingImage(url, const HttpExceptionWithStatus(500, 'boom')), isFalse);
      expect(rememberMissingImage(url, Exception('socket closed')), isFalse);
      expect(isKnownMissingImage(url), isFalse);
    });
  });
}
