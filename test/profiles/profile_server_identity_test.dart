import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';

import '../test_helpers/prefs.dart';

void main() {
  late AppDatabase db;
  late ProfileConnectionRegistry registry;
  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registry = ProfileConnectionRegistry(db);
  });
  tearDown(() => db.close());
  Future<void> profile(String id, String name) => db
      .into(db.profiles)
      .insert(ProfilesCompanion.insert(id: id, kind: 'local', displayName: name, configJson: '{}', createdAt: 0));
  Future<void> binding(
    String profileId,
    String connectionId,
    String machine,
    String user, {
    String? bindingUser,
    bool borrowed = false,
  }) async {
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: connectionId,
            kind: 'jellyfin',
            displayName: 'Server',
            configJson: jsonEncode({
              'serverMachineId': machine,
              'userId': user,
              'accessToken': 'enc:v1:INVALID CIPHERTEXT',
            }),
            createdAt: 0,
          ),
        );
    await db
        .into(db.profileConnections)
        .insert(
          ProfileConnectionsCompanion.insert(
            profileId: profileId,
            connectionId: connectionId,
            userIdentifier: bindingUser ?? user,
            userToken: const Value('enc:v1:INVALID CIPHERTEXT'),
            borrowed: Value(borrowed),
          ),
        );
  }

  test('metadata query maps same-machine compound binding and never hydrates or rewrites credentials', () async {
    await profile('nikki', 'Nikki');
    await binding('nikki', 'jf/backend-user', 'jf', 'backend-user', borrowed: true);
    final before = await db.select(db.profileConnections).getSingle();
    final configBefore = await db.select(db.connections).getSingle();
    final result = await registry.listJellyfinProfileIdentities('jf');
    expect(result.single.displayName, 'Nikki');
    expect(result.single.userIds, {'backend-user'});
    await pumpEventQueue();
    expect((await db.select(db.profileConnections).getSingle()).userToken, before.userToken);
    expect((await db.select(db.connections).getSingle()).configJson, configBefore.configJson);
  });
  test('wrong server, stale binding, malformed config and unbound profiles have unknown identity', () async {
    for (final id in ['wrong', 'stale', 'malformed', 'unbound']) {
      await profile(id, id);
    }
    await binding('wrong', 'other/user', 'other', 'user');
    await binding('stale', 'jf/user', 'jf', 'user', bindingUser: 'other-user');
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: 'bad',
            kind: 'jellyfin',
            displayName: 'bad',
            configJson: 'INVALID',
            createdAt: 0,
          ),
        );
    await db
        .into(db.profileConnections)
        .insert(
          ProfileConnectionsCompanion.insert(profileId: 'malformed', connectionId: 'bad', userIdentifier: 'user'),
        );
    final result = await registry.listJellyfinProfileIdentities('jf');
    expect(result, hasLength(4));
    expect(result.map((r) => r.userIds), everyElement(isEmpty));
  });
  test('duplicate labels and multiple identities are preserved for clarification', () async {
    await profile('one', 'Nikki');
    await profile('two', 'Nikki');
    await binding('one', 'jf/a', 'jf', 'a');
    await binding('one', 'jf/b', 'jf', 'b');
    await binding('two', 'jf/c', 'jf', 'c');
    final result = await registry.listJellyfinProfileIdentities('jf');
    expect(result.map((r) => r.displayName), ['Nikki', 'Nikki']);
    expect(result[0].userIds, {'a', 'b'});
    expect(result[1].userIds, {'c'});
  });
}
