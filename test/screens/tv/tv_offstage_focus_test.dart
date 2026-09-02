/// P5's regression guard, and the half of it that is easiest to lose again: a
/// focus request or a traversal step must never land on a screen nobody can see.
///
/// The TV shell keeps two kinds of invisible screen mounted on purpose, for the
/// same reason in both cases — switching away must not cost a rebuild of a
/// provider graph, a scroll position or a set of focus nodes (hoofdstuk 24).
/// Neither `Offstage` nor `IndexedStack` takes its hidden children out of the
/// focus tree, so both need an explicit `ExcludeFocus`, and fixing one of them
/// leaves the other reachable:
///
///  * `MainScreen`'s destination stack — every destination the bar can reach,
///    all mounted at once;
///  * `TvRootShell`'s offstage destination root, under an open nested route.
///
/// Both are driven here as the production composition rather than as a copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';

/// A stand-in destination with one focusable in it, named so a failing test can
/// say *which* invisible screen the focus reached.
class _Destination extends StatelessWidget {
  const _Destination(this.node);

  final FocusNode node;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    child: SizedBox(width: 100, height: 40, child: Text(node.debugLabel!)),
  );
}

void main() {
  testWidgets('the destination stack keeps every hidden destination out of the focus tree', (tester) async {
    final visible = FocusNode(debugLabel: 'visible');
    final hidden = FocusNode(debugLabel: 'hidden');
    addTearDown(() {
      visible.dispose();
      hidden.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: mainScreenDestinationStack(screens: [_Destination(visible), _Destination(hidden)], currentIndex: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(visible.canRequestFocus, isTrue, reason: 'sanity: the destination on screen is operable');
    expect(
      hidden.canRequestFocus,
      isFalse,
      reason: 'an offscreen destination is mounted, animation-free and unreachable — all three',
    );

    // And a request for it does not take: the node cannot be focused, so the
    // remote stays where it is rather than moving to something invisible.
    hidden.requestFocus();
    await tester.pump();
    expect(hidden.hasFocus, isFalse);
  });

  testWidgets('the stack lets go again when its destination becomes the active one', (tester) async {
    // The other direction, which a blanket `ExcludeFocus` would break: a
    // destination that comes to the front has to be operable immediately.
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(() {
      a.dispose();
      b.dispose();
    });

    Widget stack(int index) => MaterialApp(
      home: mainScreenDestinationStack(screens: [_Destination(a), _Destination(b)], currentIndex: index),
    );

    await tester.pumpWidget(stack(0));
    await tester.pumpAndSettle();
    expect(b.canRequestFocus, isFalse);

    await tester.pumpWidget(stack(1));
    await tester.pumpAndSettle();
    expect(b.canRequestFocus, isTrue);
    expect(a.canRequestFocus, isFalse);
  });

  testWidgets('a nested route makes the destination underneath unreachable too', (tester) async {
    final root = FocusNode(debugLabel: 'destination root');
    final nested = FocusNode(debugLabel: 'nested route');
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    final nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    final navScope = FocusScopeNode(debugLabel: 'nav');
    final contentScope = FocusScopeNode(debugLabel: 'content');
    addTearDown(() {
      root.dispose();
      nested.dispose();
      coordinator.dispose();
      nodes.dispose();
      navScope.dispose();
      contentScope.dispose();
    });

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget shell() => TranslationProvider(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: TvRootShell(
            coordinator: coordinator,
            contentFocus: TvContentFocusAuthority(),
            navNodes: nodes,
            navFocusScope: navScope,
            contentFocusScope: contentScope,
            isNavFocused: false,
            profile: null,
            onSelectDestination: (_) {},
            onFocusContent: ({bool restorePreviousFocus = true}) {},
            onFocusNav: () {},
            onOpenProfiles: () {},
            onOverlaySheetOpenChanged: (_) {},
            onKeyEvent: (_) => KeyEventResult.ignored,
            selectLibrary: null,
            openSettings: null,
            child: _Destination(root),
          ),
        ),
      ),
    );

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(root.canRequestFocus, isTrue, reason: 'sanity: with nothing pushed the destination is operable');

    coordinator.pushNested(coordinator.active, TvNestedRoute(id: 'nested', builder: (context) => _Destination(nested)));
    await tester.pumpAndSettle();

    expect(nested.canRequestFocus, isTrue, reason: 'the route on top is what the viewer is looking at');
    expect(
      root.canRequestFocus,
      isFalse,
      reason: '`Offstage` removes painting and hit-testing, never focusability — the destination is still mounted',
    );

    coordinator.popNested();
    await tester.pumpAndSettle();
    expect(root.canRequestFocus, isTrue, reason: 'and popping gives it back');
  });
}
