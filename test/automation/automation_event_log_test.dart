import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_event_log.dart';

void main() {
  setUp(() => AutomationEventLog.debugSetInstance(null));
  tearDown(() => AutomationEventLog.debugSetInstance(null));

  test('seq is monotone and since() only returns newer entries', () {
    AutomationEventLog.instance.emit('a');
    AutomationEventLog.instance.emit('b');
    AutomationEventLog.instance.emit('c');

    final all = AutomationEventLog.instance.since(0);
    expect(all.map((e) => e.name).toList(), ['a', 'b', 'c']);
    expect(all.map((e) => e.seq).toList(), [1, 2, 3]);

    final afterFirst = AutomationEventLog.instance.since(1);
    expect(afterFirst.map((e) => e.name).toList(), ['b', 'c']);
  });

  test('carries event data through toJson', () {
    AutomationEventLog.instance.emit('screen.changed', {'to': 'screen.discover'});
    final event = AutomationEventLog.instance.since(0).single;
    expect(event.toJson(), containsPair('name', 'screen.changed'));
    expect(event.toJson()['data'], {'to': 'screen.discover'});
  });

  test('drops the oldest entries once the buffer is full', () {
    for (var i = 0; i < 550; i++) {
      AutomationEventLog.instance.emit('e$i');
    }
    final remaining = AutomationEventLog.instance.since(0);
    expect(remaining.length, 500);
    expect(remaining.first.name, 'e50');
    expect(remaining.last.name, 'e549');
  });
}
