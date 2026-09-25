import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
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
    await settings.write(settings.profileSearchHistory, ['horror']);

    await storage.setActiveProfileId('child');
    expect(settings.read(settings.profileSearchHistory), isEmpty);
    await settings.write(settings.profileSearchHistory, ['bluey']);

    await storage.setActiveProfileId('parent');
    expect(settings.read(settings.profileSearchHistory), ['horror']);
  });

  test('opened titles are per profile too', () async {
    await storage.setActiveProfileId('parent');
    rememberSearchRecent(movie('m1'));

    await storage.setActiveProfileId('child');
    expect(readSearchRecents(), isEmpty);

    await storage.setActiveProfileId('parent');
    expect(readSearchRecents().map((item) => item.id), ['m1']);
  });

  test('the old device-wide list moves to the first profile that reads it, once', () async {
    await settings.write(SettingsService.searchHistory, ['dune']);
    await settings.write(SettingsService.searchRecentItems, const ['{"broken": true}']);

    await storage.setActiveProfileId('parent');
    expect(settings.read(settings.profileSearchHistory), ['dune']);
    expect(settings.read(settings.profileSearchRecentItems), ['{"broken": true}']);
    expect(settings.read(SettingsService.searchHistory), isEmpty, reason: 'migrated, not copied');

    await storage.setActiveProfileId('child');
    expect(settings.read(settings.profileSearchHistory), isEmpty, reason: 'a second profile does not inherit it');
  });

  test('without an active profile the device-wide key is used as before', () async {
    await settings.write(settings.profileSearchHistory, ['matrix']);
    expect(settings.read(SettingsService.searchHistory), ['matrix']);
  });

  test('deleting a profile drops its search recency and nobody else\'s', () async {
    await storage.setActiveProfileId('child');
    await settings.write(settings.profileSearchHistory, ['bluey']);
    rememberSearchRecent(movie('m2'));
    await storage.setActiveProfileId('parent');
    await settings.write(settings.profileSearchHistory, ['horror']);

    await settings.clearSearchRecencyForProfileScope(storage.userScopeForProfileId('child'));

    expect(settings.read(settings.profileSearchHistory), ['horror']);
    await storage.setActiveProfileId('child');
    expect(settings.read(settings.profileSearchHistory), isEmpty);
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
