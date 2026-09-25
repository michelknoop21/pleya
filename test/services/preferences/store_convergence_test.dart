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

  group('I3: a profile-keyed map has one canonical text', () {
    const s1 = 'plex-home-plex.e434272903092b4e-f870c16b61268c50';
    const s2 = 'plex-home-plex.e434272903092b4e-a870c16b61268c51';
    final e1 = {'audio': 'nl', 'u': 1000};
    final e2 = {'audio': 'en', 'u': 2000};
    const key = 'pleya_profile_language_preferences';

    test('the same content in another order is not written again', () async {
      final c = await build();
      await settings.prefs.setString(key, json.encode({s1: e1, s2: e2}));
      final cloud = c.cloudKeyFor(key)!;
      // What another device of this build wrote for the same two profiles:
      // sorted, so s2 comes first.
      transport.store[cloud] = json.encode({
        'type': 'string',
        'value': json.encode({s2: e2, s1: e1}),
        't': 1000,
        'd': 'appletv',
      });

      await c.reconcile();
      await c.reconcile();

      expect(transport.writes, isNot(contains(cloud)));
    });

    test('inbound and outbound both write sorted keys, so two devices converge on the text', () async {
      final c = await build();
      await settings.prefs.setString(key, json.encode({s1: e1}));
      final cloud = c.cloudKeyFor(key)!;
      transport.store[cloud] = json.encode({
        'type': 'string',
        'value': json.encode({s2: e2}),
        't': 1000,
        'd': 'appletv',
      });

      await c.applyAllRemote();
      final local = settings.prefs.getString(key)!;
      await c.reconcile();

      expect((json.decode(local) as Map).keys, [s2, s1]);
      expect(decode(transport.store[cloud]!)['value'], local);
    });
  });
}
