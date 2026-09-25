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

  group('I4: tombstones are collected after 180 days', () {
    int ago(Duration d) => DateTime.now().toUtc().millisecondsSinceEpoch - d.inMilliseconds;
    String tombstone(int at, String device) => json.encode({'x': true, 't': at, 'd': device});

    test('an expired tombstone leaves the store, and its matching local stamp goes', () async {
      final c = await build();
      final cloud = c.cloudKeyFor('subtitle_font_size')!;
      // A removal from 200 days ago, adopted here back then.
      final old = ago(const Duration(days: 200));
      await c.applyEntries({cloud: tombstone(old, 'appletv')});
      expect(c.localRevision('subtitle_font_size')!.updatedAt, old);
      transport.store[cloud] = tombstone(old, 'appletv');

      await c.reconcile();

      expect(transport.store.containsKey(cloud), isFalse);
      expect(transport.removes, [cloud]);
      expect(c.localRevision('subtitle_font_size'), isNull);
    });

    test('a young tombstone, another profile\'s, and a newer local stamp are left alone', () async {
      final c = await build();
      final old = ago(const Duration(days: 200));
      final young = c.cloudKeyFor('subtitle_font_size')!;
      transport.store[young] = tombstone(ago(const Duration(days: 10)), 'appletv');
      const otherProfile = '__pleya_pref_v2/profile/someone-else/hidden_libraries';
      transport.store[otherProfile] = tombstone(old, 'appletv');
      // This device removed theme_mode later than the store's expired
      // tombstone says; the store record goes, the local stamp stays.
      await settings.prefs.remove('theme_mode');
      await c.apply(const PreferenceMutation.remove('theme_mode'));
      final mine = c.cloudKeyFor('theme_mode')!;
      transport.store[mine] = tombstone(old, 'appletv');

      await c.reconcile();

      expect(transport.store.containsKey(young), isTrue);
      expect(transport.store.containsKey(otherProfile), isTrue);
      expect(transport.store.containsKey(mine), isFalse);
      expect(c.localRevision('theme_mode')!.deleted, isTrue);
    });

    test('a key this pass wrote a live value over is not collected', () async {
      final c = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await c.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final cloud = c.cloudKeyFor('subtitle_font_size')!;
      transport.store[cloud] = tombstone(ago(const Duration(days: 200)), 'appletv');

      await c.reconcile();

      expect(decode(transport.store[cloud]!)['value'], 44);
    });

    test('the other device takes the collection as a no-op', () async {
      final c = await build(deviceId: 'appletv');
      await settings.prefs.remove('subtitle_font_size');
      await c.apply(const PreferenceMutation.remove('subtitle_font_size'));
      final cloud = c.cloudKeyFor('subtitle_font_size')!;
      transport.store.remove(cloud); // collected by the device above

      await c.applyEntries({cloud: null});
      await c.reconcile();

      expect(settings.prefs.getInt('subtitle_font_size'), isNull);
      expect(transport.store.containsKey(cloud), isFalse, reason: 'no tombstone is sent back');
    });
  });
}
