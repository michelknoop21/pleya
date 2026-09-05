import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/automation/automation_wait.dart';

/// Deliberately its own file. `automation_wait_test.dart` covers the paths
/// that must survive *without* a live binding — `stableFrames` degrades
/// gracefully there — and a single `testWidgets` anywhere in a file installs
/// one for every test in it, which turns that one into a 30-second hang.
void main() {
  /// `visible` used to be derived from `bounds != null`, and an
  /// `IndexedStack` lays out every tab it keeps mounted — so waiting for a
  /// screen to appear was satisfied by the screen still parked behind the
  /// one on show.
  testWidgets('a mounted but undrawn node does not satisfy a wait for visible', (tester) async {
    late BuildContext hidden;

    await tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(
          index: 1,
          children: [
            Builder(
              builder: (context) {
                hidden = context;
                return const SizedBox(width: 30, height: 10);
              },
            ),
            const SizedBox(width: 30, height: 10),
          ],
        ),
      ),
    );

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(id: 'wait-hidden-probe', role: 'screen', contextGetter: () => hidden),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    final result = await tester.runAsync(
      () => const AutomationWait().resolve({
        'node': {'id': 'wait-hidden-probe', 'visible': true},
        'timeoutMs': 150,
      }),
    );

    expect(result, {'ok': false, 'reason': 'timeout'});
  });

  testWidgets('the drawn node of the same stack does satisfy it', (tester) async {
    late BuildContext shown;

    await tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(
          index: 1,
          children: [
            const SizedBox(width: 30, height: 10),
            Builder(
              builder: (context) {
                shown = context;
                return const SizedBox(width: 30, height: 10);
              },
            ),
          ],
        ),
      ),
    );

    final token = AutomationRegistry.instance.register(
      AutomationDeclaredNode(id: 'wait-shown-probe', role: 'screen', contextGetter: () => shown),
    );
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    final result = await tester.runAsync(
      () => const AutomationWait().resolve({
        'node': {'id': 'wait-shown-probe', 'visible': true},
        'timeoutMs': 2000,
      }),
    );

    expect(result?['ok'], isTrue);
  });
}
