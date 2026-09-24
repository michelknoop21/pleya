import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/pleya_profile_language_preferences.dart';
import 'package:pleya/media/track_language_choice.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_merge_strategies.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/track_preference_store.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (9). The two language maps are global preferences whose map keys
/// carry the profile scope. A Plex Home profile id built on the Plex account
/// uuid means the same profile everywhere; `local-<uuid>`, the empty scope and
/// an account connection that fell back to this device's client id belong to
/// one device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The shape Plex actually issues: 16 hex characters for both the account and
  // the home user (test/fixtures/plex_detail/home_users.json).
  final home = plexHomeProfileId(accountConnectionId: 'plex.a1b2c3d4e5f60718', homeUserUuid: 'e434272903092b4e');
  final otherHome = plexHomeProfileId(accountConnectionId: 'plex.a1b2c3d4e5f60718', homeUserUuid: 'f870c16b61268c50');
  final clientIdFallback = plexHomeProfileId(
    accountConnectionId: 'plex.9a8b7c6d-1111-4222-8333-444455556666',
    homeUserUuid: 'e434272903092b4e',
  );
  const local = 'local-9a8b7c6d-1111-2222-3333-444455556666';
  final family = buildProfileKeyedMapFamily();

  Map<String, dynamic> m(Object? raw) => Map<String, dynamic>.from(json.decode(raw as String) as Map);
  String enc(Map<String, Object?> v) => json.encode(v);
  int now() => DateTime.now().millisecondsSinceEpoch;
  final t0 = now();

  group('scope portability', () {
    test('a real Plex Home profile id travels', () {
      expect(home, 'plex-home-plex.a1b2c3d4e5f60718-e434272903092b4e');
      expect(PreferenceSyncScope.isPortableProfileScope(home), isTrue);
    });

    test('it is what the stores key on: parsePlexHomeProfileId does not strip a 16-hex home uuid', () {
      expect(parsePlexHomeProfileId(home), isNull);
    });

    test('a client-id fallback, local and empty scopes stay', () {
      expect(PreferenceSyncScope.isPortableProfileScope(clientIdFallback), isFalse);
      expect(PreferenceSyncScope.isPortableProfileScope(local), isFalse);
      expect(PreferenceSyncScope.isPortableProfileScope(''), isFalse);
      expect(PreferenceSyncScope.isPortableProfileScope('e434272903092b4e'), isFalse);
    });

    test('the scope is the part before the first pipe', () {
      expect(profileScopeOfMapKey('$home|series:42'), home);
      expect(profileScopeOfMapKey(home), home);
      expect(profileScopeOfMapKey('|x'), '');
    });
  });

  group('inbound', () {
    test('keeps local-only entries and adopts the portable ones', () {
      final mine = enc({
        '$local|s1': {'a': 'nl', 'u': 1},
        '$home|s1': {'a': 'nl', 'u': 1},
      });
      final theirs = enc({
        '$home|s1': {'a': 'en', 'u': 2},
        '$home|s2': {'a': 'de', 'u': 2},
        '$local|s9': {'a': 'fr', 'u': 2},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$local|s1'], {'a': 'nl', 'u': 1});
      expect(merged['$home|s1'], {'a': 'en', 'u': 2});
      expect(merged['$home|s2'], {'a': 'de', 'u': 2});
      expect(merged.containsKey('$local|s9'), isFalse, reason: "the sender's local profile is not ours");
    });

    test("this device's own entries for a shared scope survive: per entry, not per scope", () {
      final mine = enc({
        '$home|s1': {'a': 'nl', 'u': 100},
        '$home|s2': {'a': 'de', 'u': 100},
      });
      final theirs = enc({
        '$home|s1': {'a': 'en', 'u': 50},
        '$home|s3': {'a': 'it', 'u': 50},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$home|s1'], {'a': 'nl', 'u': 100}, reason: 'newer here');
      expect(merged['$home|s2'], {'a': 'de', 'u': 100}, reason: 'never sent, still mine');
      expect(merged['$home|s3'], {'a': 'it', 'u': 50});
    });

    test('a newer tombstone removes the entry, an older one does not', () {
      final mine = enc({
        '$home|s1': {'a': 'nl', 'u': t0 + 100},
        '$home|s2': {'a': 'de', 'u': t0 + 300},
      });
      final theirs = enc({
        '$home|s1': {'u': t0 + 200},
        '$home|s2': {'u': t0 + 200},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$home|s1'], {'u': t0 + 200});
      expect(merged['$home|s2'], {'a': 'de', 'u': t0 + 300});
    });

    test('an expired tombstone is dropped', () {
      final merged = m(
        family.inbound(
          enc({
            '$home|s1': {'a': 'nl', 'u': now()},
          }),
          enc({
            '$home|s2': {'u': 1},
          }),
        ),
      );

      expect(merged.keys, ['$home|s1']);
    });

    test('a local entry with a newer updatedAt survives an older remote one', () {
      final mine = enc({
        home: {'audio': 'nl', 'updatedAt': 200},
      });
      final theirs = enc({
        home: {'audio': 'en', 'updatedAt': 100},
      });

      expect(m(family.inbound(mine, theirs))[home], {'audio': 'nl', 'updatedAt': 200});
    });

    test('equal timestamps settle the same way on both devices', () {
      final a = enc({
        '$home|s1': {'a': 'nl', 'u': 5},
      });
      final b = enc({
        '$home|s1': {'a': 'en', 'u': 5},
      });

      expect(m(family.inbound(a, b)), m(family.inbound(b, a)));
    });

    test('an undecodable remote value leaves the local one alone', () {
      expect(family.inbound('{"a":1}', 'not json'), '{"a":1}');
    });
  });

  group('outbound', () {
    test('drops local-only entries and carries the store entries it lacks', () {
      final mine = enc({
        '$local|s1': {'a': 'nl', 'u': 1},
        '$home|s1': {'a': 'nl', 'u': 1},
      });
      final theirs = enc({
        '$otherHome|s1': {'a': 'fr', 'u': 1},
        '$home|s9': {'a': 'it', 'u': 1},
      });

      final out = m(family.outbound!(mine, theirs));

      expect(out.containsKey('$local|s1'), isFalse);
      expect(out['$home|s1'], {'a': 'nl', 'u': 1});
      expect(out['$otherHome|s1'], {'a': 'fr', 'u': 1});
      expect(out['$home|s9'], {'a': 'it', 'u': 1}, reason: 'a removal travels as a tombstone, not as absence');
    });

    test('sends nothing when nothing portable is held', () {
      expect(
        family.outbound!(
          enc({
            '$local|s1': {'a': 'nl'},
          }),
          null,
        ),
        isNull,
      );
    });

    test('a newer remote entry for a shared key is carried rather than overwritten', () {
      final mine = enc({
        home: {'audio': 'nl', 'updatedAt': 100},
      });
      final theirs = enc({
        home: {'audio': 'en', 'updatedAt': 200},
      });

      expect(m(family.outbound!(mine, theirs))[home], {'audio': 'en', 'updatedAt': 200});
    });

    test('a local tombstone beats an older remote entry', () {
      final out = m(
        family.outbound!(
          enc({
            '$home|s1': {'u': t0 + 200},
          }),
          enc({
            '$home|s1': {'a': 'nl', 'u': t0 + 100},
          }),
        ),
      );

      expect(out['$home|s1'], {'u': t0 + 200});
    });
  });

  test('a whole-record tombstone keeps the local-only entries', () {
    final kept = family.removed!(
      enc({
        '$local|s1': {'a': 'nl', 'u': 1},
        '$home|s1': {'a': 'en', 'u': 1},
      }),
    );

    expect(m(kept), {
      '$local|s1': {'a': 'nl', 'u': 1},
    });
  });

  group('the two language preferences', () {
    late SettingsService settings;
    late FakeTransport transport;

    Future<PreferenceSyncCoordinator> build() async {
      settings = await SettingsService.getInstance();
      transport = FakeTransport();
      return PreferenceSyncCoordinator(
        prefs: settings.prefs,
        activeProfileId: () => home,
        enabled: () => true,
        deviceId: 'macbook',
        transport: transport,
      );
    }

    String record(String value, int t, String device) => enc({'type': 'string', 'value': value, 't': t, 'd': device});

    setUp(() {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      TrackPreferenceStore.resetForTesting();
    });

    tearDown(() => BaseSharedPreferencesService.onMutation = null);

    test('are global maps with the profile-keyed merge', () {
      for (final key in ['pleya_profile_language_preferences', 'track_language_preferences']) {
        final policy = PreferenceSyncPolicyRegistry.policyFor(key);
        expect(policy.scope, PreferenceScopeKind.global, reason: key);
        expect(policy.maySync, isTrue, reason: key);
        expect(policy.mergeFamily, PreferenceMergeFamilies.profileKeyedMap, reason: key);
        expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isFalse, reason: key);
      }
    });

    test('an incoming profile preference lands on the key the store reads', () async {
      final coordinator = await build();
      const key = 'pleya_profile_language_preferences';
      final sent = PleyaProfileLanguagePreferences(audioLanguage: 'nld', updatedAt: now());
      transport.store[coordinator.cloudKeyFor(key)!] = record(enc({home: sent.toJson()}), 5, 'appletv');

      await coordinator.applyAllRemote();

      final stored = settings.read(SettingsService.pleyaProfileLanguagePreferences);
      expect(stored[home]?.audioLanguage, 'nld');
      expect(stored[home]?.updatedAt, sent.updatedAt);
      expect(settings.prefs.getString('user_${home}_$key'), isNull, reason: 'the dead key of B10');
    });

    test("an outgoing map leaves the local profile's entry at home", () async {
      final coordinator = await build();
      const key = 'track_language_preferences';
      final value = enc({
        '$local|s1': {'a': 'nl', 'u': 1},
        '$home|s1': {'a': 'en', 'u': 1},
      });
      await settings.prefs.setString(key, value);

      await coordinator.apply(PreferenceMutation.set(key, value));

      final sent = m((json.decode(transport.store[coordinator.cloudKeyFor(key)!]!) as Map)['value']);
      expect(sent.containsKey('$local|s1'), isFalse);
      expect(sent['$home|s1'], {'a': 'en', 'u': 1});
    });

    test("first contact after the upgrade keeps each device's own series entries", () async {
      final coordinator = await build();
      const key = 'track_language_preferences';
      // Unregistered until this build, so neither device ever sent these.
      await settings.prefs.setString(
        key,
        enc({
          '$home|mine': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 100).toJson(),
          '$home|both': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 300).toJson(),
        }),
      );
      transport.store[coordinator.cloudKeyFor(key)!] = record(
        enc({
          '$home|theirs': TrackLanguageChoice(audioLanguage: 'eng', updatedAt: 200).toJson(),
          '$home|both': TrackLanguageChoice(audioLanguage: 'eng', updatedAt: 200).toJson(),
        }),
        now() + 60000,
        'appletv',
      );

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      final here = m(settings.prefs.getString(key));
      expect(here['$home|mine']['a'], 'nld');
      expect(here['$home|theirs']['a'], 'eng');
      expect(here['$home|both']['a'], 'nld', reason: 'newer u wins per entry');
      final there = m((json.decode(transport.store[coordinator.cloudKeyFor(key)!]!) as Map)['value']);
      expect(there.keys.toSet(), {'$home|mine', '$home|theirs', '$home|both'});
      expect(there['$home|both']['a'], 'nld');
    });

    test('an override set while an older record is in flight survives it', () async {
      final coordinator = await build();
      const key = 'track_language_preferences';
      final cloudKey = coordinator.cloudKeyFor(key)!;
      final mine = enc({'$home|s1': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 300).toJson()});
      await settings.prefs.setString(key, mine);
      await coordinator.apply(PreferenceMutation.set(key, mine));

      // The other device's record was written before this override but lands
      // after it, with a later envelope stamp.
      transport.store[cloudKey] = record(
        enc({'$home|s1': TrackLanguageChoice(audioLanguage: 'eng', updatedAt: 200).toJson()}),
        now() + 60000,
        'appletv',
      );
      await coordinator.handleRemoteChange(
        RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [cloudKey]),
      );

      expect(m(settings.prefs.getString(key))['$home|s1']['a'], 'nld');
    });

    test('a removal travels: the store writes a tombstone and the other device drops the entry', () async {
      final storage = await StorageService.getInstance();
      await storage.setActiveProfileId(home);
      settings = await SettingsService.getInstance();
      await settings.write(SettingsService.trackLanguagePreferences, {
        '$home|show7': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 100),
        '$local|show7': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 100),
      });

      await TrackPreferenceStore.clearKey('show7');

      final raw = settings.prefs.getString('track_language_preferences');
      final tombstone = m(raw)['$home|show7'] as Map;
      expect(tombstone.keys, ['u'], reason: 'a tombstone, not a deleted key');
      expect(await TrackPreferenceStore.readAllForActiveScope(), isEmpty);

      final otherDevice = enc({'$home|show7': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 100).toJson()});
      final merged = m(family.inbound(otherDevice, family.outbound!(raw, null)));
      expect(TrackLanguageChoice.fromJson(merged['$home|show7'] as Map<String, dynamic>).isEmpty, isTrue);
    });

    test('a local profile removal just deletes the key', () async {
      final storage = await StorageService.getInstance();
      await storage.setActiveProfileId(local);
      settings = await SettingsService.getInstance();
      await settings.write(SettingsService.trackLanguagePreferences, {
        '$local|show7': TrackLanguageChoice(audioLanguage: 'nld', updatedAt: 100),
      });

      await TrackPreferenceStore.clearKey('show7');

      expect(settings.read(SettingsService.trackLanguagePreferences), isEmpty);
    });

    test('a key that stopped syncing stays in the store for older builds and is not applied', () async {
      final coordinator = await build();
      const cloudKey = '${PreferenceSyncScope.cloudNamespacePrefix}global/buffer_size';
      final stored = enc({'type': 'int', 'value': 512, 't': 5, 'd': 'iphone'});
      transport.store[cloudKey] = stored;
      await settings.prefs.setInt('buffer_size', 128);

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(coordinator.cloudKeyFor('buffer_size'), isNull);
      expect(transport.removes, isEmpty);
      expect(transport.store[cloudKey], stored);
      expect(settings.prefs.getInt('buffer_size'), 128);
    });
  });
}
