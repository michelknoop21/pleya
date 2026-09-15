import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';

void main() {
  group('ScreenBreakpoints boundaries', () {
    test('isMobile: strict < 600', () {
      expect(ScreenBreakpoints.isMobile(0), isTrue);
      expect(ScreenBreakpoints.isMobile(599.9), isTrue);
      expect(ScreenBreakpoints.isMobile(600), isFalse);
    });

    test('isTablet: 600 ≤ w < 1200', () {
      expect(ScreenBreakpoints.isTablet(599.9), isFalse);
      expect(ScreenBreakpoints.isTablet(600), isTrue);
      expect(ScreenBreakpoints.isTablet(899.9), isTrue);
      expect(ScreenBreakpoints.isTablet(900), isTrue);
      expect(ScreenBreakpoints.isTablet(1199.9), isTrue);
      expect(ScreenBreakpoints.isTablet(1200), isFalse);
    });

    test('isWideTablet: 900 ≤ w < 1200', () {
      expect(ScreenBreakpoints.isWideTablet(899.9), isFalse);
      expect(ScreenBreakpoints.isWideTablet(900), isTrue);
      expect(ScreenBreakpoints.isWideTablet(1199.9), isTrue);
      expect(ScreenBreakpoints.isWideTablet(1200), isFalse);
    });

    test('isDesktop: 1200 ≤ w < 1600', () {
      expect(ScreenBreakpoints.isDesktop(1199.9), isFalse);
      expect(ScreenBreakpoints.isDesktop(1200), isTrue);
      expect(ScreenBreakpoints.isDesktop(1599.9), isTrue);
      expect(ScreenBreakpoints.isDesktop(1600), isFalse);
    });

    test('isLargeDesktop: w ≥ 1600', () {
      expect(ScreenBreakpoints.isLargeDesktop(1599.9), isFalse);
      expect(ScreenBreakpoints.isLargeDesktop(1600), isTrue);
      expect(ScreenBreakpoints.isLargeDesktop(10000), isTrue);
    });

    test('isDesktopOrLarger: w ≥ 1200', () {
      expect(ScreenBreakpoints.isDesktopOrLarger(1199.9), isFalse);
      expect(ScreenBreakpoints.isDesktopOrLarger(1200), isTrue);
      expect(ScreenBreakpoints.isDesktopOrLarger(5000), isTrue);
    });

    test('isWideTabletOrLarger: w ≥ 900', () {
      expect(ScreenBreakpoints.isWideTabletOrLarger(899.9), isFalse);
      expect(ScreenBreakpoints.isWideTabletOrLarger(900), isTrue);
      expect(ScreenBreakpoints.isWideTabletOrLarger(5000), isTrue);
    });

    test('constant values match expected thresholds', () {
      expect(ScreenBreakpoints.mobile, 600);
      expect(ScreenBreakpoints.tablet, 600);
      expect(ScreenBreakpoints.wideTablet, 900);
      expect(ScreenBreakpoints.desktop, 1200);
      expect(ScreenBreakpoints.largeDesktop, 1600);
    });

    test('partitioning: every width matches exactly one of mobile/tablet/desktop/largeDesktop', () {
      for (final w in const [0.0, 300, 599.9, 600, 899.9, 1199.9, 1200, 1599.9, 1600, 2500]) {
        final matches = [
          ScreenBreakpoints.isMobile(w.toDouble()),
          ScreenBreakpoints.isTablet(w.toDouble()) && !ScreenBreakpoints.isDesktopOrLarger(w.toDouble()),
          ScreenBreakpoints.isDesktop(w.toDouble()),
          ScreenBreakpoints.isLargeDesktop(w.toDouble()),
        ].where((b) => b).length;
        expect(matches, 1, reason: 'width $w should match exactly one tier');
      }
    });
  });

  group('J3: TvLayoutConstants.scaleForHeight floors at the lowest supported TV surface', () {
    test('918px (0.85x of the 1080p canvas) is the floor — nothing below it shrinks the scale further', () {
      expect(TvLayoutConstants.scaleForHeight(918), closeTo(0.85, 0.0001));
      // A genuinely tiny surface — well under any real TV output — still gets
      // the same floor, never a smaller or negative scale.
      expect(TvLayoutConstants.scaleForHeight(200), closeTo(0.85, 0.0001));
      expect(TvLayoutConstants.scaleForHeight(0), closeTo(0.85, 0.0001));
    });

    test('just above the floor still scales down proportionally, not snapping early', () {
      final at1000 = TvLayoutConstants.scaleForHeight(1000);
      expect(at1000, closeTo(1000 / 1080, 0.0001));
      expect(at1000, greaterThan(0.85));
    });
  });

  group('scaleOf: contract is TV-only, deterministic 1.0 everywhere else', () {
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('off TV, scaleOf is 1.0 regardless of viewport height', (tester) async {
      double? scale900;
      double? scale1440;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1200, 900)),
          child: Builder(
            builder: (context) {
              scale900 = TvLayoutConstants.scaleOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1200, 1440)),
          child: Builder(
            builder: (context) {
              scale1440 = TvLayoutConstants.scaleOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(scale900, 1.0, reason: 'a non-TV widget must not drift with window height');
      expect(scale1440, 1.0, reason: 'a non-TV widget must not drift with window height');
    });

    testWidgets('on TV, scaleOf still floors/clamps against the viewport height', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      double? scale;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1037.84, 583.78)),
          child: Builder(
            builder: (context) {
              scale = TvLayoutConstants.scaleOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(scale, closeTo(0.85, 0.0001), reason: 'TV behavior must be unchanged by the off-TV guard');
    });
  });
}
