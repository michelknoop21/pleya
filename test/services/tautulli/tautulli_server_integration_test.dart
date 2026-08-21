import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

import '../../test_helpers/prefs.dart';

TautulliServerIntegration _integration({
  String machineIdentifier = 'pms-1',
  String? token = 'tok',
  TautulliConnectionState state = TautulliConnectionState.connected,
  bool? policy,
  bool conflict = false,
}) => TautulliServerIntegration(
  machineIdentifier: machineIdentifier,
  baseUrl: 'https://tautulli.example',
  authMode: TautulliAuthMode.device,
  token: token,
  connectionState: state,
  useHistoryForRecommendations: policy,
  hasUnresolvedConflict: conflict,
);

void main() {
  setUp(resetSharedPreferencesForTest);

  group('importEnabled', () {
    test('a fresh pairing with no explicit policy is on', () {
      expect(importEnabled(_integration()), isTrue);
      expect(_integration().historyPolicyEnabled, isTrue);
    });

    test('an explicit true is on', () {
      expect(importEnabled(_integration(policy: true)), isTrue);
    });

    test('an explicit false is off', () {
      expect(importEnabled(_integration(policy: false)), isFalse);
    });

    test('disconnected is off even with the policy on', () {
      expect(importEnabled(_integration(state: TautulliConnectionState.disconnected)), isFalse);
    });

    test('a missing credential is off', () {
      expect(importEnabled(_integration(token: null)), isFalse);
      expect(importEnabled(_integration(token: '')), isFalse);
    });

    test('an unresolved migration conflict is off', () {
      expect(importEnabled(_integration(conflict: true)), isFalse);
    });

    test('no integration at all is off', () {
      expect(importEnabled(null), isFalse);
    });
  });

  group('encode / decode', () {
    test('round-trips every field', () async {
      final original = _integration(policy: false, conflict: true).copyWith(
        serverName: 'Tautulli',
        version: '2.17.2',
        deviceId: 'dev-1',
        configuredByProfileId: 'profile-a',
        configuredAtMs: 111,
        policyChangedAtMs: 222,
      );
      final back = await TautulliServerIntegration.decode(await original.encode());
      expect(back.machineIdentifier, 'pms-1');
      expect(back.baseUrl, original.baseUrl);
      expect(back.authMode, TautulliAuthMode.device);
      expect(back.token, 'tok');
      expect(back.serverName, 'Tautulli');
      expect(back.version, '2.17.2');
      expect(back.deviceId, 'dev-1');
      expect(back.useHistoryForRecommendations, isFalse);
      expect(back.hasUnresolvedConflict, isTrue);
      expect(back.configuredByProfileId, 'profile-a');
      expect(back.configuredAtMs, 111);
      expect(back.policyChangedAtMs, 222);
    });

    test('the token is never stored in the clear', () async {
      final encoded = await _integration().encode();
      expect(encoded, isNot(contains('"tok"')));
      expect(jsonDecode(encoded)['token'], startsWith('enc:v1:'));
    });

    test('an absent policy key decodes to null, which reads as on', () async {
      final blob = jsonEncode({
        'machine_identifier': 'pms-1',
        'base_url': 'https://tautulli.example',
        'auth_mode': 'device',
        'token': 'plaintext-legacy',
      });
      final back = await TautulliServerIntegration.decode(blob);
      expect(back.useHistoryForRecommendations, isNull);
      expect(back.historyPolicyEnabled, isTrue);
      expect(importEnabled(back), isTrue);
    });

    test('an explicit false survives a round trip', () async {
      final back = await TautulliServerIntegration.decode(await _integration(policy: false).encode());
      expect(back.useHistoryForRecommendations, isFalse);
      expect(importEnabled(back), isFalse);
    });

    test('an unreadable credential keeps the record and the policy', () async {
      // A vault blob this device can no longer open: the record must survive,
      // because losing a credential is not the admin revoking a decision.
      final blob = jsonEncode({
        'machine_identifier': 'pms-1',
        'base_url': 'https://tautulli.example',
        'auth_mode': 'device',
        'token': 'enc:v1:{"n":"AAAA","c":"AAAA","m":"AAAA"}',
        'use_history_for_recommendations': false,
      });
      final back = await TautulliServerIntegration.decode(blob);
      expect(back.hasCredential, isFalse);
      expect(back.useHistoryForRecommendations, isFalse);
      expect(back.session, isNull);
      expect(importEnabled(back), isFalse);
    });

    test('a payload without an identifier or url is not a record at all', () async {
      await expectLater(
        TautulliServerIntegration.decode(jsonEncode({'base_url': 'x', 'auth_mode': 'device'})),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        TautulliServerIntegration.decode(jsonEncode({'machine_identifier': 'p', 'auth_mode': 'device'})),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('fromSession', () {
    TautulliSession session({String url = 'https://tautulli.example'}) =>
        TautulliSession(baseUrl: url, authMode: TautulliAuthMode.device, token: 'tok');

    test('a brand new server starts with no explicit policy', () {
      final made = TautulliServerIntegration.fromSession(session(), machineIdentifier: 'pms-1', nowMs: 5);
      expect(made.useHistoryForRecommendations, isNull);
      expect(importEnabled(made), isTrue);
      expect(made.configuredAtMs, 5);
    });

    test('re-pairing a known server keeps an explicit off', () {
      final made = TautulliServerIntegration.fromSession(
        session(),
        machineIdentifier: 'pms-1',
        existing: _integration(policy: false).copyWith(configuredAtMs: 1),
      );
      expect(made.useHistoryForRecommendations, isFalse);
      expect(made.isConnected, isTrue);
      expect(made.hasCredential, isTrue);
      expect(importEnabled(made), isFalse);
      expect(made.configuredAtMs, 1);
    });

    test('re-pairing clears an unresolved conflict', () {
      final made = TautulliServerIntegration.fromSession(
        session(),
        machineIdentifier: 'pms-1',
        existing: _integration(conflict: true),
      );
      expect(made.hasUnresolvedConflict, isFalse);
      expect(importEnabled(made), isTrue);
    });
  });

  test('describesSamePairing compares url, mode and credential', () {
    final a = _integration();
    expect(a.describesSamePairing(_integration()), isTrue);
    expect(a.describesSamePairing(_integration(token: 'other')), isFalse);
    expect(a.describesSamePairing(a.copyWith(baseUrl: 'https://elsewhere')), isFalse);
  });

  test('toString never leaks the token', () {
    expect(_integration().toString(), isNot(contains('tok')));
    expect(_integration().toString(), contains('credential: true'));
  });
}
