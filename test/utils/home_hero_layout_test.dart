import 'dart:math' as math;

import 'package:flutter/material.dart' show kMinInteractiveDimension;
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
    // (width, heroHeight) pairs shared with home_hero_artwork_test.dart, so
    // both suites agree on one envelope. iPad-portrait heights are picked
    // comfortably taller than the width (as the real fill-to-rail formula
    // produces on a tall iPad viewport) so the square branch's clamp is
    // exercised by width alone, matching the phone cases below.
    const phones = [(353.0, 500.0), (402.0, 572.0), (430.0, 650.0)];
    const tabletsPortrait = [(768.0, 968.0), (834.0, 1034.0), (1024.0, 1224.0)];
    const allNarrow = [...phones, ...tabletsPortrait];

    test('a narrow box with square art frames a square at 0.82x the box width', () {
      for (final (width, heroHeight) in allNarrow) {
        final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: BillboardArtKind.square);

        expect(geometry.canvasWidth, width, reason: 'w=$width h=$heroHeight');
        expect(geometry.canvasHeight, heroHeight, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpWidth, geometry.sharpHeight, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpWidth, closeTo(width * 0.82, 0.01), reason: 'w=$width h=$heroHeight');
        expect(geometry.requestWidth, geometry.sharpWidth, reason: 'w=$width h=$heroHeight');
        expect(geometry.requestHeight, geometry.sharpHeight, reason: 'w=$width h=$heroHeight');
        expect(geometry.useAmbientLayer, isTrue, reason: 'w=$width h=$heroHeight');
        expect(geometry.coversHero, isFalse, reason: 'w=$width h=$heroHeight');
        expect(geometry.hasSharpForeground, isTrue, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpWidth, lessThanOrEqualTo(width), reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpHeight, lessThanOrEqualTo(heroHeight), reason: 'w=$width h=$heroHeight');
      }
    });

    test('a narrow box with widescreen art frames a screen-wide 16:9 strip', () {
      for (final (width, heroHeight) in allNarrow) {
        final wide = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: BillboardArtKind.widescreen);

        expect(wide.canvasWidth, width, reason: 'w=$width h=$heroHeight');
        expect(wide.canvasHeight, heroHeight, reason: 'w=$width h=$heroHeight');
        expect(wide.sharpWidth, width, reason: 'w=$width h=$heroHeight');
        expect(wide.sharpHeight, closeTo(width * 9 / 16, 0.01), reason: 'w=$width h=$heroHeight');
        // Unlike the square branch (a smaller island), the widescreen island
        // is already screen-wide — the request follows its own 16:9 ratio.
        expect(wide.requestWidth, wide.sharpWidth, reason: 'w=$width h=$heroHeight');
        expect(wide.requestHeight, wide.sharpHeight, reason: 'w=$width h=$heroHeight');
        expect(wide.useAmbientLayer, isTrue, reason: 'w=$width h=$heroHeight');
        expect(wide.coversHero, isFalse, reason: 'w=$width h=$heroHeight');
      }
    });

    test('a fallback source keeps the old full-bleed behaviour on any box', () {
      for (final (width, heroHeight) in [...allNarrow, (1280.0, 720.0), (1600.0, 750.0)]) {
        final geometry = homeHeroArtGeometry(
          screenWidth: width,
          heroHeight: heroHeight,
          kind: BillboardArtKind.fallback,
        );

        expect(geometry.coversHero, isTrue, reason: 'w=$width h=$heroHeight');
        expect(geometry.useAmbientLayer, isFalse, reason: 'w=$width h=$heroHeight');
        expect(geometry.hasSharpForeground, isTrue, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpWidth, width, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpHeight, heroHeight, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpFadeHeight, 0, reason: 'w=$width h=$heroHeight');
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
          expect(geometry.useAmbientLayer, isFalse, reason: 'kind=$kind w=$width h=$heroHeight');
          expect(geometry.sharpFadeHeight, 0, reason: 'kind=$kind w=$width h=$heroHeight');
          expect(
            geometry.requestHeight,
            closeTo((width * 9 / 16).clamp(heroHeight, double.infinity), 0.01),
            reason: 'kind=$kind w=$width h=$heroHeight',
          );
        }
      }
    });

    test('the island envelope (sharpWidth, sharpHeight, coversHero) is pinned at 353/402/430 and 768/834/1024', () {
      for (final (width, heroHeight) in allNarrow) {
        for (final kind in [BillboardArtKind.widescreen, BillboardArtKind.square]) {
          final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: kind);
          expect(geometry.coversHero, isFalse, reason: 'kind=$kind w=$width h=$heroHeight');
          final expectedWidth = kind == BillboardArtKind.square ? width * 0.82 : width;
          expect(geometry.sharpWidth, closeTo(expectedWidth, 0.01), reason: 'kind=$kind w=$width h=$heroHeight');
          final expectedHeight = kind == BillboardArtKind.square ? width * 0.82 : width * 9 / 16;
          expect(geometry.sharpHeight, closeTo(expectedHeight, 0.01), reason: 'kind=$kind w=$width h=$heroHeight');
        }
      }
    });

    test('the fade begins at 55% of the sharp island height and always ends fully faded', () {
      for (final (width, heroHeight) in allNarrow) {
        final geometry = homeHeroArtGeometry(
          screenWidth: width,
          heroHeight: heroHeight,
          kind: BillboardArtKind.widescreen,
        );

        expect(geometry.sharpFadeHeight, greaterThan(0), reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpFadeHeight, lessThan(geometry.sharpHeight), reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpFadeHeight, closeTo(geometry.sharpHeight * 0.45, 0.01), reason: 'w=$width h=$heroHeight');
      }
    });

    test('a collapsed viewport gives zero, unusable geometry, not a bad request', () {
      for (final (width, heroHeight) in [(0.0, 500.0), (402.0, 0.0), (-1.0, 500.0), (402.0, -1.0)]) {
        final geometry = homeHeroArtGeometry(screenWidth: width, heroHeight: heroHeight, kind: BillboardArtKind.square);

        expect(geometry.canvasWidth, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.canvasHeight, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpWidth, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.sharpHeight, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.requestWidth, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.requestHeight, 0, reason: 'w=$width h=$heroHeight');
        expect(geometry.hasSharpForeground, isFalse, reason: 'w=$width h=$heroHeight');
        expect(geometry.useAmbientLayer, isFalse, reason: 'w=$width h=$heroHeight');
        expect(geometry.coversHero, isFalse, reason: 'w=$width h=$heroHeight');
      }
    });
  });

  /// The sharp layer used to be top-anchored at `y = 0`, which on an iPhone
  /// hid its top edge under the Dynamic Island. `requestedSharpTop` moves its
  /// top edge clear and, on iPhone portrait, tells it where to become fully
  /// opaque; `presentation` decides the composition: edge-to-edge on a phone,
  /// the 0.82 island everywhere else.
  ///
  /// The top anchor only ever offsets. An earlier attempt shrank the layer by
  /// the inset and let the width follow the source ratio, which turned a
  /// 402pt hero into a 320pt centred card.
  group('homeHeroSharpOpaqueInset', () {
    test('adds the control row and its padding on top of the safe-area', () {
      expect(homeHeroSharpOpaqueInset(statusBarHeight: 62), closeTo(126, 0.001));
      expect(homeHeroSharpOpaqueInset(statusBarHeight: 20), closeTo(84, 0.001));
      expect(homeHeroSharpOpaqueInset(statusBarHeight: 0), closeTo(64, 0.001));
      expect(homeHeroSharpOpaqueInset(statusBarHeight: 59), closeTo(123, 0.001));
    });

    test('matches the sum of the four shared constants, not a copied literal', () {
      for (final statusBarHeight in [0.0, 20.0, 59.0, 62.0]) {
        expect(
          homeHeroSharpOpaqueInset(statusBarHeight: statusBarHeight),
          closeTo(
            statusBarHeight + homeAppBarControlVerticalPadding + homeAppBarControlRowHeight + homeHeroArtworkTopGap,
            0.001,
          ),
          reason: 'statusBarHeight=$statusBarHeight',
        );
      }
    });

    test('the control row height matches a Material tap target', () {
      expect(homeAppBarControlRowHeight, kMinInteractiveDimension);
    });

    test('the outer bottom padding is not part of the formula', () {
      // It belongs to the appbar box's own layout tail, not to the artwork
      // above it — pinned here so it never sneaks into the sum above.
      expect(homeAppBarOuterBottomPadding, 8.0);
      expect(
        homeHeroSharpOpaqueInset(statusBarHeight: 62),
        isNot(
          closeTo(
            62 +
                homeAppBarControlVerticalPadding +
                homeAppBarControlRowHeight +
                homeHeroArtworkTopGap +
                homeAppBarOuterBottomPadding,
            0.001,
          ),
        ),
      );
    });
  });

  group('homeHeroArtGeometry with a sharp top inset', () {
    const phones = [(353.0, 500.0), (402.0, 572.0), (430.0, 650.0)];
    const kinds = [BillboardArtKind.square, BillboardArtKind.widescreen];

    /// The iPhone case: `viewPadding.top`, with nothing added to it — no
    /// opaque anchor, so no fade-in band either.
    const inset = 62.0;

    HomeHeroArtGeometry fullWidth(double width, double height, BillboardArtKind kind, {double topInset = inset}) =>
        homeHeroArtGeometry(
          screenWidth: width,
          heroHeight: height,
          kind: kind,
          requestedSharpTop: HomeHeroSharpTopAnchors(top: topInset, opaque: topInset),
          presentation: HomeHeroSharpPresentation.fullWidth,
        );

    test('full width means exactly the canvas width, for both source kinds', () {
      for (final (width, height) in phones) {
        for (final kind in kinds) {
          final g = fullWidth(width, height, kind);
          final label = 'w=$width h=$height kind=$kind';

          expect(g.sharpWidth, closeTo(width, 0.001), reason: label);
          expect(g.sharpWidth, closeTo(g.canvasWidth, 0.001), reason: label);
          expect(g.presentation, HomeHeroSharpPresentation.fullWidth, reason: label);
        }
      }
    });

    test('the square branch holds its source ratio exactly; the widescreen strip gets its own box height', () {
      for (final (width, height) in phones) {
        final square = fullWidth(width, height, BillboardArtKind.square);
        expect(square.sharpHeight, closeTo(width, 0.001), reason: 'w=$width');
        expect(square.sharpWidth / square.sharpHeight, closeTo(1.0, 0.001), reason: 'w=$width');

        // The widescreen box is no longer derived from the 16:9 source: its
        // height is `min(width * 0.72, 292)`, clamped by whatever the hero
        // leaves under the inset — `cover` crops the source to fit, it does
        // not shrink the box.
        final wide = fullWidth(width, height, BillboardArtKind.widescreen);
        final expectedHeight = math.min(math.min(width * 0.72, 292.0), height - inset);
        expect(wide.sharpHeight, closeTo(expectedHeight, 0.01), reason: 'w=$width');
        expect(wide.sharpWidth, closeTo(width, 0.001), reason: 'still full width: w=$width');
        expect(wide.sharpUsesCoverFit, isTrue, reason: 'w=$width');
      }
    });

    test('the inset offsets and never resizes', () {
      for (final (width, height) in phones) {
        for (final kind in kinds) {
          final at0 = fullWidth(width, height, kind, topInset: 0);
          final at62 = fullWidth(width, height, kind);
          final label = 'w=$width h=$height kind=$kind';

          expect(at62.sharpWidth, closeTo(at0.sharpWidth, 0.001), reason: 'width unchanged by the inset: $label');
          expect(at62.sharpHeight, closeTo(at0.sharpHeight, 0.001), reason: 'height unchanged by the inset: $label');
          expect(at62.sharpTopInset, closeTo(inset, 0.001), reason: label);
          expect(at0.sharpTopInset, 0, reason: label);
          // The whole layer moves down by the inset, nothing is trimmed.
          expect(at62.sharpTopInset + at62.sharpHeight, closeTo(at0.sharpHeight + inset, 0.001), reason: label);

          // Neither does the opaque anchor: it only shifts where the layer
          // reaches full opacity, never its size.
          final withOpaque = homeHeroArtGeometry(
            screenWidth: width,
            heroHeight: height,
            kind: kind,
            requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 126),
            presentation: HomeHeroSharpPresentation.fullWidth,
          );
          expect(withOpaque.sharpWidth, closeTo(at62.sharpWidth, 0.001), reason: 'width unchanged: $label');
          expect(withOpaque.sharpHeight, closeTo(at62.sharpHeight, 0.001), reason: 'height unchanged: $label');
          expect(withOpaque.sharpOpaqueTopInset, closeTo(126, 0.001), reason: label);
        }
      }
    });

    test('the geometry echoes whatever anchors it is handed', () {
      // homeHeroArtGeometry never derives the anchors itself — they are a
      // pure offset, and it is the caller's job (homeHeroSharpTopAnchors,
      // exercised above) to decide what they mean.
      for (final topInset in [0.0, 44.0, 59.0, 62.0]) {
        final g = fullWidth(402, 572, BillboardArtKind.widescreen, topInset: topInset);
        expect(g.sharpTopInset, closeTo(topInset, 0.001), reason: 'topInset=$topInset');
      }

      // An incoherent pair (opaque above top) reads as "no blend", not as a
      // negative band.
      final incoherent = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 10),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(incoherent.sharpTopInset, closeTo(62, 0.001));
      expect(incoherent.sharpOpaqueTopInset, closeTo(62, 0.001), reason: 'clamped up to the top anchor');
      expect(incoherent.sharpTopBlendHeight, 0);
    });

    test(
      'the request size matches the sharp rect exactly, except the widescreen strip which requests wider for its cover crop',
      () {
        for (final (width, height) in phones) {
          for (final kind in kinds) {
            final g = fullWidth(width, height, kind);
            final label = 'w=$width h=$height kind=$kind';
            expect(g.requestHeight, g.sharpHeight, reason: label);
            if (kind == BillboardArtKind.widescreen) {
              // The box is no longer 16:9, so the transcode request asks for
              // the full 16:9-ratio width at the target height instead of the
              // (narrower) box width — otherwise `BoxFit.cover` would crop a
              // too-small image rather than the source.
              expect(g.requestWidth, closeTo(g.sharpHeight * 16 / 9, 0.01), reason: label);
            } else {
              expect(g.requestWidth, g.sharpWidth, reason: label);
            }
          }
        }
      },
    );

    test('the 402pt iPhone lands on the numbers this change was specified with', () {
      // This is the caller's contract, not the primitive's: DiscoverScreen
      // passes homeHeroSharpTopAnchors(statusBarHeight: 62) — top at the raw
      // 62pt safe-area, opaque at homeHeroSharpOpaqueInset(...) == 126.
      final anchors = homeHeroSharpTopAnchors(statusBarHeight: 62);
      expect(anchors.top, closeTo(62, 0.001));
      expect(anchors.opaque, closeTo(126, 0.001));
      expect(anchors.blend, closeTo(64, 0.001));

      final square = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.square,
        requestedSharpTop: anchors,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(square.sharpWidth, closeTo(402, 0.01));
      expect(square.sharpHeight, closeTo(402, 0.01));
      expect(square.sharpTopInset, closeTo(62, 0.01));
      expect(square.sharpOpaqueTopInset, closeTo(126, 0.01));
      expect(square.sharpTopBlendHeight, closeTo(64, 0.01));

      final wide = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: anchors,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(wide.sharpWidth, closeTo(402, 0.01));
      // 402 * 0.72 = 289.44, under the 292 cap and under the 510pt this hero
      // leaves under the inset — the fraction wins.
      expect(wide.sharpHeight, closeTo(289.44, 0.01));
      expect(wide.sharpTopInset, closeTo(62, 0.01));
      expect(wide.sharpOpaqueTopInset, closeTo(126, 0.01));
      expect(wide.sharpTopBlendHeight, closeTo(64, 0.01));
      // This is the one shape whose request width diverges from its box
      // width: the box height no longer matches the source's 16:9 ratio, so
      // the request asks for the full ratio at the target height.
      expect(wide.requestWidth, closeTo(289.44 * 16 / 9, 0.01));
    });

    test('the fade band stays at 45% of the sharp height', () {
      for (final (width, height) in phones) {
        for (final kind in kinds) {
          final g = fullWidth(width, height, kind);
          expect(g.sharpFadeHeight / g.sharpHeight, closeTo(0.45, 0.001), reason: 'w=$width kind=$kind');
        }
      }
    });

    test('the island presentation is untouched — the regression pin for iPad and every other caller', () {
      for (final (width, height) in [...phones, (768.0, 968.0), (834.0, 1034.0), (1024.0, 1224.0)]) {
        for (final kind in kinds) {
          final legacy = homeHeroArtGeometry(screenWidth: width, heroHeight: height, kind: kind);
          final explicit = homeHeroArtGeometry(
            screenWidth: width,
            heroHeight: height,
            kind: kind,
            requestedSharpTop: HomeHeroSharpTopAnchors.none,
            presentation: HomeHeroSharpPresentation.island,
          );
          final label = 'w=$width h=$height kind=$kind';

          expect(legacy.presentation, HomeHeroSharpPresentation.island, reason: 'island is the default: $label');
          expect(explicit.sharpWidth, legacy.sharpWidth, reason: label);
          expect(explicit.sharpHeight, legacy.sharpHeight, reason: label);
          expect(explicit.sharpTopInset, 0, reason: label);
          expect(explicit.sharpFadeHeight, legacy.sharpFadeHeight, reason: label);
          expect(explicit.requestWidth, legacy.requestWidth, reason: label);
          expect(explicit.requestHeight, legacy.requestHeight, reason: label);
          expect(explicit.coversHero, legacy.coversHero, reason: label);
        }

        // The island square is still 0.82 of the box, not the full width.
        final island = homeHeroArtGeometry(screenWidth: width, heroHeight: height, kind: BillboardArtKind.square);
        expect(island.sharpWidth, closeTo(width * 0.82, 0.01), reason: 'w=$width');
        expect(island.sharpWidth, lessThan(width), reason: 'w=$width');
      }
    });

    test('a negative inset is clamped to zero, never used to move the layer up', () {
      for (final kind in kinds) {
        final g = fullWidth(402, 572, kind, topInset: -40);
        expect(g.sharpTopInset, 0, reason: 'kind=$kind');
        expect(g.sharpWidth, closeTo(402, 0.001), reason: 'kind=$kind');
      }
    });

    test('the full-bleed branch ignores both the anchors and the presentation', () {
      final wideBox = homeHeroArtGeometry(
        screenWidth: 1280,
        heroHeight: 500,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 126),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(wideBox.coversHero, isTrue);
      expect(wideBox.sharpTopInset, 0);
      expect(wideBox.sharpOpaqueTopInset, 0);
      expect(wideBox.sharpHeight, 500);
      expect(wideBox.sharpWidth, 1280);

      final fallback = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 572,
        kind: BillboardArtKind.fallback,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 126),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(fallback.coversHero, isTrue);
      expect(fallback.sharpTopInset, 0);
      expect(fallback.sharpOpaqueTopInset, 0);
      expect(fallback.sharpHeight, 572);
      expect(fallback.sharpWidth, 402);
    });

    test('a hero too short for a full-width square shrinks it instead of lying about its size', () {
      // Reachable on a 375pt phone whose first rail drives homeHeroHeight to
      // its 360pt floor. Unclamped, the geometry reported 375x375 while layout
      // squeezed the box to 375x340 and BoxFit.contain drew 340x340 with 17.5pt
      // of ambient down each side — and both fade bands computed their stops
      // from a height the layer never had.
      final g = homeHeroArtGeometry(
        screenWidth: 375,
        heroHeight: 360,
        kind: BillboardArtKind.square,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 20, opaque: 20),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(g.sharpHeight, closeTo(340, 0.001), reason: 'heroHeight 360 minus the 20pt inset');
      expect(g.sharpWidth, closeTo(340, 0.001), reason: 'still exactly 1:1');
      expect(g.sharpTopInset + g.sharpHeight, lessThanOrEqualTo(360.001), reason: 'fits under the inset');
    });

    test('a square source on a real 402pt iPhone: no size change once the top moves to 62', () {
      // heroHeight 470 is above the new fitScale-1 threshold (>= 464) but
      // below the old one (>= 528): under the old 126pt inset this would have
      // scaled down; under the new 62pt top anchor it does not.
      final anchors = homeHeroSharpTopAnchors(statusBarHeight: 62);
      final g = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 470,
        kind: BillboardArtKind.square,
        requestedSharpTop: anchors,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(g.sharpWidth, closeTo(402, 0.001));
      expect(g.sharpHeight, closeTo(402, 0.001));
      expect(g.sharpTopInset, closeTo(62, 0.001));
      expect(g.sharpTopBlendHeight, closeTo(64, 0.001));
    });

    test('a square source below the new threshold is genuinely larger than the old inset gave it', () {
      // heroHeight 410 is below both thresholds, so both old (126) and new
      // (62) insets scale the layer down — but the new one leaves 64pt more
      // room, so the layer (and its bottom fade) comes out larger, not just
      // shifted.
      const oldInset = 126.0;
      final old = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 410,
        kind: BillboardArtKind.square,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: oldInset, opaque: oldInset),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      final anchors = homeHeroSharpTopAnchors(statusBarHeight: 62);
      final g = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 410,
        kind: BillboardArtKind.square,
        requestedSharpTop: anchors,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(old.sharpHeight, closeTo(284.0, 0.5), reason: '410 - 126, scaled 1:1');
      expect(g.sharpHeight, closeTo(348.0, 0.5), reason: '410 - 62, scaled 1:1');
      expect(g.sharpHeight - old.sharpHeight, closeTo(64.0, 0.5), reason: 'the full 64pt shows up as size, not shift');
      expect(g.sharpWidth, closeTo(g.sharpHeight, 0.001), reason: 'still exactly 1:1');
      expect(g.sharpFadeHeight, greaterThan(old.sharpFadeHeight), reason: 'the bottom fade scales with the layer');
    });

    test('a short hero clamps the full-width widescreen strip on its height, keeping it full width', () {
      // 375/270 = 1.389, just inside the 1.39 narrow-box threshold, so this
      // still takes the island/full-width path rather than the full-bleed one.
      // The box's natural height (min(375*0.72, 292) = 270) is taller than the
      // 208pt left under a 62pt inset, so the height clamp bites.
      final g = homeHeroArtGeometry(
        screenWidth: 375,
        heroHeight: 270,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 62),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(g.coversHero, isFalse, reason: 'precondition: still a narrow box');
      expect(g.sharpHeight, closeTo(208, 0.001), reason: '270 minus the 62pt inset');
      expect(g.sharpTopInset + g.sharpHeight, lessThanOrEqualTo(270.001));
      // Unlike the old contain-fit box, the height clamp never shrinks the
      // width: `cover` crops the source instead, so the strip stays edge to
      // edge.
      expect(g.sharpWidth, closeTo(375, 0.001), reason: 'stays full width');
      expect(g.sharpUsesCoverFit, isTrue);
    });

    test('every full-width layer fits under its own anchors, across a sweep of hero heights', () {
      for (final width in [353.0, 375.0, 402.0, 430.0]) {
        for (final height in [360.0, 400.0, 460.0, 500.0, 572.0, 650.0]) {
          for (final kind in [BillboardArtKind.square, BillboardArtKind.widescreen]) {
            for (final top in [0.0, 44.0, 62.0, 59.0]) {
              // Mirrors the real iPhone contract (opaque 64pt past top) so the
              // sweep also exercises sharpTopBlendHeight's own clamp, not just
              // the position math.
              final g = homeHeroArtGeometry(
                screenWidth: width,
                heroHeight: height,
                kind: kind,
                requestedSharpTop: HomeHeroSharpTopAnchors(top: top, opaque: top + 64),
                presentation: HomeHeroSharpPresentation.fullWidth,
              );
              if (!g.hasSharpForeground) continue;
              final label = 'w=$width h=$height kind=$kind top=$top';
              expect(g.sharpTopInset + g.sharpHeight, lessThanOrEqualTo(height + 0.001), reason: label);
              expect(g.sharpWidth, lessThanOrEqualTo(width + 0.001), reason: label);
              if (kind == BillboardArtKind.square) {
                expect(g.sharpWidth / g.sharpHeight, closeTo(1.0, 0.001), reason: 'ratio held: $label');
              } else {
                // The widescreen strip no longer holds the source ratio in
                // its own box — it stays full width and lets `cover` crop.
                expect(g.sharpWidth, closeTo(width, 0.001), reason: 'always full width: $label');
                expect(
                  g.sharpHeight,
                  lessThanOrEqualTo(math.min(width * 0.72, 292.0) + 0.001),
                  reason: 'clamped by the viewport-height formula: $label',
                );
              }
              expect(
                g.sharpTopBlendHeight + g.sharpFadeHeight,
                lessThanOrEqualTo(g.sharpHeight + 0.001),
                reason: 'the two blend bands fit inside the layer: $label',
              );
            }
          }
        }
      }
    });

    test('the widescreen strip height formula: fraction, cap, and available-height each get their own case', () {
      // Fraction bites: 402 * 0.72 = 289.44, well under the 292 cap and under
      // what a tall hero leaves under the inset.
      final fractionWins = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 800,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 62),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(fractionWins.sharpHeight, closeTo(289.44, 0.01));
      expect(fractionWins.sharpWidth, closeTo(402, 0.001));

      // Cap bites: 500 * 0.72 = 360 > 292, so the 292 ceiling wins on a wide
      // phone/tall hero, not the fraction.
      final capWins = homeHeroArtGeometry(
        screenWidth: 500,
        heroHeight: 800,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 62),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(capWins.sharpHeight, closeTo(292.0, 0.01));
      expect(capWins.sharpWidth, closeTo(500, 0.001));

      // availableSharpHeight bites: a short hero leaves less room than either
      // the fraction or the cap would ask for, and the strip stays full width
      // regardless — `cover` crops the source, the box never narrows.
      final availableWins = homeHeroArtGeometry(
        screenWidth: 402,
        heroHeight: 300,
        kind: BillboardArtKind.widescreen,
        requestedSharpTop: const HomeHeroSharpTopAnchors(top: 62, opaque: 62),
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(availableWins.sharpHeight, closeTo(238, 0.01), reason: '300 - 62');
      expect(availableWins.sharpWidth, closeTo(402, 0.001));
    });

    test('the full-bleed branch reports the presentation it was handed', () {
      final g = homeHeroArtGeometry(
        screenWidth: 1280,
        heroHeight: 500,
        kind: BillboardArtKind.widescreen,
        presentation: HomeHeroSharpPresentation.fullWidth,
      );
      expect(g.coversHero, isTrue);
      expect(g.presentation, HomeHeroSharpPresentation.fullWidth, reason: 'no silent downgrade to island');
      expect(g.sharpTopBlendHeight, 0, reason: 'a covering frame has nothing beneath it to blend into');
    });

    test('an inset taller than the hero drops the sharp layer, keeping the ambient wash', () {
      for (final (width, height) in phones) {
        for (final kind in kinds) {
          final g = fullWidth(width, height, kind, topInset: height + 1);
          final label = 'w=$width h=$height kind=$kind';

          expect(g.hasSharpForeground, isFalse, reason: label);
          expect(g.useAmbientLayer, isTrue, reason: 'the ambient wash still carries the hero: $label');
          expect(g.coversHero, isFalse, reason: label);
          expect(g.sharpWidth, 0, reason: label);
          expect(g.sharpHeight, 0, reason: label);
          expect(g.sharpFadeHeight, 0, reason: label);
          // Never a silent fall back to inset 0 at full size — that is the
          // exact defect this inset exists to remove.
          expect(g.sharpTopInset, 0, reason: label);
          expect(g.requestWidth, greaterThan(0), reason: label);
          expect(g.requestHeight, greaterThan(0), reason: label);
        }
      }
    });
  });

  group('homeHeroLogoConstraints', () {
    test('phone stays within the padded hero and the 78% cap', () {
      for (final width in [353.0, 402.0, 430.0]) {
        final metrics = homeHeroLogoConstraints(screenWidth: width, tier: HomeHeroContentTier.phone);

        expect(metrics.width, lessThanOrEqualTo(width - 48), reason: 'w=$width');
        expect(metrics.width, lessThanOrEqualTo(width * 0.78 + 0.01), reason: 'w=$width');
        expect(metrics.height, greaterThanOrEqualTo(90), reason: 'w=$width');
        expect(metrics.height, lessThanOrEqualTo(96), reason: 'w=$width');
      }
    });

    test('tabletPortrait scales up to a visibly larger logo, capped at 520x160', () {
      // Pinned to the mockup-derived formula: width = min(520, min(w*0.55, w-64)),
      // height = (w*0.18).clamp(120, 160).
      const cases = [(768.0, 422.4, 138.24), (834.0, 458.7, 150.12), (1024.0, 520.0, 160.0)];
      for (final (width, expectedWidth, expectedHeight) in cases) {
        final metrics = homeHeroLogoConstraints(screenWidth: width, tier: HomeHeroContentTier.tabletPortrait);

        expect(metrics.width, closeTo(expectedWidth, 0.5), reason: 'w=$width');
        expect(metrics.height, closeTo(expectedHeight, 0.5), reason: 'w=$width');
        expect(metrics.width, lessThanOrEqualTo(520), reason: 'w=$width');
        expect(metrics.height, lessThanOrEqualTo(160), reason: 'w=$width');
        expect(metrics.width, lessThanOrEqualTo(width - 64), reason: 'w=$width');
        // Visibly bigger than the phone formula would give at this width —
        // the whole point of the tabletPortrait-specific formula.
        final phoneMetrics = homeHeroLogoConstraints(screenWidth: width, tier: HomeHeroContentTier.phone);
        expect(metrics.width, greaterThan(phoneMetrics.width), reason: 'w=$width');
        expect(metrics.height, greaterThan(phoneMetrics.height), reason: 'w=$width');
      }
    });

    test('wide keeps the fixed 400x120 box', () {
      for (final width in [900.0, 1280.0, 1920.0]) {
        final metrics = homeHeroLogoConstraints(screenWidth: width, tier: HomeHeroContentTier.wide);

        expect(metrics.width, 400);
        expect(metrics.height, 120);
      }
    });
  });

  group('homeHeroContentMetrics', () {
    test('phone rhythm: pinned values, no overlap with the pagination row', () {
      final metrics = homeHeroContentMetrics(tier: HomeHeroContentTier.phone);

      expect(metrics.logoToMeta, 12);
      expect(metrics.metaToButton, 16);
      expect(metrics.buttonToSummary, 12);
      expect(metrics.paginationHeight, 18);
      expect(metrics.paginationBottomInset, 16);
      expect(metrics.contentBottomInset, 48);
      expect(metrics.maxContentWidth, isNull);
      // The content column's own bottom anchor must sit at or above the
      // pagination row's top edge, with the declared gap between them.
      final paginationTop = metrics.paginationBottomInset + metrics.paginationHeight;
      expect(metrics.contentBottomInset, greaterThanOrEqualTo(paginationTop), reason: 'no overlap');
      expect(metrics.contentBottomInset - paginationTop, closeTo(metrics.contentToPagination, 0.01));
      expect(metrics.paginationToRailHeading, inInclusiveRange(16, 20));
    });

    test('tabletPortrait shares the phone rhythm but caps content width at 600', () {
      final metrics = homeHeroContentMetrics(tier: HomeHeroContentTier.tabletPortrait);
      final phoneMetrics = homeHeroContentMetrics(tier: HomeHeroContentTier.phone);

      expect(metrics.logoToMeta, phoneMetrics.logoToMeta);
      expect(metrics.metaToButton, phoneMetrics.metaToButton);
      expect(metrics.buttonToSummary, phoneMetrics.buttonToSummary);
      expect(metrics.contentBottomInset, phoneMetrics.contentBottomInset);
      expect(metrics.maxContentWidth, 600);
      expect(metrics.paginationToRailHeading, inInclusiveRange(16, 24));
    });

    test('wide keeps the hero content rhythm this layout always used', () {
      final metrics = homeHeroContentMetrics(tier: HomeHeroContentTier.wide);

      expect(metrics.logoToMeta, 16);
      expect(metrics.metaToButton, 20);
      expect(metrics.buttonToSummary, 12);
      expect(metrics.contentBottomInset, 80);
      expect(metrics.maxContentWidth, isNull);
    });
  });
}
