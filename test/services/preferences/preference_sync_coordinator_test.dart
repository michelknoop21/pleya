import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profileA = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);
  final profileB = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: '11111111-2222-3333-4444-555555555555');

  late SettingsService settings;
  late FakeTransport transport;
  String? activeProfile;
  bool enabled = true;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => activeProfile,
      enabled: () => enabled,
      deviceId: 'macbook',
      transport: transport,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    activeProfile = profileA;
    enabled = true;
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('REMOVE is first class', () {
    test('a local removal reaches the transport', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      expect(transport.store.containsKey(cloudKey), isTrue);

      await coordinator.apply(const PreferenceMutation.remove('subtitle_font_size'));

      expect(transport.removes, contains(cloudKey));
      expect(transport.store.containsKey(cloudKey), isFalse);
    });

    test('a removal of a device-local key is not sent anywhere', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.remove('custom_download_path'));

      expect(transport.removes, isEmpty);
    });

    test('a reset removal travels, because a reset is a decision', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.remove('theme_mode', source: PreferenceSource.reset));

      expect(transport.removes, contains(coordinator.cloudKeyFor('theme_mode')));
    });
  });

  group('sources', () {
    test('a remote change never echoes back', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark', source: PreferenceSource.remote));

      expect(transport.writes, isEmpty);
      expect(transport.removes, isEmpty);
    });

    test('a read-path migration pushes nothing and stamps no user change', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark', source: PreferenceSource.migration));

      expect(transport.writes, isEmpty);
      expect(coordinator.localRevision('theme_mode'), isNull, reason: 'a migration is not the user choosing');
    });

    test('a deliberate change does stamp, with this device on it', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'dark');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));

      final revision = coordinator.localRevision('theme_mode');
      expect(revision, isNotNull);
      expect(revision!.deviceId, 'macbook');
      expect(revision.value, 'dark');
    });

    test('an import stamps and travels; it is the user asking for it', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'light');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'light', source: PreferenceSource.import));

      expect(transport.writes, contains(coordinator.cloudKeyFor('theme_mode')));
      expect(coordinator.localRevision('theme_mode'), isNotNull);
    });
  });

  group('transport failures are not swallowed', () {
    test('a failed write lands in the status instead of an unawaited future', () async {
      final coordinator = await build();
      transport.throwOnWrite = StateError('channel down');

      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));

      expect(coordinator.status.value.state, PreferenceSyncState.error);
      expect(coordinator.status.value.errorCategory, isNotNull);
    });

    test('a successful write reports success and counts', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));

      expect(coordinator.status.value.state, PreferenceSyncState.success);
      expect(coordinator.status.value.pushed, 1);
    });
  });

  group('profile isolation', () {
    test('profile A and profile B do not share a slot', () async {
      final coordinator = await build();

      activeProfile = profileA;
      final keyA = coordinator.cloudKeyFor('user_${homeUuid}_hidden_libraries');
      activeProfile = profileB;
      final keyB = coordinator.cloudKeyFor('user_11111111-2222-3333-4444-555555555555_hidden_libraries');

      // Block 1 still uses the v1 wire format, where the two collide. The
      // scoped form they will move to under A6 does not, and that is the check
      // that has to hold once the format flips.
      expect(coordinator.scopeFor('hidden_libraries').id, isNotNull);
      expect(keyA, isNotNull);
      expect(keyB, isNotNull);
      activeProfile = profileA;
      expect(
        coordinator.scopeFor('hidden_libraries').cloudKey('hidden_libraries'),
        isNot(
          PreferenceSyncCoordinator(
            prefs: settings.prefs,
            activeProfileId: () => profileB,
            enabled: () => true,
            deviceId: 'macbook',
          ).scopeFor('hidden_libraries').cloudKey('hidden_libraries'),
        ),
      );
    });

    test('another profile\'s key is not touched at all', () async {
      final coordinator = await build();
      activeProfile = profileA;

      expect(coordinator.baseKeyOf('user_someone-else_hidden_libraries'), isNull);
      expect(coordinator.cloudKeyFor('user_someone-else_hidden_libraries'), isNull);
    });

    test('a profile-scoped remote value is dropped when no profile is active', () async {
      final coordinator = await build();
      activeProfile = null;
      transport.store['hidden_libraries'] = enc('string', '["lib1"]');

      await coordinator.applyRemoteKeys(['hidden_libraries']);

      expect(settings.prefs.getString('hidden_libraries'), isNull);
    });

    test('a local profile has no portable identity, so its keys stay home', () async {
      final coordinator = await build();
      activeProfile = 'local-9a8b7c6d-1111-2222-3333-444455556666';

      expect(coordinator.cloudKeyFor('user_local-9a8b7c6d-1111-2222-3333-444455556666_hidden_libraries'), isNull);
    });
  });

  group('reconcile', () {
    test('a failed read deletes nothing', () async {
      final coordinator = await build();
      transport.store[coordinator.cloudKeyFor('theme_mode')!] = enc('string', 'dark');
      transport.failReadAll = true;

      await coordinator.reconcile();

      expect(transport.removes, isEmpty);
    });

    test('a failed read during a remote event does not wipe local values', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.failReadAll = true;

      await coordinator.applyRemoteKeys([coordinator.cloudKeyFor('subtitle_font_size')!]);

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('running twice changes nothing', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);

      await coordinator.reconcile();
      final first = Map<String, String>.from(transport.store);
      await coordinator.reconcile();

      expect(transport.store, first);
    });

    test('a key that is present locally but no longer eligible is left in the store, not deleted', () async {
      final coordinator = await build();
      // The state after tightening the policy: the cloud still holds a value
      // this device now classifies as device-local. Deleting it would take it
      // away from an older client that still syncs it, and it would turn any
      // forgotten registration into data loss on every other device.
      transport.store['volume'] = enc('double', 50.0);
      await settings.prefs.setDouble('volume', 80.0);

      await coordinator.reconcile();

      expect(transport.removes, isEmpty);
      expect(transport.store['volume'], enc('double', 50.0), reason: 'frozen v1: left alone, not deleted');
    });

    test('a key that is genuinely gone locally is still pruned', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      transport.store[cloudKey] = enc('string', 'dark');

      await coordinator.reconcile();

      expect(transport.removes, contains(cloudKey), reason: 'absent locally means removed');
    });

    test('a key the registry does not allow is neither pushed nor left behind locally', () async {
      final coordinator = await build();
      await settings.prefs.setString('companion_remote_last_host_address', '192.168.1.20');

      await coordinator.reconcile();

      expect(transport.store.containsKey('companion_remote_last_host_address'), isFalse);
      expect(settings.prefs.getString('companion_remote_last_host_address'), '192.168.1.20');
    });
  });

  group('oversize values', () {
    test('an oversized value is skipped and reported, not silently dropped', () async {
      final coordinator = await build();
      transport.valueCap = 32;

      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));

      expect(transport.writes, isEmpty);
      expect(coordinator.status.value.state, PreferenceSyncState.warning);
      expect(coordinator.status.value.oversize, 1);
    });

    test('an oversized value is not deleted from the store by the next reconcile', () async {
      final coordinator = await build();
      // A smaller version of the value is already in the cloud.
      transport.store[coordinator.cloudKeyFor('theme_mode')!] = enc('string', 'dark');
      await settings.prefs.setString('theme_mode', 'x' * 200);
      transport.valueCap = 32;

      await coordinator.reconcile();

      expect(
        transport.store.containsKey(coordinator.cloudKeyFor('theme_mode')!),
        isTrue,
        reason: 'growing past the cap must not delete what is already there',
      );
      expect(coordinator.status.value.state, PreferenceSyncState.warning);
    });
  });

  group('format version', () {
    test('the version marker can be read back, not only written', () async {
      final coordinator = await build();
      await coordinator.reconcile();

      expect(await coordinator.readFormatVersion(), PreferenceSyncCoordinator.v2FormatVersion);
    });

    test('a failed read reports unknown rather than guessing', () async {
      final coordinator = await build();
      transport.failReadAll = true;

      expect(await coordinator.readFormatVersion(), isNull);
    });
  });

  test('after the cutover every write is a v2 record', () async {
    final coordinator = await build();
    await settings.prefs.setInt('subtitle_font_size', 44);
    await settings.prefs.setString('user_${homeUuid}_hidden_libraries', '["lib1"]');

    await coordinator.reconcile();
    await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));

    expect(PreferenceSyncCoordinator.v2CloudFormatEnabled, isTrue, reason: 'the cutover has happened');
    expect(
      transport.writes.every((k) => k.startsWith('__pleya_pref_v2/')),
      isTrue,
      reason: 'v2 is the only writable truth',
    );
  });
}
