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

  // The hero artwork audit of 2 September 2026. `roundDimensions` clamped width
  // and height independently, so a request for the hero's 2.59 box went out as
  // a 1.78 one and Plex cropped to that before Flutter cropped again.
  group('MediaImageHelper aspect-ratio-aware rounding', () {
    // The measured Apple TV hero: 956.24 x 368.88 logical at dpr 3.7.
    const heroLogicalWidth = 956.24;
    const heroLogicalHeight = 368.88;
    const dpr = 3.7;
    const heroAr = heroLogicalWidth / heroLogicalHeight; // 2.592

    ({int w, int h}) request(ImageType type) {
      final (w, h) = MediaImageHelper.calculateOptimalDimensions(
        maxWidth: heroLogicalWidth,
        maxHeight: heroLogicalHeight,
        devicePixelRatio: dpr,
        imageType: type,
      );
      return (w: w, h: h);
    }

    test('heroArt keeps the intended hero aspect ratio within bucketing tolerance', () {
      final r = request(ImageType.heroArt);
      expect(r.w / r.h, closeTo(heroAr, heroAr * 0.03));
    });

    test('heroArt asks for at least the physical render size', () {
      final r = request(ImageType.heroArt);
      expect(r.w, greaterThanOrEqualTo((heroLogicalWidth * dpr).round()));
      expect(r.h, greaterThanOrEqualTo((heroLogicalHeight * dpr).round()));
    });

    test('plain art keeps its own smaller cap, so cards do not grow with the hero', () {
      expect(request(ImageType.art).w, lessThanOrEqualTo(2560));
    });

    // The three source ratios the audit measured. What is asserted is the
    // request shape, which is the thing the clamp used to destroy; the source
    // ratio does not enter the request at all, and that is the point -- one
    // request shape per container, not per artwork.
    for (final source in <({String name, double ar})>[
      (name: '2.40', ar: 2.40),
      (name: '1.78', ar: 16 / 9),
      (name: '1.48', ar: 1600 / 1080),
    ]) {
      test('a ${source.name} source still yields a request shaped like the hero, not like the source', () {
        final r = request(ImageType.heroArt);
        expect(r.w / r.h, closeTo(heroAr, heroAr * 0.03));
        expect(
          r.w / r.h,
          isNot(closeTo(source.ar, 0.05)),
          reason: 'the request follows the container, not the artwork',
        );
      });
    }

    test('an oversized box is fitted, not squared off', () {
      // 4:1, far past both caps: the old code returned 2560x1440 (1.78).
      final (w, h) = MediaImageHelper.roundDimensions(8000, 2000);
      expect(w / h, closeTo(4.0, 4.0 * 0.05));
    });

    test('a box inside the caps is only bucketed', () {
      final (w, h) = MediaImageHelper.roundDimensions(800, 600);
      expect(w, 800);
      expect(h, 600);
    });
  });
}
