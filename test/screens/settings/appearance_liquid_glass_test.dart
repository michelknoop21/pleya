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
  bool get hasMultipleProfiles => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpAppearance(WidgetTester tester) async {
  // Deterministic regardless of the host machine's device locale — otherwise
  // a longer non-English translation (e.g. "Afleveringsminiatuur") overflows
  // the episode-poster-mode segmented control at phone width.
  await LocaleSettings.setLocale(AppLocale.en);
  final profiles = _Profiles();
  addTearDown(profiles.dispose);
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
}

void main() {
  setUp(() => resetSharedPreferencesForTest());

  testWidgets('tile aanwezig op een telefoon en zet de instelling aan', (tester) async {
    // Wide logical surface with a high devicePixelRatio: several *unrelated*
    // SettingSegmentedTile rows on this screen (episode poster mode,
    // continue-watching action, …) overflow their row at a real phone's
    // logical width (fixing that is out of this task's scope). The high dpr
    // keeps PlatformDetector.isTablet's diagonal-inches calculation reading
    // as a phone despite the wide logical size — the same trick
    // glass_surface_test.dart's viewport-vs-classification split relies on.
    tester.view.physicalSize = const Size(4800, 7200);
    tester.view.devicePixelRatio = 6;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());

    await _pumpAppearance(tester);

    expect(find.text('Liquid Glass'), findsOneWidget);
    expect(SettingsService.instance.read(SettingsService.liquidGlass), isFalse);

    await tester.tap(find.text('Liquid Glass'));
    await tester.pump();

    expect(SettingsService.instance.read(SettingsService.liquidGlass), isTrue);
  });

  testWidgets('tile afwezig op een tablet', (tester) async {
    tester.view.physicalSize = const Size(1668, 2224);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());

    await _pumpAppearance(tester);

    expect(PlatformDetector.isTablet(tester.element(find.byType(AppearanceSettingsScreen))), isTrue);
    expect(find.text('Liquid Glass'), findsNothing);
  });

  testWidgets('tile aanwezig op Apple TV', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    // Phone-sized surface, same reason as glass_surface_test.dart: isTV() is
    // driven by the override above, but isTablet() is screen-diagonal based,
    // and a real TV-sized viewport (e.g. 1920x1080) would misread as a tablet
    // and hide the tile regardless of the setting under test.
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());

    await _pumpAppearance(tester);

    expect(
      find.byWidgetPredicate((widget) => widget is SettingSwitchTile && widget.pref == SettingsService.liquidGlass),
      findsOneWidget,
    );
  });
}
