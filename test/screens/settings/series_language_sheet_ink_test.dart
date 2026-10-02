import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/screens/settings/parts/series_language_sheet.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

/// VIS-0925 recheck item 4: the TV contrast raise of the source-picker
/// tertiary ink must not reach the phone, tablet and desktop copy of this
/// panel. Off TV the "globally" values keep their pre-branch 0.5.
void main() {
  Future<List<double>> globalValueAlphas(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: false),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeriesLanguagePanel(
                entry: (key: 'show:x', choice: const TrackLanguageChoice(audioLanguage: 'eng', updatedAt: 1)),
                global: const PleyaProfileLanguagePreferences(subtitleLanguage: 'nld'),
                onUseGlobal: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = monoTheme(dark: false).colorScheme.onSurface;
    return [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.style?.color != null && t.style!.color!.withValues(alpha: 1) == text.withValues(alpha: 1))
          t.style!.color!.a,
    ];
  }

  testWidgets('off TV the global values keep ink 0.5', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final alphas = await globalValueAlphas(tester);
    expect(alphas.where((a) => (a - 0.5).abs() < 0.005), isNotEmpty);
    expect(alphas.where((a) => (a - TvSourcePickerLayout.inkTertiary).abs() < 0.005), isEmpty);
  });

  testWidgets('on TV they take the audited tertiary ink', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    expect(seriesSheetGlobalValueInk(), TvSourcePickerLayout.inkTertiary);
  });
}
