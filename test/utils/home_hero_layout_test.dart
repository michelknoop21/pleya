import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart' show BillboardArtKind;
import 'package:pleya/utils/home_hero_layout.dart';

/// The rail the hero sizes itself against on a phone: a Continue Watching row
/// of 16:9 episode cards, as HubSectionState.railHeight computes it for a
/// ~402pt-wide phone (header 41 + artwork 105.8 + labels/focus 42).
const _episodeRail = 188.0;

/// A rail of 2:3 posters is far taller, which is why the hero has to know
/// which kind of rail sits below it.
const _posterRail = 262.0;

double phoneHero({
  required double screenHeight,
  required double screenWidth,
  required double bottomChrome,
  double statusBar = 59,
  double rail = _episodeRail,
}) => homeHeroHeight(
  useSideNav: false,
  viewportExtent: screenHeight - bottomChrome,
  screenHeight: screenHeight,
  screenWidth: screenWidth,
  statusBarHeight: statusBar,
  firstRailHeight: rail,
);

void main() {
  group('phone', () {
    test('hero plus the first rail exactly fills the viewport', () {
      // iPhone 16 Pro in logical points, tab bar with labels + home indicator.
      const height = 874.0, width = 402.0, chrome = 114.0;
      const viewport = height - chrome;

      final hero = phoneHero(screenHeight: height, screenWidth: width, bottomChrome: chrome);

      expect(hero + _episodeRail, closeTo(viewport, 0.5), reason: 'nothing below the first rail should be on screen');
      // The old fixed 52vh left ~64pt of the next rail peeking in.
      expect(hero, greaterThan((height * 0.52).clamp(360.0, 560.0) + 59));
    });

    test('a taller poster rail gets a shorter hero, not a cropped rail', () {
      const height = 874.0, width = 402.0, chrome = 114.0;

      final withEpisodes = phoneHero(screenHeight: height, screenWidth: width, bottomChrome: chrome);
      final withPosters = phoneHero(screenHeight: height, screenWidth: width, bottomChrome: chrome, rail: _posterRail);

      expect(withPosters, lessThan(withEpisodes));
      expect(withPosters + _posterRail, closeTo(height - chrome, 0.5));
    });

    test('holds up across phone sizes', () {
      // SE-class, standard, and Max-class — the fill must track the viewport
      // rather than a fraction that only looks right on one of them.
      for (final (h, w, chrome) in [(667.0, 375.0, 83.0), (874.0, 402.0, 114.0), (956.0, 440.0, 114.0)]) {
        final hero = phoneHero(screenHeight: h, screenWidth: w, bottomChrome: chrome);
        final viewport = h - chrome;
        // Either it fills exactly, or the cap kicked in on a short screen.
        final exact = (hero + _episodeRail - viewport).abs() < 0.5;
        expect(exact || hero == viewport * 0.82, isTrue, reason: 'h=$h w=$w hero=$hero viewport=$viewport');
        expect(hero, lessThan(viewport), reason: 'the rail must never be pushed fully off screen');
      }
    });

    test('a rail too tall to fit leaves the hero usable, not squeezed to nothing', () {
      // Contrived: a rail that would eat almost the whole viewport, so there is
      // no height left to fill. The floor wins over the leftover here — a 84pt
      // hero would be worse than letting the rail run past the fold.
      const viewport = 667.0 - 83.0;
      final hero = phoneHero(screenHeight: 667, screenWidth: 375, bottomChrome: 83, rail: 500);

      expect(hero, 360);
      expect(hero, lessThanOrEqualTo(viewport * 0.82));
      expect(viewport - hero, greaterThan(0), reason: 'part of the rail still shows, so the page reads as scrollable');
    });

    test('survives the viewport the search keyboard leaves behind', () {
      // The home tab keeps being laid out inside the IndexedStack while the
      // search tab has focus, so its viewport shrinks by the keyboard. Below
      // ~439pt the floor used to exceed the cap and the whole billboard threw,
      // which a release build renders as an empty box that never recovers.
      for (final viewport in [438.0, 400.0, 300.0, 120.0]) {
        final hero = homeHeroHeight(
          useSideNav: false,
          viewportExtent: viewport,
          screenHeight: 874,
          screenWidth: 402,
          statusBarHeight: 59,
          firstRailHeight: _episodeRail,
        );

        expect(hero, closeTo(viewport * 0.82, 0.001), reason: 'viewport=$viewport');
        expect(hero, lessThan(viewport), reason: 'viewport=$viewport');
      }
    });

    test('a collapsed viewport gives a zero hero instead of throwing', () {
      for (final viewport in [0.0, -10.0]) {
        expect(
          homeHeroHeight(
            useSideNav: false,
            viewportExtent: viewport,
            screenHeight: 874,
            screenWidth: 402,
            statusBarHeight: 59,
            firstRailHeight: _episodeRail,
          ),
          0,
          reason: 'viewport=$viewport',
        );
      }
    });

    test('a wide window falls back to the 16:9 frame instead of a stunted hero', () {
      // iPad landscape-ish without side nav: leftover height is small, but the
      // billboard should still be as tall as its own aspect ratio wants.
      final hero = phoneHero(screenHeight: 500, screenWidth: 1200, bottomChrome: 60, statusBar: 24);

      expect(hero, greaterThan(500 - 60 - _episodeRail));
    });

    test('total hero height is pinned at 353, 402, and 430pt wide', () {
      // Regression guard: the iOS billboard source-order and fade changes
      // must not shift `homeHeroHeight()` itself, nor the first rail's
      // position under it. Each case is set up so `fill` (viewport minus the
      // rail) is what wins, matching the (width, heroHeight) pairs already
      // used by the art-geometry and artwork-widget tests below/in
      // home_hero_artwork_test.dart, so all three suites agree on one shared
      // envelope.
      const cases = [
        (width: 353.0, screenHeight: 767.0, chrome: 79.0, expected: 500.0),
        (width: 402.0, screenHeight: 874.0, chrome: 114.0, expected: 572.0),
        (width: 430.0, screenHeight: 935.0, chrome: 97.0, expected: 650.0),
      ];
      for (final c in cases) {
        final hero = phoneHero(screenHeight: c.screenHeight, screenWidth: c.width, bottomChrome: c.chrome);
        expect(hero, closeTo(c.expected, 0.01), reason: 'width=${c.width}');
      }
    });
  });

  group('desktop and tablet', () {
    test('keep the fixed slice, ignoring the rail', () {
      final hero = homeHeroHeight(
        useSideNav: true,
        viewportExtent: 900,
        screenHeight: 1000,
        screenWidth: 1600,
        statusBarHeight: 0,
        firstRailHeight: _posterRail,
      );

      expect(hero, 750);
    });

    test('stay within their clamp on extreme window heights', () {
      double sideNav(double h) => homeHeroHeight(
        useSideNav: true,
        viewportExtent: h,
        screenHeight: h,
        screenWidth: 1600,
        statusBarHeight: 0,
        firstRailHeight: _posterRail,
      );

      expect(sideNav(400), 480);
      expect(sideNav(4000), 900);
    });
  });

  group('homeHeroArtGeometry', () {
    const phones = [(353.0, 500.0), (402.0, 572.0), (430.0, 650.0)];

    test('a narrow box with square art frames a square, never wider than the box', () {
      for (final (width, heroHeight) in phones) {
        final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: BillboardArtKind.square);

        expect(geometry.height, geometry.width, reason: 'w=$width h=$heroHeight');
        expect(geometry.requestHeight, width, reason: 'w=$width h=$heroHeight');
        expect(geometry.coversHero, isFalse, reason: 'w=$width h=$heroHeight');
        expect(geometry.height, lessThanOrEqualTo(heroHeight), reason: 'w=$width h=$heroHeight');
      }
    });

    test('a narrow box with widescreen art frames 16:9, requested at its own ratio', () {
      for (final (width, heroHeight) in phones) {
        final wide = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: BillboardArtKind.widescreen);

        expect(wide.height, closeTo(width * 9 / 16, 0.01), reason: 'w=$width h=$heroHeight');
        // Unlike the square branch (which requests a square), the request
        // follows the 16:9 source ratio too — never the box's own ratio.
        expect(wide.requestHeight, closeTo(width * 9 / 16, 0.01), reason: 'w=$width h=$heroHeight');
        expect(wide.coversHero, isFalse, reason: 'w=$width h=$heroHeight');
      }
    });

    test('a fallback source keeps the old full-bleed behaviour on any box', () {
      for (final (width, heroHeight) in [...phones, (1280.0, 720.0), (1600.0, 750.0)]) {
        final geometry = homeHeroArtGeometry(
          screenWidth: width,
          heroHeight: heroHeight,
          kind: BillboardArtKind.fallback,
        );

        expect(geometry.coversHero, isTrue, reason: 'w=$width h=$heroHeight');
        expect(geometry.width, width, reason: 'w=$width h=$heroHeight');
        expect(geometry.height, heroHeight, reason: 'w=$width h=$heroHeight');
        expect(
          geometry.requestHeight,
          closeTo((width * 9 / 16).clamp(heroHeight, double.infinity), 0.01),
          reason: 'w=$width h=$heroHeight',
        );
      }
    });

    test('a wide box keeps the old full-bleed behaviour regardless of source kind', () {
      for (final kind in [BillboardArtKind.widescreen, BillboardArtKind.square]) {
        for (final (width, heroHeight) in [(1280.0, 720.0), (1600.0, 750.0)]) {
          final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: kind);

          expect(geometry.coversHero, isTrue, reason: 'kind=$kind w=$width h=$heroHeight');
          expect(
            geometry.requestHeight,
            closeTo((width * 9 / 16).clamp(heroHeight, double.infinity), 0.01),
            reason: 'kind=$kind w=$width h=$heroHeight',
          );
        }
      }
    });

    test('the island frame envelope (width, height, coversHero) is pinned at 353, 402, and 430pt wide', () {
      for (final (width, heroHeight) in phones) {
        for (final kind in [BillboardArtKind.widescreen, BillboardArtKind.square]) {
          final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: kind);
          expect(geometry.width, width, reason: 'kind=$kind w=$width h=$heroHeight');
          expect(geometry.coversHero, isFalse, reason: 'kind=$kind w=$width h=$heroHeight');
          final expectedHeight = kind == BillboardArtKind.square ? math.min(width, heroHeight) : width * 9 / 16;
          expect(geometry.height, closeTo(expectedHeight, 0.01), reason: 'kind=$kind w=$width h=$heroHeight');
        }
      }
    });

    test('the fade is roughly half the frame height, always shorter than the frame', () {
      for (final (width, heroHeight) in phones) {
        final geometry = homeHeroArtGeometry(
          screenWidth: width,
          heroHeight: heroHeight,
          kind: BillboardArtKind.widescreen,
        );

        expect(geometry.fadeHeight, greaterThan(0), reason: 'w=$width h=$heroHeight');
        expect(geometry.fadeHeight, lessThan(geometry.height), reason: 'w=$width h=$heroHeight');
        expect(
          geometry.fadeHeight,
          closeTo(math.min(geometry.height * 0.5, 200.0), 0.01),
          reason: 'w=$width h=$heroHeight',
        );
      }
    });

    test('a collapsed viewport gives zero geometry, not a bad request', () {
      for (final (width, heroHeight) in [(0.0, 500.0), (402.0, 0.0), (-1.0, 500.0), (402.0, -1.0)]) {
        final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: BillboardArtKind.square);

        expect(geometry.width, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.height, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.requestHeight, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.coversHero, isFalse, reason: 'w=$width h=$heroHeight');
      }
    });
  });

  group('homeHeroLogoConstraints', () {
    test('a phone-width logo box stays within the padded hero and the 78% cap', () {
      for (final width in [353.0, 402.0, 430.0]) {
        final metrics = homeHeroLogoConstraints(screenWidth: width, isLargeScreen: false);

        expect(metrics.width, lessThanOrEqualTo(width - 48), reason: 'w=$width');
        expect(metrics.width, lessThanOrEqualTo(width * 0.78 + 0.01), reason: 'w=$width');
        expect(metrics.height, greaterThanOrEqualTo(90), reason: 'w=$width');
        expect(metrics.height, lessThanOrEqualTo(96), reason: 'w=$width');
      }
    });

    test('a large screen keeps the fixed 400x120 box', () {
      for (final width in [900.0, 1280.0, 1920.0]) {
        final metrics = homeHeroLogoConstraints(screenWidth: width, isLargeScreen: true);

        expect(metrics.width, 400);
        expect(metrics.height, 120);
      }
    });
  });
}
