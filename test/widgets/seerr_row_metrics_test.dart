import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/seerr_poster_card.dart';

import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<SeerrRowMetrics> resolveMetrics(WidgetTester tester) async {
    late SeerrRowMetrics metrics;
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutBuilder(
          builder: (context, constraints) {
            metrics = seerrRowMetricsOf(context, constraints.maxWidth);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return metrics;
  }

  testWidgets('TV metrics reserve focus headroom and proportional gap', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    try {
      final m = await resolveMetrics(tester);
      final minGap = m.cardWidth * (FocusTheme.focusScale - 1) / 2 + FocusTheme.focusBorderWidth;
      final minReserve = m.cardHeight * (FocusTheme.focusScale - 1) / 2 + FocusTheme.focusBorderWidth;
      expect(m.focusReserve, greaterThanOrEqualTo(minReserve));
      expect(m.rowHeight - m.cardHeight, greaterThanOrEqualTo(2 * m.focusReserve));
      expect(m.itemGap, greaterThanOrEqualTo(minGap));
    } finally {
      TvDetectionService.debugSetAppleTVOverride(null);
    }
  });

  testWidgets('non-TV metrics keep the plain 12px gap and no reserve', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    try {
      final m = await resolveMetrics(tester);
      expect(m.focusReserve, 0);
      expect(m.itemGap, 12);
      expect(m.rowHeight, m.cardHeight);
    } finally {
      TvDetectionService.debugSetAppleTVOverride(null);
    }
  });
}
