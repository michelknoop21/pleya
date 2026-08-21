import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// A12. A value that does not fit, and a store that is full, are both things
/// the user is entitled to know about. Neither may cost them data: the local
/// preference keeps working, and nothing gets deleted from the store because
/// the replacement was too big to send.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

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

  String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('a value that does not fit', () {
    test('the local preference still works', () async {
      final coordinator = await build();
      BaseSharedPreferencesService.onMutation = coordinator.apply;
      transport.valueCap = 32;

      await settings.prefs.setString('theme_mode', 'x' * 200);
      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));

      expect(settings.prefs.getString('theme_mode'), 'x' * 200);
    });

    test('it is reported as a warning rather than swallowed', () async {
      final coordinator = await build();
      transport.valueCap = 32;

      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));

      expect(coordinator.status.value.state, PreferenceSyncState.warning);
      expect(coordinator.status.value.oversize, 1);
      expect(transport.writes, isEmpty);
    });

    test('it never turns into a removal', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      transport.store[cloudKey] = enc('string', 'dark');
      transport.valueCap = 32;

      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));

      expect(transport.removes, isEmpty);
      expect(transport.store[cloudKey], enc('string', 'dark'));
    });

    test('a reconcile holds it back from the push and from the prune alike', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      transport.store[cloudKey] = enc('string', 'dark');
      await settings.prefs.setString('theme_mode', 'x' * 200);
      transport.valueCap = 32;

      await coordinator.reconcile();

      expect(transport.store[cloudKey], enc('string', 'dark'));
      expect(transport.removes, isNot(contains(cloudKey)));
      expect(coordinator.status.value.state, PreferenceSyncState.warning);
      expect(coordinator.status.value.oversize, greaterThan(0));
    });

    test('the warning is not erased by the next value that does fit', () async {
      final coordinator = await build();
      transport.valueCap = 64;
      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));
      expect(coordinator.status.value.state, PreferenceSyncState.warning);

      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      expect(coordinator.status.value.state, PreferenceSyncState.warning);
      expect(coordinator.status.value.pushed, 1);
    });

    test('a reconcile in which everything fits clears the warning', () async {
      final coordinator = await build();
      transport.valueCap = 64;
      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));
      expect(coordinator.status.value.state, PreferenceSyncState.warning);

      await settings.prefs.setString('theme_mode', 'dark');
      transport.valueCap = 100 * 1024;
      await coordinator.reconcile();

      expect(coordinator.status.value.state, PreferenceSyncState.success);
    });
  });

  group('a store that is full', () {
    test('the quota reason from the transport becomes a quota status', () async {
      final coordinator = await build();
      coordinator.listen();

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.quotaExceeded));
      await Future<void>.value();

      expect(coordinator.status.value.state, PreferenceSyncState.quota);
      expect(coordinator.status.value.health, PreferenceSyncHealth.quota);
    });

    test('a quota stop outranks an oversize warning', () async {
      final coordinator = await build();
      coordinator.listen();
      transport.valueCap = 32;
      await coordinator.apply(PreferenceMutation.set('theme_mode', 'x' * 200));

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.quotaExceeded));
      await Future<void>.value();

      expect(coordinator.status.value.state, PreferenceSyncState.quota);
    });

    test('a quota event with sync switched off changes nothing', () async {
      settings = await SettingsService.getInstance();
      transport = FakeTransport();
      final coordinator = PreferenceSyncCoordinator(
        prefs: settings.prefs,
        activeProfileId: () => profile,
        enabled: () => false,
        deviceId: 'macbook',
        transport: transport,
      );
      coordinator.listen();

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.quotaExceeded));
      await Future<void>.value();

      expect(coordinator.status.value.state, PreferenceSyncState.disabled);
    });
  });
}
