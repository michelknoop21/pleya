import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_device_id.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_quarantine.dart';
import 'package:pleya/services/preferences/preference_revision.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// What the revision envelope needs before it can decide anything: an identity
/// to sign with, a clock that cannot walk backwards locally, a sane starting
/// point for values nobody chose, and a rule for records whose owner is
/// unknown.
String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String? activeProfile, String deviceId = 'macbook'}) async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => activeProfile,
      enabled: () => true,
      deviceId: deviceId,
      transport: transport,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('device id', () {
    test('is generated once and reused on the next launch', () async {
      final prefs = (await SettingsService.getInstance()).prefs;

      final first = await PreferenceDeviceId.getOrCreate(prefs);
      final second = await PreferenceDeviceId.getOrCreate(prefs);

      expect(first, isNotEmpty);
      expect(second, first, reason: 'a fresh id per launch would make every tie break arbitrarily');
    });

    test('is unique per installation', () async {
      final prefs = (await SettingsService.getInstance()).prefs;
      final mine = await PreferenceDeviceId.getOrCreate(prefs);

      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      final theirs = await PreferenceDeviceId.getOrCreate((await SettingsService.getInstance()).prefs);

      expect(theirs, isNot(mine));
    });

    test('device id never syncs, and is not the Plex client identifier', () async {
      final coordinator = await build();
      await settings.prefs.setString(PreferenceDeviceId.prefsKey, 'my-device');
      await settings.prefs.setString('client_identifier', 'plex-client-id');

      await coordinator.reconcile();

      expect(transport.store.containsKey(PreferenceDeviceId.prefsKey), isFalse);
      expect(PreferenceSyncPolicyRegistry.maySync(PreferenceDeviceId.prefsKey), isFalse);
      expect(
        PreferenceDeviceId.prefsKey,
        isNot('client_identifier'),
        reason: 'the Plex id is sent to plex.tv; do not copy an external identity into every record',
      );
    });
  });

  group('monotonic local revisions', () {
    test('a clock set backwards does not put a newer change under its predecessor', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'dark');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));
      final first = coordinator.localRevision('theme_mode')!;

      // Simulate the clock having been an hour ahead: rewrite the stored
      // revision to a future timestamp, then make a genuinely newer change.
      final revisions = json.decode(settings.prefs.getString(PreferenceSyncCoordinator.revisionStoreKey)!) as Map;
      final future = DateTime.now().toUtc().millisecondsSinceEpoch + const Duration(hours: 1).inMilliseconds;
      revisions['theme_mode'] = {'t': future, 'd': 'macbook'};
      await settings.prefs.setString(PreferenceSyncCoordinator.revisionStoreKey, json.encode(revisions));

      await settings.prefs.setString('theme_mode', 'light');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'light'));
      final second = coordinator.localRevision('theme_mode')!;

      expect(
        second.updatedAt,
        greaterThan(future),
        reason: 'the newer local value must not lose to the value it just replaced',
      );
      expect(second.winsOver(first), isTrue);
    });

    test('ordinary consecutive changes still move forward', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'dark');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));
      final first = coordinator.localRevision('theme_mode')!;

      await settings.prefs.setString('theme_mode', 'light');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'light'));
      final second = coordinator.localRevision('theme_mode')!;

      expect(second.updatedAt, greaterThanOrEqualTo(first.updatedAt));
      expect(second.winsOver(first), isTrue);
    });
  });

  group('legacy bootstrap', () {
    test('a value that was already there gets a legacy revision, not a fake now', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'dark');

      await coordinator.bootstrapLegacyRevision('theme_mode');
      final bootstrapped = coordinator.localRevision('theme_mode')!;

      expect(bootstrapped.updatedAt, PreferenceSyncCoordinator.legacyRevisionAt);
      expect(
        bootstrapped.updatedAt,
        lessThan(DateTime.now().toUtc().millisecondsSinceEpoch),
        reason: 'stamping the migration moment would make the last device to upgrade the newest editor',
      );
    });

    test('the first real user change always beats a bootstrapped value', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'dark');
      await coordinator.bootstrapLegacyRevision('theme_mode');
      final legacy = coordinator.localRevision('theme_mode')!;

      final chosen = PreferenceRevision(
        value: 'light',
        updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        deviceId: 'appletv',
      );

      expect(chosen.winsOver(legacy), isTrue);
      expect(PreferenceRevision.resolve(legacy, chosen), chosen);
    });

    test('bootstrapping is idempotent and never downgrades a real revision', () async {
      final coordinator = await build();
      await settings.prefs.setString('theme_mode', 'dark');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));
      final real = coordinator.localRevision('theme_mode')!;

      await coordinator.bootstrapLegacyRevision('theme_mode');
      await coordinator.bootstrapLegacyRevision('theme_mode');

      expect(coordinator.localRevision('theme_mode')!.updatedAt, real.updatedAt);
    });
  });

  group('quarantine', () {
    test('a v1 profile record is recorded and never handed to the active profile', () async {
      final coordinator = await build(activeProfile: profile);
      transport.store['hidden_libraries'] = enc('string', '["srv:1"]');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getString('user_${homeUuid}_hidden_libraries'), isNull);
      expect(PreferenceQuarantine.isQuarantined(settings.prefs, 'hidden_libraries'), isTrue);
    });

    test('the quarantine record survives a second pass without duplicating', () async {
      final coordinator = await build(activeProfile: profile);
      transport.store['hidden_libraries'] = enc('string', '["srv:1"]');

      await coordinator.applyAllRemote();
      await coordinator.applyAllRemote();

      expect(PreferenceQuarantine.keys(settings.prefs), {'hidden_libraries'});
    });

    test('quarantining does not delete the cloud record either', () async {
      final coordinator = await build(activeProfile: profile);
      transport.store['hidden_libraries'] = enc('string', '["srv:1"]');

      await coordinator.applyAllRemote();

      expect(transport.store.containsKey('hidden_libraries'), isTrue);
    });

    test('a released entry is gone, which is the documented way out', () async {
      final prefs = (await SettingsService.getInstance()).prefs;
      await PreferenceQuarantine.quarantine(prefs, 'hidden_libraries', reason: 'test', seenAt: 1);

      await PreferenceQuarantine.release(prefs, 'hidden_libraries');

      expect(PreferenceQuarantine.isQuarantined(prefs, 'hidden_libraries'), isFalse);
    });

    test('a global v1 key is not quarantined; only profile-scoped ones are ambiguous', () async {
      final coordinator = await build(activeProfile: profile);
      transport.store['subtitle_font_size'] = enc('int', 60);

      await coordinator.applyAllRemote();

      // After the cutover a v1 record is never merged, whatever its scope. What
      // separates the two is attribution: a global value has an owner (the
      // account) and reaches v2 once through the bootstrap, a profile-scoped one
      // has none and keeps a quarantine record instead.
      expect(PreferenceQuarantine.isQuarantined(settings.prefs, 'subtitle_font_size'), isFalse);

      await coordinator.bootstrapFromLegacyV1();
      expect(settings.prefs.getInt('subtitle_font_size'), 60);
    });
  });
}
