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

    test('a failure that is only a moment old is retried by the second attempt of a resume', () {
      backoff
        ..failed('a')
        ..failed('a');
      expect(backoff.remaining('a'), const Duration(seconds: 10));

      clock = clock.add(const Duration(seconds: 3));
      expect(backoff.remaining('a', justFailed: const Duration(seconds: 10)), isNull);
      expect(backoff.remaining('a'), const Duration(seconds: 7), reason: 'an ordinary sweep still waits');

      clock = clock.add(const Duration(seconds: 8));
      expect(backoff.remaining('a', justFailed: const Duration(seconds: 10)), isNull);
    });

    test('a failure older than the grace keeps its wait', () {
      backoff
        ..failed('a')
        ..failed('a')
        ..failed('a');
      clock = clock.add(const Duration(seconds: 11));

      expect(backoff.remaining('a', justFailed: const Duration(seconds: 10)), const Duration(seconds: 9));
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
      expect(
        manager.reconnectSweepServerIds(forceRediscovery: false, retryJustFailed: const Duration(seconds: 10)),
        ['srv-1'],
        reason: 'the second attempt of a resume retries what failed a moment ago',
      );
    });

    test('forgets the wait when the server comes back by another way than a sweep', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_Offline('srv-1'), online: false);
      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      expect(manager.reconnectSweepServerIds(forceRediscovery: false), isEmpty);

      manager.updateServerStatus(ServerId('srv-1'), true);
      manager.updateServerStatus(ServerId('srv-1'), false);

      expect(manager.reconnectSweepServerIds(forceRediscovery: false), ['srv-1']);
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
