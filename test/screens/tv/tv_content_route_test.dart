/// PB-1: a TV content route keeps the top navigation.
///
/// The first test in here is the negative control, and it asserts the *old*
/// behaviour on purpose: a screen pushed on the navigator above the shell
/// covers the bar. That is what the approved detail, collection, person and
/// settings surfaces are no longer allowed to do, and a fix nobody can see fail
/// is a fix nobody can trust. The second test drives the same subpage through
/// [openTvContentRoute] and finds the bar still there.
///
/// Against the production [TvRootShell] and [TvTopNavigation], with a real
/// navigator above them standing in for the one `ProfileSessionScreen` owns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

/// Stands in for a settings subpage: a full-page `Scaffold` that paints over
/// everything under it, which is the property the negative control turns on.
class _SubPage extends StatelessWidget {
  const _SubPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF141414),
    body: Center(child: Text('subpage')),
  );
}

/// Anything of the bar the remote or a pointer can still reach.
///
/// The bar's own widget stays in the tree under a pushed route — `find.byType`
/// would find it either way — so what is asserted is reachability: with a
/// full-window route on top, nothing inside the bar is in the hit-test path any
/// more. Hit-testing the bar widget itself proves nothing, because its centre
/// falls in the gap between two pills.
Finder reachableBar() => find.descendant(of: find.byType(TvTopNavigation), matching: find.byType(Text)).hitTestable();

void main() {
  late TvNavigationCoordinator coordinator;
  late FocusMemoryTracker nodes;
  late FocusScopeNode navScope;
  late FocusScopeNode contentScope;

  setUp(() {
    coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    navScope = FocusScopeNode(debugLabel: 'nav');
    contentScope = FocusScopeNode(debugLabel: 'content');
  });

  tearDown(() {
    coordinator.dispose();
    nodes.dispose();
    navScope.dispose();
    contentScope.dispose();
  });

  /// The shell, under a navigator, with a button that opens [_SubPage] the way
  /// the caller under test would. [useShellRoute] picks which of the two paths
  /// that caller takes.
  Future<void> pump(WidgetTester tester, {required bool useShellRoute}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
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
              onFocusDestination: (_) {},
              onFocusContent: ({bool restorePreviousFocus = true}) {},
              onFocusNav: () {},
              onOpenProfiles: () {},
              onOverlaySheetOpenChanged: (_) {},
              onKeyEvent: (_) => KeyEventResult.ignored,
              selectLibrary: null,
              openSettings: null,
              child: Builder(
                builder: (context) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('destination root'),
                    TextButton(
                      onPressed: () {
                        if (useShellRoute &&
                            openTvContentRoute(id: 'tvSettings_x', builder: (_) => const _SubPage()) != null) {
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _SubPage()));
                      },
                      child: const Text('open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the route contract', () {
    testWidgets('NEGATIVE CONTROL: the old full-window push covers the top navigation', (tester) async {
      // Nothing attached, so `openTvContentRoute` cannot take the call even if
      // it were asked: this is the path every TV content push took before PB-1.
      expect(tvContentRouteRegistry.isAvailable, isFalse);

      await pump(tester, useShellRoute: false);
      expect(reachableBar(), findsAtLeast(1), reason: 'bar is there to begin with');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('subpage'), findsOneWidget);
      expect(
        reachableBar(),
        findsNothing,
        reason: 'this is the defect PB-1 removes: the subpage paints over the shell',
      );
    });

    testWidgets('a content route opens inside the shell, with the bar still on screen', (tester) async {
      Future<Object?> push(TvNestedRoute route) => coordinator.pushNested(coordinator.active, route).result;
      tvContentRouteRegistry.attach(push);
      addTearDown(() => tvContentRouteRegistry.detach(push));

      await pump(tester, useShellRoute: true);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('subpage'), findsOneWidget);
      expect(reachableBar(), findsAtLeast(1));
      expect(
        find.text('destination root'),
        findsNothing,
        reason: 'the root is offstage under the route, not beside it',
      );
    });

    testWidgets('popping the content route brings the destination root back', (tester) async {
      Future<Object?> push(TvNestedRoute route) => coordinator.pushNested(coordinator.active, route).result;
      tvContentRouteRegistry.attach(push);
      addTearDown(() => tvContentRouteRegistry.detach(push));

      await pump(tester, useShellRoute: true);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('subpage'), findsOneWidget);

      coordinator.popNested();
      await tester.pumpAndSettle();

      expect(find.text('subpage'), findsNothing);
      expect(find.text('destination root'), findsOneWidget);
      expect(reachableBar(), findsAtLeast(1));
    });
  });

  group('the result a caller awaits', () {
    test('a popped route completes with what it was popped with', () async {
      final route = TvNestedRoute(id: 'a', builder: (_) => const SizedBox());
      final live = coordinator.pushNested(coordinator.active, route);
      expect(identical(live, route), isTrue);

      coordinator.popNested(true);
      expect(await route.result, isTrue);
    });

    test('a discarded duplicate hands back the route that will actually pop', () async {
      final first = TvNestedRoute(id: 'a', builder: (_) => const SizedBox());
      final second = TvNestedRoute(id: 'a', builder: (_) => const SizedBox());

      coordinator.pushNested(coordinator.active, first);
      final live = coordinator.pushNested(coordinator.active, second);

      expect(identical(live, first), isTrue, reason: 'awaiting `second` would wait forever: it is not on the stack');
      expect(coordinator.nestedRoutesFor(coordinator.active), hasLength(1));

      coordinator.popNested('done');
      expect(await live.result, 'done');
    });

    test('clearing the stacks completes every route still waiting', () async {
      final route = TvNestedRoute(id: 'a', builder: (_) => const SizedBox());
      coordinator.pushNested(coordinator.active, route);

      coordinator.clearNestedRoutes();

      expect(await route.result, isNull);
    });

    test('completing twice is harmless, so a sweep after a pop cannot throw', () {
      final route = TvNestedRoute(id: 'a', builder: (_) => const SizedBox());
      coordinator.pushNested(coordinator.active, route);
      coordinator.popNested('first');
      expect(() => route.completeResult('second'), returnsNormally);
    });
  });

  group('the registry', () {
    setUp(() {
      // The registry is process-wide, so a test that attaches has to leave it
      // the way it found it or the next one inherits a shell that is not there.
      expect(tvContentRouteRegistry.isAvailable, isFalse);
    });

    test('no shell means no route, which is the caller\'s signal to push as before', () {
      expect(openTvContentRoute(id: 'x', builder: (_) => const SizedBox()), isNull);
    });

    test('a shell that is being replaced cannot detach the one that took over', () {
      Future<Object?> outgoing(TvNestedRoute route) async => null;
      Future<Object?> incoming(TvNestedRoute route) async => 'incoming';

      tvContentRouteRegistry.attach(outgoing);
      tvContentRouteRegistry.attach(incoming);
      // A profile switch mounts the new `MainScreen` before disposing the old
      // one, so this detach arrives last and must be ignored.
      tvContentRouteRegistry.detach(outgoing);

      expect(tvContentRouteRegistry.isAvailable, isTrue);
      tvContentRouteRegistry.detach(incoming);
      expect(tvContentRouteRegistry.isAvailable, isFalse);
    });
  });
}
