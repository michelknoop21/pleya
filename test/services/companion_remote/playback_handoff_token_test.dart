import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/utils/log_redaction_manager.dart';

// A-23c: the Plex token that lets the Apple TV skip the PIN of the sender's profile.

const _token = 'tok-anna';

PlaybackHandoffRequest _request({String? token}) => PlaybackHandoffRequest(
  id: 'h1',
  serverId: 'server_1',
  itemId: 'item_9',
  positionMs: 226000,
  title: 'Big Buck Bunny',
  from: 'iPhone van Anna',
  plexUserToken: token,
);

Profile _plexHome({bool protected = true, String parent = 'plex-1', String uuid = 'u-anna'}) => Profile.plexHome(
  id: 'plex-anna',
  displayName: 'Anna',
  parentConnectionId: parent,
  plexHomeUserUuid: uuid,
  plexProtected: protected,
  createdAt: DateTime(2026),
);

Profile _local({String? pinHash = 'hash'}) =>
    Profile.local(id: 'local-anna', displayName: 'Anna', pinHash: pinHash, createdAt: DateTime(2026));

ProfileConnection _row(String profileId, {String connectionId = 'plex-1', String user = 'u-anna', String? token}) =>
    ProfileConnection(profileId: profileId, connectionId: connectionId, userIdentifier: user, userToken: token);

