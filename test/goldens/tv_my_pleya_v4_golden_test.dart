/// A-24c: Mijn Pleya on TV next to its northstar
/// (`docs/assets/a24c-northstars/02-Mijn-Pleya-v4/images/A10`..`A15`).
///
/// Production widgets only, through `pumpTvMyPleyaPage`: the real shell, bar
/// and page at the 1038 x 584 Apple TV canvas. Linux-rendered like every
/// golden here; the simulator screenshots in the PR are the tvOS evidence.
///
/// Regenerate after an intentional visual change with the `goldens.yml`
/// workflow (`test/goldens/tv_my_pleya_v4_golden_test.dart`).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart' show tvNavProfileFocusKey;
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/tv_my_pleya_page.dart';

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    // The northstar is Dutch; the picture should read the same words.
    await LocaleSettings.setLocale(AppLocale.nl);
  });
  tearDownAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  Future<void> shoot(WidgetTester tester, String name) => expectMatchesGolden(find.byType(TvRootShell), name);

  for (final (theme, name) in [
    (TvMyPleyaTheme.dark, 'tv_my_pleya_v4_dark'),
    (TvMyPleyaTheme.light, 'tv_my_pleya_v4_light'),
    (TvMyPleyaTheme.oled, 'tv_my_pleya_v4_oled'),
  ]) {
    testWidgets('A10-A12: ${theme.name}, focus on Big P', (tester) async {
      final page = await pumpTvMyPleyaPage(tester, theme: theme);
      page.state.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      await shoot(tester, name);
    });
  }

  testWidgets('A13: the ring on Instellingen, the capsule on Mijn Pleya', (tester) async {
    final page = await pumpTvMyPleyaPage(tester);
    page.navNodes.get(TvDestinationId.settings.focusKey).requestFocus();
    await tester.pumpAndSettle();
    await shoot(tester, 'tv_my_pleya_v4_settings_focus');
  });

  testWidgets('A14: the account menu under the avatar', (tester) async {
    final page = await pumpTvMyPleyaPage(tester);
    page.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_my_pleya_v4_account_menu');
  });

  testWidgets('A15: without Seerr and Activiteit the row closes up', (tester) async {
    final page = await pumpTvMyPleyaPage(tester, conditions: const TvMyPleyaPageConditions.withoutSeerrAndActivity());
    page.state.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    await shoot(tester, 'tv_my_pleya_v4_without_seerr_activity');
  });

  testWidgets('the focus on a dock tile', (tester) async {
    final page = await pumpTvMyPleyaPage(tester);
    page.state.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await shoot(tester, 'tv_my_pleya_v4_dock_focus');
  });
}
