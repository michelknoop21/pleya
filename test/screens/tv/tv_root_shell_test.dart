/// The fase-7 TV root (hoofdstuk 6.2, 7.5, and 33's shared shell).
///
/// Against the production [TvRootShell] with the production [TvTopNavigation]
/// inside it — not a test-only arrangement that merely looks like the shell.
/// What is being proved here is structural: that the TV root has one navigation
/// authority and it is horizontal, that a nested route keeps the bar on screen
/// and its destination mounted underneath, and that the scope every content
/// screen already talks to is wired to the bar.
library;

import 'package:flutter/material.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

void main() {
  late TvNavigationCoordinator coordinator;
  late FocusMemoryTracker nodes;
  late FocusScopeNode navScope;
  late FocusScopeNode contentScope;
  late List<TvDestinationId> selected;
  late int navFocusCalls;
  late int contentFocusCalls;

  setUp(() {
    coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    navScope = FocusScopeNode(debugLabel: 'nav');
    contentScope = FocusScopeNode(debugLabel: 'content');
    selected = [];
    navFocusCalls = 0;
    contentFocusCalls = 0;
  });

  tearDown(() {
    coordinator.dispose();
    nodes.dispose();
    navScope.dispose();
    contentScope.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    Widget? content,
    VoidCallback? onFocusNav,
    ValueChanged<bool>? onOverlaySheetOpenChanged,
  }) async {
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
              onSelectDestination: selected.add,
              onFocusContent: ({bool restorePreviousFocus = true}) => contentFocusCalls++,
              onFocusNav: onFocusNav ?? () => navFocusCalls++,
              onOpenProfiles: () {},
              onOverlaySheetOpenChanged: onOverlaySheetOpenChanged ?? (_) {},
              onKeyEvent: (_) => KeyEventResult.ignored,
              selectLibrary: null,
              openSettings: null,
              child: content ?? const _Destination(label: 'destination root'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // One root, and it is horizontal (hoofdstuk 6.2)
  // ---------------------------------------------------------------------------

  group('the root', () {
    testWidgets('has a top navigation and no side navigation rail', (tester) async {
      await pump(tester);

      expect(find.byType(TvTopNavigation), findsOneWidget);
      // The decided end state: no sidebar in the final TV UI. A shell that drew
      // both would have two root navigation authorities and two answers to
      // every Left press.
      expect(find.byType(SideNavigationRail), findsNothing);
    });

    testWidgets('the bar sits above the content, across the full width', (tester) async {
      await pump(tester);

      final bar = tester.getRect(find.byType(TvTopNavigation));
      final content = tester.getRect(find.text('destination root'));

      expect(bar.top, lessThan(content.top));
      expect(bar.bottom, lessThanOrEqualTo(content.top));
      expect(bar.width, tester.getRect(find.byType(TvRootShell)).width);
    });

    testWidgets('content starts at the left edge and is as wide as the screen', (tester) async {
      await pump(tester);

      final context = tester.element(find.text('destination root'));
      // A top bar takes height, not width. Every horizontal value the scope
      // carries is the full viewport, so the bleed builders that counter-animate
      // a sliding rail have nothing to counter.
      expect(MainScreenFocusScope.foregroundLeftOf(context), 0);
      expect(MainScreenFocusScope.sideNavigationBleedOf(context), 0);
      expect(MainScreenFocusScope.foregroundWidthOf(context), MainScreenFocusScope.fullBleedWidthOf(context));
    });

    testWidgets('the scope every content screen already talks to reaches the bar', (tester) async {
      await pump(tester);

      // Content screens call `focusSidebar` to leave content. On this shell that
      // target is the top navigation, which is why fase 7 needed no edit to the
      // screens that already did it.
      MainScreenFocusScope.of(tester.element(find.text('destination root')), listen: false)!.focusSidebar();
      expect(navFocusCalls, 1);
    });

    // The test above proves the scope reaches `onFocusNav`; this one proves the
    // ring actually lands on a destination in the bar, which is what a viewer
    // pressing UP out of a header or LEFT out of a grid is really asking for.
    //
    // The `onFocusNav` body here mirrors `MainScreen._focusSidebar`'s TV branch
    // (`lib/screens/main_screen.dart:1419`) — focus the node for
    // `coordinator.focusedDestination`. It is a mirror and not the real thing:
    // nothing in the suite mounts `MainScreen`, so the last link of the
    // content → bar chain is still joined by hand here. Registered as an open
    // edge case rather than left implied; see I24 in
    // docs/qa/tvos-unified-edge-cases.md.
    testWidgets('reaching the bar puts the ring on a destination in it', (tester) async {
      await pump(tester, onFocusNav: () => nodes.get(coordinator.focusedDestination.focusKey).requestFocus());

      MainScreenFocusScope.of(tester.element(find.text('destination root')), listen: false)!.focusSidebar();
      await tester.pump();

      final focused = FocusManager.instance.primaryFocus;
      expect(focused, same(nodes.get(coordinator.focusedDestination.focusKey)));
      // Not merely "some node took focus": it has to be a node the bar renders,
      // or the ring is on something the viewer cannot see.
      expect(
        find.ancestor(of: find.byWidget(focused!.context!.widget), matching: find.byType(TvTopNavigation)),
        findsOneWidget,
      );
    });

    // Hoofdstuk 7.6 through the bar: the ring returns to the item it was last
    // on, not to whichever destination happens to be open. Walking to a
    // neighbour and going back down into content must not silently re-point the
    // bar at the active page.
    testWidgets('the bar remembers the item the ring was on, not the open destination', (tester) async {
      await pump(tester, onFocusNav: () => nodes.get(coordinator.focusedDestination.focusKey).requestFocus());

      // Walk the ring off the active destination without activating anything.
      nodes.get(TvDestinationId.series.focusKey).requestFocus();
      await tester.pump();
      expect(selected, isEmpty, reason: 'moving the ring is not choosing a destination');

      MainScreenFocusScope.of(tester.element(find.text('destination root')), listen: false)!.focusSidebar();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(nodes.get(TvDestinationId.series.focusKey)));
    });

    testWidgets('activating a destination in the bar reports it to the shell owner', (tester) async {
      await pump(tester);

      // Through the remote, which is the only input this surface has.
      nodes.get(TvDestinationId.series.focusKey).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(selected, [TvDestinationId.series]);
    });
  });

  // ---------------------------------------------------------------------------
  // I14: an open overlay owns the remote (hoofdstuk 7.5 step 1)
  // ---------------------------------------------------------------------------

  group('I14: switching tab while an overlay is open', () {
    /// Content that opens a sheet on demand, through the same
    /// [OverlaySheetController] every production overlay uses.
    Widget sheetOpener() => Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => OverlaySheetController.of(context).show<void>(
            builder: (_) => const SizedBox(height: 120, child: Center(child: Text('SHEET'))),
          ),
          child: const Text('open sheet'),
        ),
      ),
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();
      expect(find.text('SHEET'), findsOneWidget);
    }

    testWidgets('Select goes to the sheet, never to the bar underneath', (tester) async {
      final open = <bool>[];
      await pump(tester, content: sheetOpener(), onOverlaySheetOpenChanged: open.add);
      await openSheet(tester);
      expect(open.last, isTrue, reason: 'the shell is told, so it can stand down');

      final before = coordinator.active;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(
        selected,
        isEmpty,
        reason: 'the sheet owns the remote while it is up: no destination is activated behind it',
      );
      expect(coordinator.active, before);
      expect(find.text('SHEET'), findsOneWidget);
    });

    testWidgets('arrow keys do not walk the bar underneath it', (tester) async {
      await pump(tester, content: sheetOpener());
      await openSheet(tester);

      final before = coordinator.focusedDestination;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(coordinator.focusedDestination, before, reason: 'traversal is confined to the sheet\'s own focus scope');
      expect(selected, isEmpty);
    });

    testWidgets('Back closes the sheet and leaves the destination alone', (tester) async {
      final open = <bool>[];
      await pump(tester, content: sheetOpener(), onOverlaySheetOpenChanged: open.add);
      await openSheet(tester);

      final before = coordinator.active;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('SHEET'), findsNothing);
      expect(open.last, isFalse);
      expect(
        coordinator.active,
        before,
        reason: 'one press does one thing: it closed the sheet, it did not also leave the destination',
      );
      expect(selected, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Nested routes (hoofdstuk 7.5 step 2, 33's shared shell)
  // ---------------------------------------------------------------------------

  group('a nested route', () {
    TvNestedRoute route(String label) => TvNestedRoute(
      id: label,
      builder: (context) => _Destination(label: label),
    );

    testWidgets('renders inside the shell, with the bar still on screen', (tester) async {
      await pump(tester);

      coordinator.pushNested(coordinator.active, route('all movies'));
      await tester.pumpAndSettle();

      expect(find.text('all movies'), findsOneWidget);
      // Hoofdstuk 33's shared shell is binding on all eight references, "Alle
      // films" (33.5) included — so this screen keeps the bar rather than
      // covering it the way a full-screen push would.
      expect(find.byType(TvTopNavigation), findsOneWidget);
    });

    testWidgets('leaves its destination mounted underneath rather than throwing it away', (tester) async {
      await pump(tester);

      coordinator.pushNested(coordinator.active, route('all movies'));
      await tester.pumpAndSettle();

      // Offstage, not removed: the landing keeps its scroll position, its
      // providers and its focus nodes, so popping costs no reload
      // (hoofdstuk 24).
      expect(find.text('destination root', skipOffstage: false), findsOneWidget);
      expect(find.text('destination root'), findsNothing);
    });

    testWidgets('popping brings the destination back', (tester) async {
      await pump(tester);

      coordinator.pushNested(coordinator.active, route('all movies'));
      await tester.pumpAndSettle();
      expect(coordinator.activeCanPop, isTrue);

      coordinator.popNested();
      await tester.pumpAndSettle();

      expect(find.text('destination root'), findsOneWidget);
      expect(find.text('all movies'), findsNothing);
    });

    testWidgets('belongs to its own destination and does not follow the viewer elsewhere', (tester) async {
      await pump(tester);

      coordinator.activate(TvDestinationId.movies);
      coordinator.pushNested(TvDestinationId.movies, route('all movies'));
      await tester.pumpAndSettle();
      expect(find.text('all movies'), findsOneWidget);

      coordinator.activate(TvDestinationId.series);
      await tester.pumpAndSettle();

      expect(find.text('all movies'), findsNothing);
      expect(coordinator.activeCanPop, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Live TV (hoofdstuk 19)
  // ---------------------------------------------------------------------------

  group('a conditional Live TV slot', () {
    testWidgets('appears and disappears without disturbing its neighbours', (tester) async {
      await pump(tester);
      expect(find.text(t.navigation.liveTv), findsNothing);

      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      await tester.pumpAndSettle();
      expect(find.text(t.navigation.liveTv), findsOneWidget);

      // Every other destination is still there, in the same order.
      final labels = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList();
      expect(
        labels,
        containsAllInOrder(<String>[
          t.common.home,
          t.unifiedCatalog.seriesTitle,
          t.unifiedCatalog.moviesTitle,
          t.navigation.liveTv,
          t.navigation.myPleya,
        ]),
      );
    });

    testWidgets('losing it while it is open moves the viewer to Home', (tester) async {
      await pump(tester);
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      coordinator.activate(TvDestinationId.liveTv);
      await tester.pumpAndSettle();

      final displaced = coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));
      await tester.pumpAndSettle();

      // Hoofdstuk 19: "als de gebruiker Live TV open heeft, gaat Pleya naar
      // Home". Never a bar with nothing lit on it.
      expect(displaced, tvRootDestination);
      expect(coordinator.active, tvRootDestination);
      expect(find.text(t.navigation.liveTv), findsNothing);
    });
  });
}

/// Stands in for a destination's screen. Deliberately inert: this file is about
/// the shell around the content, and a real screen would drag its providers in
/// without proving anything more about the shell.
class _Destination extends StatelessWidget {
  const _Destination({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topLeft, child: Text(label));
}
