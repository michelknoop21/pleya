import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_device_id.dart';
import 'package:pleya/services/preferences/preference_legacy_bootstrap.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_quarantine.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// Review constraint R6. The engine's own bookkeeping describes *this*
/// installation: which import has run here, what this device is called, what it
/// last edited, and which ambiguous records it has seen. Syncing any of it
/// would move one device's runtime onto another — the bootstrap marker in
/// particular would land on a second device and stop the import it still needs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  final bookkeepingKeys = <String>[
    PreferenceLegacyBootstrap.completedKey,
    PreferenceDeviceId.prefsKey,
    PreferenceQuarantine.prefsKey,
    PreferenceSyncCoordinator.revisionStoreKey,
    PreferenceSyncScope.activeProfileIdKey,
  ];

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: 'macbook',
      transport: transport,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  test('none of them may sync, by policy', () {
    for (final key in bookkeepingKeys) {
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
    }
  });

  test('none of them has a cloud key at all', () async {
    final coordinator = await build();
    for (final key in bookkeepingKeys) {
      expect(coordinator.cloudKeyFor(key), isNull, reason: key);
    }
  });

  test('a direct mutation of each one sends nothing', () async {
    final coordinator = await build();
    for (final key in bookkeepingKeys) {
      await coordinator.apply(PreferenceMutation.set(key, 'value'));
      await coordinator.apply(PreferenceMutation.remove(key));
    }

    expect(transport.writes, isEmpty);
    expect(transport.removes, isEmpty);
  });

  test('a reconcile does not push them either, however they got there', () async {
    final coordinator = await build();
    await settings.prefs.setBool(PreferenceLegacyBootstrap.completedKey, true);
    await settings.prefs.setString(PreferenceDeviceId.prefsKey, 'device-1');
    await settings.prefs.setString(PreferenceQuarantine.prefsKey, '{}');
    await settings.prefs.setString(PreferenceSyncCoordinator.revisionStoreKey, '{}');
    await settings.prefs.setString(PreferenceSyncScope.activeProfileIdKey, profile);

    await coordinator.reconcile();

    for (final key in bookkeepingKeys) {
      expect(transport.store.keys.any((k) => k.endsWith(key)), isFalse, reason: key);
    }
  });

  test('a remote record that names one of them is not applied', () async {
    final coordinator = await build();
    await settings.prefs.setBool(PreferenceLegacyBootstrap.completedKey, false);

    await coordinator.applyEntries({PreferenceLegacyBootstrap.completedKey: '{"type":"bool","value":true}'});

    expect(settings.prefs.getBool(PreferenceLegacyBootstrap.completedKey), isFalse);
  });

  test('the bootstrap marker stays local, so a second device still runs its own import', () async {
    final coordinator = await build();
    await settings.prefs.setBool(PreferenceLegacyBootstrap.completedKey, true);
    await coordinator.reconcile();

    // Whatever the store now holds, the marker is not in it.
    expect(
      transport.store.keys.where((k) => k.contains('bootstrap')),
      isEmpty,
      reason: 'a second device would read it and skip an import it has never run',
    );
  });

  test('a revision stamp never leaves the device', () async {
    final coordinator = await build();
    await settings.prefs.setString('theme_mode', 'dark');

    await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));

    expect(coordinator.localRevision('theme_mode'), isNotNull);
    expect(transport.store.keys.where((k) => k.contains('revision')), isEmpty);
  });
}
