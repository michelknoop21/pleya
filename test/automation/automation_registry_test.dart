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
}
