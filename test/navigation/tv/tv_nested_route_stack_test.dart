/// The nested stack is a stack: pushing on top must not throw away what is
/// underneath.
///
/// `pushNested` always kept a real stack, but the shell built only its last
/// entry, so the route below left the widget tree and its `State` went with it.
/// Nothing noticed while one nested route was the most anyone could open. SYS-1b
/// put detail, collection and person on the same contract, and from that moment
/// two of them could stack, which broke two things at once:
///
///   - Opening a cast member from a detail page threw the detail away. Back
///     rebuilt it from nothing, so metadata was refetched and the season,
///     episode and scroll position the viewer had were gone.
///   - The everyday one, and the worse one: a caller that is itself nested gets
///     unmounted the moment it opens a detail. `media_navigation_helper` and
///     `MediaCard` both guard their post-navigation callbacks with
///     `context.mounted`, so those guards bailed and the callbacks never ran.
///     Marking something watched from "Alle films" left the row it came from
///     stale; deleting a collection left it in the grid.
///
/// What is asserted here is the property of the stack, not of one screen: a
/// counted `initState` is the difference between "still there" and "built
/// again", and a screen that merely looks right on Back could be either.
///
/// The second group covers the other half of the same event. `tvBackStep` puts
/// `popNested` ahead of the focus test on purpose, so Back with the remote in
/// the top bar pops through the shell and the screen's own dismissal never
/// runs. The route completed with `null` then, and whatever the screen had to
/// say was dropped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';

/// Counts how often it was built from scratch, which is the whole question.
class _CountingProbe extends StatefulWidget {
  const _CountingProbe({required this.label, required this.onInit});

  final String label;
  final VoidCallback onInit;

  @override
  State<_CountingProbe> createState() => _CountingProbeState();
}

class _CountingProbeState extends State<_CountingProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.label));
}

/// Records a result on its route the way a screen does when its state changes.
class _MarkingProbe extends StatelessWidget {
  const _MarkingProbe({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    TvNestedRouteScope.readOf(context)?.markResult(value);
    return Center(child: Text(label));
  }
}

void main() {
  const window = Size(1280, 720);

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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = window;
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
              dismissNestedRoute: ([_]) {},
              child: const Center(child: Text('destination root')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a route pushed on top of another', () {
    testWidgets('leaves the one underneath mounted rather than disposing it', (tester) async {
      await pump(tester);
      var builds = 0;

      coordinator.pushNested(
        coordinator.active,
        TvNestedRoute(id: 'detail', builder: (_) => _CountingProbe(label: 'detail', onInit: () => builds++)),
      );
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(builds, 1);

      coordinator.pushNested(
        coordinator.active,
        TvNestedRoute(id: 'person', builder: (_) => const Center(child: Text('person'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('person'), findsOneWidget, reason: 'the new route is the one on show');
      expect(
        find.text('detail', skipOffstage: false),
        findsOneWidget,
        reason: 'still in the tree, which is what keeps its State and its scroll position alive',
      );
      expect(find.text('detail'), findsNothing, reason: 'mounted is not the same as visible');
      expect(builds, 1, reason: 'a second initState here means it was thrown away and rebuilt');
    });

    testWidgets('comes back on Back without being built again', (tester) async {
      await pump(tester);
      var builds = 0;

      coordinator.pushNested(
        coordinator.active,
        TvNestedRoute(id: 'detail', builder: (_) => _CountingProbe(label: 'detail', onInit: () => builds++)),
      );
      await tester.pumpAndSettle();
      coordinator.pushNested(
        coordinator.active,
        TvNestedRoute(id: 'person', builder: (_) => const Center(child: Text('person'))),
      );
      await tester.pumpAndSettle();

      coordinator.popNested();
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsOneWidget);
      expect(find.text('person', skipOffstage: false), findsNothing, reason: 'popped means gone, not hidden');
      expect(
        builds,
        1,
        reason: 'this is the regression: before the fix Back rebuilt the detail from scratch, '
            'refetching its metadata and losing where the viewer was',
      );
    });

    testWidgets('takes the covered route out of the focus tree', (tester) async {
      await pump(tester);

      coordinator.pushNested(
        coordinator.active,
        TvNestedRoute(id: 'detail', builder: (_) => _CountingProbe(label: 'detail', onInit: () {})),
      );
      await tester.pumpAndSettle();
      coordinator.pushNested(
        coordinator.active,
        TvNestedRoute(id: 'person', builder: (_) => const Center(child: Text('person'))),
      );
      await tester.pumpAndSettle();

      bool excluded(Finder of) => tester
          .widgetList<ExcludeFocus>(find.ancestor(of: of, matching: find.byType(ExcludeFocus)))
          .any((w) => w.excluding);

      expect(
        excluded(find.text('detail', skipOffstage: false)),
        isTrue,
        reason: 'mounted underneath must not mean reachable: an invisible screen the remote can '
            'still walk into is the bug ExcludeFocus exists for',
      );
      expect(
        excluded(find.text('person')),
        isFalse,
        reason: 'the route on top is the one the remote is meant to reach',
      );
    });
  });

  group('a route popped by the shell', () {
    testWidgets('completes with what the screen recorded', (tester) async {
      await pump(tester);
      final route = TvNestedRoute(
        id: 'detail',
        builder: (_) => const _MarkingProbe(label: 'detail', value: true),
      );

      coordinator.pushNested(coordinator.active, route);
      await tester.pumpAndSettle();

      // No argument, the way `MainScreen` pops when Back is pressed with the
      // remote in the top bar and the screen's own dismissal never runs.
      coordinator.popNested();
      await tester.pumpAndSettle();

      expect(
        await route.result,
        isTrue,
        reason: 'without this the watch-state change made on the detail is dropped and the row '
            'it was opened from never refreshes',
      );
    });

    testWidgets('lets an explicit result win over what the screen recorded', (tester) async {
      await pump(tester);
      final route = TvNestedRoute(
        id: 'detail',
        builder: (_) => const _MarkingProbe(label: 'detail', value: true),
      );

      coordinator.pushNested(coordinator.active, route);
      await tester.pumpAndSettle();

      coordinator.popNested(false);
      await tester.pumpAndSettle();

      expect(await route.result, isFalse);
    });
  });

  test('a route nobody recorded anything on still completes with null', () async {
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    addTearDown(coordinator.dispose);
    final route = TvNestedRoute(id: 'a', builder: (_) => const SizedBox());

    coordinator.pushNested(coordinator.active, route);
    coordinator.popNested();

    expect(await route.result, isNull, reason: 'pendingResult must not invent a result where there was none');
  });
}
