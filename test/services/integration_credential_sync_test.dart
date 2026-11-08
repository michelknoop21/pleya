import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/integration_credential_changes.dart';
import 'package:pleya/services/integration_credential_codec.dart';
import 'package:pleya/services/integration_credential_sync_service.dart';
import 'package:pleya/services/integration_credential_transport.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_account_store.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/prefs.dart';

const _profile = 'plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e';
const _key = 'user_${_profile}_seerr_session';
const _otherKey = 'user_plex-home-plex.a1b2c3d4e5f60718-1234567890abcdef_seerr_session';

SeerrSession _session(String token) =>
    SeerrSession(baseUrl: 'https://requests.test', authMode: SeerrAuthMode.apiKey, apiKey: token);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;

  Future<_Device> device(String id) async {
    // Each cache is a different simulated installation. All persistence is
    // mocked; no app container, Keychain, iCloud account or server is touched.
    resetSharedPreferencesForTest();
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString('credential_vault_key_v1', base64Encode(List.filled(32, 7)));
    final result = _Device(prefs, cloud, id);
    await result.sync.initialize();
    return result;
  }

  setUp(() {
    cloud = _Cloud();
    IntegrationCredentialChanges.onLocalChange = null;
    IntegrationCredentialChanges.mayWrite = null;
  });
  tearDown(() {
    IntegrationCredentialChanges.onLocalChange = null;
    IntegrationCredentialChanges.mayWrite = null;
  });

  test('connection crosses devices and is re-encrypted locally, never copied as a vault blob', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('private-api-key').encode());
    await phone.connect();
    final tv = await device('tv');
    await tv.connect();

    final local = tv.prefs.getString(_key)!;
    expect((await SeerrSession.decode(local)).apiKey, 'private-api-key');
    expect(local, isNot(phone.prefs.getString(_key)), reason: 'receiver generates its own encrypted envelope');
    expect(local, isNot(contains('private-api-key')));
    expect(cloud.payload, isNot(contains('credential_vault_key_v1')));
    expect(
      cloud.payload,
      isNot(contains('enc:v1:')),
      reason: 'device-local ciphertext cannot decrypt on another device',
    );
  });

  test('Tautulli connection and policy migrate to another device without changing server identity', () async {
    final phone = await device('phone');
    const record = TautulliServerIntegration(
      machineIdentifier: 'plex-server',
      baseUrl: 'https://stats.test',
      authMode: TautulliAuthMode.apiKey,
      token: 'tautulli-secret',
      useHistoryForRecommendations: false,
    );
    await phone.set('tautulli_integration_plex-server', await record.encode());
    await phone.connect();
    final tv = await device('tv');
    await tv.connect();

    final received = await TautulliServerIntegration.decode(tv.prefs.getString('tautulli_integration_plex-server')!);
    expect(received.token, 'tautulli-secret');
    expect(received.machineIdentifier, 'plex-server');
    expect(received.useHistoryForRecommendations, isFalse);
  });

  test('unbound, device-local and unrelated credentials never enter the cloud snapshot', () async {
    final phone = await device('phone');
    for (final key in [
      'seerr_session',
      'user_seerr_session',
      'user_local-random_seerr_session',
      'user_somebody_tautulli_session',
      'plex_token',
    ]) {
      await phone.prefs.setString(key, 'must-stay-local');
    }
    await phone.set(_key, await _session('allowed').encode());
    await phone.connect();

    expect(cloud.payload, isNot(contains('must-stay-local')));
    expect((jsonDecode(cloud.payload!)['entries'] as Map).keys, [_key]);
  });

  test('different portable profiles retain separate request credentials', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('one').encode());
    await phone.set(_otherKey, await _session('two').encode());
    await phone.connect();
    final tv = await device('tv');
    await tv.connect();

    expect((await SeerrSession.decode(tv.prefs.getString(_key)!)).apiKey, 'one');
    expect((await SeerrSession.decode(tv.prefs.getString(_otherKey)!)).apiKey, 'two');
  });

  test('legacy installation state loses to an existing cloud choice instead of becoming a fresh edit', () async {
    final first = await device('first');
    await first.prefs.setString(_key, await _session('cloud-choice').encode());
    await first.connect(); // bootstrap t=0
    final second = await device('second');
    await second.prefs.setString(_key, await _session('older-local-choice').encode());
    await second.connect();

    expect((await SeerrSession.decode(second.prefs.getString(_key)!)).apiKey, 'cloud-choice');
    expect(cloud.entry(_key)['t'], 0);
  });

  test('offline disconnect is a durable tombstone and cannot be resurrected by an idle device', () async {
    final first = await device('first');
    await first.set(_key, await _session('credential').encode());
    await first.connect();
    final second = await device('second');
    await second.connect();
    second.enabled = false;
    second.time += 1000;
    await second.set(_key, null);
    // A restart keeps the outbox, including the removal.
    final restarted = _Device(second.prefs, cloud, 'second')..time = second.time;
    await restarted.sync.initialize();
    await restarted.connect();
    await first.sync.sync();

    expect(cloud.entry(_key)['x'], isTrue);
    expect(first.prefs.getString(_key), isNull);
    expect(second.prefs.getString(_key), isNull);
  });

  test('a failed read preserves local credentials and writes nothing', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('safe-local').encode());
    cloud.failRead = true;
    await phone.connect();

    expect(phone.sync.status.value, IntegrationCredentialSyncStatus.error);
    expect((await SeerrSession.decode(phone.prefs.getString(_key)!)).apiKey, 'safe-local');
    expect(cloud.writes, 0);
  });

  test('a failed upload retries the durable local revision on the next pass', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('pending').encode());
    cloud.failWrite = true;
    await phone.connect();
    expect(phone.sync.status.value, IntegrationCredentialSyncStatus.error);
    cloud.failWrite = false;
    await phone.sync.sync();

    expect(cloud.entry(_key)['value']['api_key'], 'pending');
    expect(phone.sync.status.value, IntegrationCredentialSyncStatus.idle);
  });

  test('CAS conflict re-reads and preserves the other device update', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('mine').encode());
    cloud.competingEntry = {
      't': 99,
      'd': 'other',
      'x': false,
      'value': {'base_url': 'https://other.test', 'auth_mode': 'apiKey', 'api_key': 'theirs'},
    };
    await phone.connect();

    expect(cloud.entry(_key)['value']['api_key'], 'mine');
    expect(cloud.entry(_otherKey)['value']['api_key'], 'theirs');
  });

  test('a local edit during a cloud read remains the winning edit', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('before').encode());
    cloud.readStarted = Completer<void>();
    cloud.releaseRead = Completer<void>();
    phone.enabled = true;
    final running = phone.sync.sync();
    await cloud.readStarted!.future;
    await IntegrationCredentialChanges.exclusively(() async {
      await phone.prefs.setString(_key, await _session('during').encode());
      await phone.sync.localChanged(_key, IntegrationCredentialChangeSource.edit);
    });
    cloud.releaseRead!.complete();
    await running;

    expect(cloud.entry(_key)['value']['api_key'], 'during');
    expect((await SeerrSession.decode(phone.prefs.getString(_key)!)).apiKey, 'during');
  });

  test('iCloud switch never seeds the other account with existing credentials', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('account-A-only').encode());
    await phone.connect();
    final writes = cloud.writes;
    cloud.account = 'account-B';
    cloud.payload = null;
    cloud.version++;
    await phone.sync.sync();

    expect(cloud.writes, writes);
    expect(cloud.payload, isNull);
    expect(phone.sync.status.value, IntegrationCredentialSyncStatus.accountChanged);
  });

  test('disabled sync leaves credentials local and performs no cloud access', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('offline').encode());
    await phone.sync.sync();

    expect(cloud.reads, 0);
    expect(cloud.writes, 0);
  });

  test('ordinary Seerr auth refresh cannot overrule another device disconnect', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('shared-key').encode());
    await phone.connect();
    final tv = await device('tv');
    await tv.connect();
    final provider = SeerrProvider(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'id': 7, 'permissions': 2, 'displayName': 'viewer'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(provider.dispose);
    await provider.onActiveProfileChanged(_profile);
    phone.time += 1000;
    await phone.set(_key, null);
    tv.time += 5000; // A refresh would appear newer if incorrectly stamped as an edit.
    final refreshed = Completer<void>();
    IntegrationCredentialChanges.mayWrite = tv.sync.mayWrite;
    IntegrationCredentialChanges.onLocalChange = (key, source) async {
      await tv.sync.localChanged(key, source);
      if (source == IntegrationCredentialChangeSource.refresh && !refreshed.isCompleted) refreshed.complete();
    };
    await provider.client!.getMe();
    await refreshed.future;
    await tv.sync.sync();

    expect(cloud.entry(_key)['x'], isTrue);
    expect(tv.prefs.getString(_key), isNull);
  });

  test('a stale refresh cannot replace a newly configured Seerr credential', () async {
    final phone = await device('phone');
    await phone.set(_key, await _session('new-key').encode());
    await SeerrAccountStore.instance.save(_profile, _session('old-key'), refresh: true);

    expect((await SeerrSession.decode(phone.prefs.getString(_key)!)).apiKey, 'new-key');
  });

  test('Tautulli policy edit cannot reconnect an instance disconnected on another device', () async {
    final phone = await device('phone');
    const key = 'tautulli_integration_plex-server';
    const record = TautulliServerIntegration(
      machineIdentifier: 'plex-server',
      baseUrl: 'https://stats.test',
      authMode: TautulliAuthMode.apiKey,
      token: 'secret',
      useHistoryForRecommendations: true,
      policyChangedAtMs: 1000,
    );
    await phone.set(key, await record.encode());
    await phone.connect();
    final tv = await device('tv');
    await tv.connect();
    phone.time += 1000;
    await phone.set(
      key,
      await record.copyWith(clearToken: true, connectionState: TautulliConnectionState.disconnected).encode(),
    );
    tv.time += 5000;
    IntegrationCredentialChanges.onLocalChange = tv.sync.localChanged;
    IntegrationCredentialChanges.mayWrite = tv.sync.mayWrite;
    await TautulliIntegrationStore.instance.save(
      record.copyWith(useHistoryForRecommendations: false, policyChangedAtMs: 2000),
      policyOnly: true,
    );
    await tv.sync.sync();

    final local = await TautulliServerIntegration.decode(tv.prefs.getString(key)!);
    expect(local.isConnected, isFalse);
    expect(local.token, isNull);
    expect(local.useHistoryForRecommendations, isFalse);
    expect(cloud.entry(key)['value']['connection_state'], 'disconnected');
    expect(cloud.entry(key)['value']['use_history_for_recommendations'], isFalse);
  });

  test('Tautulli policy syncs even when the credential configuration stamp is unchanged', () async {
    final phone = await device('phone');
    const key = 'tautulli_integration_plex-server';
    const record = TautulliServerIntegration(
      machineIdentifier: 'plex-server',
      baseUrl: 'https://stats.test',
      authMode: TautulliAuthMode.apiKey,
      token: 'secret',
      useHistoryForRecommendations: true,
      policyChangedAtMs: 1000,
    );
    await phone.set(key, await record.encode());
    await phone.connect();
    final configurationTime = cloud.entry(key)['t'];
    final tv = await device('tv');
    await tv.connect();
    IntegrationCredentialChanges.onLocalChange = tv.sync.localChanged;
    IntegrationCredentialChanges.mayWrite = tv.sync.mayWrite;
    await TautulliIntegrationStore.instance.save(
      record.copyWith(useHistoryForRecommendations: false, policyChangedAtMs: 2000),
      policyOnly: true,
    );
    await tv.sync.sync();
    await phone.sync.sync();

    expect(cloud.entry(key)['t'], configurationTime);
    expect((await TautulliServerIntegration.decode(phone.prefs.getString(key)!)).useHistoryForRecommendations, isFalse);
  });

  test('Tautulli policy update changes only policy on the latest local binding', () async {
    final phone = await device('phone');
    const key = 'tautulli_integration_plex-server';
    const old = TautulliServerIntegration(
      machineIdentifier: 'plex-server',
      baseUrl: 'https://stats.test',
      authMode: TautulliAuthMode.apiKey,
      token: 'old',
    );
    await phone.set(key, await old.copyWith(token: 'new-credential').encode());
    await TautulliIntegrationStore.instance.save(
      old.copyWith(useHistoryForRecommendations: false, policyChangedAtMs: 2000),
      policyOnly: true,
    );

    final current = await TautulliServerIntegration.decode(phone.prefs.getString(key)!);
    expect(current.token, 'new-credential');
    expect(current.useHistoryForRecommendations, isFalse);
    await phone.set(key, null);
    await TautulliIntegrationStore.instance.save(old, policyOnly: true);
    expect(phone.prefs.getString(key), isNull);
  });

  test('simultaneous Tautulli policy choices converge to off at the same policy time', () async {
    final phone = await device('phone');
    const key = 'tautulli_integration_plex-server';
    const record = TautulliServerIntegration(
      machineIdentifier: 'plex-server',
      baseUrl: 'https://stats.test',
      authMode: TautulliAuthMode.apiKey,
      token: 'secret',
      useHistoryForRecommendations: true,
      policyChangedAtMs: 1000,
    );
    await phone.set(key, await record.encode());
    await phone.connect();
    final tv = await device('tv');
    await tv.connect();
    phone.enabled = false;
    tv.enabled = false;
    await phone.set(
      key,
      await record.copyWith(policyChangedAtMs: 2000).encode(),
      source: IntegrationCredentialChangeSource.refresh,
    );
    await tv.set(
      key,
      await record.copyWith(useHistoryForRecommendations: false, policyChangedAtMs: 2000).encode(),
      source: IntegrationCredentialChangeSource.refresh,
    );
    await tv.connect();
    await phone.connect();

    expect(cloud.entry(key)['value']['use_history_for_recommendations'], isFalse);
    expect((await TautulliServerIntegration.decode(phone.prefs.getString(key)!)).useHistoryForRecommendations, isFalse);
  });

  for (final removed in [false, true]) {
    test('delayed legacy migration cannot replace the cloud binding (removed=$removed)', () async {
      final phone = await device('phone');
      const key = 'tautulli_integration_plex-server';
      const connection = TautulliServerIntegration(
        machineIdentifier: 'plex-server',
        baseUrl: 'https://stats.test',
        authMode: TautulliAuthMode.apiKey,
        token: 'current-cloud-token',
      );
      await phone.set(key, await connection.encode());
      await phone.connect();
      final tv = await device('tv');
      await tv.connect();
      if (removed) {
        phone.time += 1000;
        await phone.set(key, null);
        await tv.sync.sync();
      }
      final current = tv.prefs.getString(key);
      IntegrationCredentialChanges.onLocalChange = tv.sync.localChanged;
      IntegrationCredentialChanges.mayWrite = tv.sync.mayWrite;
      // Migration observed no server-scoped record before the remote import.
      await IntegrationCredentialChanges.write(
        key,
        await connection.copyWith(token: 'obsolete-legacy-token').encode(),
        source: IntegrationCredentialChangeSource.migration,
        expected: {key: null},
      );

      expect(tv.prefs.getString(key), current);
      expect(cloud.entry(key)['x'], removed);
    });
  }

  test('remote server mismatch fails closed and preserves the local connection', () async {
    final phone = await device('phone');
    const key = 'tautulli_integration_plex-server';
    const local = TautulliServerIntegration(
      machineIdentifier: 'plex-server',
      baseUrl: 'https://stats.test',
      authMode: TautulliAuthMode.apiKey,
      token: 'local',
    );
    await phone.prefs.setString(key, await local.encode());
    cloud.payload = jsonEncode({
      'v': 1,
      'entries': {
        key: {
          't': 100,
          'd': 'remote',
          'x': false,
          'value': {
            'machine_identifier': 'another-server',
            'base_url': 'https://wrong.test',
            'auth_mode': 'apiKey',
            'token': 'wrong',
          },
        },
      },
    });
    await phone.connect();

    expect(phone.sync.status.value, IntegrationCredentialSyncStatus.error);
    expect((await TautulliServerIntegration.decode(phone.prefs.getString(key)!)).token, 'local');
    expect(cloud.writes, 0);
  });

  test('codec refuses an unreadable local vault blob instead of publishing an empty credential', () async {
    await device('phone');
    final raw = jsonEncode({'base_url': 'https://requests.test', 'auth_mode': 'apiKey', 'api_key': 'enc:v1:broken'});
    await expectLater(IntegrationCredentialCodec.toCloud(_key, raw), throwsA(anything));
  });

  for (final localEdit in [false, true]) {
    test('interrupted import keeps its original revision and respects a newer local edit ($localEdit)', () async {
      final phone = await device('phone');
      final before = await _session('before-import').encode();
      final desired = await _session('imported').encode();
      await phone.prefs.setString(_key, localEdit ? await _session('new-local-edit').encode() : before);
      await phone.prefs.setString(
        IntegrationCredentialSyncService.metadataKey,
        jsonEncode({
          'v': 1,
          'account': 'account-A',
          'entries': {},
          'pending': {
            _key: {
              't': 100,
              'd': 'remote',
              'x': false,
              'raw': desired,
              'before': sha256.convert(utf8.encode(before)).toString(),
            },
          },
        }),
      );
      cloud.payload = jsonEncode({
        'v': 1,
        'entries': {
          _key: {
            't': 200,
            'd': 'other-device',
            'x': false,
            'value': {'base_url': 'https://requests.test', 'auth_mode': 'apiKey', 'api_key': 'newer-cloud'},
          },
        },
      });
      final restarted = _Device(phone.prefs, cloud, 'phone');
      await restarted.sync.initialize();
      await restarted.connect();

      final expected = localEdit ? 'new-local-edit' : 'newer-cloud';
      expect((await SeerrSession.decode(phone.prefs.getString(_key)!)).apiKey, expected);
      expect(cloud.entry(_key)['value']['api_key'], expected);
    });
  }
}

