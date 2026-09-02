import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_event_log.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/automation/automation_wait.dart';

void main() {
  setUp(() => AutomationEventLog.debugSetInstance(null));
  tearDown(() => AutomationEventLog.debugSetInstance(null));

  test('resolves immediately when the event already happened', () async {
    AutomationEventLog.instance.emit('screen.ready', {'id': 'screen.discover'});
    final result = await const AutomationWait().resolve({
      'event': {'name': 'screen.ready'},
      'timeoutMs': 2000,
    });
    expect(result['ok'], isTrue);
  });

  test('times out when the event never arrives', () async {
    final result = await const AutomationWait().resolve({
      'event': {'name': 'nope'},
      'timeoutMs': 150,
    });
    expect(result, {'ok': false, 'reason': 'timeout'});
  });

  test('resolves on a declared node matching id/visible/focused', () async {
    final token = AutomationRegistry.instance.register(const AutomationDeclaredNode(id: 'wait-probe', role: 'button'));
    addTearDown(() => AutomationRegistry.instance.unregister(token));

    final result = await const AutomationWait().resolve({
      'node': {'id': 'wait-probe'},
      'timeoutMs': 2000,
    });
    expect(result['ok'], isTrue);
    expect((result['node'] as Map)['id'], 'wait-probe');
  });

  test('times out when no node matches', () async {
    final result = await const AutomationWait().resolve({
      'node': {'id': 'does-not-exist'},
      'timeoutMs': 150,
    });
    expect(result, {'ok': false, 'reason': 'timeout'});
  });

  test('falls back to stableFrames and degrades gracefully without a binding', () async {
    final result = await const AutomationWait().resolve({});
    expect(result, {'ok': true, 'reason': 'stableFrames'});
  });
}
