import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_merge_strategies.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (9). The two language maps are global preferences whose map keys
/// carry the profile scope. A Plex Home uuid means the same profile everywhere;
/// `local-<uuid>` and the empty scope belong to one device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const home = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  const otherHome = '11111111-2222-3333-4444-555555555555';
  const local = 'local-9a8b7c6d-1111-2222-3333-444455556666';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: home);
  final family = buildProfileKeyedMapFamily();

  Map<String, dynamic> m(Object? raw) => Map<String, dynamic>.from(json.decode(raw as String) as Map);

  group('scope portability', () {
    test('a Plex Home uuid travels, local and empty scopes stay', () {
      expect(PreferenceSyncScope.isPortableProfileScope(home), isTrue);
      expect(PreferenceSyncScope.isPortableProfileScope(local), isFalse);
      expect(PreferenceSyncScope.isPortableProfileScope(''), isFalse);
    });

    test('the scope is the part before the first pipe', () {
      expect(profileScopeOfMapKey('$home|series:42'), home);
      expect(profileScopeOfMapKey(home), home);
      expect(profileScopeOfMapKey('|x'), '');
    });
  });

  group('inbound', () {
    test('keeps local-only entries and adopts the portable ones', () {
      final mine = json.encode({
        '$local|s1': {'a': 'nl'},
        '$home|s1': {'a': 'nl'},
      });
      final theirs = json.encode({
        '$home|s1': {'a': 'en'},
        '$home|s2': {'a': 'de'},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$local|s1'], {'a': 'nl'});
      expect(merged['$home|s1'], {'a': 'en'});
      expect(merged['$home|s2'], {'a': 'de'});
    });

    test('a series entry the sender removed for a shared scope is removed here too', () {
      final mine = json.encode({
        '$home|s1': {'a': 'nl'},
        '$home|s2': {'a': 'de'},
      });
      final theirs = json.encode({
        '$home|s1': {'a': 'nl'},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged.containsKey('$home|s2'), isFalse);
    });

    test('a scope the sender does not know is kept whole', () {
      final mine = json.encode({
        '$otherHome|s1': {'a': 'nl'},
      });
      final theirs = json.encode({
        '$home|s1': {'a': 'en'},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged['$otherHome|s1'], {'a': 'nl'});
      expect(merged['$home|s1'], {'a': 'en'});
    });

    test('a local entry with a newer updatedAt survives an older remote one', () {
      final mine = json.encode({
        home: {'audio': 'nl', 'updatedAt': 200},
      });
      final theirs = json.encode({
        home: {'audio': 'en', 'updatedAt': 100},
      });

      final merged = m(family.inbound(mine, theirs));

      expect(merged[home], {'audio': 'nl', 'updatedAt': 200});
    });

    test('the stores\' own short timestamp `u` settles a shared entry', () {
      final mine = json.encode({
        '$home|s1': {'a': 'nl', 'u': 200},
      });
      final theirs = json.encode({
        '$home|s1': {'a': 'en', 'u': 100},
      });

      expect(m(family.inbound(mine, theirs))['$home|s1'], {'a': 'nl', 'u': 200});
      expect(m(family.outbound!(theirs, mine))['$home|s1'], {'a': 'nl', 'u': 200});
    });

    test('an undecodable remote value leaves the local one alone', () {
      expect(family.inbound('{"a":1}', 'not json'), '{"a":1}');
    });
  });

  group('outbound', () {
    test('drops local-only entries and keeps store entries for scopes this device lacks', () {
      final mine = json.encode({
        '$local|s1': {'a': 'nl'},
        '$home|s1': {'a': 'nl'},
      });
      final theirs = json.encode({
        '$otherHome|s1': {'a': 'fr'},
        '$home|s9': {'a': 'it'},
      });

      final out = m(family.outbound!(mine, theirs));

      expect(out.containsKey('$local|s1'), isFalse);
      expect(out['$home|s1'], {'a': 'nl'});
      expect(out['$otherHome|s1'], {'a': 'fr'}, reason: 'not mine to drop');
      expect(out.containsKey('$home|s9'), isFalse, reason: 'my scope, and I no longer have it');
    });

    test('sends nothing when nothing portable is held', () {
      final mine = json.encode({
        '$local|s1': {'a': 'nl'},
      });

      expect(family.outbound!(mine, null), isNull);
    });

    test('a newer remote entry for a shared key is carried rather than overwritten', () {
      final mine = json.encode({
        home: {'audio': 'nl', 'updatedAt': 100},
      });
      final theirs = json.encode({
        home: {'audio': 'en', 'updatedAt': 200},
      });

      final out = m(family.outbound!(mine, theirs));

      expect(out[home], {'audio': 'en', 'updatedAt': 200});
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
      transport.store[coordinator.cloudKeyFor(key)!] = json.encode({
        'type': 'string',
        'value': json.encode({
          home: {'audioLanguage': 'nl', 'updatedAt': 5},
        }),
        't': 5,
        'd': 'appletv',
      });

      await coordinator.applyAllRemote();

      expect(settings.prefs.getString(key), contains('"nl"'));
      expect(settings.prefs.getString('user_${home}_$key'), isNull, reason: 'the dead key of B10');
    });

    test('an outgoing map leaves the local profile\'s entry at home', () async {
      final coordinator = await build();
      const key = 'track_language_preferences';
      final value = json.encode({
        '$local|s1': {'a': 'nl'},
        '$home|s1': {'a': 'en'},
      });
      await settings.prefs.setString(key, value);

      await coordinator.apply(PreferenceMutation.set(key, value));

      final record = json.decode(transport.store[coordinator.cloudKeyFor(key)!]!) as Map;
      final sent = m(record['value']);
      expect(sent.containsKey('$local|s1'), isFalse);
      expect(sent['$home|s1'], {'a': 'en'});
    });

    test('a key that stopped syncing stays in the store for older builds and is not applied', () async {
      final coordinator = await build();
      const cloudKey = '${PreferenceSyncScope.cloudNamespacePrefix}global/buffer_size';
      final record = json.encode({'type': 'int', 'value': 512, 't': 5, 'd': 'iphone'});
      transport.store[cloudKey] = record;
      await settings.prefs.setInt('buffer_size', 128);

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(coordinator.cloudKeyFor('buffer_size'), isNull);
      expect(transport.removes, isEmpty);
      expect(transport.store[cloudKey], record);
      expect(settings.prefs.getInt('buffer_size'), 128);
    });
  });
}
