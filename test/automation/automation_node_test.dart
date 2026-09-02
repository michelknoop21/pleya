import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/automation/automation_screen.dart';

/// `AutomationNode`/`AutomationScreen` only register when the build has
/// `--dart-define=PLEYA_VERIFY=true`, so the registration behaviour below
/// cannot be observed in a default `flutter test` run. Same shape as
/// `automation_auth_test.dart`'s token group: skipped by default, with the
/// command that runs it in the skip reason.
const bool _verifyOn = bool.fromEnvironment('PLEYA_VERIFY');
const String _skipReason = 'run with --dart-define=PLEYA_VERIFY=true';

/// A parent that rebuilds its child with a new value, the way a real screen
/// does — `NavigationRailItem` passes `selected`/`collapsed` into
/// `AutomationNode.state` as an inline closure over its own fields, so every
/// rebuild produces a *different* closure over *different* values.
class _Rebuildable extends StatefulWidget {
  final Widget Function(BuildContext context, bool selected) builder;

  const _Rebuildable({super.key, required this.builder});

  @override
  State<_Rebuildable> createState() => _RebuildableState();
}

class _RebuildableState extends State<_Rebuildable> {
  bool selected = false;

  void select() => setState(() => selected = true);

  @override
  Widget build(BuildContext context) => widget.builder(context, selected);
}

Map<String, Object?>? _declaredById(String id) {
  final declared = (AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map<String, Object?>>();
  for (final node in declared) {
    if (node['id'] == id) return node;
  }
  return null;
}

void main() {
  group('AutomationNode reports current state, not the state it mounted with', () {
    testWidgets('a rebuild with a new state closure is visible in /v1/ui_tree', (tester) async {
      final key = GlobalKey<_RebuildableState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _Rebuildable(
            key: key,
            builder: (context, selected) => AutomationNode(
              id: 'nav.item',
              role: 'navItem',
              state: () => {'selected': selected},
              child: const Text('Home'),
            ),
          ),
        ),
      );

      expect(_declaredById('nav.item')?['state'], {'selected': false});

      key.currentState!.select();
      await tester.pump();

      // The registry used to keep the closure captured at registration
      // time, so this stayed `false` forever: /v1/ui_tree reported the nav
      // state from before the tab switch, and a scenario asserting on it
      // passed or failed against stale truth.
      expect(_declaredById('nav.item')?['state'], {'selected': true});
    });

    testWidgets('a changed label re-registers, so a stale label cannot survive either', (tester) async {
      final key = GlobalKey<_RebuildableState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _Rebuildable(
            key: key,
            builder: (context, selected) => AutomationNode(
              id: 'nav.item',
              role: 'navItem',
              label: selected ? 'Home (selected)' : 'Home',
              child: const Text('Home'),
            ),
          ),
        ),
      );

      expect(_declaredById('nav.item')?['label'], 'Home');

      key.currentState!.select();
      await tester.pump();

      expect(_declaredById('nav.item')?['label'], 'Home (selected)');
    });

    testWidgets('one registration survives a rebuild — no duplicate entries', (tester) async {
      final key = GlobalKey<_RebuildableState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _Rebuildable(
            key: key,
            builder: (context, selected) => AutomationNode(
              id: 'nav.item',
              role: 'navItem',
              state: () => {'selected': selected},
              child: const Text('Home'),
            ),
          ),
        ),
      );
      key.currentState!.select();
      await tester.pump();

      final snapshot = AutomationRegistry.instance.snapshot();
      final declared = (snapshot['declared'] as List).cast<Map<String, Object?>>();
      expect(declared.where((n) => (n['id'] as String).startsWith('nav.item')).length, 1);
      expect(snapshot['duplicates'], isEmpty);
    });

    testWidgets('disposing unregisters', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AutomationNode(id: 'nav.item', role: 'navItem', child: Text('Home')),
        ),
      );
      expect(_declaredById('nav.item'), isNotNull);

      await tester.pumpWidget(const MaterialApp(home: Text('gone')));
      expect(_declaredById('nav.item'), isNull);
    });
  }, skip: _verifyOn ? false : _skipReason);

  group('AutomationScreen reports current readiness, not the readiness it mounted with', () {
    testWidgets('a screen that finishes loading flips to ready in /v1/screens', (tester) async {
      final key = GlobalKey<_RebuildableState>();

      await tester.pumpWidget(
        MaterialApp(
          home: _Rebuildable(
            key: key,
            builder: (context, loaded) => AutomationScreen(
              id: 'screen.probe',
              readiness: () => loaded ? const AutomationReadiness.ready() : const AutomationReadiness.loading('data'),
              child: const Text('content'),
            ),
          ),
        ),
      );

      expect(AutomationScreenRegistry.instance.snapshot().single, containsPair('ready', false));

      key.currentState!.select();
      await tester.pump();

      // Registering the mount-time closure froze this at "loading" for a
      // screen that had long since finished — and a
      // `wait_until: {id: screen.…}` step blocks on exactly this value, so
      // the scenario would time out against a screen that was ready.
      expect(AutomationScreenRegistry.instance.snapshot().single, containsPair('ready', true));
    });
  }, skip: _verifyOn ? false : _skipReason);
}
