/// A-24c: the account menu under the profile avatar (A14,
/// LEESMIJ-v4 "Focusafspraken").
///
/// Pumped under the production shell, with the avatar opening the menu the
/// way `MainScreen` does, so what is proved is the remote's path: the avatar,
/// two actions and nothing else, a background that cannot take the focus,
/// and Back returning the remote to the avatar.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/widgets/tv/tv_account_menu.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/tv_my_pleya_page.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    // The Siri Remote's Menu arrives as goBack, which the simulator has no
    // physical key for; it is sent on the escape key's.
    await tester.sendKeyEvent(key, physicalKey: key == LogicalKeyboardKey.goBack ? PhysicalKeyboardKey.escape : null);
    await tester.pumpAndSettle();
  }

  Future<TvMyPleyaPage> openMenu(WidgetTester tester) async {
    final page = await pumpTvMyPleyaPage(tester);
    page.navNodes.get(tvNavProfileFocusKey).requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.select);
    return page;
  }

  Finder action(TvAccountAction action) => find.byWidgetPredicate(
    (w) =>
        w is FocusableWrapper &&
        w.automationId == AutomationIds.accountMenuAction &&
        w.automationInstance == action.automationInstance,
  );

  testWidgets('the avatar opens a menu with exactly Wissel profiel and Uitloggen', (tester) async {
    final page = await openMenu(tester);

    expect(find.byType(TvAccountMenu), findsOneWidget);
    expect(find.text(t.tvAccountMenu.title), findsOneWidget);
    expect(find.text(t.tvAccountMenu.signedInAs(name: 'Michel')), findsOneWidget);
    expect(action(TvAccountAction.switchProfile), findsOneWidget);
    expect(action(TvAccountAction.logout), findsOneWidget);
    expect(
      find.descendant(of: find.byType(TvAccountMenu), matching: find.byType(FocusableWrapper)),
      findsNWidgets(2),
      reason: 'two actions and nothing else',
    );
    // The first action holds the focus when the menu opens.
    expect(page.focused, 'tvAccountMenu_switchProfile');
  });

  testWidgets('Up and Down move between the two actions; the background never takes the focus', (tester) async {
    final page = await openMenu(tester);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(page.focused, 'tvAccountMenu_logout');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(page.focused, 'tvAccountMenu_logout', reason: 'no wrap');
    for (final key in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
      await press(tester, key);
      expect(page.focused, 'tvAccountMenu_logout', reason: 'nothing beside the menu is reachable');
    }
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(page.focused, 'tvAccountMenu_switchProfile');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(page.focused, 'tvAccountMenu_switchProfile', reason: 'the bar behind it is not reachable');
  });

  for (final back in [LogicalKeyboardKey.escape, LogicalKeyboardKey.goBack]) {
    testWidgets('Back (${back.keyLabel}) closes the menu and puts the remote back on the avatar', (tester) async {
      final page = await openMenu(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);

      await press(tester, back);

      expect(find.byType(TvAccountMenu), findsNothing);
      expect(page.menuChoices, [null], reason: 'Back chooses nothing');
      expect(page.navNodes.isFocused(tvNavProfileFocusKey), isTrue);
    });
  }

  testWidgets('each action reports itself and closes the menu', (tester) async {
    final page = await openMenu(tester);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byType(TvAccountMenu), findsNothing);

    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);

    expect(page.menuChoices, [TvAccountAction.switchProfile, TvAccountAction.logout]);
  });
}
