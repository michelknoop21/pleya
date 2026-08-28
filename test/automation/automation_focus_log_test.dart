import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_event_log.dart';
import 'package:pleya/automation/automation_focus_log.dart';

void main() {
  setUp(() {
    AutomationEventLog.debugSetInstance(null);
    AutomationFocusLog.debugSetInstance(null);
  });
  tearDown(() {
    AutomationFocusLog.debugSetInstance(null);
    AutomationEventLog.debugSetInstance(null);
  });

  testWidgets('a focus change is recorded with from/to and mirrored as an event', (tester) async {
    final nodeA = FocusNode(debugLabel: 'a');
    final nodeB = FocusNode(debugLabel: 'b');
    addTearDown(() {
      nodeA.dispose();
      nodeB.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: nodeA, child: const SizedBox(width: 10, height: 10)),
              Focus(focusNode: nodeB, child: const SizedBox(width: 10, height: 10)),
            ],
          ),
        ),
      ),
    );

    AutomationFocusLog.instance.start();

    nodeA.requestFocus();
    await tester.pump();
    nodeB.requestFocus();
    await tester.pump();

    final entries = AutomationFocusLog.instance.since(0);
    expect(entries, isNotEmpty);
    final last = entries.last;
    expect(last.from, 'a');
    expect(last.to, 'b');

    final events = AutomationEventLog.instance.since(0).where((e) => e.name == 'focus.changed');
    expect(events, isNotEmpty);
    expect(events.last.data, {'from': 'a', 'to': 'b'});
  });

  testWidgets('seq is monotone across multiple changes', (tester) async {
    final nodes = List.generate(3, (i) => FocusNode(debugLabel: 'n$i'));
    addTearDown(() {
      for (final n in nodes) {
        n.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [for (final n in nodes) Focus(focusNode: n, child: const SizedBox(width: 5, height: 5))],
          ),
        ),
      ),
    );

    AutomationFocusLog.instance.start();
    for (final node in nodes) {
      node.requestFocus();
      await tester.pump();
    }

    final entries = AutomationFocusLog.instance.since(0);
    final seqs = entries.map((e) => e.seq).toList();
    expect(seqs, List.generate(seqs.length, (i) => i + 1));
  });
}