void main() {
  group('PlaybackHandoffRequest token on the wire', () {
    test('a token goes along and comes back', () {
      final back = PlaybackHandoffRequest.fromData(_request(token: _token).toData());
      expect(back?.plexUserToken, _token);
    });

    test('without a token the key is not on the wire at all', () {
      final data = _request().toData();
      expect(data.keys, isNot(contains('plexUserToken')));
      expect(PlaybackHandoffRequest.fromData(data)?.plexUserToken, isNull);
    });

    test('a token that is not a string costs the PIN skip, not the handoff', () {
      final data = _request().toData()..['plexUserToken'] = 42;
      final back = PlaybackHandoffRequest.fromData(data);
      expect(back, isNotNull);
      expect(back!.id, 'h1');
      expect(back.plexUserToken, isNull);
    });

    test('a token far longer than a Plex token is dropped, the handoff stays', () {
      final long = 'x' * (PlaybackHandoffRequest.maxPlexUserTokenLength + 1);
      final back = PlaybackHandoffRequest.fromData(_request(token: long).toData());
      expect(back, isNotNull);
      expect(back!.plexUserToken, isNull);
      final edge = 'x' * PlaybackHandoffRequest.maxPlexUserTokenLength;
      expect(PlaybackHandoffRequest.fromData(_request(token: edge).toData())?.plexUserToken, edge);
    });

    test('withPlexUserToken keeps everything else', () {
      final withToken = _request().withPlexUserToken(_token);
      expect(withToken.toData(), {..._request().toData(), 'plexUserToken': _token});
    });
  });

  group('plexUserTokenForHandoff (phone)', () {
    test('a protected Plex Home profile sends its token for the account of the handshake', () {
      final profile = _plexHome();
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: 'plex-1',
          row: _row(profile.id, token: _token),
        ),
        _token,
      );
    });

    test('an unprotected profile sends nothing', () {
      final profile = _plexHome(protected: false);
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: 'plex-1',
          row: _row(profile.id, token: _token),
        ),
        isNull,
      );
      final open = _local(pinHash: null);
      expect(
        plexUserTokenForHandoff(
          profile: open,
          plexConnectionId: 'plex-1',
          row: _row(open.id, token: _token),
        ),
        isNull,
      );
    });

    test('no row, an empty token or no Plex account of the handshake sends nothing', () {
      final profile = _plexHome();
      expect(plexUserTokenForHandoff(profile: profile, plexConnectionId: 'plex-1', row: null), isNull);
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: 'plex-1',
          row: _row(profile.id, token: ''),
        ),
        isNull,
      );
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: null,
          row: _row(profile.id, token: _token),
        ),
        isNull,
      );
    });

    test('a row of another account or profile sends nothing', () {
      final profile = _plexHome();
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: 'plex-2',
          row: _row(profile.id, connectionId: 'plex-2', token: _token),
        ),
        isNull,
        reason: 'the handshake used another account than the profile belongs to',
      );
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: 'plex-1',
          row: _row('someone', token: _token),
        ),
        isNull,
      );
    });

    test('a protected local profile sends the token of its row for that account', () {
      final profile = _local();
      expect(
        plexUserTokenForHandoff(
          profile: profile,
          plexConnectionId: 'plex-1',
          row: _row(profile.id, token: _token),
        ),
        _token,
      );
    });
  });

  group('handoffTokenProofUuid (Apple TV)', () {
    test('a protected Plex Home profile on the account of the handshake', () {
      expect(handoffTokenProofUuid(_plexHome(), connectionId: 'plex-1', targetRows: const []), 'u-anna');
    });

    test('an unprotected profile needs no proof', () {
      expect(handoffTokenProofUuid(_plexHome(protected: false), connectionId: 'plex-1', targetRows: const []), isNull);
    });

    test('a Plex Home profile of another account takes no token', () {
      expect(
        handoffTokenProofUuid(
          _plexHome(parent: 'plex-2'),
          connectionId: 'plex-1',
          targetRows: const [],
        ),
        isNull,
      );
    });

    test('a protected local profile with its one row on that account', () {
      final local = _local();
      expect(handoffTokenProofUuid(local, connectionId: 'plex-1', targetRows: [_row(local.id)]), 'u-anna');
    });

    test('a local profile with two join rows keeps its PIN', () {
      final local = _local();
      expect(
        handoffTokenProofUuid(
          local,
          connectionId: 'plex-1',
          targetRows: [
            _row(local.id),
            _row(local.id, connectionId: 'jf-1', user: 'jf-user'),
          ],
        ),
        isNull,
      );
    });

    test('a local profile whose one row is on another account keeps its PIN', () {
      final local = _local();
      expect(
        handoffTokenProofUuid(
          local,
          connectionId: 'plex-1',
          targetRows: [_row(local.id, connectionId: 'plex-2')],
        ),
        isNull,
      );
    });
  });

  group('verifyPlexHomeTokenProof', () {
    late List<String> asked;

    Future<Map<String, dynamic>> Function(String) answer(Object uuidOrError) => (token) async {
      asked.add(token);
      if (uuidOrError is Exception) throw uuidOrError;
      return {'uuid': uuidOrError};
    };

    setUp(() => asked = []);

    test('plex.tv names the same user as the profile and the handshake: the token is the proof', () async {
      final proof = await verifyPlexHomeTokenProof(
        userInfo: answer('u-anna'),
        token: _token,
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      expect(proof, _token);
      expect(asked, [_token]);
    });

    test('a token of another user is no proof', () async {
      final proof = await verifyPlexHomeTokenProof(
        userInfo: answer('u-bram'),
        token: _token,
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      expect(proof, isNull);
    });

    test('only a proven token joins the redaction list, so forged ones cannot push real ones out', () async {
      LogRedactionManager.clearTrackedValues();
      await verifyPlexHomeTokenProof(
        userInfo: answer('u-bram'),
        token: 'forged-token-1',
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      await verifyPlexHomeTokenProof(
        userInfo: answer(Exception('401')),
        token: 'forged-token-2',
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      expect(LogRedactionManager.redact('t=forged-token-1 forged-token-2'), contains('forged-token-1'));
      expect(LogRedactionManager.redact('t=forged-token-2'), contains('forged-token-2'));
      await verifyPlexHomeTokenProof(
        userInfo: answer('u-anna'),
        token: 'real-token-anna',
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      expect(LogRedactionManager.redact('t=real-token-anna'), isNot(contains('real-token-anna')));
      LogRedactionManager.clearTrackedValues();
    });

    test('a handshake that named someone else is no proof, without asking plex.tv', () async {
      final proof = await verifyPlexHomeTokenProof(
        userInfo: answer('u-anna'),
        token: _token,
        expectedUuid: 'u-anna',
        peerUuid: 'u-bram',
      );
      expect(proof, isNull);
      expect(asked, isEmpty);
    });

    test('plex.tv refusing or unreachable is no proof', () async {
      final proof = await verifyPlexHomeTokenProof(
        userInfo: answer(Exception('401')),
        token: _token,
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      expect(proof, isNull);
    });

    test('no answer in time is no proof', () async {
      final proof = await verifyPlexHomeTokenProof(
        userInfo: (_) => Completer<Map<String, dynamic>>().future,
        token: _token,
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
        timeout: const Duration(milliseconds: 20),
      );
      expect(proof, isNull);
    });

    test('an empty token or uuid is no proof, without asking plex.tv', () async {
      for (final (token, uuid) in [(null, 'u-anna'), ('', 'u-anna'), (_token, '')]) {
        final proof = await verifyPlexHomeTokenProof(
          userInfo: answer(uuid),
          token: token,
          expectedUuid: uuid,
          peerUuid: uuid,
        );
        expect(proof, isNull);
      }
      expect(asked, isEmpty);
    });

    test('an answer without a uuid is no proof', () async {
      final proof = await verifyPlexHomeTokenProof(
        userInfo: (_) async => const {'username': 'anna'},
        token: _token,
        expectedUuid: 'u-anna',
        peerUuid: 'u-anna',
      );
      expect(proof, isNull);
    });
  });
}
