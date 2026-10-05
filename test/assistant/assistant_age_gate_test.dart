import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_age_gate.dart';
import 'package:pleya/assistant/assistant_kids_ages_store.dart';
import 'package:pleya/assistant/assistant_kids_profile_store.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/screens/profile/profile_delete_flow.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

TitleFacts _facts(Map<String, String> certs, {List<String> genres = const [], String source = 'tmdb'}) =>
    TitleFacts.from(source, certifications: certs, genres: genres);

void main() {
  group('AgeGate', () {
    final hp = _facts({'NL': '12', 'US': 'PG-13'});

    for (final (name, facts, region, age, allowed) in [
      ('Deathly Hallows 2, 8 years, NL', hp, 'NL', 8, false),
      ('Deathly Hallows 2, 13 years, NL', hp, 'NL', 13, true),
      ('only US PG-13 in NL: US counts, 13 passes', _facts({'US': 'PG-13'}), 'NL', 13, true),
      ('only US PG-13 in NL: 12 fails', _facts({'US': 'PG-13'}), 'NL', 12, false),
      ('NL 6 wins over US PG-13: 8 passes', _facts({'NL': '6', 'US': 'PG-13'}), 'NL', 8, true),
      ('NL 6 wins, 5 still fails', _facts({'NL': '6', 'US': 'PG-13'}), 'NL', 5, false),
      ('in the US the US rating counts', _facts({'NL': '6', 'US': 'PG-13'}), 'US', 8, false),
      ('Toy Story G, 4 years', _facts({'US': 'G'}), 'NL', 4, true),
      ('TV-MA, 16 years', _facts({'US': 'TV-MA'}), 'NL', 16, false),
      ('unrated Animation', _facts({}, genres: ['Animation']), 'NL', 4, true),
      ('unrated Familie', _facts({}, genres: ['Familie']), 'NL', 4, true),
      ('unrated TMDB id 10762', _facts({}, genres: ['10762']), 'NL', 4, true),
      ('unrated Drama', _facts({}, genres: ['Drama']), 'NL', 17, false),
      ('server PG-13, 13', _facts({'*': 'PG-13'}, source: 'server'), 'NL', 13, true),
      ('server PG-13, 12', _facts({'*': 'PG-13'}, source: 'server'), 'NL', 12, false),
      ('server nl/12, 12', _facts({'*': 'nl/12'}, source: 'server'), 'NL', 12, true),
      ('server nl/12, 11', _facts({'*': 'nl/12'}, source: 'server'), 'NL', 11, false),
      ('server de/FSK 16 under its own country', _facts({'DE': 'FSK 16'}, source: 'server'), 'NL', 15, false),
      ('non-server DE rating is ignored, unrated Drama', _facts({'DE': '16'}, genres: ['Drama']), 'NL', 17, false),
      ('unparsable region rating falls to US', _facts({'NL': 'NR', 'US': 'R'}), 'NL', 16, false),
    ]) {
      test(name, () => expect(AgeGate.allows(facts, age, region), allowed));
    }

    test('minimum ages per table', () {
      const cases = {
        ('NL', 'AL'): 0,
        ('BE', 'KT'): 0,
        ('DE', '0'): 0,
        ('GB', 'PG'): 8,
        ('GB', '12A'): 12,
        ('FR', 'TP'): 0,
        ('US', 'PG'): 8,
        ('US', 'R'): 17,
        ('US', 'TV-PG'): 10,
        ('US', 'TV-Y7'): 7,
        ('SE', '11'): 11,
      };
      for (final MapEntry(key: (country, code), :value) in cases.entries) {
        expect(AgeGate.ageFor(code, country), value, reason: '$country $code');
      }
      expect(AgeGate.ageFor('NR', 'US'), isNull);
      expect(AgeGate.ageFor('Unrated'), isNull);
    });

    test('reason names the deciding rating', () {
      expect(AgeGate.reason(hp, 'NL'), 'NL 12');
      expect(AgeGate.reason(_facts({'US': 'PG-13'}), 'NL'), 'US PG-13');
      expect(AgeGate.reason(_facts({'*': 'PG'}, source: 'server'), 'NL'), 'server PG');
      expect(AgeGate.reason(const TitleFacts(), 'NL'), 'unrated');
    });

    test('toModelJson carries age_min', () {
      expect(hp.toModelJson('NL')['age_min'], 12);
      expect(_facts({}, genres: ['Drama']).toModelJson('NL').containsKey('age_min'), isFalse);
    });
  });

  group('KidsAgesStore', () {
    late StorageService storage;

    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      storage = await StorageService.getInstance();
      await SettingsService.getInstance();
    });

    test('per profile, youngest from what was read', () async {
      await storage.setActiveProfileId('parent');
      await KidsAgesStore().save([9, 4]);
      await storage.setActiveProfileId('other');
      final other = KidsAgesStore();
      expect(await other.read(), isEmpty);
      expect(other.youngest, isNull);
      await storage.setActiveProfileId('parent');
      final store = KidsAgesStore();
      expect(await store.read(), [9, 4]);
      expect(store.youngest, 4);
      await store.clear();
      expect(await KidsAgesStore().read(), isEmpty);
    });

    test('without an active profile nothing is kept', () async {
      await KidsAgesStore().save([6]);
      expect(await KidsAgesStore().read(), isEmpty);
    });

    test('deleting a profile drops its ages and nobody else\'s', () async {
      await storage.setActiveProfileId('child');
      await KidsAgesStore().save([6]);
      await storage.setActiveProfileId('parent');
      await KidsAgesStore().save([10]);

      await clearProfileScopedStores(storage, 'child');

      expect(await KidsAgesStore().read(), [10]);
      await storage.setActiveProfileId('child');
      expect(await KidsAgesStore().read(), isEmpty);
    });

    test('the policy keeps the ages on this device and out of exports', () {
      const key = 'assistant_kids_ages';
      expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isTrue);
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse);
    });
  });

  group('KidsProfileStore', () {
    late StorageService storage;

    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      storage = await StorageService.getInstance();
      await SettingsService.getInstance();
    });

    test('per profile: the switch of one profile is not the other\'s', () async {
      await storage.setActiveProfileId('child');
      await KidsProfileStore().save(true);
      await storage.setActiveProfileId('parent');
      expect(await KidsProfileStore().read(), isFalse);
      await storage.setActiveProfileId('child');
      expect(await KidsProfileStore().read(), isTrue);
      await KidsProfileStore().save(false);
      expect(await KidsProfileStore().read(), isFalse);
    });

    test('without an active profile nothing is kept', () async {
      await KidsProfileStore().save(true);
      expect(await KidsProfileStore().read(), isFalse);
    });

    test('deleting a profile drops its switch and nobody else\'s', () async {
      await storage.setActiveProfileId('child');
      await KidsProfileStore().save(true);
      await storage.setActiveProfileId('other');
      await KidsProfileStore().save(true);

      await clearProfileScopedStores(storage, 'child');

      expect(await KidsProfileStore().read(), isTrue);
      await storage.setActiveProfileId('child');
      expect(await KidsProfileStore().read(), isFalse);
    });

    test('the policy keeps the switch on this device and out of exports', () {
      const key = 'assistant_kids_profile';
      expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isTrue);
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse);
    });

    final created = DateTime(2026);
    test('a Plex Home account Plex marks as restricted is a children\'s profile without the switch', () async {
      await storage.setActiveProfileId('plex');
      final kid = Profile.plexHome(id: 'plex', displayName: 'Mila', plexRestricted: true, createdAt: created);
      final adult = Profile.plexHome(id: 'plex', displayName: 'Ouder', createdAt: created);
      expect(await assistantIsKidsProfile(kid), isTrue);
      expect(await assistantIsKidsProfile(adult), isFalse);
    });

    test('any other profile follows its own switch', () async {
      await storage.setActiveProfileId('local');
      final local = Profile.local(id: 'local', displayName: 'Thuis', createdAt: created);
      expect(await assistantIsKidsProfile(local), isFalse);
      await KidsProfileStore().save(true);
      expect(await assistantIsKidsProfile(local), isTrue);
      expect(await assistantIsKidsProfile(null), isTrue, reason: 'the switch of the active scope still counts');
    });
  });
}
