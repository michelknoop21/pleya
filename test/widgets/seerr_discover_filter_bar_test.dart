import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/seerr/seerr_discover_filter_bar.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/focusable_tab_chip.dart';

import '../test_helpers/prefs.dart';

/// The filter line on Requests, driven the way a remote drives it.
///
/// It went out with no focus nodes at all: every chip was focusable, but nothing
/// could send focus to one, so a D-pad had to rely on Flutter's default
/// directional traversal through a horizontally scrolling row inside a sliver.
/// On a television that is the difference between a line you can use and one you
/// cannot. These tests hold the chain rather than the pixels: press a direction,
/// see where focus lands.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  const genres = <SeerrDiscoverGenre>[(id: 28, name: 'Action'), (id: 35, name: 'Comedy')];

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// The label of the chip that holds focus right now, or null when nothing does.
  String? focusedTabLabel(WidgetTester tester) {
    for (final element in find.byType(FocusableTabChip).evaluate()) {
      final chip = element.widget as FocusableTabChip;
      final node = chip.focusNode;
      if (node != null && node.hasFocus) return chip.label;
    }
    return null;
  }

  Future<FocusNode> pumpBar(
    WidgetTester tester, {
    SeerrDiscoverType type = SeerrDiscoverType.movies,
    List<SeerrDiscoverGenre> genreList = genres,
    int? genreId,
    VoidCallback? onExitLeft,
    VoidCallback? onExitUp,
    VoidCallback? onExitDown,
    ValueChanged<SeerrDiscoverType>? onTypeSelected,
  }) async {
    final firstTab = FocusNode(debugLabel: 'FirstTabUnderTest');
    addTearDown(firstTab.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SeerrDiscoverFilterBar(
              type: type,
              genres: genreList,
              genreId: genreId,
              onTypeSelected: onTypeSelected ?? (_) {},
              onGenreSelected: (_) {},
              firstTabFocusNode: firstTab,
              onExitLeft: onExitLeft,
              onExitUp: onExitUp,
              onExitDown: onExitDown,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return firstTab;
  }

  testWidgets('the screen can aim focus at the first tab', (tester) async {
    final firstTab = await pumpBar(tester);

    firstTab.requestFocus();
    await tester.pumpAndSettle();

    expect(focusedTabLabel(tester), t.seerr.filterAll);
  });

  testWidgets('right walks the type tabs and then reaches the genre action', (tester) async {
    final firstTab = await pumpBar(tester);
    firstTab.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTabLabel(tester), t.seerr.filterMovies);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTabLabel(tester), t.seerr.filterShows);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTabLabel(tester), isNull, reason: 'focus left the tabs');
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'SeerrGenreAction',
      reason: 'right from the last tab is the action beside it',
    );
  });

  testWidgets('left walks back and leaves the bar at the first tab', (tester) async {
    var exitedLeft = 0;
    final firstTab = await pumpBar(tester, onExitLeft: () => exitedLeft++);
    firstTab.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedTabLabel(tester), t.seerr.filterAll);
    expect(exitedLeft, 0, reason: 'there was still a tab to move to');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(exitedLeft, 1, reason: 'left off the first tab is the screen\'s business');
  });

  testWidgets('up and down hand the line back to the screen', (tester) async {
    var up = 0;
    var down = 0;
    final firstTab = await pumpBar(tester, onExitUp: () => up++, onExitDown: () => down++);
    firstTab.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(up, 1);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(down, 1);
  });

  testWidgets('right stops at the last tab when there is no genre action', (tester) async {
    // "All" has no single genre list, so the action is not drawn. Right must
    // then stay put instead of handing focus to a node that is not on screen.
    final firstTab = await pumpBar(tester, type: SeerrDiscoverType.all);
    firstTab.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTabLabel(tester), t.seerr.filterShows);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedTabLabel(tester), t.seerr.filterShows, reason: 'nowhere to go, so nowhere to lose focus');
  });

  testWidgets('the genre action disappearing under the focus hands it back to the tabs', (tester) async {
    // The action comes and goes with the type and with an active search. Letting
    // it vanish while focused left the screen with nothing focused at all, which
    // on a remote reads as the app having stopped responding.
    final firstTab = await pumpBar(tester);
    firstTab.requestFocus();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, 'SeerrGenreAction');

    // What the screen does when a search starts: the genres go away.
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SeerrDiscoverFilterBar(
              type: SeerrDiscoverType.movies,
              genres: const [],
              genreId: null,
              onTypeSelected: (_) {},
              onGenreSelected: (_) {},
              firstTabFocusNode: firstTab,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(focusedTabLabel(tester), t.seerr.filterShows, reason: 'focus falls back to the last tab, not to nothing');
  });
}
