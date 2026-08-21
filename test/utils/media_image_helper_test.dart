import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/media_image_helper.dart' show ImageType, MediaImageHelper;

void main() {
  group('MediaImageHelper.getOptimizedImageUrl', () {
    test('adds size hints to absolute Jellyfin artwork URLs', () {
      final url = MediaImageHelper.getOptimizedImageUrl(
        thumbPath: 'https://jf.example/Items/item-1/Images/Primary?tag=abc&api_key=token',
        maxWidth: 120,
        maxHeight: 180,
        devicePixelRatio: 2,
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters['tag'], 'abc');
      expect(uri.queryParameters['api_key'], 'token');
      expect(uri.queryParameters['maxWidth'], '240');
      expect(uri.queryParameters['maxHeight'], '360');
    });

    test('preserves existing Jellyfin size hints and fills missing dimension', () {
      final url = MediaImageHelper.getOptimizedImageUrl(
        thumbPath: 'https://jf.example/Items/item-1/Images/Primary?api_key=token&maxWidth=100',
        maxWidth: 120,
        maxHeight: 180,
        devicePixelRatio: 2,
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters['api_key'], 'token');
      expect(uri.queryParameters['maxWidth'], '100');
      expect(uri.queryParameters['maxHeight'], '360');
    });

    test('leaves non-Jellyfin external URLs unchanged without a proxy client', () {
      const original = 'https://images.example/poster.jpg';

      final url = MediaImageHelper.getOptimizedImageUrl(
        thumbPath: original,
        maxWidth: 120,
        maxHeight: 180,
        devicePixelRatio: 2,
      );

      expect(url, original);
    });

    test('leaves Jellyfin artwork unchanged when transcoding is disabled', () {
      const original = 'https://jf.example/Items/item-1/Images/Primary?tag=abc&api_key=token';

      final url = MediaImageHelper.getOptimizedImageUrl(
        thumbPath: original,
        maxWidth: 120,
        maxHeight: 180,
        devicePixelRatio: 2,
        enableTranscoding: false,
      );

      expect(url, original);
    });
  });

  group('MediaImageHelper.catalogPosterUrl', () {
    const poster = 'https://metadata-static.plex.tv/1/gracenote/16d409c65c018341b0b142504779b09c.jpg';

    test('proxies a catalogue poster through the public resizer', () {
      final url = Uri.parse(MediaImageHelper.catalogPosterUrl(poster, width: 300, height: 450));

      expect(url.host, 'images.plex.tv');
      expect(url.path, '/photo');
      expect(url.queryParameters['width'], '300');
      expect(url.queryParameters['height'], '450');
      expect(url.queryParameters['url'], poster);
    });

    test('carries no token, so the cache key holds nothing private', () {
      final url = MediaImageHelper.catalogPosterUrl(poster, width: 300, height: 450);

      expect(url.toLowerCase(), isNot(contains('token')));
      expect(url.toLowerCase(), isNot(contains('api_key')));
      expect(url.toLowerCase(), isNot(contains('/photo/:/transcode')));
    });

    test('handles a tmdb-hosted poster the same way', () {
      const tmdb = 'https://image.tmdb.org/t/p/original/p53wbsukyhJ8TieisoeU1zZr9iA.jpg';

      expect(Uri.parse(MediaImageHelper.catalogPosterUrl(tmdb, width: 300, height: 450)).queryParameters['url'], tmdb);
    });

    test('does not wrap an already proxied url twice', () {
      final once = MediaImageHelper.catalogPosterUrl(poster, width: 300, height: 450);

      expect(MediaImageHelper.catalogPosterUrl(once, width: 600, height: 900), once);
    });

    test('leaves a relative path alone and answers empty for nothing', () {
      expect(
        MediaImageHelper.catalogPosterUrl('/library/metadata/1/thumb', width: 300, height: 450),
        '/library/metadata/1/thumb',
      );
      expect(MediaImageHelper.catalogPosterUrl(null, width: 300, height: 450), '');
      expect(MediaImageHelper.catalogPosterUrl('', width: 300, height: 450), '');
    });
  });

  group('MediaImageHelper.calculateOptimalDimensions (ImageType.art)', () {
    // Regression: a portrait hero box used to request a square-shaped source
    // at the box's own (portrait) ratio, which Plex's server-side crop then
    // honoured — slicing the sides off before Flutter ever saw the image.
    // The request must follow the *source*'s ratio, not the container's.
    test('a square request stays square after 40x60 bucketing', () {
      // Phone hero widths (see home_hero_layout_test.dart). Bucketing to 40px
      // width / 60px height steps skews the ratio more at small absolute
      // sizes, so this stays above typical phone widths rather than picking
      // an arbitrarily small one.
      for (final side in [353.0, 402.0, 430.0]) {
        final (width, height) = MediaImageHelper.calculateOptimalDimensions(
          maxWidth: side,
          maxHeight: side,
          devicePixelRatio: 2,
          imageType: ImageType.art,
        );

        final ratio = width / height;
        expect(ratio, closeTo(1.0, 0.05), reason: 'side=$side got ${width}x$height');
      }
    });

    test('a 16:9 request lands far closer to 1.78 than to a portrait container ratio', () {
      const containerRatio = 0.70; // roughly a phone-portrait hero box

      for (final width in [353.0, 402.0, 430.0]) {
        final (w, h) = MediaImageHelper.calculateOptimalDimensions(
          maxWidth: width,
          maxHeight: width * 9 / 16,
          devicePixelRatio: 2,
          imageType: ImageType.art,
        );

        final ratio = w / h;
        expect((ratio - 16 / 9).abs(), lessThan((ratio - containerRatio).abs()), reason: 'width=$width got ${w}x$h');
      }
    });
  });
}
