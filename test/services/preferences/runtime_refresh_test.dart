import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_refresh.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// A9 and review constraint R4. Every assertion here is on what the provider
/// *shows* after a remote apply. "A callback fired" is not the property: the
/// bug was that the value in storage was right while the screen kept the copy
/// it read at construction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const uuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: uuid);
  const plexId = 'plex-machine';

  late SettingsService settings;
  late StorageService storage;
  late FakeTransport transport;
  late PreferenceRefreshBus bus;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    storage = await StorageService.getInstance();
    transport = FakeTransport();
    bus = PreferenceRefreshBus();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: 'macbook',
      isServerIdPortable: (id) => id == plexId,
      transport: transport,
    )..onRuntimeRefresh = bus.invalidate;
  }

  String encList(List<String> entries) => json.encode({'type': 'string', 'value': json.encode(entries)});

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() async {
    BaseSharedPreferencesService.onMutation = null;
    await bus.dispose();
  });

  test('a remotely hidden library shows up in the provider without a restart', () async {
    final coordinator = await build();
    final provider = HiddenLibrariesProvider(storageService: storage, profileId: profile, refreshBus: bus);
    await provider.ensureInitialized();
    expect(provider.hiddenLibraryKeys, isEmpty);

    await coordinator.applyEntries({
      coordinator.cloudKeyFor('user_${uuid}_hidden_libraries')!: encList(['$plexId:12']),
    });
    await Future<void>.delayed(Duration.zero);

    expect(provider.hiddenLibraryKeys, contains('$plexId:12'));
    expect(provider.isLibraryHidden('$plexId:12'), isTrue);
    provider.dispose();
  });

  test('a remote unhide removes it from the provider too', () async {
    final coordinator = await build();
    await settings.prefs.setString('user_${uuid}_hidden_libraries', json.encode(['$plexId:12']));
    final provider = HiddenLibrariesProvider(storageService: storage, profileId: profile, refreshBus: bus);
    await provider.ensureInitialized();
    expect(provider.hiddenLibraryKeys, contains('$plexId:12'));

    await coordinator.applyEntries({coordinator.cloudKeyFor('user_${uuid}_hidden_libraries')!: encList(<String>[])});
    await Future<void>.delayed(Duration.zero);

    expect(provider.hiddenLibraryKeys, isEmpty);
    provider.dispose();
  });

  test('a remote library order re-sorts the list already on screen, without a fetch', () async {
    final coordinator = await build();
    // LibrariesProvider reads the order through the active profile, not through
    // a passed-in id, so the app-level active profile has to be the same one.
    await storage.setActiveProfileId(profile);
    final provider = LibrariesProvider(storageService: storage, refreshBus: bus);
    provider.debugSetLibraries([
      const MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Films', serverId: plexId),
      const MediaLibrary(id: '2', backend: MediaBackend.plex, title: 'Series', serverId: plexId),
    ]);
    expect(provider.libraries.map((l) => l.id), ['1', '2']);

    await coordinator.applyEntries({
      coordinator.cloudKeyFor('user_${uuid}_library_order')!: encList(['$plexId:2', '$plexId:1']),
    });
    await Future<void>.delayed(Duration.zero);

    expect(provider.libraries.map((l) => l.id), ['2', '1']);
    provider.dispose();
  });

  test('the home layout reloads on the local signal an import or reset raises', () async {
    await build();
    final provider = HomeLayoutProvider(storageService: storage, profileId: profile, refreshBus: bus);
    await provider.ensureInitialized();
    expect(provider.hiddenRowIds, isEmpty);

    // What an import does: write straight to storage, then announce.
    await storage.saveHiddenHomeRows(profile, {'$plexId:home.continue'});
    bus.invalidateAll();
    await Future<void>.delayed(Duration.zero);

    expect(provider.hiddenRowIds, contains('$plexId:home.continue'));
    provider.dispose();
  });

  test('the home layout provider reloads after it is initialised, which the init guard blocked', () async {
    await build();
    final provider = HomeLayoutProvider(storageService: storage, profileId: profile, refreshBus: bus);
    await provider.ensureInitialized();

    await storage.saveHomeRowOrder(profile, ['b', 'a']);
    await provider.refresh();

    expect(provider.order, ['b', 'a']);
    provider.dispose();
  });

  test('a device-local preference does not invalidate anything', () async {
    final coordinator = await build();
    var announced = 0;
    final sub = bus.changes.listen((_) => announced++);

    await coordinator.applyEntries({
      coordinator.cloudKeyFor('subtitle_font_size')!: json.encode({'type': 'int', 'value': 44}),
    });
    await Future<void>.delayed(Duration.zero);

    expect(announced, 0);
    await sub.cancel();
  });

  test('a provider that was disposed does not reload', () async {
    final coordinator = await build();
    final provider = HiddenLibrariesProvider(storageService: storage, profileId: profile, refreshBus: bus);
    await provider.ensureInitialized();
    provider.dispose();

    await coordinator.applyEntries({
      coordinator.cloudKeyFor('user_${uuid}_hidden_libraries')!: encList(['$plexId:12']),
    });
    await Future<void>.delayed(Duration.zero);

    // No "used after dispose" assert, and the disposed provider kept its state.
    expect(provider.hiddenLibraryKeys, isEmpty);
  });
}
