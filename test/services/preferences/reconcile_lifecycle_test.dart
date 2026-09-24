import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
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
