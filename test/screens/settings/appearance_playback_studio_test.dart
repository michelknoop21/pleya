/// A-24b: Weergave and Afspelen off TV in the Studio series' order
/// (`ios/02-weergave-01..03`, `ios/04-afspelen-01..05`, anchors `01`/`03`),
/// with every row the pages had, the choices as value rows with a picker and
/// the live preview on Weergave. The TV order is covered by
/// `appearance_settings_screen_test.dart` and stays as it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/providers/theme_provider.dart';
import 'package:pleya/screens/settings/appearance_settings_screen.dart';
import 'package:pleya/screens/settings/playback_settings_screen.dart';
import 'package:pleya/services/settings_service.dart' as settings;
import 'package:pleya/services/settings_service.dart' hide ThemeMode;
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/settings/settings_live_preview_card.dart';
import 'package:pleya/widgets/settings_section.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _Profiles extends ChangeNotifier implements ActiveProfileProvider {
  _Profiles({required this.multiple});

  final bool multiple;

  @override
  bool get hasMultipleProfiles => multiple;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ThemeProvider themeProvider;

  Future<void> pump(WidgetTester tester, Widget page, {bool multipleProfiles = true}) async {
    tester.view.physicalSize = const Size(393, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    resetSharedPreferencesForTest();
    await tester.runAsync(() => SettingsService.getInstance());
    themeProvider = ThemeProvider();
    final profiles = _Profiles(multiple: multipleProfiles);
    addTearDown(profiles.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: profiles),
          ],
          // As a settings row opens it: inside the Studio palette.
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: SettingsStudioTheme(child: page),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text).first).dy;

  void expectOrder(WidgetTester tester, List<String> texts) {
    for (var i = 1; i < texts.length; i++) {
      expect(top(tester, texts[i - 1]), lessThan(top(tester, texts[i])), reason: '${texts[i - 1]} before ${texts[i]}');
    }
  }

  group('Weergave', () {
    testWidgets('the preview first, then Scherm, Home, Navigatie and Inhoud en venster, without segments', (
      tester,
    ) async {
      await pump(tester, const AppearanceSettingsScreen());

      expect(find.byType(SettingsLivePreviewCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SettingsLivePreviewCard)).dy,
        lessThan(top(tester, t.settings.display.toUpperCase())),
      );
      expectOrder(tester, [
        t.settings.display.toUpperCase(),
        t.settings.theme,
        t.settings.language,
        t.settings.libraryDensity,
        t.settings.viewMode,
        t.settings.episodePosterMode,
        t.settings.showEpisodeNumberOnCards,
        t.settings.showSeasonPostersOnTabs,
        t.settings.homeScreen.toUpperCase(),
        t.settings.showHeroSection,
        t.settings.personalizedRecommendations,
        t.settings.continueWatchingAction,
        t.settings.useGlobalHubs,
        t.settings.showServerNameOnHubs,
        t.settings.navigation.toUpperCase(),
        t.settings.startupSection,
        t.settings.requireProfileSelectionOnOpen,
        t.settings.showUnwatchedCount,
        t.settingsStudio.contentAndWindow.toUpperCase(),
        t.settings.hideSpoilers,
        t.settings.liveTvDefaultFavorites,
        t.settings.episodeAction,
        t.settings.autoHidePerformanceOverlay,
      ]);
      expect(find.byType(SegmentedButton<Object>), findsNothing);
      expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
      // The one line the Studio rows keep: the four modes under Thema.
      final modes = [t.settings.systemTheme, t.settings.lightTheme, t.settings.darkTheme, t.settings.oledTheme];
      expect(find.text(modes.join(' · ')), findsOneWidget);
      expect(find.text(t.settings.hideSpoilersDescription), findsNothing);
    });

    testWidgets('Profielkeuze bij opstart is there only with more than one profile', (tester) async {
      await pump(tester, const AppearanceSettingsScreen(), multipleProfiles: false);
      expect(find.text(t.settings.requireProfileSelectionOnOpen), findsNothing);
    });

    testWidgets('Thema opens the picker; the choice is written, applied and shown on the preview', (tester) async {
      await pump(tester, const AppearanceSettingsScreen());
      expect(find.textContaining(t.settingsStudio.oledMode), findsOneWidget, reason: 'OLED is the default');

      await tester.tap(find.text(t.settings.theme));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settings.lightTheme).last);
      await tester.pumpAndSettle();

      expect(SettingsService.instance.read(SettingsService.themeMode), settings.ThemeMode.light);
      expect(themeProvider.themeMode, settings.ThemeMode.light);
      expect(find.textContaining(t.settingsStudio.lightMode), findsOneWidget);
    });

    testWidgets('Dichtheid shows its step out of five and writes the one picked', (tester) async {
      await pump(tester, const AppearanceSettingsScreen());
      final now = SettingsService.instance.read(SettingsService.libraryDensity);
      expect(find.text(t.settingsStudio.densityValue(value: '$now')), findsOneWidget);

      await tester.tap(find.text(t.settings.libraryDensity));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 · ${t.settings.comfortable}'));
      await tester.pumpAndSettle();
      expect(SettingsService.instance.read(SettingsService.libraryDensity), 5);
      expect(find.text(t.settingsStudio.densityValue(value: '5')), findsOneWidget);
    });

    testWidgets('a switch writes its preference', (tester) async {
      await pump(tester, const AppearanceSettingsScreen());
      final before = SettingsService.instance.read(SettingsService.hideSpoilers);
      await tester.tap(find.text(t.settings.hideSpoilers));
      await tester.pump();
      expect(SettingsService.instance.read(SettingsService.hideSpoilers), !before);
    });

    testWidgets('the list view shows on the preview line', (tester) async {
      await pump(tester, const AppearanceSettingsScreen());
      await tester.tap(find.text(t.settings.viewMode));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settings.listView).last);
      await tester.pumpAndSettle();
      expect(SettingsService.instance.read(SettingsService.viewMode), ViewMode.list);
      expect(find.textContaining(t.settingsStudio.listView), findsOneWidget);
    });
  });

  group('Afspelen', () {
    testWidgets('Speler, Kwaliteit, Audio, Zoeken en timing, Gedrag, Automatisch overslaan', (tester) async {
      await pump(tester, const PlaybackSettingsScreen());

      expectOrder(tester, [
        t.settings.player.toUpperCase(),
        t.settings.hardwareDecoding,
        t.settingsStudio.quality.toUpperCase(),
        t.settings.defaultQualityTitle,
        t.settings.bufferSize,
        t.settings.displayMaxResolutionTitle,
        t.mpvConfig.title,
        t.settings.audio.toUpperCase(),
        t.videoSettings.audioLevelVolume,
        t.videoSettings.audioReduceLoudSounds,
        t.videoSettings.audioSync,
        t.settings.maxVolume,
        t.settings.seekAndTiming.toUpperCase(),
        t.settings.smallSkipDuration,
        t.settings.largeSkipDuration,
        t.settings.rewindOnResume,
        t.settings.defaultSleepTimer,
        t.settings.showChapterMarkersOnTimeline,
        t.settings.behavior.toUpperCase(),
        t.languageSettings.title,
        t.settings.autoSkip.toUpperCase(),
        t.settings.autoSkipIntro,
        t.settings.autoSkipCredits,
        t.settings.forceSkipMarkerFallback,
        t.settings.autoSkipDelay,
        t.settings.introPattern,
        t.settings.creditsPattern,
      ]);
      // No separate Geavanceerd group any more: MPV sits in Kwaliteit.
      expect(find.text(t.settings.advanced.toUpperCase()), findsNothing);
      expect(find.text(t.settings.hardwareDecodingDescription), findsNothing);
    });

    testWidgets('on TV the order stays as it was, with MPV under Geavanceerd', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      await pump(tester, const PlaybackSettingsScreen());
      // The TV rows are tall and built lazily, so read the cards' titles from
      // the list itself.
      final list = tester.widget<SliverList>(find.byType(SliverList).first).delegate as SliverChildListDelegate;
      final titles = [
        for (final child in list.children)
          if (child is SettingsWidthLimit && child.child is SettingsGroup) (child.child as SettingsGroup).title,
      ];
      expect(titles, [
        t.settings.player,
        t.settings.advanced,
        t.settings.audio,
        t.settings.seekAndTiming,
        t.settings.behavior,
        t.settings.autoSkip,
      ]);
    });
  });
}
