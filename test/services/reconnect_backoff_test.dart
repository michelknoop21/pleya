import 'dart:io';

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

    test('the second attempt of a resume retries what the first one raced, and nothing else', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_Offline('raced'), online: false);
      manager.debugRegisterClientForTesting(_Offline('skipped'), online: false);
      for (final id in ['raced', 'skipped']) {
        manager.debugRecordUnreachableForTesting(ServerId(id));
        manager.debugRecordUnreachableForTesting(ServerId(id));
      }
      // Attempt 0: both wait, so the sweep takes nobody on.
      expect(await manager.reconnectOfflineServers(), isEmpty);

      expect(manager.reconnectSweepServerIds(forceRediscovery: false, alsoRetry: {'raced'}), ['raced']);
      expect(await manager.reconnectOfflineServers(alsoRetry: {'raced'}), {'raced'});
    });

    test('a sweep reports the servers it took on, for the second attempt to pass back', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_Offline('srv-1'), online: false);

      expect(await manager.reconnectOfflineServers(), {'srv-1'});
    });

    test('a health probe that finds the server up forgets the wait', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final client = _Offline('srv-1');
      manager.debugRegisterClientForTesting(client, online: false);
      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      expect(manager.reconnectSweepServerIds(forceRediscovery: false), isEmpty);

      await manager.checkServerHealth();
      expect(manager.isServerOnline(ServerId('srv-1')), isTrue);
      manager.updateServerStatus(ServerId('srv-1'), false);

      expect(manager.reconnectSweepServerIds(forceRediscovery: false), ['srv-1']);
    });

    test('disconnecting every server forgets the waits', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(_Offline('srv-1'), online: false);
      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      manager.debugRecordUnreachableForTesting(ServerId('srv-1'));
      expect(manager.reconnectSweepServerIds(forceRediscovery: false), isEmpty);

      manager.disconnectAll();
      manager.debugRegisterClientForTesting(_Offline('srv-1'), online: false);

      expect(manager.reconnectSweepServerIds(forceRediscovery: false), ['srv-1']);
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

  test('the resume probe hands what its first attempt raced to the second', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('raced = await _serverManager.reconnectOfflineServers(alsoRetry: raced);'));
  });
}

class _Offline implements MediaServerClient {
  _Offline(this.id);

  final String id;

  @override
  ServerId get serverId => ServerId(id);

  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
