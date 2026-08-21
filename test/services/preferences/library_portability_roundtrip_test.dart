import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// The six round-trips the library families have to survive once their identity
/// travels: two portable backends, one that is not, a mixed list, and a remote
/// apply that must not eat what it never saw.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);
  const plexId = 'plex-machine';
  const jellyfinId = 'jellyfin-machine';
  const localFolderId = 'local-row-1';

  bool isPortable(String serverId) => serverId == plexId || serverId == jellyfinId;

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({bool v2 = false}) async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: 'macbook',
      isServerIdPortable: isPortable,
      useV2CloudFormat: v2,
      transport: transport,
    );
  }

  String hiddenKey() => 'user_${homeUuid}_hidden_libraries';
  List<String> storedHidden() => (json.decode(settings.prefs.getString(hiddenKey())!) as List).cast<String>();
  List<String> cloudHidden() =>
      (json.decode(json.decode(transport.store['hidden_libraries']!)['value'] as String) as List).cast<String>();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  test('a Plex library entry travels', () async {
    final coordinator = await build();
    await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$plexId:12'])));

    expect(cloudHidden(), ['$plexId:12']);
  });

  test('a Jellyfin library entry travels', () async {
    final coordinator = await build();
    await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$jellyfinId:films'])));

    expect(cloudHidden(), ['$jellyfinId:films']);
  });

  test('a local-folder entry is never transported', () async {
    final coordinator = await build();
    await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$localFolderId:7'])));

    expect(
      transport.store.containsKey('hidden_libraries'),
      isFalse,
      reason: 'nothing portable in the list, so nothing to send',
    );
    expect(transport.removes, isEmpty, reason: 'and nothing to delete either');
  });

  test('a mixed list sends only the portable half', () async {
    final coordinator = await build();
    await coordinator.apply(
      PreferenceMutation.set(hiddenKey(), json.encode(['$plexId:12', '$localFolderId:7', '$jellyfinId:films'])),
    );

    expect(cloudHidden(), ['$plexId:12', '$jellyfinId:films']);
  });

  test('a remote apply keeps the local-folder entries it never saw', () async {
    // v2: only there does the cloud key name the profile, so an incoming
    // library record may be applied at all. Under v1 it is quarantined, which
    // the last two tests pin.
    final coordinator = await build(v2: true);
    await settings.prefs.setString(hiddenKey(), json.encode(['$plexId:12', '$localFolderId:7']));

    // The other device has no local folder, so its list simply lacks that
    // entry. Treating the absence as a removal would wipe it on every change.
    final cloudKey = coordinator.cloudKeyFor(hiddenKey())!;
    transport.store[cloudKey] = json.encode({
      'type': 'string',
      'value': json.encode(['$plexId:12', '$plexId:34']),
    });
    await coordinator.applyRemoteKeys([cloudKey]);

    expect(storedHidden(), ['$plexId:12', '$plexId:34', '$localFolderId:7']);
  });

  test('a portable entry removed on the other device really is removed here', () async {
    final coordinator = await build(v2: true);
    await settings.prefs.setString(hiddenKey(), json.encode(['$plexId:12', '$plexId:34', '$localFolderId:7']));

    final cloudKey = coordinator.cloudKeyFor(hiddenKey())!;
    transport.store[cloudKey] = json.encode({
      'type': 'string',
      'value': json.encode(['$plexId:12']),
    });
    await coordinator.applyRemoteKeys([cloudKey]);

    expect(storedHidden(), ['$plexId:12', '$localFolderId:7']);
  });

  test('a per-library key on a non-portable server is skipped whole', () async {
    final coordinator = await build();

    expect(coordinator.cloudKeyFor('user_${homeUuid}_library_sort_$plexId:12'), 'library_sort_$plexId:12');
    expect(
      coordinator.cloudKeyFor('user_${homeUuid}_library_sort_$localFolderId:7'),
      isNull,
      reason: 'the identity is in the key, so there is nothing to filter out of the value',
    );
  });

  test('reconcile pushes the filtered value, not the raw one', () async {
    final coordinator = await build();
    await settings.prefs.setString(hiddenKey(), json.encode(['$plexId:12', '$localFolderId:7']));

    await coordinator.reconcile();

    expect(cloudHidden(), ['$plexId:12']);
  });

  test('home rows stay local-only, and the reason is hub.identifier', () async {
    final coordinator = await build();

    expect(PreferenceSyncPolicyRegistry.maySync('home_row_order'), isFalse);
    expect(PreferenceSyncPolicyRegistry.maySync('hidden_home_rows'), isFalse);
    expect(coordinator.cloudKeyFor('user_${homeUuid}_home_row_order'), isNull);
    // Not because of serverId: that half is portable, same as the library
    // families above. It is `hub.identifier` that has not been shown to be the
    // same on two devices for the same hub.
    expect(coordinator.cloudKeyFor('user_${homeUuid}_hidden_libraries'), isNotNull);
  });

  test('under v1 an incoming library record is quarantined, not handed to the active profile', () async {
    final coordinator = await build();
    await settings.prefs.setString(hiddenKey(), json.encode(['$plexId:12']));

    // The v1 cloud key is bare `hidden_libraries`: the format stripped the
    // profile, so there is no way to tell whose it is.
    transport.store['hidden_libraries'] = json.encode({
      'type': 'string',
      'value': json.encode(['$plexId:99']),
    });
    await coordinator.applyRemoteKeys(['hidden_libraries']);

    expect(storedHidden(), ['$plexId:12'], reason: 'the active profile does not inherit an unowned record');
  });
}
