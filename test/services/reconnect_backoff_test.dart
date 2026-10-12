import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/reconnect_backoff.dart';

import '../test_helpers/prefs.dart';

void main() {
  group('ReconnectBackoff', () {
    late DateTime clock;
    late ReconnectBackoff backoff;

    setUp(() {
      clock = DateTime(2026, 10, 12, 10);
      backoff = ReconnectBackoff(now: () => clock);
    });

    test('the first failure waits for nothing: the resume retry is what catches a sleeping network stack', () {
      backoff.failed('a');

      expect(backoff.remaining('a'), isNull);
    });

    test('from the second failure the wait doubles up to the cap', () {
      final waits = <Duration>[];
      for (var i = 0; i < 8; i++) {
        backoff.failed('a');
        waits.add(backoff.remaining('a') ?? Duration.zero);
      }

      expect(waits, [
        Duration.zero,
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        const Duration(seconds: 40),
        const Duration(seconds: 80),
        const Duration(minutes: 2),
        const Duration(minutes: 2),
        const Duration(minutes: 2),
      ]);
    });

    test('the server may be tried again when its wait is over', () {
      backoff
        ..failed('a')
        ..failed('a');
      clock = clock.add(const Duration(seconds: 9));
      expect(backoff.remaining('a'), const Duration(seconds: 1));

      clock = clock.add(const Duration(seconds: 1));
      expect(backoff.remaining('a'), isNull);
    });

    test('a success, a reset and other servers are independent of the failures', () {
      backoff
        ..failed('a')
        ..failed('a')
        ..failed('b')
        ..failed('b');
      expect(backoff.remaining('c'), isNull);

      backoff.succeeded('a');
      expect(backoff.remaining('a'), isNull);
      expect(backoff.remaining('b'), isNotNull);

      backoff.reset();
      expect(backoff.remaining('b'), isNull);
    });
  });

  group('the reconnect sweep', () {
    setUp(resetSharedPreferencesForTest);

    test('leaves a server that stayed unreachable alone, but not for a manual reconnect', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_Offline('srv-1'), online: false);
      expect(manager.reconnectSweepServerIds(forceRediscovery: false), ['srv-1']);

      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      expect(manager.reconnectSweepServerIds(forceRediscovery: false), [
        'srv-1',
      ], reason: 'one failure: try again at once');

      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      expect(manager.reconnectSweepServerIds(forceRediscovery: false), isEmpty);
      expect(manager.reconnectSweepServerIds(forceRediscovery: true), ['srv-1']);
    });
  });
}

class _Offline implements MediaServerClient {
  _Offline(this.id);

  final String id;

  @override
  ServerId get serverId => ServerId(id);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
