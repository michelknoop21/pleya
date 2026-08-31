import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_screen.dart';

void main() {
  setUp(() => AutomationScreenRegistry.debugSetInstance(null));
  tearDown(() => AutomationScreenRegistry.debugSetInstance(null));

  group('AutomationScreenRegistry (the primitive, not gated by kPleyaVerify)', () {
    test('snapshot reports id, ready and reason from a lazily-invoked getter', () {
      var ready = false;
      final token = AutomationScreenRegistry.instance.register(
        'screen.probe',
        () => ready ? const AutomationReadiness.ready() : const AutomationReadiness.loading('data'),
      );
      addTearDown(() => AutomationScreenRegistry.instance.unregister(token));

      var snapshot = AutomationScreenRegistry.instance.snapshot();
      expect(snapshot.single, containsPair('id', 'screen.probe'));
      expect(snapshot.single, containsPair('ready', false));
      expect(snapshot.single, containsPair('reason', 'data'));

      ready = true;
      snapshot = AutomationScreenRegistry.instance.snapshot();
      expect(snapshot.single, containsPair('ready', true));
      expect(snapshot.single.containsKey('reason'), isFalse);
    });

    test('unregister removes the entry', () {
      final token = AutomationScreenRegistry.instance.register('screen.probe', () => const AutomationReadiness.ready());
      expect(AutomationScreenRegistry.instance.snapshot(), hasLength(1));
      AutomationScreenRegistry.instance.unregister(token);
      expect(AutomationScreenRegistry.instance.snapshot(), isEmpty);
    });
  });

  group('AutomationReadiness', () {
    test('toJson carries state/ready/reason', () {
      expect(const AutomationReadiness.ready().toJson(), {'state': 'ready', 'ready': true});
      expect(const AutomationReadiness.loading('x').toJson(), {'state': 'loading', 'ready': false, 'reason': 'x'});
      expect(const AutomationReadiness.error('y').toJson(), {'state': 'error', 'ready': false, 'reason': 'y'});
    });
  });

  // kPleyaVerify is false in a normal `flutter test` run — real
  // registration/event behavior lives in AutomationScreenRegistry above and
  // is exercised there directly. What matters at the widget layer under the
  // default (off) build is that wrapping a screen changes nothing: no
  // registration, and the child renders exactly as given.
  testWidgets('is a true no-op wrapper when kPleyaVerify is false (the default build)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AutomationScreen(
          id: 'screen.probe',
          readiness: () => const AutomationReadiness.ready(),
          child: const Text('content'),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(AutomationScreenRegistry.instance.snapshot(), isEmpty);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
