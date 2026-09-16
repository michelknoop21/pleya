import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/detail_header_layout.dart';

/// Finding 2, review round on `docs/density-audit-2026-09.md`: F-D1's floor
/// (400 desktop / 360 tablet) guaranteed a usable backdrop on a short window,
/// but nothing bounded how far it could push past the window's own 60%
/// baseline — on a short enough window the floor could dominate the
/// viewport, and on one shorter than the floor itself the header could
/// literally exceed the window. No app-wide minimum window height exists
/// (grepped for `setMinimumSize` in `lib/`, `macos/`, `windows/`, `linux/`:
/// no hits), so an arbitrarily short desktop window is reachable.
void main() {
  group('detailHeaderHeight: the header never exceeds the viewport', () {
    test('invariant: headerHeight < screenHeight, across a sweep down to a near-zero window', () {
      for (final ceiling in [680.0, 600.0]) {
        for (final floor in [400.0, 360.0]) {
          for (final height in [1440.0, 900.0, 667.0, 600.0, 500.0, 410.0, 390.0, 300.0, 100.0, 1.0]) {
            final result = detailHeaderHeight(screenWidth: 1200, screenHeight: height, ceiling: ceiling, floor: floor);
            expect(
              result,
              lessThan(height),
              reason:
                  'floor=$floor ceiling=$ceiling height=$height produced $result, '
                  'which does not fit inside the window that asked for it',
            );
          }
        }
      }
    });

    test('desktop (floor 400): a 300pt-tall window used to get a 400pt header, taller than the window', () {
      final result = desktopDetailHeaderHeight(1200, 300);
      expect(result, lessThan(300));
    });

    test('desktop: the floor still yields a usable backdrop just above the natural 60% baseline', () {
      // 550pt is exactly the range the review called out: the raw floor (400)
      // would be 72.7% of this window. The fix must keep the floor doing its
      // job — clamping up from the 60% baseline — without letting it run away.
      final result = desktopDetailHeaderHeight(1200, 550);
      expect(result / 550, lessThanOrEqualTo(0.70), reason: 'floor must not claim more than 70% of a short window');
      expect(
        result / 550,
        greaterThan(0.6),
        reason: 'the floor should still lift a short window above the 60% baseline',
      );
    });
  });

  group('detailHeaderHeight: unchanged at every size this audit already measured (F-D1 regression)', () {
    test('desktop 1440x900 -> 540 (base, no clamp)', () {
      expect(desktopDetailHeaderHeight(1440, 900), closeTo(540.0, 0.01));
    });

    test('desktop 1920x1080 -> 648 (base, no clamp)', () {
      expect(desktopDetailHeaderHeight(1920, 1080), closeTo(648.0, 0.01));
    });

    test('desktop 2560x1440 -> 680 (ceiling)', () {
      expect(desktopDetailHeaderHeight(2560, 1440), closeTo(680.0, 0.01));
    });

    test('iPad portrait 1032x1376 -> 580.5 (16:9 cap)', () {
      expect(tabletDetailHeaderHeight(1032, 1376), closeTo(580.5, 0.01));
    });

    test('iPad landscape 1376x1032 -> 600 (ceiling)', () {
      expect(tabletDetailHeaderHeight(1376, 1032), closeTo(600.0, 0.01));
    });
  });

  group('detailHeaderHeight: the review-requested short-window matrix', () {
    test('desktop 1200x667: floor does not trigger (base already exceeds it)', () {
      final result = desktopDetailHeaderHeight(1200, 667);
      expect(result, closeTo(667 * 0.6, 0.5));
      expect(result, lessThan(667));
    });

    test('desktop 1200x600: floor lifts the header, but stays under the viewport and under 70%', () {
      final result = desktopDetailHeaderHeight(1200, 600);
      expect(result, lessThan(600));
      expect(result / 600, lessThanOrEqualTo(0.70));
    });

    test('tablet 1200x667: matches the desktop shape at the same height', () {
      final result = tabletDetailHeaderHeight(1200, 667);
      expect(result, lessThan(667));
    });

    test('tablet 1200x600: floor stays under the viewport and under 70%', () {
      final result = tabletDetailHeaderHeight(1200, 600);
      expect(result, lessThan(600));
      expect(result / 600, lessThanOrEqualTo(0.70));
    });
  });
}
