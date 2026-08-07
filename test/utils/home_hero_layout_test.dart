import 'package:flutter_test/flutter_test.dart';
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

    test('a wide window falls back to the 16:9 frame instead of a stunted hero', () {
      // iPad landscape-ish without side nav: leftover height is small, but the
      // billboard should still be as tall as its own aspect ratio wants.
      final hero = phoneHero(screenHeight: 500, screenWidth: 1200, bottomChrome: 60, statusBar: 24);

      expect(hero, greaterThan(500 - 60 - _episodeRail));
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
}
