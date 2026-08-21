import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/storage_service.dart';

import '../../test_helpers/prefs.dart';

/// The eight library and home families used to take two different routes: the
/// four that went through `_setStringList` fired the write hook by hand, and
/// the four that called `prefs.setString` directly fired nothing. None of the
/// *removals* fired anything at all, so iCloud saw every set and no delete, and
/// a hidden library un-hidden on one device stayed hidden on the other.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late List<PreferenceMutation> seen;

  Future<StorageService> storageWithProfile() async {
    final storage = await StorageService.getInstance();
    await storage.setActiveProfileId(profile);
    seen.clear();
    return storage;
  }

  setUp(() {
    resetSharedPreferencesForTest();
    seen = [];
    BaseSharedPreferencesService.onMutation = (m) async => seen.add(m);
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('every family reports its writes', () {
    test('all eight reach the pipeline', () async {
      final storage = await storageWithProfile();

      await storage.saveHiddenLibraries({'srv:1'});
      await storage.saveLibraryOrder(['srv:1', 'srv:2']);
      await storage.saveHomeRowOrder(profile, ['srv:hub1']);
      await storage.saveHiddenHomeRows(profile, {'srv:hub2'});
      await storage.saveLibraryFilters({'genre': 'action'});
      await storage.saveLibrarySort('srv:1', 'title');
      await storage.saveLibraryGrouping('srv:1', 'movies');
      await storage.saveLibraryTab('srv:1', 'Recommended');

      final keys = seen.map((m) => m.key).toList();
      for (final suffix in [
        'hidden_libraries',
        'library_order',
        'home_row_order',
        'hidden_home_rows',
        'library_filters',
        'library_sort_srv:1',
        'library_grouping_srv:1',
        'library_tab_srv:1',
      ]) {
        expect(keys, contains('user_${homeUuid}_$suffix'), reason: suffix);
      }
      expect(seen.every((m) => m.operation == PreferenceOperation.set), isTrue);
      expect(seen.every((m) => m.source == PreferenceSource.local), isTrue);
    });

    test('the selected-library key travels the same path', () async {
      final storage = await storageWithProfile();
      await storage.saveSelectedLibraryKey('srv:1');

      expect(seen.map((m) => m.key), contains('user_${homeUuid}_selected_library_key'));
    });
  });

  group('removals report too', () {
    test('clearing library preferences emits removals, not silence', () async {
      final storage = await storageWithProfile();
      await storage.saveHiddenLibraries({'srv:1'});
      await storage.saveLibraryOrder(['srv:1']);
      seen.clear();

      await storage.clearLibraryPreferences();

      final removals = seen.where((m) => m.operation == PreferenceOperation.remove).map((m) => m.key).toSet();
      expect(removals, contains('user_${homeUuid}_hidden_libraries'));
      expect(removals, contains('user_${homeUuid}_library_order'));
      expect(
        seen.where((m) => m.operation == PreferenceOperation.remove).every((m) => m.source == PreferenceSource.reset),
        isTrue,
        reason: 'a clear is a reset, not an ordinary edit',
      );
    });

    test('dropping a server rewrites the list it appears in, and reports that', () async {
      final storage = await storageWithProfile();
      await storage.saveLibraryOrder(['srv1:a', 'srv2:b']);
      await storage.saveHiddenLibraries({'srv1:c'});
      seen.clear();

      await storage.clearLibraryPreferencesForServer(ServerId('srv1'), profileId: profile);

      final keys = seen.map((m) => m.key).toSet();
      expect(keys, contains('user_${homeUuid}_library_order'), reason: 'the surviving entry is written back');
      expect(
        keys,
        contains('user_${homeUuid}_hidden_libraries'),
        reason: 'the list became empty, so the key is removed',
      );
      expect(storage.getLibraryOrder(), ['srv2:b']);
      expect(storage.getHiddenLibraries(), isEmpty);
    });
  });

  group('read-path migrations are marked as migrations', () {
    test('promoting a legacy unscoped value does not look like a user edit', () async {
      final storage = await StorageService.getInstance();
      await storage.prefs.setString('hidden_libraries', '["srv:legacy"]');
      await storage.setActiveProfileId(profile);
      seen.clear();

      expect(storage.getHiddenLibrariesForProfile(profile), {'srv:legacy'});
      await pumpEventQueue();

      expect(seen, isNotEmpty, reason: 'the promotion still travels the one pipeline');
      expect(
        seen.every((m) => m.source == PreferenceSource.migration),
        isTrue,
        reason: 'a device that upgrades last must not look like the most recent editor',
      );
    });

    test('the legacy library-order promotion is a migration as well', () async {
      final storage = await StorageService.getInstance();
      await storage.prefs.setString('library_order', '["srv:legacy"]');
      await storage.setActiveProfileId(profile);
      seen.clear();

      expect(storage.getLibraryOrder(), ['srv:legacy']);
      await pumpEventQueue();

      expect(seen.map((m) => m.source).toSet(), {PreferenceSource.migration});
    });
  });

  test('values still round-trip, so the rewiring changed the route and not the behaviour', () async {
    final storage = await storageWithProfile();

    await storage.saveHiddenLibraries({'srv:1', 'srv:2'});
    await storage.saveLibraryOrder(['srv:2', 'srv:1']);
    await storage.saveHomeRowOrder(profile, ['srv:hub1']);
    await storage.saveHiddenHomeRows(profile, {'srv:hub2'});
    await storage.saveLibraryGrouping('srv:1', 'movies');
    await storage.saveLibraryTab('srv:1', 'Recommended');
    await storage.saveLibrarySort('srv:1', 'title', descending: true);
    await storage.saveLibraryFilters({'genre': 'action'});

    expect(storage.getHiddenLibraries(), {'srv:1', 'srv:2'});
    expect(storage.getLibraryOrder(), ['srv:2', 'srv:1']);
    expect(storage.getHomeRowOrder(profile), ['srv:hub1']);
    expect(storage.getHiddenHomeRows(profile), {'srv:hub2'});
    expect(storage.getLibraryGrouping('srv:1'), 'movies');
    expect(storage.getLibraryTab('srv:1'), 'Recommended');
    expect(storage.getLibrarySort('srv:1'), {'key': 'title', 'descending': true});
    expect(storage.getLibraryFilters(), {'genre': 'action'});
  });
}
