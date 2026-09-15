import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/media_grid_delegate.dart';

/// F-D2 (docs/density-audit-2026-09.md): `MediaGridDelegate.spacingFor` used
/// to read `TvLayoutConstants.scaleOf(context)` unconditionally, so a plain
/// desktop/iPad grid's own poster spacing drifted with the window's height —
/// 10.2 at 900pt tall, 12 at 1080pt, 16 at 1440pt — even off TV, where
/// nothing is a ten-foot surface. It must now stay pinned to scale 1 off TV,
/// and TV must stay bit-for-bit unchanged.
void main() {
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<double> spacingAt(WidgetTester tester, double height, {bool fullBleedImage = false}) async {
    tester.view.physicalSize = Size(1200, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late double spacing;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            spacing = MediaGridDelegate.spacingFor(context: context, fullBleedImage: fullBleedImage);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return spacing;
  }

  group('off TV: pinned to scale 1 regardless of window height', () {
    for (final height in [900.0, 1080.0, 1440.0]) {
      testWidgets('height=$height -> spacing stays ${GridLayoutConstants.posterGridSpacingForScale(1)}', (
        tester,
      ) async {
        final spacing = await spacingAt(tester, height);
        expect(spacing, GridLayoutConstants.posterGridSpacingForScale(1));
      });
    }

    testWidgets('2560x1440 desktop window: still 12, not the old drifted 16', (tester) async {
      final spacing = await spacingAt(tester, 1440);
      expect(spacing, 12.0);
    });
  });

  group('on TV: unchanged, still scales with scaleOf', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));

    for (final height in [900.0, 1080.0, 1440.0]) {
      testWidgets('height=$height -> spacing follows scaleOf, as before', (tester) async {
        final spacing = await spacingAt(tester, height);
        final expected = GridLayoutConstants.posterGridSpacingForScale(TvLayoutConstants.scaleForHeight(height));
        expect(spacing, expected);
      });
    }
  });
}
