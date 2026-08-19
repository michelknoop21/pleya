import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';

import '../test_helpers/prefs.dart';

/// A Pleya Server connection has to survive a restart, and its refresh token
/// has to survive it *encrypted*. Both are asserted here against a real
/// database rather than a mock, because the row is where the failure would be.
void main() {
  late AppDatabase db;
  late ConnectionRegistry registry;

  PleyaServerConnection connection({String id = 'pleyaServer.srv-1', String refreshToken = 'rt-secret'}) =>
      PleyaServerConnection(
        id: id,
        baseUrl: 'http://nas.lan:8832',
        serverId: 'srv-1',
        serverName: 'Zolder',
        userName: 'michel',
        refreshToken: refreshToken,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000000),
      );

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registry = ConnectionRegistry(db);
  });

  tearDown(() async => db.close());

  test('a stored connection comes back as a Pleya Server connection', () async {
    await registry.upsert(connection());
    final restored = await registry.get('pleyaServer.srv-1');
    expect(restored, isA<PleyaServerConnection>());
    final pleya = restored! as PleyaServerConnection;
    expect(pleya.baseUrl, 'http://nas.lan:8832');
    expect(pleya.serverId, 'srv-1');
    expect(pleya.serverName, 'Zolder');
    expect(pleya.userName, 'michel');
    expect(pleya.refreshToken, 'rt-secret');
  });

  test('the refresh token is not readable in the stored row', () async {
    await registry.upsert(connection());
    final row = await (db.select(db.connections)..where((t) => t.id.equals('pleyaServer.srv-1'))).getSingle();
    expect(row.configJson, isNot(contains('rt-secret')), reason: 'the vault protects it like every other credential');
    final json = jsonDecode(row.configJson) as Map<String, dynamic>;
    expect(json['baseUrl'], 'http://nas.lan:8832', reason: 'the address is not a secret and stays readable');
    expect(json.containsKey('refreshToken'), isTrue);
  });

  test('a rotated token replaces the old one without changing the row identity', () async {
    await registry.upsert(connection());
    await registry.upsert(connection(refreshToken: 'rt-rotated'));
    final all = await registry.list();
    expect(all, hasLength(1));
    expect((all.single as PleyaServerConnection).refreshToken, 'rt-rotated');
  });

  test('listPleyaServers filters by type and not by id prefix', () async {
    await registry.upsert(connection());
    await registry.upsert(
      JellyfinConnection(
        id: 'jf-1',
        baseUrl: 'http://jf.lan',
        serverName: 'JF',
        serverMachineId: 'jf-1',
        userId: 'u',
        userName: 'u',
        accessToken: 't',
        deviceId: 'd',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000000),
      ),
    );
    expect(await registry.listPleyaServers(), hasLength(1));
    expect(await registry.getPleyaServer('jf-1'), isNull);
    expect(await registry.getPleyaServer('pleyaServer.srv-1'), isNotNull);
  });

  test('the kind column round-trips the new discriminator', () async {
    await registry.upsert(connection());
    final row = await (db.select(db.connections)..where((t) => t.id.equals('pleyaServer.srv-1'))).getSingle();
    expect(row.kind, 'pleyaServer');
    expect(ConnectionKind.fromId(row.kind), ConnectionKind.pleyaServer);
  });

  test('the first connection of any kind becomes the default', () async {
    await registry.upsert(connection());
    expect((await registry.getDefault())?.id, 'pleyaServer.srv-1');
  });
}
