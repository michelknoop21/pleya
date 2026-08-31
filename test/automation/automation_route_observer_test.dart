import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_event_log.dart';
import 'package:pleya/automation/automation_route_observer.dart';

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with RouteAware {
  int pushCount = 0;
  static AutomationRouteObserver? observer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    observer!.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void didPush() => pushCount++;

  @override
  void dispose() {
    observer!.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUp(() => AutomationEventLog.debugSetInstance(null));
  tearDown(() => AutomationEventLog.debugSetInstance(null));

  testWidgets('still forwards RouteAware notifications like a plain RouteObserver (regression)', (tester) async {
    final observer = AutomationRouteObserver();
    _ProbeState.observer = observer;

    await tester.pumpWidget(MaterialApp(navigatorObservers: [observer], home: const _Probe()));

    final probeState = tester.state<_ProbeState>(find.byType(_Probe));
    // didPush fires once the route observer sees the initial route land.
    expect(probeState.pushCount, 1);
  });

  testWidgets('emits nothing under the default (kPleyaVerify=false) build', (tester) async {
    final observer = AutomationRouteObserver();
    _ProbeState.observer = observer;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _Probe())),
            child: const Text('push'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(AutomationEventLog.instance.since(0), isEmpty);
  });
}
