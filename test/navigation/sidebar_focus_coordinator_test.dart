import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/sidebar_focus_coordinator.dart';

/// A shell shaped like the main screen: a rail on the left inside one focus
/// scope, content on the right inside another, and nothing else. Enough to ask
/// the questions that matter — where is the focus, and does the rail think it
/// is open — without standing up the twenty providers the real screen needs.
class _Shell extends StatefulWidget {
  const _Shell({super.key, required this.coordinator, this.contentIsFocusable = true});

  final SidebarFocusCoordinator coordinator;

  /// When false the content has no focusable child, which is what a tab that
  /// has not finished loading looks like from the outside.
  final bool contentIsFocusable;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final FocusNode railItem = FocusNode(debugLabel: 'railItem');
  final FocusNode contentItem = FocusNode(debugLabel: 'contentItem');

  /// The tab the user came from. It stays mounted behind the new one, the way
  /// every tab does in the main screen's IndexedStack, so its focus node is
  /// still a perfectly valid thing for the scope to restore — offscreen.
  final FocusNode previousTabItem = FocusNode(debugLabel: 'previousTabItem');

  @override
  void dispose() {
    railItem.dispose();
    contentItem.dispose();
    previousTabItem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 200,
              child: FocusScope(
                node: widget.coordinator.sidebarScope,
                child: Focus(focusNode: railItem, child: const SizedBox.expand()),
              ),
            ),
            Expanded(
              child: FocusScope(
                node: widget.coordinator.contentScope,
                child: Column(
                  children: [
                    Focus(focusNode: previousTabItem, child: const SizedBox(height: 10, width: 10)),
                    if (widget.contentIsFocusable)
                      Focus(focusNode: contentItem, child: const SizedBox(height: 10, width: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('selecting a destination', () {
    testWidgets('focus leaves the rail and the rail closes, even when the new tab declines the focus', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator, contentIsFocusable: false));

      // The user is on a nav item and presses Select.
      coordinator.focusSidebar(focusActiveItem: () => key.currentState!.railItem.requestFocus());
      await tester.pumpAndSettle();
      expect(coordinator.isSidebarFocused, isTrue);
      expect(key.currentState!.railItem.hasFocus, isTrue);

      // The destination opens, and its screen is not ready to take the focus.
      var declined = 0;
      coordinator.focusContent(restorePreviousFocus: false, focusDefault: () => declined++);
      await tester.pumpAndSettle();

      expect(declined, 1, reason: 'the new tab is still asked to place the focus');
      expect(
        key.currentState!.railItem.hasFocus,
        isFalse,
        reason: 'a tab that declines must not leave the remote on the nav item that was just pressed',
      );
      expect(coordinator.sidebarScope.hasFocus, isFalse);
      expect(coordinator.isSidebarFocused, isFalse, reason: 'the rail closes');
    });

    testWidgets('a tab that declines does not inherit the previous tab\'s position', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator, contentIsFocusable: false));

      // The user was deep in the previous tab before going back to the rail.
      key.currentState!.previousTabItem.requestFocus();
      await tester.pumpAndSettle();
      coordinator.focusSidebar(focusActiveItem: () => key.currentState!.railItem.requestFocus());
      await tester.pumpAndSettle();

      // Another destination, whose screen is not ready to take the focus.
      coordinator.focusContent(restorePreviousFocus: false, focusDefault: () {});
      await tester.pumpAndSettle();

      expect(
        key.currentState!.previousTabItem.hasFocus,
        isFalse,
        reason: 'the remote must not park on a row of the tab the user just left, which is offscreen now',
      );
      expect(coordinator.contentScope.hasFocus, isTrue, reason: 'the scope itself holds it until the tab is ready');
      expect(coordinator.isSidebarFocused, isFalse);
    });

    testWidgets('a ready tab keeps the focus it placed', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      coordinator.focusSidebar(focusActiveItem: () => key.currentState!.railItem.requestFocus());
      await tester.pumpAndSettle();

      coordinator.focusContent(
        restorePreviousFocus: false,
        focusDefault: () => key.currentState!.contentItem.requestFocus(),
      );
      await tester.pumpAndSettle();

      expect(key.currentState!.contentItem.hasFocus, isTrue);
      expect(coordinator.isSidebarFocused, isFalse);
    });
  });

  group('fast repeated remote input', () {
    testWidgets('the last request decides, and the older callback stands down', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      var sidebarCallbacks = 0;
      var contentCallbacks = 0;

      // Two presses inside one frame: Menu back to the rail, then Select on a
      // destination before the frame that would have honoured the first one.
      coordinator.focusSidebar(
        focusActiveItem: () {
          sidebarCallbacks++;
          key.currentState!.railItem.requestFocus();
        },
      );
      coordinator.focusContent(
        restorePreviousFocus: false,
        focusDefault: () {
          contentCallbacks++;
          key.currentState!.contentItem.requestFocus();
        },
      );
      await tester.pumpAndSettle();

      expect(sidebarCallbacks, 0, reason: 'the superseded request must not pull the focus back');
      expect(contentCallbacks, 1);
      expect(coordinator.isSidebarFocused, isFalse);
      expect(key.currentState!.contentItem.hasFocus, isTrue);
    });

    testWidgets('select, then back to the rail, ends in the rail', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      var contentCallbacks = 0;
      coordinator.focusContent(
        restorePreviousFocus: false,
        focusDefault: () {
          contentCallbacks++;
          key.currentState!.contentItem.requestFocus();
        },
      );
      coordinator.focusSidebar(focusActiveItem: () => key.currentState!.railItem.requestFocus());
      await tester.pumpAndSettle();

      expect(contentCallbacks, 0);
      expect(coordinator.isSidebarFocused, isTrue);
      expect(key.currentState!.railItem.hasFocus, isTrue);
    });

    testWidgets('a burst of alternating requests leaves no half-open state', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      for (var i = 0; i < 8; i++) {
        coordinator.focusSidebar(focusActiveItem: () => key.currentState!.railItem.requestFocus());
        coordinator.focusContent(
          restorePreviousFocus: false,
          focusDefault: () => key.currentState!.contentItem.requestFocus(),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(coordinator.isSidebarFocused, isFalse);
      expect(coordinator.sidebarScope.hasFocus, isFalse);
      expect(
        coordinator.isSidebarFocused,
        coordinator.sidebarScope.hasFocus,
        reason: 'the flag and the focus tree must never disagree',
      );
    });
  });

  group('the flag follows the focus', () {
    testWidgets('focus leaving the rail by any route closes it', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      coordinator.focusSidebar(focusActiveItem: () => key.currentState!.railItem.requestFocus());
      await tester.pumpAndSettle();
      expect(coordinator.isSidebarFocused, isTrue);

      // Nobody called focusContent: something in the content simply took the
      // focus, the way a pointer click does on desktop.
      key.currentState!.contentItem.requestFocus();
      await tester.pumpAndSettle();

      expect(coordinator.isSidebarFocused, isFalse, reason: 'the rail must not stay open over content that has focus');
    });

    testWidgets('focus returning to the rail opens it again', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      addTearDown(coordinator.dispose);
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      coordinator.focusContent(
        restorePreviousFocus: false,
        focusDefault: () => key.currentState!.contentItem.requestFocus(),
      );
      await tester.pumpAndSettle();
      expect(coordinator.isSidebarFocused, isFalse);

      // A route pushed from a rail row (now watching) popping back is this:
      // focus lands in the rail without the shell asking for it.
      key.currentState!.railItem.requestFocus();
      await tester.pumpAndSettle();

      expect(coordinator.isSidebarFocused, isTrue);
    });

    testWidgets('a callback after dispose does not throw', (tester) async {
      final coordinator = SidebarFocusCoordinator();
      final key = GlobalKey<_ShellState>();
      await tester.pumpWidget(_Shell(key: key, coordinator: coordinator));

      var ran = 0;
      coordinator.focusContent(restorePreviousFocus: false, focusDefault: () => ran++);
      // Disposed before the frame that would have run the callback — the shell
      // being torn down while a focus request is in flight.
      coordinator.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(ran, 0);
    });
  });
}
