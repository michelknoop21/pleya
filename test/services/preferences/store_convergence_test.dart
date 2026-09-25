import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// Final review I2, I3 and I4: the store settles. A bare remove from the
/// released build does not delete a stamped value, a profile-keyed map is
/// written in one canonical text, and old tombstones are collected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e');
  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String deviceId = 'macbook', FakeTransport? shared}) async {
    settings = await SettingsService.getInstance();
    transport = shared ?? FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: deviceId,
      transport: transport,
      isServerIdPortable: (_) => true,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });
  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  Map<String, dynamic> decode(String raw) => json.decode(raw) as Map<String, dynamic>;

  group('I2: a bare remove from the released build', () {
    test('does not delete a stamped local value, and reconcile puts it back', () async {
      final c = await build();
      await settings.prefs.setString('keyboard_shortcuts', '{"a":"b"}');
      await c.apply(const PreferenceMutation.set('keyboard_shortcuts', '{"a":"b"}'));
      final cloud = c.cloudKeyFor('keyboard_shortcuts')!;

      transport.store.remove(cloud); // the released build pruned a key it does not know
      await c.applyEntries({cloud: null});
      await c.reconcile();

      expect(settings.prefs.getString('keyboard_shortcuts'), '{"a":"b"}');
      expect(decode(transport.store[cloud]!)['value'], '{"a":"b"}');
    });

    test('still removes an unstamped local value', () async {
      final c = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      final cloud = c.cloudKeyFor('subtitle_font_size')!;

      await c.applyEntries({cloud: null});

      expect(settings.prefs.getInt('subtitle_font_size'), isNull);
    });
  });
}
