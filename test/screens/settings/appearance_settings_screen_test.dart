import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/screens/settings/appearance_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _Profiles extends ChangeNotifier implements ActiveProfileProvider {
  @override
  bool get hasMultipleProfiles => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('TV-categorieën behouden de bestaande voorkeuren en profielvoorwaarde', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    resetSharedPreferencesForTest();
    await tester.runAsync(() => SettingsService.getInstance());
    final profiles = _Profiles();
    addTearDown(profiles.dispose);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: profiles),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), home: const AppearanceSettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    void expectPref(Pref<bool> pref) {
      expect(find.byWidgetPredicate((widget) => widget is SettingSwitchTile && widget.pref == pref), findsOneWidget);
    }

    expectPref(SettingsService.tvFullCardLayout);
    expectPref(SettingsService.focusGlow);
    expectPref(SettingsService.tvShowTitlesUnderPosters);
    expectPref(SettingsService.tvReduceMotion);
    expectPref(SettingsService.showEpisodeNumberOnCards);
    expect(find.byWidgetPredicate((widget) => widget is SegmentedButton), findsNothing);
    await tester.tap(find.text(t.settings.viewMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.listView).last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.viewMode), ViewMode.list);

    await tester.tap(find.text(t.settings.homeScreen).first);
    await tester.pump();
    expectPref(SettingsService.tvHeroClearLogo);
    expectPref(SettingsService.tvHeroAutoAdvance);
    expectPref(SettingsService.personalizedRecommendations);
    expectPref(SettingsService.useGlobalHubs);
    expectPref(SettingsService.showServerNameOnHubs);
    expect(find.byWidgetPredicate((widget) => widget is SegmentedButton), findsNothing);
    final advanceBefore = SettingsService.instance.read(SettingsService.tvHeroAutoAdvance);
    await tester.tap(find.text(t.settings.tvHeroAutoAdvance));
    await tester.pump();
    expect(SettingsService.instance.read(SettingsService.tvHeroAutoAdvance), !advanceBefore);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SettingSwitchTile && widget.pref == SettingsService.hoverExpandCards,
      ),
      findsNothing,
    );

    await tester.tap(find.text(t.settings.navigation).first);
    await tester.pump();
    expectPref(SettingsService.alwaysKeepSidebarOpen);
    expectPref(SettingsService.groupLibrariesByServer);
    expectPref(SettingsService.showUnwatchedCount);

    await tester.tap(find.text(t.settings.content).first);
    await tester.pump();
    expectPref(SettingsService.liveTvDefaultFavorites);
    expectPref(SettingsService.hideSpoilers);
    expectPref(SettingsService.requireProfileSelectionOnOpen);
    expectPref(SettingsService.autoHidePerformanceOverlay);
  });
}
