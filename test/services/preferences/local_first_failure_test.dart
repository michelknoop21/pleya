import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// The failure boundary is local-first.
///
/// Turning the write hook from `void` into a `Future` is what lets a transport
/// error be reported at all, and it is exactly the change that could make a
/// user's setting depend on iCloud being up. It must not. The local value is
/// written first and stays written; the cloud attempt is the part allowed to
/// fail, and it fails into the status.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => null,
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

  test('a failed SET keeps the local value and does not throw at the caller', () async {
    final coordinator = await build();
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    transport.throwOnWrite = StateError('iCloud is down');

    await settings.write(SettingsService.subtitleFontSize, 44);

    expect(settings.read(SettingsService.subtitleFontSize), 44, reason: 'the user keeps their setting');
    expect(coordinator.status.value.state, PreferenceSyncState.error);
    expect(coordinator.status.value.errorCategory, isNotNull);
  });

  test('a failed REMOVE keeps the local removal', () async {
    final coordinator = await build();
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    await settings.prefs.setString('theme_mode', 'dark');
    transport.throwOnRemove = StateError('iCloud is down');

    await coordinator.apply(const PreferenceMutation.remove('theme_mode'));
    await settings.prefs.remove('theme_mode');

    expect(settings.prefs.getString('theme_mode'), isNull, reason: 'the removal is not rolled back');
    expect(coordinator.status.value.state, PreferenceSyncState.error);
  });

  test('the write hook never rethrows, whatever the transport does', () async {
    final coordinator = await build();
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    transport.throwOnWrite = Exception('boom');

    await expectLater(settings.write(SettingsService.seekTimeSmall, 12), completes);
    expect(settings.read(SettingsService.seekTimeSmall), 12);
  });

  test('a later reconcile recovers what the failed write never delivered', () async {
    final coordinator = await build();
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    transport.throwOnWrite = StateError('iCloud is down');

    final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
    await settings.write(SettingsService.subtitleFontSize, 44);
    expect(transport.store.containsKey(cloudKey), isFalse);

    // The network comes back. Reconcile pushes from local state, so the value
    // that never made it is picked up without anyone having to queue it.
    transport.throwOnWrite = null;
    await coordinator.reconcile();

    expect(transport.store[cloudKey], contains('44'));
    expect(coordinator.status.value.state, PreferenceSyncState.success);
  });

  test('a failure on one key does not stop the next key from syncing', () async {
    final coordinator = await build();
    BaseSharedPreferencesService.onMutation = coordinator.apply;

    transport.throwOnWrite = StateError('transient');
    await settings.write(SettingsService.subtitleFontSize, 44);
    transport.throwOnWrite = null;
    await settings.write(SettingsService.seekTimeSmall, 12);

    expect(transport.store.containsKey(coordinator.cloudKeyFor('seek_time_small')!), isTrue);
    expect(settings.read(SettingsService.subtitleFontSize), 44);
  });

  test('with sync disabled a local change still lands, and nothing is sent', () async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    final coordinator = PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => null,
      enabled: () => false,
      deviceId: 'macbook',
      transport: transport,
    );
    BaseSharedPreferencesService.onMutation = coordinator.apply;

    await settings.write(SettingsService.subtitleFontSize, 44);

    expect(settings.read(SettingsService.subtitleFontSize), 44);
    expect(transport.writes, isEmpty);
  });
}
