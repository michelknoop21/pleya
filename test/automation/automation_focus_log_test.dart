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

  testWidgets('records focus changes when start() ran before any widget existed', (tester) async {
    // The real bootstrap order, and the one every other test in this file
    // gets wrong: `AutomationBootstrap` calls start() before the first
    // frame, when `primaryFocus` is null. The node listener then has nothing
    // to attach to, and since only that node's own notification re-points
    // it, it never attached to anything afterwards either.
    //
    // Every evidence bundle written up to Fase 11 had an empty
    // focus-trace.json because of this — on iOS, macOS and tvOS — while
    // focus was visibly moving. Starting first is the whole point of this
    // test; pumping first hides the bug.
    AutomationFocusLog.instance.start();

    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    addTearDown(() {
      first.dispose();
      second.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: first, child: const SizedBox(width: 5, height: 5)),
              Focus(focusNode: second, child: const SizedBox(width: 5, height: 5)),
            ],
          ),
        ),
      ),
    );

    first.requestFocus();
    await tester.pump();
    second.requestFocus();
    await tester.pump();

    final labels = AutomationFocusLog.instance.since(0).map((e) => e.to).toList();
    expect(labels, contains('first'));
    expect(labels, contains('second'));
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

  testWidgets('the frame watch installs at most once across repeated instance replacement', (tester) async {
    // `addPersistentFrameCallback` cannot be unregistered, so a per-instance
    // callback would leak one every time a test swaps the singleton — this
    // file's own setUp/tearDown does exactly that between every test. What
    // is reliably testable without reaching into Flutter internals (no API
    // reports "how many persistent callbacks are registered") is our own
    // call count into that API, via the `@visibleForTesting` counter.
    final before = AutomationFocusLog.debugFrameWatchInstallCount;

    final nodes = List.generate(4, (i) => FocusNode(debugLabel: 'swap$i'));
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

    // Swap the singleton and start() a fresh instance several times within
    // one test — the real shape of this file's setUp/tearDown, repeated
    // here so a leaked extra callback would actually show up in the count.
    for (var i = 0; i < nodes.length; i++) {
      AutomationFocusLog.debugSetInstance(null);
      AutomationFocusLog.instance.start();
      nodes[i].requestFocus();
      await tester.pump();
    }

    // Installed at most once more than before this test ran (zero if some
    // earlier test in this binding already installed it) — never once per
    // swap, which is what the old per-instance callback would have done.
    expect(AutomationFocusLog.debugFrameWatchInstallCount, lessThanOrEqualTo(before + 1));

    // And the currently-live instance still tracks correctly: the one
    // static callback redirects to whichever instance is current, not
    // whichever one first installed it.
    final labels = AutomationFocusLog.instance.since(0).map((e) => e.to).toList();
    expect(labels, contains('swap3'));
  });
}
