import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/icloud_sync_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';

/// Where the preference engine stops.
///
/// After `migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary`,
/// the legacy `SharedPreferences` store and the `SharedPreferencesWithCache`
/// store are two separate stores: the migration copies once and deletes
/// nothing, and the "already migrated" flag lives in the destination, so it
/// never runs again. Five services still write to the legacy one
/// (`local_folder_client`, `favorite_channels_repository`,
/// `local_server_match_service`, and the two `pleya_share` services).
///
/// The consequence for `local_progress_*` is worse than a missed sync: two
/// values exist. The live one sits in the legacy store where the push cannot
/// see it, and a frozen copy from the migration moment sits in the cache store
/// where the push can. Uploading that copy would put a ghost in the cloud.
///
/// These tests pin the boundary rather than the plumbing, so they keep working
/// if the plumbing is rewritten again.
String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pleya/icloud_kvs');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Map<String, String> kvs;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    kvs = {};
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getAll':
          return Map<String, String>.from(kvs);
        case 'set':
          final args = call.arguments as Map;
          kvs[args['key'] as String] = args['value'] as String;
          return null;
        case 'remove':
          kvs.remove((call.arguments as Map)['key']);
          return null;
        case 'synchronize':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    ICloudSyncService.debugReset();
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('the legacy store namespace never reaches the cloud', () {
    test('a `flutter.`-prefixed key is not pushed by a reconcile', () async {
      final settings = await SettingsService.getInstance();
      // What a frozen legacy copy looks like on Apple, where both stores share
      // the UserDefaults domain and only the key name differs.
      await settings.prefs.setString('flutter.local_progress_srv1', '{"item":42}');
      await settings.prefs.setInt('flutter.subtitle_font_size', 30);
      await settings.prefs.setInt('subtitle_font_size', 44);

      final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => 'someone');
      await svc.pushAll();
      await pumpEventQueue();

      expect(kvs.keys.where((k) => k.startsWith('flutter.')), isEmpty);
      expect(
        kvs['__pleya_pref_v2/global/subtitle_font_size'],
        enc('int', 44),
        reason: 'the real key still syncs, now under the v2 namespace',
      );
    });

    test('a `flutter.`-prefixed key is not pushed by a single write either', () async {
      final settings = await SettingsService.getInstance();
      final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => 'someone');
      await settings.write(SettingsService.icloudSyncEnabled, true);
      kvs.clear();

      await settings.prefs.setInt('flutter.subtitle_font_size', 30);
      await BaseSharedPreferencesService.notifyMutation(const PreferenceMutation.set('flutter.subtitle_font_size', 30));
      await pumpEventQueue();

      expect(kvs.keys.where((k) => k.startsWith('flutter.')), isEmpty);
      expect(svc, isNotNull);
    });
  });

  group('the named historic legacy keys are not preferences this engine owns', () {
    test('local playback bookkeeping stays out of the cloud', () async {
      final settings = await SettingsService.getInstance();
      // The frozen cache-store copies from the migration moment. The live
      // values live in the legacy store, so pushing these uploads a ghost.
      await settings.prefs.setString('local_progress_folder1', '{"a":10}');
      await settings.prefs.setString('local_watched_folder1', '{"a":true}');
      await settings.prefs.setString('local_server_match_v1', '{"cached":true}');

      final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => 'someone');
      await svc.pushAll();
      await pumpEventQueue();

      for (final key in ['local_progress_folder1', 'local_watched_folder1', 'local_server_match_v1']) {
        expect(kvs.containsKey(key), isFalse, reason: key);
      }
    });

    test('Pleya Share credentials stay local', () async {
      final settings = await SettingsService.getInstance();
      await settings.prefs.setString('pleya_share_tokens', '{"tok":"secret"}');
      await settings.prefs.setString('pleya_share_guests', '[{"id":"g"}]');
      await settings.prefs.setString('pleya_share_relay_host_id', 'host-abc');
      await settings.prefs.setString('pleya_share_watch_pair1', '{"p":1}');

      final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => 'someone');
      await svc.pushAll();
      await pumpEventQueue();

      expect(kvs.keys.where((k) => k.startsWith('pleya_share_')), isEmpty);
    });

    test('the classification is on the key, so an inbound one is refused too', () async {
      final settings = await SettingsService.getInstance();
      final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => 'someone');
      await settings.write(SettingsService.icloudSyncEnabled, true);

      // An older Pleya version put progress in the cloud. Reading it back must
      // not write it into a store that nothing reads.
      kvs['local_progress_folder1'] = enc('string', '{"a":99}');
      await svc.debugHandleEvent({
        'reason': 0,
        'changedKeys': ['local_progress_folder1'],
      });
      await pumpEventQueue();

      expect(settings.prefs.getString('local_progress_folder1'), isNull);
    });
  });

  group('the mergeProgressMaps verdict', () {
    test('it still parses legacy inbound data correctly', () {
      // Kept as legacy inbound compatibility, so older clouds are read without
      // corruption. Its removal condition is written on the method.
      expect(ICloudSyncService.mergeProgressMaps('{"a":10}', '{"a":20,"b":5}', watchedMap: false), '{"a":20,"b":5}');
      expect(ICloudSyncService.mergeProgressMaps('{"a":true}', '{"a":false}', watchedMap: true), '{"a":true}');
    });

    test('the keys it serves are classified as runtime cache, which is what makes it unreachable', () {
      for (final key in ['local_progress_x', 'local_watched_x']) {
        expect(PreferenceSyncPolicyRegistry.policyFor(key).sensitivity, PreferenceSensitivity.runtimeCache);
        expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
      }
    });
  });
}
