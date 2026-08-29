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
}
