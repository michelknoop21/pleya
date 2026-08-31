/// The Back/Menu contract on the fase-7 TV root (hoofdstuk 7.5).
///
/// The contract is an *ordered* list, and the order is the part that breaks
/// silently. A shell that asked "where is the focus?" before "is anything open
/// inside this destination?" would send someone standing in Bibliotheken up to
/// the bar instead of back to the Mijn Pleya hub, and nothing would throw — the
/// press would simply land somewhere sensible-looking and wrong. So the order
/// is pinned here, one case per step.
///
/// Steps 1 and 3 are not this function's: an open overlay is closed by
/// `OverlaySheetHost` before the key path is reached, and a detail page or the
/// player is a route on the profile navigator, which pops itself. That
/// separation is exactly why the nested step exists as its own mechanism
/// ([TvNestedRoute]) rather than as a second `Navigator`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/main_screen.dart';

void main() {
  group('the back chain', () {
    test('step 2 comes first: something open inside the destination closes', () {
      expect(
        tvBackStep(hasNestedRoute: true, isNavigationFocused: false),
        TvBackStep.popNested,
        reason: 'Back on a card inside Bibliotheken returns to the Mijn Pleya hub',
      );
    });

    test('step 2 beats the focus test, wherever the remote happens to be', () {
      // The viewer walked up to the bar without leaving the section. Back still
      // means "close the section" — the alternative would strand the section
      // open with no way back to the hub except selecting Mijn Pleya again.
      expect(tvBackStep(hasNestedRoute: true, isNavigationFocused: true), TvBackStep.popNested);
    });

    test('step 4: root content hands the focus to the top navigation', () {
      expect(tvBackStep(hasNestedRoute: false, isNavigationFocused: false), TvBackStep.focusTopNavigation);
    });

    test('step 5: the top navigation at the root defers to the system contract', () {
      expect(tvBackStep(hasNestedRoute: false, isNavigationFocused: true), TvBackStep.rootContract);
    });
  });

  group('the tvOS Menu hand-off', () {
    bool shouldPass({bool isSidebarFocused = true, bool isCurrentTabRoot = true, bool isOverlaySheetOpen = false}) =>
        shouldPassTvosMenuToSystem(
          isAppleTV: true,
          isShowingProfileSelection: false,
          isOverlaySheetOpen: isOverlaySheetOpen,
          isRouteCurrent: true,
          isSidebarFocused: isSidebarFocused,
          hasVisibleTabs: true,
          isCurrentTabRoot: isCurrentTabRoot,
        );

    test('Menu reaches the system only from the root destination with the bar focused', () {
      // The fase-7 shell feeds the same predicate: "sidebar focused" is the top
      // navigation, and the root destination is Home. The engine claims presses
      // before UIKit sees them (CLAUDE.md, DEC-019), so this predicate is the
      // only place the app decides to let one through — it is not re-derived
      // anywhere in the new shell.
      expect(shouldPass(), isTrue);
      expect(shouldPass(isSidebarFocused: false), isFalse);
    });

    test('a destination with something open inside it keeps Menu for the app', () {
      // `isCurrentTabRoot` is where the shell folds in "and nothing is open
      // inside this destination". Handing Menu to tvOS while a nested route is
      // showing would leave the app with a route it can still pop and no press
      // left to pop it with.
      expect(shouldPass(isCurrentTabRoot: false), isFalse);
    });

    test('an open overlay keeps Menu for the app', () {
      expect(shouldPass(isOverlaySheetOpen: true), isFalse);
    });
  });
}
