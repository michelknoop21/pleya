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
    await row('dad', c, token: c.accessToken, acquired: _t(0));
    await row('kid', c, token: c.accessToken, acquired: _t(5));
    // Chain: a second borrower copied the connection token via the kid.
    await row('guest', c, token: c.accessToken, acquired: _t(9));

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
    await row('dad', c, token: c.accessToken, acquired: _t(0));
    await row('kid', c, token: c.accessToken, acquired: _t(0));

    expect(await run(), 2);
    expect(await borrowedByProfile(c), {'dad': true, 'kid': true});
  });

  test('a null earliest time marks the whole group borrowed', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: c.accessToken);
    await row('kid', c, token: c.accessToken, acquired: _t(4));

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

  test('lender signed in again after lending: the borrower row with the old token is borrowed', () async {
    // Probe P2 from review 2. The kid copied T1 at minute 5; dad later signed
    // in again, which wrote T2 into the connection and into his own row. The
    // binder binds the kid with the connection token T2, so T1 is stale.
    final c = _jellyfin();
    await connections.upsert(c);
    await row('kid', c, token: 'tok-T1', acquired: _t(5));
    await row('dad', c, token: c.accessToken, acquired: _t(60));

    expect(await run(), 1);
    expect(await borrowedByProfile(c), {'dad': false, 'kid': true});
  });

  test('two separate logins of the same user: the older one loses rights until it signs in again', () async {
    // Accepted false positive on the closed side: the binder binds both with
    // the connection token, so the older row's own token is never used.
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok-phone', acquired: _t(0));
    await row('dad-tv', c, token: c.accessToken, acquired: _t(1));

    expect(await run(), 1);
    expect(await borrowedByProfile(c), {'dad': true, 'dad-tv': false});
  });

  test('no row carries the connection token: every row is borrowed', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: 'tok-a', acquired: _t(0));
    await row('kid', c, token: 'tok-b', acquired: _t(1));

    expect(await run(), 2);
    expect(await borrowedByProfile(c), {'dad': true, 'kid': true});
  });

  test('runs once: the stored flag skips a second pass', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: c.accessToken, acquired: _t(0));
    await row('kid', c, token: c.accessToken, acquired: _t(1));
    expect(await run(), 1);
    expect(storage.readBool(borrowedBackfillDoneKey), isTrue);

    // A new copy after the first pass is the borrow flow's job, not ours.
    await row('guest', c, token: c.accessToken, acquired: _t(2));
    expect(await run(), 0);
    expect(await borrowedByProfile(c), {'dad': false, 'kid': true, 'guest': false});
  });

  test('a failure halfway leaves the flag unset so the next launch retries', () async {
    final c = _jellyfin();
    await connections.upsert(c);
    await row('dad', c, token: c.accessToken, acquired: _t(0));
    await row('kid', c, token: c.accessToken, acquired: _t(1));

    await expectLater(
      backfillBorrowedJellyfinRows(
        profileConnections: _FailingMarkRegistry(db),
        connections: connections,
        storage: storage,
      ),
      throwsStateError,
    );
    expect(storage.readBool(borrowedBackfillDoneKey), isFalse);

    expect(await run(), 1);
    expect(await borrowedByProfile(c), {'dad': false, 'kid': true});
  });
}

/// Fails every `markBorrowed`, as a database error halfway through would.
class _FailingMarkRegistry extends ProfileConnectionRegistry {
  _FailingMarkRegistry(AppDatabase db) : super(db);

  @override
  Future<void> markBorrowed(String profileId, String connectionId) async => throw StateError('disk full');
}
