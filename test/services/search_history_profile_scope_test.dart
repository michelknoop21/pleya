import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/profile/profile_delete_flow.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/search_recency_store.dart';
import 'package:pleya/services/search_recents.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

/// Z8 of the search analysis: search history and "Recent gezocht" were one
/// device-wide list, so a child profile saw what the parent searched and
/// opened. Both now live under the active profile's `user_<scope>_` prefix.
void main() {
  late StorageService storage;
  late SettingsService settings;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    storage = await StorageService.getInstance();
    settings = await SettingsService.getInstance();
  });

  MediaItem movie(String id) => MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Movie $id',
    serverId: 'server_1',
    serverName: 'Server',
  );

  test('two profiles keep separate query histories', () async {
    await storage.setActiveProfileId('parent');
    await SearchRecencyStore.writeHistory(['horror']);

    await storage.setActiveProfileId('child');
    expect(SearchRecencyStore.readHistory(), isEmpty);
    await SearchRecencyStore.writeHistory(['bluey']);

    await storage.setActiveProfileId('parent');
    expect(SearchRecencyStore.readHistory(), ['horror']);
  });

  test('opened titles are per profile too', () async {
    await storage.setActiveProfileId('parent');
    rememberSearchRecent(movie('m1'));

    await storage.setActiveProfileId('child');
    expect(readSearchRecents(), isEmpty);

    await storage.setActiveProfileId('parent');
    expect(readSearchRecents().map((item) => item.id), ['m1']);
  });

  test('the old device-wide lists are dropped, so every profile starts empty', () async {
    // Nobody can tell whose searches the pre-upgrade list holds; handing it to
    // whichever profile opens Zoeken first (the child, on a shared Apple TV)
    // is exactly the leak Z8 closes.
    await settings.write(SettingsService.searchHistory, ['dune']);
    await settings.write(SettingsService.searchRecentItems, const ['{"broken": true}']);

    await storage.setActiveProfileId('child');
    expect(SearchRecencyStore.readHistory(), isEmpty);
    expect(SearchRecencyStore.readRecentItems(), isEmpty);
    await pumpEventQueue();
    expect(settings.prefs.containsKey(SettingsService.searchHistory.key), isFalse);
    expect(settings.prefs.containsKey(SettingsService.searchRecentItems.key), isFalse);

    await storage.setActiveProfileId('parent');
    expect(SearchRecencyStore.readHistory(), isEmpty);
  });

  test('without an active profile nothing is read or written', () async {
    await SearchRecencyStore.writeHistory(['matrix']);
    rememberSearchRecent(movie('m3'));
    await pumpEventQueue();

    expect(SearchRecencyStore.readHistory(), isEmpty);
    expect(settings.prefs.containsKey(SettingsService.searchHistory.key), isFalse);
    expect(settings.prefs.containsKey(SettingsService.searchRecentItems.key), isFalse);
    await storage.setActiveProfileId('parent');
    expect(SearchRecencyStore.readHistory(), isEmpty, reason: 'nothing to migrate to the next profile');
    expect(readSearchRecents(), isEmpty);
  });

  test('deleting a profile drops its search recency and nobody else\'s', () async {
    await storage.setActiveProfileId('child');
    await SearchRecencyStore.writeHistory(['bluey']);
    rememberSearchRecent(movie('m2'));
    await storage.setActiveProfileId('parent');
    await SearchRecencyStore.writeHistory(['horror']);

    await SearchRecencyStore.clearForProfileScope(storage.userScopeForProfileId('child'));

    expect(SearchRecencyStore.readHistory(), ['horror']);
    await storage.setActiveProfileId('child');
    expect(SearchRecencyStore.readHistory(), isEmpty);
    expect(readSearchRecents(), isEmpty);
  });

  test('the profile delete flow takes the search recency along', () async {
    await storage.setActiveProfileId('child');
    await SearchRecencyStore.writeHistory(['bluey']);
    rememberSearchRecent(movie('m4'));

    await clearProfileScopedStores(storage, 'child');

    expect(SearchRecencyStore.readHistory(), isEmpty);
    expect(readSearchRecents(), isEmpty);
  });

  test('the sync policy keeps both lists on the device and out of exports', () {
    for (final key in const ['search_history', 'search_recent_items']) {
      expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isTrue, reason: key);
      expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse, reason: key);
      expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse, reason: key);
    }
  });
}
