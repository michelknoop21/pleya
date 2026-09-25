import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/profiles/pleya_server_credentials.dart';
import 'package:pleya/profiles/profile.dart';

/// PS-9, architecture 4.1: a Pleya Server profile acts with its own account's
/// connection, or with none.
///
/// The failure this guards against is not a crash. It is a resolution that
/// quietly succeeds with the wrong identity, which on a backend with roles and
/// per-library permissions means one household member acting as another. Every
/// test below therefore checks the *miss* as carefully as the hit: "no answer"
/// is the correct answer, and a fallback that produced something would pass a
/// naive test just as well.
void main() {
  PleyaServerConnection connection({required String id, String userName = 'sanne'}) => PleyaServerConnection(
    id: id,
    baseUrl: 'http://nas.lan:8832',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: userName,
    refreshToken: 'refresh-$id',
    createdAt: DateTime(2026, 9, 3),
  );

  Profile pleyaProfile({String? connectionId = 'pleyaServer.sanne'}) => Profile.pleyaServer(
    id: 'pleyaServer-1',
    displayName: 'Sanne',
    pleyaConnectionId: connectionId,
    pleyaUsername: 'sanne',
    createdAt: DateTime(2026, 9, 3),
  );

  const resolver = PleyaServerCredentialResolver();

  group('PleyaServerCredentialResolver', () {
    test('a profile acts with the connection it names', () {
      final own = connection(id: 'pleyaServer.sanne');
      final resolved = resolver.resolve(pleyaProfile(), own);
      expect(resolved.isHit, isTrue);
      expect(resolved.connection, same(own));
      expect(resolved.miss, isNull);
    });

    test("another account's connection on the same server is refused", () {
      // Both connections point at srv-1 and both work. MultiServerManager keys
      // its clients on serverId, so registering this one under Sanne's profile
      // would not fail: she would simply browse as Michel.
      final michel = connection(id: 'pleyaServer.michel', userName: 'michel');
      final resolved = resolver.resolve(pleyaProfile(), michel);
      expect(resolved.isHit, isFalse);
      expect(resolved.connection, isNull);
      expect(resolved.miss, PleyaServerCredentialMiss.otherAccount);
    });

    test('a profile without a connection id gets nothing, not the one offered', () {
      final resolved = resolver.resolve(pleyaProfile(connectionId: null), connection(id: 'pleyaServer.sanne'));
      expect(resolved.isHit, isFalse);
      expect(resolved.miss, PleyaServerCredentialMiss.noConnection);
    });

    test('a profile of another kind is passed through unchanged', () {
      // Every sign-in before PS-9 produced a local profile with the connection
      // on it, and that shape keeps working: there is one identity in play, so
      // there is nothing to confuse it with.
      final conn = connection(id: 'pleyaServer.sanne');
      for (final profile in [
        Profile.local(id: 'local-1', displayName: 'Owner', createdAt: DateTime(2026, 9, 3)),
        Profile.plexHome(id: 'plex-1', displayName: 'Sarah', createdAt: DateTime(2026, 9, 3)),
        null,
      ]) {
        expect(resolver.resolve(profile, conn).isHit, isTrue);
      }
    });
  });

  group('PleyaServerProfile', () {
    test('carries its connection and username, and no Plex fields', () {
      final profile = pleyaProfile();
      expect(profile.kind, ProfileKind.pleyaServer);
      expect(profile.isPleyaServer, isTrue);
      expect(profile.isLocal, isFalse);
      expect(profile.isPlexHome, isFalse);
      expect(profile.pleyaConnectionId, 'pleyaServer.sanne');
      expect(profile.pleyaUsername, 'sanne');
      expect(profile.parentConnectionId, isNull);
      expect(profile.plexHomeUserUuid, isNull);
      // The server owns the password; a four-digit code in front of it would
      // suggest a protection the account already provides better.
      expect(profile.isPinProtected, isFalse);
    });

    test('round-trips through a stored row', () {
      final profile = pleyaProfile();
      final restored = Profile.fromRow(
        id: profile.id,
        kind: ProfileKind.pleyaServer.id,
        displayName: profile.displayName,
        avatarThumbUrl: null,
        json: profile.toConfigJson(),
        sortOrder: 0,
        createdAt: profile.createdAt,
        lastUsedAt: null,
      );
      expect(restored, isA<PleyaServerProfile>());
      expect(restored.pleyaConnectionId, profile.pleyaConnectionId);
      expect(restored.pleyaUsername, profile.pleyaUsername);
    });

    test('the kind id is stable', () {
      expect(ProfileKind.pleyaServer.id, 'pleya_server');
      expect(ProfileKind.fromId('pleya_server'), ProfileKind.pleyaServer);
    });
  });
}
