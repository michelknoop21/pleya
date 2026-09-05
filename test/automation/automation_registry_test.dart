import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_registry.dart';

void main() {
  test('declared nodes with a duplicate id get a #2 suffix and land in duplicates', () {
    final tokenOne = AutomationRegistry.instance.register(
      const AutomationDeclaredNode(id: 'dup-a', role: 'button', label: 'one'),
    );
    final tokenTwo = AutomationRegistry.instance.register(
      const AutomationDeclaredNode(id: 'dup-a', role: 'button', label: 'two'),
    );
    addTearDown(() {
      AutomationRegistry.instance.unregister(tokenOne);
      AutomationRegistry.instance.unregister(tokenTwo);
    });

    final snapshot = AutomationRegistry.instance.snapshot();
    final declared = (snapshot['declared'] as List).cast<Map<String, Object?>>();
    final ids = declared.map((n) => n['id']).toList();

    // `#2` for the second occurrence, matching snapshot()'s own doc. The
    // suffix used to be `seen.length` at collision time, which made this
    // `#1` — off by one, and worse, not per-id (see the next test).
    expect(ids, containsAll(['dup-a', 'dup-a#2']));
    expect(snapshot['duplicates'], contains('dup-a'));
  });

  test('interleaved duplicates of different ids stay unique — the suffix counts per id', () {
    // With one shared counter, `a, a, b, b, a` produced `a#2, b#4, a#4`:
    // two nodes sharing an id in the snapshot, which is exactly what the
    // suffix exists to prevent and what snapshot()'s doc promises never
    // happens.
    final tokens = [
      for (final id in ['dup-x', 'dup-x', 'dup-y', 'dup-y', 'dup-x'])
        AutomationRegistry.instance.register(AutomationDeclaredNode(id: id, role: 'button')),
    ];
    addTearDown(() {
      for (final token in tokens) {
        AutomationRegistry.instance.unregister(token);
      }
    });

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
    final ids = declared.map((n) => n['id'] as String).where((id) => id.startsWith('dup-')).toList();

    expect(ids.toSet().length, ids.length, reason: 'every reported id must be unique: $ids');
    expect(ids, containsAll(['dup-x', 'dup-x#2', 'dup-x#3', 'dup-y', 'dup-y#2']));
  });

  testWidgets('discovered focusables are reported with bounds', (tester) async {
    final focusNode = FocusNode(debugLabel: 'probe');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(focusNode: focusNode, child: const SizedBox(width: 40, height: 20)),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    final snapshot = AutomationRegistry.instance.snapshot();
    final discovered = (snapshot['discovered'] as List).cast<Map<String, Object?>>();
    final probe = discovered.firstWhere((n) => n['label'] == 'probe');

    expect(probe['focused'], isTrue);
    expect(probe['bounds'], isNotNull);
    final bounds = probe['bounds'] as Map<String, Object?>;
    expect(bounds['width'], 40);
    expect(bounds['height'], 20);
  });

  testWidgets('declared nodes report live bounds, focus and state', (tester) async {
    final focusNode = FocusNode(debugLabel: 'declared-probe');
    addTearDown(focusNode.dispose);
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return Focus(focusNode: focusNode, child: const SizedBox(width: 30, height: 10));
            },
          ),
        ),
      ),
    );

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(
        id: 'declared-probe',
        role: 'button',
        focusNode: focusNode,
        contextGetter: () => capturedContext,
        state: () => {'selected': true},
      ),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    focusNode.requestFocus();
    await tester.pump();

    final snapshot = AutomationRegistry.instance.snapshot();
    final declared = (snapshot['declared'] as List).cast<Map<String, Object?>>();
    final node = declared.firstWhere((n) => n['id'] == 'declared-probe');

    expect(node['focused'], isTrue);
    expect(node['bounds'], {'x': 0.0, 'y': 0.0, 'width': 30.0, 'height': 10.0});
    expect(node['state'], {'selected': true});
  });

  // The regression the whole coordinate fix exists for. Before it, `_boundsOf`
  // was `localToGlobal(Offset.zero) & size`: the offset resolved through every
  // ancestor transform, the size did not. Under a Transform.scale -- which is
  // exactly what `_AppleTvScale` puts above the app on Apple TV (DEC-028,
  // factor 1.85) -- a node's reported position was in the scaled space and its
  // reported width in the unscaled one, 1.85x out of step with itself.
  //
  // Both assertions here fail on the old implementation: the width came back
  // 40, not 80, while x already came back 100.
  testWidgets('bounds report position and size in the same space under a Transform.scale', (tester) async {
    final focusNode = FocusNode(debugLabel: 'scaled-probe');
    addTearDown(focusNode.dispose);
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Transform.scale(
          scale: 2,
          alignment: Alignment.topLeft,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 50, top: 25),
              child: Builder(
                builder: (context) {
                  capturedContext = context;
                  return Focus(focusNode: focusNode, child: const SizedBox(width: 40, height: 12));
                },
              ),
            ),
          ),
        ),
      ),
    );

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(
        id: 'scaled-probe',
        role: 'button',
        focusNode: focusNode,
        contextGetter: () => capturedContext,
      ),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));
    await tester.pump();

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
    final bounds = declared.firstWhere((n) => n['id'] == 'scaled-probe')['bounds']! as Map<String, Object?>;

    // Position was already scaled; size now agrees with it.
    expect(bounds['x'], 100.0);
    expect(bounds['y'], 50.0);
    expect(bounds['width'], 80.0);
    expect(bounds['height'], 24.0);
  });

  testWidgets('an unscaled tree is unaffected by the same code path', (tester) async {
    final focusNode = FocusNode(debugLabel: 'plain-probe');
    addTearDown(focusNode.dispose);
    late BuildContext capturedContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return Focus(focusNode: focusNode, child: const SizedBox(width: 40, height: 12));
            },
          ),
        ),
      ),
    );

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(
        id: 'plain-probe',
        role: 'button',
        focusNode: focusNode,
        contextGetter: () => capturedContext,
      ),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));
    await tester.pump();

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
    expect(declared.firstWhere((n) => n['id'] == 'plain-probe')['bounds'], {
      'x': 0.0,
      'y': 0.0,
      'width': 40.0,
      'height': 12.0,
    });
  });

  testWidgets('rootSpaceScaleOf reads the factor off the render tree', (tester) async {
    late BuildContext scaled;
    late BuildContext plain;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Transform.scale(
              scale: 1.85,
              child: Builder(
                builder: (context) {
                  scaled = context;
                  return const SizedBox(width: 10, height: 10);
                },
              ),
            ),
            Builder(
              builder: (context) {
                plain = context;
                return const SizedBox(width: 10, height: 10);
              },
            ),
          ],
        ),
      ),
    );

    expect(rootSpaceScaleOf(scaled), closeTo(1.85, 1e-9));
    expect(rootSpaceScaleOf(plain), closeTo(1.0, 1e-9));
  });

  // The stale-state regression the top-nav scenario surfaced: a node registers
  // once, in initState, and `didUpdateWidget` does not re-register, so handing
  // the registry `widget.automationState` handed it the first build's closure.
  // `/v1/route` reported the destination had changed while the nav pill's own
  // `active` was still the value it was born with, from the same frame.
  testWidgets('a declared node reports the current build\'s state, not the one it registered with', (tester) async {
    final focusNode = FocusNode(debugLabel: 'live-state-probe');
    addTearDown(focusNode.dispose);
    final active = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    late BuildContext capturedContext;
    bool isActive = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, value, _) {
            isActive = value;
            return Builder(
              builder: (context) {
                capturedContext = context;
                return Focus(focusNode: focusNode, child: const SizedBox(width: 10, height: 10));
              },
            );
          },
        ),
      ),
    );

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(
        id: 'live-state-probe',
        role: 'nav',
        focusNode: focusNode,
        contextGetter: () => capturedContext,
        // The shape FocusableWrapper now registers: a thunk, not the closure
        // that existed at registration time.
        state: () => {'active': isActive},
      ),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    Map<String, Object?> read() {
      final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
      return declared.firstWhere((n) => n['id'] == 'live-state-probe')['state']! as Map<String, Object?>;
    }

    expect(read(), {'active': false});

    active.value = true;
    await tester.pump();

    expect(read(), {'active': true}, reason: 'the registry must read through to the current build');
  });

  testWidgets('a duplicate id addresses the copy the remote can reach, not the one the shell excluded', (tester) async {
    // `SettingsScreen` and `LibrariesScreen` are `MainScreen` destinations and
    // Mijn Pleya sections at the same time, and the shell keeps its
    // destinations alive with the inactive ones inside `ExcludeFocus`. Both
    // copies register the same ids. Registration order used to decide which
    // one got the bare id, and the offstage copy registers first, so
    // `tvos.my-pleya.library-chooser` waited out its timeout on a chip that
    // cannot take focus while the chip on screen was focused as `…#2`.
    final excluded = FocusNode(debugLabel: 'offstage-copy');
    final onScreen = FocusNode(debugLabel: 'on-screen-copy');
    addTearDown(excluded.dispose);
    addTearDown(onScreen.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            ExcludeFocus(
              child: Focus(focusNode: excluded, child: const SizedBox(width: 10, height: 10)),
            ),
            Focus(focusNode: onScreen, child: const SizedBox(width: 10, height: 10)),
          ],
        ),
      ),
    );

    // Registered in the order the shell registers them: offstage first.
    for (final node in [excluded, onScreen]) {
      final token = AutomationRegistry.instance.register(
        AutomationDeclaredNode(id: 'twice-mounted', role: 'button', focusNode: node),
      );
      addTearDown(() => AutomationRegistry.instance.unregister(token));
    }

    onScreen.requestFocus();
    await tester.pump();

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
    final bare = declared.firstWhere((n) => n['id'] == 'twice-mounted');
    final suffixed = declared.firstWhere((n) => n['id'] == 'twice-mounted#2');

    expect(bare['canRequestFocus'], isTrue, reason: 'the bare id is the copy a scenario can act on');
    expect(bare['focused'], isTrue);
    expect(suffixed['canRequestFocus'], isFalse, reason: 'the excluded copy keeps its place, behind the suffix');
  });

  testWidgets('an id that is not duplicated keeps its registration order', (tester) async {
    // The reordering is narrow on purpose: it must not shuffle a tree that has
    // no collisions in it.
    final tokens = [
      for (final id in ['first', 'second', 'third'])
        AutomationRegistry.instance.register(AutomationDeclaredNode(id: id, role: 'button')),
    ];
    for (final token in tokens) {
      addTearDown(() => AutomationRegistry.instance.unregister(token));
    }

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
    expect(declared.map((n) => n['id']), containsAllInOrder(['first', 'second', 'third']));
  });

  testWidgets('a state-only duplicate resolves to the copy that is painted', (tester) async {
    // `library.header` has no focus node, so the `canRequestFocus` signal
    // above says nothing about it. It duplicates for the same reason the chips
    // do — `LibrariesScreen` is a `MainScreen` destination and a Mijn Pleya
    // section at once — and `tvos.my-pleya.library-chooser` read "Movies" off
    // the untouched offstage copy while the page on screen already showed
    // Shows.
    const hiddenValue = 'Movies';
    const shownValue = 'Shows';
    BuildContext? hiddenContext;
    BuildContext? shownContext;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: IndexedStack(
          index: 1,
          children: [
            Builder(
              builder: (context) {
                hiddenContext = context;
                return const SizedBox(width: 10, height: 10);
              },
            ),
            Builder(
              builder: (context) {
                shownContext = context;
                return const SizedBox(width: 10, height: 10);
              },
            ),
          ],
        ),
      ),
    );

    // Registered offstage-first, the order `MainScreen` produces.
    for (final entry in [(() => hiddenContext, () => hiddenValue), (() => shownContext, () => shownValue)]) {
      final token = AutomationRegistry.instance.register(
        AutomationDeclaredNode(
          id: 'header-twice',
          role: 'region',
          contextGetter: entry.$1,
          state: () => {'library': entry.$2()},
        ),
      );
      addTearDown(() => AutomationRegistry.instance.unregister(token));
    }

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
    final bare = declared.firstWhere((n) => n['id'] == 'header-twice');

    expect(
      (bare['state']! as Map<String, Object?>)['library'],
      'Shows',
      reason: 'the bare id is the copy on screen, not the one the IndexedStack is not showing',
    );

    // The hidden one keeps its place behind the suffix rather than vanishing.
    final suffixed = declared.firstWhere((n) => n['id'] == 'header-twice#2');
    expect((suffixed['state']! as Map<String, Object?>)['library'], 'Movies');
  });

  test('a FocusNode keeps one node number across snapshots, and two nodes never share one', () {
    final first = FocusNode(debugLabel: 'node-number-first');
    final second = FocusNode(debugLabel: 'node-number-second');
    addTearDown(() {
      first.dispose();
      second.dispose();
    });

    final tokens = [
      AutomationRegistry.instance.register(
        AutomationDeclaredNode(id: 'node-number.first', role: 'button', focusNode: first),
      ),
      AutomationRegistry.instance.register(
        AutomationDeclaredNode(id: 'node-number.second', role: 'button', focusNode: second),
      ),
    ];
    addTearDown(() {
      for (final token in tokens) {
        AutomationRegistry.instance.unregister(token);
      }
    });

    Map<String, Object?> declaredFor(String id) => (AutomationRegistry.instance.snapshot()['declared'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((n) => n['id'] == id);

    final firstNumber = declaredFor('node-number.first')['node'];
    final secondNumber = declaredFor('node-number.second')['node'];

    expect(firstNumber, isA<int>());
    expect(secondNumber, isA<int>());
    expect(firstNumber, isNot(secondNumber));

    // Stable across snapshots is the whole point: a focus walk lines up the
    // frame before a press against the frame after it, and a number that was
    // re-derived per snapshot would pair up the wrong two nodes.
    expect(declaredFor('node-number.first')['node'], firstNumber);
    expect(declaredFor('node-number.second')['node'], secondNumber);
  });

  test('a declared node without a FocusNode carries no node number', () {
    final token = AutomationRegistry.instance.register(
      const AutomationDeclaredNode(id: 'node-number.nodeless', role: 'text'),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((n) => n['id'] == 'node-number.nodeless');

    // Absent rather than null: the runner treats `node` as optional and falls
    // back to rects, and a null would have to be special-cased everywhere.
    expect(declared.containsKey('node'), isFalse);
  });

  testWidgets('the focus snapshot reports the same node number the tree does', (tester) async {
    final focusNode = FocusNode(debugLabel: 'node-number-focus');
    addTearDown(focusNode.dispose);

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(id: 'node-number.focused', role: 'button', focusNode: focusNode),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: focusNode, child: const SizedBox(width: 10, height: 10)),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    final declared = (AutomationRegistry.instance.snapshot()['declared'] as List)
        .cast<Map<String, Object?>>()
        .firstWhere((n) => n['id'] == 'node-number.focused');
    final focus = AutomationRegistry.instance.focusSnapshot();

    expect(focus, isNotNull);
    expect(focus!['node'], declared['node']);
  });
}
