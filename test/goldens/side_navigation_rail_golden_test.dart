import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

// Fase-0 baseline for Pleya Unified TV 2026 (docs/tvos-unified-experience.md
// hoofdstuk 27, 29): the first golden-test baselines of an EXISTING surface,
// established before any unified-catalog code lands. `SideNavigationRail` is
// chosen because it is already heavily covered by
// `test/widgets/side_navigation_rail_test.dart` and does not depend on live
// server data, which keeps this baseline deterministic. New end-screen
// goldens for the unified redesign itself are added in the fase that builds
// each screen (hoofdstuk 27), not here.
//
// Uses the real `monoTheme(dark: true)` (colors + `fontFamily: 'Inter'`)
// rather than a hand-rolled test theme, so this baseline reflects the actual
// production surface, not an approximation of it.

Future<void> _pumpRail(WidgetTester tester, {required bool alwaysExpanded}) async {
  await SettingsService.getInstance();

  final librariesProvider = LibrariesProvider();
  addTearDown(librariesProvider.dispose);

  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  await hiddenLibrariesProvider.ensureInitialized();
  addTearDown(hiddenLibrariesProvider.dispose);

  final manager = MultiServerManager();
  final aggregation = DataAggregationService(manager);
  final multiServerProvider = MultiServerProvider(manager, aggregation);
  addTearDown(multiServerProvider.dispose);

  setGoldenSurfaceSize(tester, size: const Size(320, 584));

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SideNavigationRail(
              selectedTab: NavigationTabId.discover,
              isSidebarFocused: false,
              alwaysExpanded: alwaysExpanded,
              onDestinationSelected: (_) {},
              onLibrarySelected: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFontsForGoldens);

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('baseline: collapsed TV rail', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    await _pumpRail(tester, alwaysExpanded: false);

    await expectMatchesGolden(find.byType(Scaffold), 'side_navigation_rail_collapsed');
  });

  testWidgets('baseline: always-expanded (desktop) rail', (tester) async {
    await _pumpRail(tester, alwaysExpanded: true);

    await expectMatchesGolden(find.byType(Scaffold), 'side_navigation_rail_expanded');
  });
}
