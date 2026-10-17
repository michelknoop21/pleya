import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/household_kids_store.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

HouseholdKid _kid(String month, {String id = 'a'}) => HouseholdKid(id: id, name: 'Sam', birthMonth: month);

void main() {
  group('strict age in whole months', () {
    final now = DateTime(2026, 10, 16);

    test('the birthday counts from the month after the birth month', () {
      expect(_kid('2022-10').ageAt(now), 3, reason: 'fourth birthday month: still three');
      expect(_kid('2022-09').ageAt(now), 4, reason: 'the month after the birth month');
      expect(_kid('2022-11').ageAt(now), 3);
      expect(_kid('2026-10').ageAt(now), 0, reason: 'born this month');
      expect(_kid('2026-09').ageAt(now), 0);
    });

    test('a future month and an age of 18 or older are ignored', () {
      expect(_kid('2026-11').ageAt(now), isNull);
      expect(_kid('2008-09').ageAt(now), isNull, reason: '18 years and one month');
      expect(_kid('2008-10').ageAt(now), 17, reason: 'the birthday month itself still counts as 17');
      expect(_kid('garbage').ageAt(now), isNull);
    });

    test('the youngest intended child sets the gate; a name narrows', () {
      final kids = [_kid('2022-10', id: 'old'), _kid('2025-01', id: 'young'), _kid('2030-01', id: 'future')];
      expect(householdGateAge(kids, now), 1);
      expect(householdGateAge(kids, now, ids: {'old'}), 3);
      expect(householdGateAge([kids.last], now), isNull);
    });
  });

  group('the store', () {
    late StorageService storage;

    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      storage = await StorageService.getInstance();
      await SettingsService.getInstance();
    });

    test('one global key: every profile reads what an adult profile saved', () async {
      await storage.setActiveProfileId('parent');
      expect(await HouseholdKidsStore().save([_kid('2022-10')], kidsProfile: false), isTrue);
      await storage.setActiveProfileId('child');
      expect((await HouseholdKidsStore().read()).single.birthMonth, '2022-10');
    });

    test('a children\'s profile cannot edit', () async {
      expect(await HouseholdKidsStore().save([_kid('2022-10')], kidsProfile: true), isFalse);
      expect(await HouseholdKidsStore().read(), isEmpty);
    });

    test('the policy keeps the household on this device and out of exports', () {
      const key = 'household_kids';
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse);
    });
  });
}
