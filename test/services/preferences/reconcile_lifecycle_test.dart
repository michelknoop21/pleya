import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_legacy_bootstrap.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_reconcile_scheduler.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/settings_export_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// A8. Every moment the engine has to catch up with the store is a named
/// trigger, and a profile switch hydrates the namespace that belongs to the
/// profile that is now active — without touching the one that is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uuidA = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  const uuidB = '11111111-2222-3333-4444-555555555555';
  final profileA = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: uuidA);
  final profileB = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: uuidB);

  late SettingsService settings;
  late FakeTransport transport;
  String? activeProfile;
  var enabled = true;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => activeProfile,
      enabled: () => enabled,
      deviceId: 'macbook',
      isServerIdPortable: (id) => id == 'plex',
      transport: transport,
    );
  }

  String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    activeProfile = profileA;
    enabled = true;
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('the trigger decides what the run does', () {
    test('an import is stamped, so it survives the next pull over a stamped store record', () async {
      final coordinator = await build();
      BaseSharedPreferencesService.onMutation = coordinator.apply;
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      // Another device chose 'dark' an hour ago, with a stamp.
      final earlier = DateTime.now().toUtc().millisecondsSinceEpoch - 60 * 60 * 1000;
      transport.store[cloudKey] = json.encode({'type': 'string', 'value': 'dark', 't': earlier, 'd': 'appletv'});

      await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            'theme_mode': {'type': 'string', 'value': 'light'},
          },
        },
        settings.prefs,
        currentUserUuid: uuidA,
      );
      await coordinator.requestReconcile(ReconcileTrigger.imported);
      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getString('theme_mode'), 'light', reason: 'the pull did not undo the import');
      final sent = json.decode(transport.store[cloudKey]!) as Map;
      expect(sent['value'], 'light');
      expect(sent['t'], greaterThan(earlier), reason: 'the import carries a fresh stamp');
      expect(sent['d'], 'macbook');
    });

    test('a foreground pulls the store before it pushes', () async {
      final coordinator = await build();
      transport.store[coordinator.cloudKeyFor('theme_mode')!] = enc('string', 'dark');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getString('theme_mode'), 'dark');
    });

    test('with sync off a trigger does nothing at all', () async {
      final coordinator = await build();
      enabled = false;

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.writes, isEmpty);
      expect(transport.removes, isEmpty);
    });
  });

  group('a profile switch', () {
    test('is noticed by the engine itself, whichever path switched it', () async {
      final coordinator = await build();
      final runsBefore = coordinator.scheduler.runCount;

      await coordinator.apply(PreferenceMutation.set(PreferenceSyncScope.activeProfileIdKey, profileB));
      await coordinator.requestReconcile(ReconcileTrigger.profileChanged);

      expect(coordinator.scheduler.runCount, greaterThan(runsBefore));
    });

    test('the key the engine watches is the one storage actually writes', () async {
      settings = await SettingsService.getInstance();
      final storage = await StorageService.getInstance();
      final seen = <String>[];
      BaseSharedPreferencesService.onMutation = (m) async => seen.add(m.key);

      await storage.setActiveProfileId(profileB);

      expect(seen, contains(PreferenceSyncScope.activeProfileIdKey));
    });

    test('hydrates the new profile and leaves the old profile\'s records alone', () async {
      final coordinator = await build();
      final keyA = 'user_${uuidA}_hidden_libraries';
      final keyB = 'user_${uuidB}_hidden_libraries';
      // Profile A has state locally and in the store; profile B only in the store.
      await settings.prefs.setString(keyA, json.encode(['plex:1']));
      activeProfile = profileA;
      final cloudA = coordinator.cloudKeyFor(keyA)!;
      transport.store[cloudA] = enc('string', json.encode(['plex:1']));
      activeProfile = profileB;
      final cloudB = coordinator.cloudKeyFor(keyB)!;
      transport.store[cloudB] = enc('string', json.encode(['plex:2']));

      await coordinator.requestReconcile(ReconcileTrigger.profileChanged);

      // B's value landed under B's local prefix, A's local value is untouched,
      // and A's cloud record was not pruned by B's reconcile.
      expect(json.decode(settings.prefs.getString(keyB)!), ['plex:2']);
      expect(json.decode(settings.prefs.getString(keyA)!), ['plex:1']);
      expect(transport.store.containsKey(cloudA), isTrue);
      expect(transport.removes, isNot(contains(cloudA)));
    });

    test('does not carry the previous profile\'s value into the new profile', () async {
      final coordinator = await build();
      final keyA = 'user_${uuidA}_library_order';
      await settings.prefs.setString(keyA, json.encode(['plex:a']));
      activeProfile = profileA;
      transport.store[coordinator.cloudKeyFor(keyA)!] = enc('string', json.encode(['plex:a']));

      activeProfile = profileB;
      await coordinator.requestReconcile(ReconcileTrigger.profileChanged);

      expect(settings.prefs.getString('user_${uuidB}_library_order'), isNull);
    });
  });

  group('an iCloud account change', () {
    test('a sign-out reports unavailable and does not try to sync', () async {
      final coordinator = await build();
      coordinator.listen();
      transport.available = false;
      final runsBefore = coordinator.scheduler.runCount;

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
      expect(coordinator.scheduler.runCount, runsBefore);
    });

    test('a switch to another signed-in account reconciles once', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(transport.store.containsKey(coordinator.cloudKeyFor('subtitle_font_size')!), isTrue);
    });

    test('the new account\'s values win, even over a fresher local stamp', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      // Account B's store: an older stamp from another device.
      transport.store.clear();
      transport.store[cloudKey] = json.encode({'type': 'int', 'value': 99, 't': 1000, 'd': 'other-device'});

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(settings.prefs.getInt('subtitle_font_size'), 99, reason: 'the old account\'s stamps mean nothing here');
      expect(coordinator.localRevision('subtitle_font_size')!.deviceId, 'other-device');
    });

    test('what the new account lacks is pushed with the oldest stamp, so its first real change wins', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('seek_time_small', 5);
      await coordinator.apply(const PreferenceMutation.set('seek_time_small', 5));
      transport.store.clear();

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final record = json.decode(transport.store[coordinator.cloudKeyFor('seek_time_small')!]!) as Map;
      expect(record['value'], 5);
      expect(record['t'], PreferenceSyncCoordinator.legacyRevisionAt);
      expect(settings.prefs.getInt('seek_time_small'), 5, reason: 'nothing local is wiped');
    });

    test('a switch runs the v1 bootstrap again for the new account', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setBool(PreferenceLegacyBootstrap.completedKey, true);
      transport.store['theme_mode'] = enc('string', 'dark'); // account B still has a v1 device

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(settings.prefs.getString('theme_mode'), 'dark');
    });

    test('a sign-out clears no stamps', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.available = false;

      await coordinator.handleRemoteChange(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));

      expect(coordinator.localRevision('subtitle_font_size'), isNotNull);
    });

    test('an edit made while signed out loses to the store where it holds the key, and keeps the rest', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 30);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 30));
      final subtitleKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      final seekKey = coordinator.cloudKeyFor('seek_time_small')!;
      expect(transport.store.containsKey(subtitleKey), isTrue);
      expect(transport.store.containsKey(seekKey), isFalse);

      transport.available = false;
      await coordinator.handleRemoteChange(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await settings.prefs.setInt('seek_time_small', 5);
      await coordinator.apply(const PreferenceMutation.set('seek_time_small', 5));

      // Back into the same store. There is no account identity to tell it apart.
      transport.available = true;
      await coordinator.handleRemoteChange(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));

      expect(settings.prefs.getInt('subtitle_font_size'), 30, reason: 'the store held the key, so it wins');
      expect(settings.prefs.getInt('seek_time_small'), 5, reason: 'the store lacked the key');
      expect((json.decode(transport.store[seekKey]!) as Map)['value'], 5);
    });

    test('A, then B, then A again: nothing from the B period travels into A', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 30);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 30));
      final key = coordinator.cloudKeyFor('subtitle_font_size')!;
      final storeA = Map<String, String>.from(transport.store);

      // Account B: another person's Apple TV chose 50, later than this device's edit in A.
      final later = DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 1000;
      transport.store
        ..clear()
        ..[key] = json.encode({'type': 'int', 'value': 50, 't': later, 'd': 'appletv-b'});
      await coordinator.handleRemoteChange(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));
      expect(settings.prefs.getInt('subtitle_font_size'), 50);

      // Back to A. Its store holds records this device wrote, which proves nothing
      // about whether the stamps held now describe A's history.
      transport.store
        ..clear()
        ..addAll(storeA);
      await coordinator.handleRemoteChange(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));

      expect(settings.prefs.getInt('subtitle_font_size'), 30, reason: "A's store wins what it holds");
      expect((json.decode(transport.store[key]!) as Map)['value'], 30, reason: "B's value never reaches A");
    });

    test("another account's map entries replace this device's, and the entries it lacks stay", () async {
      final coordinator = await build();
      const s1 = 'plex-home-plex.e434272903092b4e-f870c16b61268c50';
      const s2 = 'plex-home-plex.e434272903092b4e-a870c16b61268c51';
      const key = 'pleya_profile_language_preferences';
      final cloudKey = coordinator.cloudKeyFor(key)!;
      final mine = json.encode({
        s1: {'audio': 'nl', 'u': 5000},
        s2: {'audio': 'de', 'u': 5000},
      });
      await settings.prefs.setString(key, mine);
      await coordinator.apply(PreferenceMutation.set(key, mine));
      // Account B's store: an older entry for s1 from another device, nothing for s2.
      transport.store
        ..clear()
        ..[cloudKey] = json.encode({
          'type': 'string',
          'value': json.encode({
            s1: {'audio': 'en', 'u': 1000},
          }),
          't': 1000,
          'd': 'other-device',
        });

      await coordinator.handleRemoteChange(const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged));

      final local = json.decode(settings.prefs.getString(key)!) as Map;
      expect(local[s1], {'audio': 'en', 'u': 1000}, reason: 'the store holds s1, so its entry wins');
      expect(local[s2], {'audio': 'de', 'u': 5000}, reason: 'nothing local is wiped');
      final pushed = json.decode((json.decode(transport.store[cloudKey]!) as Map)['value'] as String) as Map;
      expect(pushed.keys, containsAll([s1, s2]));
      expect(pushed[s1], {'audio': 'en', 'u': 1000});
    });

    test('a sign-out does not pass for ready while availability is re-checked', () async {
      final coordinator = await build();
      transport.available = false;
      await coordinator.refreshAvailability();

      final handling = coordinator.handleRemoteChange(
        const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged),
      );
      // Lands while the account change is still asking the transport.
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await handling;

      expect(coordinator.status.value.pushed, 0);
      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
    });
  });

  group('the initial download', () {
    test('is followed by a reconcile, so a write the system discarded before it is sent again', () async {
      final coordinator = await build();
      coordinator.listen();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      transport.store.remove(cloudKey); // what InitialSyncChange means: that write never landed

      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.initialSync));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(transport.store.containsKey(cloudKey), isTrue);
    });
  });

  group('coalescing at the engine level', () {
    test('a burst of triggers reconciles once', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      final before = coordinator.scheduler.runCount;

      await Future.wait([
        coordinator.requestReconcile(ReconcileTrigger.boot),
        coordinator.requestReconcile(ReconcileTrigger.foreground),
        coordinator.requestReconcile(ReconcileTrigger.profileChanged),
      ]);

      expect(coordinator.scheduler.runCount - before, 1);
      expect(transport.store.containsKey(coordinator.cloudKeyFor('subtitle_font_size')!), isTrue);
    });
  });
}