class _Device {
  _Device(this.prefs, _Cloud cloud, String id) {
    sync = IntegrationCredentialSyncService(
      prefs: prefs,
      transport: cloud,
      deviceId: id,
      enabled: () => enabled,
      now: () => DateTime.fromMillisecondsSinceEpoch(time),
    );
  }
  final SharedPreferencesWithCache prefs;
  late final IntegrationCredentialSyncService sync;
  bool enabled = false;
  int time = 1800000000000;

  Future<void> set(
    String key,
    String? raw, {
    IntegrationCredentialChangeSource source = IntegrationCredentialChangeSource.edit,
  }) async {
    await IntegrationCredentialChanges.exclusively(() async {
      if (raw == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, raw);
      }
      await sync.localChanged(key, source);
    });
    await sync.sync();
  }

  Future<void> connect() async {
    enabled = true;
    await sync.sync();
  }
}

class _Cloud implements IntegrationCredentialTransport {
  String account = 'account-A';
  String? payload;
  int version = 0;
  int reads = 0;
  int writes = 0;
  bool failRead = false;
  bool failWrite = false;
  Map<String, dynamic>? competingEntry;
  Completer<void>? readStarted;
  Completer<void>? releaseRead;

  Map<String, dynamic> entry(String key) => Map<String, dynamic>.from(jsonDecode(payload!)['entries'][key] as Map);

  @override
  Future<IntegrationCredentialSnapshot> read() async {
    reads++;
    if (failRead) throw PlatformException(code: 'OFFLINE');
    final snapshot = IntegrationCredentialSnapshot(
      account: account,
      payload: payload,
      tag: payload == null ? null : '$version',
    );
    if (readStarted != null && !readStarted!.isCompleted) {
      readStarted!.complete();
      await releaseRead!.future;
    }
    return snapshot;
  }

  @override
  Future<void> write(IntegrationCredentialSnapshot expected, String value) async {
    if (failWrite) throw PlatformException(code: 'OFFLINE');
    if (competingEntry != null) {
      payload = jsonEncode({
        'v': 1,
        'entries': {_otherKey: competingEntry},
      });
      competingEntry = null;
      version++;
    }
    if (expected.account != account) throw PlatformException(code: 'CREDENTIAL_ACCOUNT_CHANGED');
    if (expected.tag != (payload == null ? null : '$version')) throw PlatformException(code: 'CREDENTIAL_CONFLICT');
    payload = value;
    version++;
    writes++;
  }
}
