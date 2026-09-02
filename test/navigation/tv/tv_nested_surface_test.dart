/// Focus entry into a TV nested route, and who owns Back inside one.
///
/// Both halves were reproduced on a real tvOS simulator with HID remote input
/// before they were written here. Opening Mijn Pleya > Media put the remote on
/// the content `FocusScope` itself and then on a rail that answered every
/// press with nothing; Menu moved the ring to the tab strip and left the
/// section open, so the only way out of it was to quit the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/key_event_utils.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/navigation/tv/tv_nested_back_owner.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';

void main() {
  TvNestedRoute routeFor(Widget child, {GlobalKey? screenKey}) =>
      TvNestedRoute(id: 'test.route', builder: (_) => child, screenKey: screenKey);

  Future<TvNestedSurfaceState> pump(WidgetTester tester, TvNestedRoute route) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TvNestedSurface(
          key: route.surfaceKey,
          route: route,
          child: Builder(builder: route.builder),
        ),
      ),
    );
    await tester.pump();
    return route.surfaceKey.currentState!;
  }

  group('focus entry', () {
    testWidgets('focuses the first focusable control when the screen has no FocusableTab', (tester) async {
      // The case that broke six of the ten sections: three of them are
      // StatelessWidgets, so there is no State for a GlobalKey to resolve to
      // and no contract to ask. A generic entry has to work anyway.
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final state = await pump(
        tester,
        routeFor(
          Column(
            children: [
              Focus(focusNode: first, child: const Text('a')),
              Focus(focusNode: second, child: const Text('b')),
            ],
          ),
        ),
      );

      expect(state.focusEntry(), isTrue);
      await tester.pump();
      expect(first.hasPrimaryFocus, isTrue);
      expect(state.holdsFocus, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('prefers the screen own contract when it has one', (tester) async {
      final key = GlobalKey<_ContractScreenState>();
      final state = await pump(tester, routeFor(_ContractScreen(key: key), screenKey: key));

      expect(state.focusEntry(), isTrue);
      await tester.pump();
      expect(key.currentState!.calls, 1, reason: 'the screen was asked, not bypassed');
      expect(key.currentState!.preferred.hasPrimaryFocus, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('reports false and keeps trying when the subtree has nothing focusable yet', (tester) async {
      // `LibrariesScreen` resolves its selected library from storage in a
      // post-frame callback and only then builds a grid, so a single attempt
      // on the frame the route mounts is a coin flip. The caller needs the
      // `false` to keep its pending intent armed — `focusActiveTabIfReady()`
      // returns void, which is exactly why the original breakage was silent.
      final late = FocusNode(debugLabel: 'late');
      addTearDown(late.dispose);
      final content = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(content.dispose);

      final state = await pump(
        tester,
        routeFor(ValueListenableBuilder<Widget>(valueListenable: content, builder: (_, child, _) => child)),
      );

      expect(state.focusEntry(), isFalse);
      expect(state.holdsFocus, isFalse);

      content.value = Focus(focusNode: late, child: const Text('arrived'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(late.hasPrimaryFocus, isTrue, reason: 'the bounded retry consumed the pending entry when content landed');
      await tester.pumpAndSettle();
    });

    testWidgets('a cancelled entry does not take the focus back afterwards', (tester) async {
      // P2: late content may consume an explicit intent and may never help
      // itself to the remote.
      final late = FocusNode(debugLabel: 'late');
      final elsewhere = FocusNode(debugLabel: 'elsewhere');
      addTearDown(late.dispose);
      addTearDown(elsewhere.dispose);
      final content = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(content.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Focus(focusNode: elsewhere, child: const Text('outside')),
              Builder(
                builder: (context) {
                  final route = _sharedRoute ??= TvNestedRoute(
                    id: 'test.route',
                    builder: (_) =>
                        ValueListenableBuilder<Widget>(valueListenable: content, builder: (_, child, _) => child),
                  );
                  return TvNestedSurface(
                    key: route.surfaceKey,
                    route: route,
                    child: Builder(builder: route.builder),
                  );
                },
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final state = _sharedRoute!.surfaceKey.currentState!;
      expect(state.focusEntry(), isFalse);
      state.cancelPendingEntry();

      elsewhere.requestFocus();
      await tester.pump();
      content.value = Focus(focusNode: late, child: const Text('arrived'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(elsewhere.hasPrimaryFocus, isTrue, reason: 'the cancelled retry must not steal it back');
      _sharedRoute = null;
      await tester.pumpAndSettle();
    });
  });

  group('back ownership', () {
    testWidgets('a focus-move back handler stands down inside a nested route', (tester) async {
      var moved = 0;
      late BuildContext inner;
      await tester.pumpWidget(
        MaterialApp(
          home: TvNestedBackOwner(
            child: Builder(builder: (context) => SizedBox(key: ValueKey(inner = context))),
          ),
        ),
      );

      final result = handleBackKeyFocusMove(
        inner,
        const KeyUpEvent(
          logicalKey: LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        () => moved++,
      );

      expect(result, KeyEventResult.ignored, reason: 'so the shell back chain gets its turn');
      expect(moved, 0);
    });

    testWidgets('and still handles Back where no nested route owns it', (tester) async {
      var moved = 0;
      late BuildContext inner;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) => SizedBox(key: ValueKey(inner = context))),
        ),
      );

      final result = handleBackKeyFocusMove(
        inner,
        const KeyUpEvent(
          logicalKey: LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        () => moved++,
      );

      expect(result, KeyEventResult.handled);
      expect(moved, 1, reason: 'desktop and mobile keep the behaviour they had');
    });
  });
}

TvNestedRoute? _sharedRoute;

class _ContractScreen extends StatefulWidget {
  const _ContractScreen({super.key});

  @override
  State<_ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<_ContractScreen> with FocusableTab {
  final FocusNode decoy = FocusNode(debugLabel: 'decoy');
  final FocusNode preferred = FocusNode(debugLabel: 'preferred');
  int calls = 0;

  @override
  void focusActiveTabIfReady() {
    calls++;
    preferred.requestFocus();
  }

  @override
  void dispose() {
    decoy.dispose();
    preferred.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Focus(focusNode: decoy, child: const Text('decoy comes first in traversal order')),
      Focus(focusNode: preferred, child: const Text('but the screen knows better')),
    ],
  );
}
