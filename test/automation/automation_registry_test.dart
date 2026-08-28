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

    expect(ids, containsAll(['dup-a', 'dup-a#1']));
    expect(snapshot['duplicates'], contains('dup-a'));
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
