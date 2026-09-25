import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// Final review I1: a profile-scoped key carries one stamp per profile. With
/// one stamp per base key, profile A's change decided profile B's conflicts on
/// the same device, and A's removal wrote a tombstone into B's namespace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profA = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e');
  final profB = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: '7a1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5f');
  late SettingsService settings;
  late FakeTransport transport;
  late String active;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => active,
      enabled: () => true,
      deviceId: 'macbook',
      transport: transport,
      isServerIdPortable: (_) => true,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });
  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  const base = 'library_sort_srv1:lib1';
  int past() => DateTime.now().toUtc().millisecondsSinceEpoch - 60 * 1000;
  Map<String, dynamic> decode(String raw) => json.decode(raw) as Map<String, dynamic>;

  test("profile A's stamp neither blocks nor reverts profile B's newer remote change", () async {
    active = profA;
    final c = await build();
    final keyA = 'user_${c.activeUserScope}_$base';
    await settings.prefs.setString(keyA, 'titleA');
    await c.apply(PreferenceMutation.set(keyA, 'titleA'));

    active = profB;
    final keyB = 'user_${c.activeUserScope}_$base';
    await settings.prefs.setString(keyB, 'staleB');
    final cloudB = c.cloudKeyFor(keyB)!;
    transport.store[cloudB] = json.encode({'type': 'string', 'value': 'newB', 't': past(), 'd': 'appletv'});
    await c.applyAllRemote();
    await c.reconcile();

    expect(settings.prefs.getString(keyB), 'newB');
    expect(decode(transport.store[cloudB]!)['value'], 'newB');
    expect(c.localRevision(base)!.deviceId, 'appletv', reason: "B's stamp is the adopted one");
  });

  test("profile A's removal writes no tombstone into profile B's namespace", () async {
    active = profA;
    final c = await build();
    final keyA = 'user_${c.activeUserScope}_$base';
    await settings.prefs.remove(keyA);
    await c.apply(PreferenceMutation.remove(keyA));

    active = profB;
    final keyB = 'user_${c.activeUserScope}_$base';
    await settings.prefs.setString(keyB, 'valueB');
    final cloudB = c.cloudKeyFor(keyB)!;
    transport.store[cloudB] = json.encode({'type': 'string', 'value': 'valueB', 't': past(), 'd': 'appletv'});
    await c.applyAllRemote();
    await c.reconcile();

    expect(settings.prefs.getString(keyB), 'valueB');
    expect(decode(transport.store[cloudB]!)['value'], 'valueB');
    expect(decode(transport.store[cloudB]!).containsKey('x'), isFalse);

    active = profA;
    expect(c.localRevision(base)!.deleted, isTrue, reason: "A's own removal is still remembered");
  });

  group('I5: profile-scoped keys travel for a real Plex Home profile', () {
    // The shapes production makes: two 16-hex uuids, or the account connection
    // fell back to this device's client identifier (a v4 uuid).
    final real = plexHomeProfileId(accountConnectionId: 'plex.a1b2c3d4e5f60718', homeUserUuid: 'e434272903092b4e');
    final fallback = plexHomeProfileId(
      accountConnectionId: 'plex.9a8b7c6d-1111-4222-8333-444455556666',
      homeUserUuid: 'e434272903092b4e',
    );

    test('the real 16-hex shape gets a cloud key under its own id, local prefix unchanged', () async {
      active = real;
      final c = await build();
      expect(c.activeUserScope, real);
      final key = 'user_${real}_hidden_libraries';
      expect(c.cloudKeyFor(key), '__pleya_pref_v2/profile/$real/hidden_libraries');
      expect(c.cloudKeyFor('user_${real}_$base'), isNotNull);
      expect(c.cloudKeyFor('user_${real}_library_order'), isNotNull);
    });

    test('a round trip lands on the same profile on the other device', () async {
      active = real;
      final c = await build();
      final key = 'user_${real}_library_order';
      await settings.prefs.setString(key, '["plex:1","plex:2"]');
      await c.apply(PreferenceMutation.set(key, '["plex:1","plex:2"]'));
      final cloud = c.cloudKeyFor(key)!;
      expect(decode(transport.store[cloud]!)['value'], '["plex:1","plex:2"]');

      // The other device: no local value, no stamp.
      await settings.prefs.remove(key);
      await c.clearRevisions();
      await c.applyEntries({cloud: transport.store[cloud]});
      expect(settings.prefs.getString(key), '["plex:1","plex:2"]');
    });

    test('the client-id fallback and a local profile stay on the device', () async {
      for (final id in [fallback, 'local-9a8b7c6d-1111-2222-3333-444455556666']) {
        active = id;
        final c = await build();
        expect(c.cloudKeyFor('user_${id}_hidden_libraries'), isNull, reason: id);
        expect(c.cloudKeyFor('user_${id}_$base'), isNull, reason: id);
      }
    });
  });
}
