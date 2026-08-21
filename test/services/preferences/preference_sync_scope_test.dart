import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';

/// v1 stripped the profile identity before a value went to iCloud, so every
/// profile shared one cloud slot per key and the last writer won. These tests
/// pin the replacement, including the case where the honest answer is "this
/// cannot sync at all".
void main() {
  const plexHomeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final plexHomeProfile = plexHomeProfileId(accountConnectionId: 'conn-1', homeUserUuid: plexHomeUuid);

  group('portability', () {
    test('a Plex Home profile is portable: Plex hands out the same UUID everywhere', () {
      final scope = PreferenceSyncScope.forProfile(plexHomeProfile);

      expect(scope.kind, PreferenceScopeKind.profile);
      expect(scope.id, plexHomeUuid);
      expect(scope.portable, isTrue);
    });

    test('a local profile is not portable: the id is generated per device', () {
      final scope = PreferenceSyncScope.forProfile('local-9a8b7c6d-1111-2222-3333-444455556666');

      expect(scope.kind, PreferenceScopeKind.profile);
      expect(scope.portable, isFalse);
      expect(scope.cloudKey('hidden_libraries'), isNull, reason: 'no portable identity, so nowhere to sync to');
    });

    test('no active profile means no profile namespace at all', () {
      expect(PreferenceSyncScope.forProfile(null), PreferenceSyncScope.none);
      expect(PreferenceSyncScope.forProfile(''), PreferenceSyncScope.none);
      expect(PreferenceSyncScope.none.cloudKey('hidden_libraries'), isNull);
    });

    test('device-local never produces a cloud key, whatever the profile is', () {
      expect(PreferenceSyncScope.deviceLocal.cloudKey('custom_download_path'), isNull);
    });
  });

  group('namespaces', () {
    test('two profiles never share a slot', () {
      final a = PreferenceSyncScope.forProfile(
        plexHomeProfileId(accountConnectionId: 'conn-1', homeUserUuid: plexHomeUuid),
      );
      final b = PreferenceSyncScope.forProfile(
        plexHomeProfileId(accountConnectionId: 'conn-1', homeUserUuid: '11111111-2222-3333-4444-555555555555'),
      );

      expect(a.cloudKey('hidden_libraries'), isNot(b.cloudKey('hidden_libraries')));
      expect(a.cloudKey('hidden_libraries'), isNotNull);
    });

    test('the same profile resolves identically on another device', () {
      final here = PreferenceSyncScope.forProfile(
        plexHomeProfileId(accountConnectionId: 'conn-mac', homeUserUuid: plexHomeUuid),
      );
      // Same Plex Home user, different local connection row: the connection id
      // is device-assigned, the home-user UUID is not.
      final there = PreferenceSyncScope.forProfile(
        plexHomeProfileId(accountConnectionId: 'conn-appletv', homeUserUuid: plexHomeUuid),
      );

      expect(here.cloudKey('library_order'), there.cloudKey('library_order'));
    });

    test('global is shared and stays outside any profile namespace', () {
      final key = PreferenceSyncScope.global.cloudKey('subtitle_font_size');

      expect(key, isNotNull);
      expect(key, isNot(contains('profile/')));
    });

    test('every cloud key lives under the namespace an old client leaves alone', () {
      final keys = [
        PreferenceSyncScope.global.cloudKey('subtitle_font_size'),
        PreferenceSyncScope.forProfile(plexHomeProfile).cloudKey('hidden_libraries'),
      ];

      for (final key in keys) {
        expect(key, isNotNull);
        expect(
          key!.startsWith('__'),
          isTrue,
          reason: 'a shipped build prunes cloud keys it cannot reproduce, except `__` ones',
        );
      }
    });
  });

  group('local storage prefix', () {
    test('a profile scope keeps the prefix StorageService already writes', () {
      expect(PreferenceSyncScope.forProfile(plexHomeProfile).localPrefix, 'user_${plexHomeUuid}_');
    });

    test('global and device-local are unprefixed', () {
      expect(PreferenceSyncScope.global.localPrefix, '');
      expect(PreferenceSyncScope.deviceLocal.localPrefix, '');
      expect(PreferenceSyncScope.none.localPrefix, '');
    });
  });
}
