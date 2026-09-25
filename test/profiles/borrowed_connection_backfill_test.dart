import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/profiles/borrowed_connection_backfill.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

JellyfinConnection _jellyfin({String userId = 'dad'}) => JellyfinConnection(
  id: 'jf-machine/$userId',
  baseUrl: 'https://jellyfin.local',
  serverName: 'Jellyfin',
  serverMachineId: 'jf-machine',
  userId: userId,
  userName: userId,
  accessToken: 'access-$userId',
  deviceId: 'device-1',
  isAdministrator: true,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
);

DateTime _t(int minute) => DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000 + minute * 60000);

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late StorageService storage;

  setUp(() async {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    storage = await StorageService.getInstance();
  });

  tearDown(() async => db.close());

  Future<void> row(String profileId, JellyfinConnection c, {String? token, DateTime? acquired}) =>
      profileConnections.upsert(
        ProfileConnection(
          profileId: profileId,
          connectionId: c.id,
          userToken: token,
          userIdentifier: c.userId,
          tokenAcquiredAt: acquired,
        ),
      );

  Future<Map<String, bool>> borrowedByProfile(JellyfinConnection c) async => {
    for (final pc in await profileConnections.listForConnection(c.id)) pc.profileId: pc.borrowed,
  };

  Future<int> run() =>
      backfillBorrowedJellyfinRows(profileConnections: profileConnections, connections: connections, storage: storage);

  test('the earliest row keeps owner rights, later copies of its token become borrowed', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok-dad', acquired: _t(0));
    await row('kid', c, token: 'tok-dad', acquired: _t(5));
    // Chain: a second borrower copied the connection token via the kid.
    await row('guest', c, token: 'tok-dad', acquired: _t(9));

    expect(await run(), 2);
    expect(await borrowedByProfile(c), {'dad': false, 'kid': true, 'guest': true});
  });

  test('an empty user token falls back to the connection access token', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, acquired: _t(0));
    await row('kid', c, token: c.accessToken, acquired: _t(3));

    expect(await run(), 1);
    expect(await borrowedByProfile(c), {'dad': false, 'kid': true});
  });

  test('a tie on the earliest time marks the whole group borrowed', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok', acquired: _t(0));
    await row('kid', c, token: 'tok', acquired: _t(0));

    expect(await run(), 2);
    expect(await borrowedByProfile(c), {'dad': true, 'kid': true});
  });

  test('a null earliest time marks the whole group borrowed', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok');
    await row('kid', c, token: 'tok', acquired: _t(4));

    expect(await run(), 2);
    expect(await borrowedByProfile(c), {'dad': true, 'kid': true});
  });

  test('the real owner is not stripped when only one profile holds the connection', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok', acquired: _t(0));

    expect(await run(), 0);
    expect(await borrowedByProfile(c), {'dad': false});
  });

  test('two separate logins of the same user (different tokens) stay owned', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok-phone', acquired: _t(0));
    await row('dad-tv', c, token: 'tok-tv', acquired: _t(1));

    expect(await run(), 0);
    expect(await borrowedByProfile(c), {'dad': false, 'dad-tv': false});
  });

  test('runs once: the stored flag skips a second pass', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok', acquired: _t(0));
    await row('kid', c, token: 'tok', acquired: _t(1));
    expect(await run(), 1);
    expect(storage.readBool(borrowedBackfillDoneKey), isTrue);

    // A new copy after the first pass is the borrow flow's job, not ours.
    await row('guest', c, token: 'tok', acquired: _t(2));
    expect(await run(), 0);
    expect(await borrowedByProfile(c), {'dad': false, 'kid': true, 'guest': false});
  });
}
