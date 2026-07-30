import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/seerr_poster_card.dart';

import '../test_helpers/prefs.dart';

/// Renders a horizontal seerr row exactly the way the discover screen's
/// `_SeerrRowView` does (SizedBox of `rowHeight`, ListView with a vertical
/// padding of `focusReserve`) and verifies the real rendered card geometry
/// fits inside the row: no top/bottom clipping, card top == focusReserve.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  const media = SeerrMedia(tmdbId: 1, mediaType: 'movie', title: 'Test Movie', year: '2026');

  const testTokens = MonoTokens(
    radiusSm: 8,
    radiusMd: 12,
    space: 8,
    fast: Duration(milliseconds: 1),
    normal: Duration(milliseconds: 1),
    slow: Duration(milliseconds: 1),
    bg: Colors.black,
    surface: Colors.black,
    surfaceElevated: Color(0xFF2F2F2F),
    outline: Colors.white24,
    text: Colors.white,
    textMuted: Colors.white70,
    isLight: false,
    accent: Color(0xFFF42B1F),
    accentAlt: Color(0xFFFFB020),
    splashFactory: NoSplash.splashFactory,
  );

  Future<void> pumpRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [testTokens]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final metrics = seerrRowMetricsOf(context, constraints.maxWidth);
                return SizedBox(
                  height: metrics.rowHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: metrics.focusReserve),
                    itemCount: 3,
                    separatorBuilder: (_, _) => SizedBox(width: metrics.itemGap),
                    itemBuilder: (context, index) =>
                        SeerrPosterCard(media: media, onTap: () {}, width: metrics.cardWidth),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('TV row: card renders fully inside the row bounds', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    try {
      await pumpRow(tester);
      expect(tester.takeException(), isNull);

      late final BuildContext context = tester.element(find.byType(ListView));
      final metrics = seerrRowMetricsOf(context, 1920);

      final row = tester.getRect(find.byType(ListView));
      final card = tester.getRect(find.byType(SeerrPosterCard).first);

      // The rendered card must match the metrics' card size...
      expect(card.width, moreOrLessEquals(metrics.cardWidth, epsilon: 0.5));
      expect(card.height, moreOrLessEquals(metrics.cardHeight, epsilon: 0.5));
      // ...and sit exactly one focusReserve below the row top, fully inside.
      expect(card.top - row.top, moreOrLessEquals(metrics.focusReserve, epsilon: 0.5));
      expect(row.bottom - card.bottom, moreOrLessEquals(metrics.focusReserve, epsilon: 0.5));
      // Focus-scaled card (+ ring) stays within the row's reserved headroom.
      final scaledOverhang = card.height * 0.025 + 2.5;
      expect(metrics.focusReserve, greaterThanOrEqualTo(scaledOverhang - 0.5));
    } finally {
      TvDetectionService.debugSetAppleTVOverride(null);
    }
  });

  testWidgets('non-TV row: card fills the row exactly, no reserve', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    try {
      await pumpRow(tester);
      expect(tester.takeException(), isNull);

      final row = tester.getRect(find.byType(ListView));
      final card = tester.getRect(find.byType(SeerrPosterCard).first);
      expect(card.top, moreOrLessEquals(row.top, epsilon: 0.5));
      expect(card.height, moreOrLessEquals(row.height, epsilon: 0.5));
    } finally {
      TvDetectionService.debugSetAppleTVOverride(null);
    }
  });
}
