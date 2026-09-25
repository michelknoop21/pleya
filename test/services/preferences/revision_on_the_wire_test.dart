import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (2) and (3). The envelope leaves the device with every record and
/// decides on arrival. A record without a stamp is one the previous build
/// wrote and counts as the oldest possible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String deviceId = 'macbook'}) async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: deviceId,
      transport: transport,
    );
  }

  String bare(String type, Object? value) => json.encode({'type': type, 'value': value});
  String stamped(String type, Object? value, int at, String device) =>
      json.encode({'type': type, 'value': value, 't': at, 'd': device});
  String tombstone(int at, String device) => json.encode({'x': true, 't': at, 'd': device});
  Map<String, dynamic> record(PreferenceSyncCoordinator c, String baseKey) =>
      json.decode(transport.store[c.cloudKeyFor(baseKey)!]!) as Map<String, dynamic>;
  int future() => DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 60 * 1000;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('outbound', () {
    test('a write carries its stamp next to the typed value', () async {
      final coordinator = await build();

      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      final r = record(coordinator, 'subtitle_font_size');
      expect(r['type'], 'int');
      expect(r['value'], 44);
      expect(r['t'], isA<int>());
      expect(r['t'], greaterThan(0));
      expect(r['d'], 'macbook');
    });

    test('the meta record stays a bare typed value', () async {
      final coordinator = await build();

      await coordinator.reconcile();

      final meta = json.decode(transport.store[PreferenceSyncCoordinator.v2MetaVersionKey]!) as Map;
      expect(meta.containsKey('t'), isFalse);
    });
  });

  group('inbound', () {
    test('an older remote record does not overwrite a newer local change', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, 1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('a newer remote record wins and its stamp is adopted', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final at = future();
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, at, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 99);
      final adopted = coordinator.localRevision('subtitle_font_size')!;
      expect(adopted.updatedAt, at);
      expect(adopted.deviceId, 'appletv');
    });

    test('a later local change stamps past an adopted remote stamp', () async {
      final coordinator = await build();
      final at = future();
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, at, 'appletv');
      await coordinator.applyAllRemote();

      await settings.prefs.setInt('subtitle_font_size', 50);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 50));

      expect(coordinator.localRevision('subtitle_font_size')!.updatedAt, greaterThan(at));
      expect(record(coordinator, 'subtitle_font_size')['value'], 50);
    });

    test('a record from the previous build beats an unstamped local value: the store wins', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 30);
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = bare('int', 99);

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 99, reason: 'two unstamped sides: the store wins');
    });

    test('a stamped local value beats a record from the previous build', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = bare('int', 99);

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('an identical stamp on both sides applies nothing', () async {
      final coordinator = await build();
      final at = future();
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, at, 'appletv');
      await coordinator.applyAllRemote();
      final applied = coordinator.status.value.applied;

      await coordinator.applyAllRemote();

      expect(coordinator.status.value.applied, applied);
    });

    test('a newer tombstone removes the local value and is remembered', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = tombstone(future(), 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), isNull);
      expect(coordinator.localRevision('subtitle_font_size')!.deleted, isTrue);
    });

    test('an older tombstone does not remove a newer local value', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = tombstone(1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('a key named in the event but absent from the store is still removed, as the previous build did', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);

      await coordinator.applyRemoteKeys([coordinator.cloudKeyFor('subtitle_font_size')!]);

      expect(settings.prefs.getInt('subtitle_font_size'), isNull);
    });

    test('an absent-key removal resets an adopted stamp, so a later lower-stamped record still lands', () async {
      final coordinator = await build();
      final cloudKey0 = coordinator.cloudKeyFor('subtitle_font_size')!;
      // Adopted from the previous build: unstamped, so a bare remove still
      // applies (a stamped local value survives it, see store_convergence_test).
      transport.store[cloudKey0] = bare('int', 44);
      await coordinator.applyAllRemote();
      expect(settings.prefs.getInt('subtitle_font_size'), 44);
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      transport.store.remove(cloudKey);
      await coordinator.applyRemoteKeys([cloudKey]);
      expect(settings.prefs.getInt('subtitle_font_size'), isNull);

      transport.store[cloudKey] = stamped('int', 70, 1000, 'appletv');
      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 70, reason: 'a live stamp without a value must not block it');
    });

    test('on an equal timestamp the higher device id wins', () async {
      final coordinator = await build();
      final at = future();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      transport.store[cloudKey] = stamped('int', 50, at, 'macmini');
      await coordinator.applyAllRemote();

      transport.store[cloudKey] = stamped('int', 60, at, 'appletv');
      await coordinator.applyAllRemote();
      expect(settings.prefs.getInt('subtitle_font_size'), 50, reason: "'appletv' sorts below 'macmini'");

      transport.store[cloudKey] = stamped('int', 70, at, 'tv-zz');
      await coordinator.applyAllRemote();
      expect(settings.prefs.getInt('subtitle_font_size'), 70, reason: "'tv-zz' sorts above 'macmini'");
      expect(coordinator.localRevision('subtitle_font_size')!.deviceId, 'tv-zz');
    });

    test('a merge family merges regardless of the stamp', () async {
      final coordinator = await build();
      coordinator.serverIdPortability = (id) => id == 'plex';
      final key = 'user_${homeUuid}_hidden_libraries';
      await settings.prefs.setString(key, json.encode(['plex:1', 'folder:9']));
      await coordinator.apply(PreferenceMutation.set(key, json.encode(['plex:1', 'folder:9'])));
      transport.store[coordinator.cloudKeyFor(key)!] = stamped('string', json.encode(['plex:2']), 1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(json.decode(settings.prefs.getString(key)!), unorderedEquals(['plex:2', 'folder:9']));
    });
  });

  // The rule for a local value without a stamp: it is older than any stamped
  // remote record. Unstamped means nobody wrote it through the pipeline: a
  // value from before the revision store, a write before start() installed the
  // hook, or a migration. A user's write in this session is always stamped,
  // including one that lands inside a remote batch.
  group('an unstamped local value', () {
    test('loses to any stamped remote record, however old', () async {
      final coordinator = await build();
      // Written past the pipeline, as anything before start() is.
      await settings.prefs.setInt('subtitle_font_size', 30);
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, 1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 99);
    });

    test('a bootstrapped legacy value also loses to a stamped remote record', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 30);
      await coordinator.bootstrapLegacyRevision('subtitle_font_size');
      transport.store[coordinator.cloudKeyFor('subtitle_font_size')!] = stamped('int', 99, 1000, 'appletv');

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 99);
    });

    test('a user write inside a remote batch is stamped and beats the batch', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 30);
      final batch = coordinator.applyEntries({
        coordinator.cloudKeyFor('seek_time_small')!: stamped('int', 9, future(), 'appletv'),
        coordinator.cloudKeyFor('subtitle_font_size')!: stamped('int', 99, 1000, 'appletv'),
      });

      // applyEntries is parked on its first write, so this lands in the window.
      await settings.prefs.setInt('subtitle_font_size', 50);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 50));
      await batch;

      expect(coordinator.localRevision('subtitle_font_size')!.deviceId, 'macbook');
      expect(
        settings.prefs.getInt('subtitle_font_size'),
        50,
        reason: 'the older remote record lost to the fresh stamp',
      );
      expect(settings.prefs.getInt('seek_time_small'), 9);
    });
  });
}
