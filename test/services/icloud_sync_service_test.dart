import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/icloud_sync_service.dart';
import 'package:pleya/services/settings_service.dart';

import '../test_helpers/prefs.dart';

// The native KVS plugin is faked with an in-memory store behind a mock method
// channel. These tests exercise the pure Dart logic: eligibility filtering,
// typed encode/decode, remote-apply (with no echo back to KVS), the enable
// merge order, and stale-key pruning in pushAll.

String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pleya/icloud_kvs');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Map<String, String> kvs;
  late bool failGetAll;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    kvs = {};
    failGetAll = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getAll':
          if (failGetAll) throw PlatformException(code: 'ERR', message: 'channel down');
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

  test('eligible write mirrors to KVS as typed JSON; the toggle itself never syncs', () async {
    final settings = await SettingsService.getInstance();
    ICloudSyncService.debugCreate(settings: settings);

    await settings.write(SettingsService.icloudSyncEnabled, true);
    await settings.write(SettingsService.subtitleFontSize, 44);
    await pumpEventQueue();

    expect(kvs['subtitle_font_size'], enc('int', 44));
    expect(kvs.containsKey('icloud_sync_enabled'), isFalse);
  });

  test('denylisted key (plex_token) is never pushed', () async {
    final settings = await SettingsService.getInstance();
    ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);

    // plex_token is written by StorageService via raw prefs; drive the hook
    // directly to prove the filter drops it even if it ever flowed through.
    await settings.prefs.setString('plex_token', 'secret');
    BaseSharedPreferencesService.onKeyWritten!('plex_token');
    await pumpEventQueue();

    expect(kvs.containsKey('plex_token'), isFalse);
  });

  test('remote change applies to prefs without echoing back to KVS', () async {
    final settings = await SettingsService.getInstance();
    final svc = ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);
    kvs.clear(); // drop the toggle-driven meta churn; isolate the apply

    kvs['subtitle_font_size'] = enc('int', 60);
    final snapshot = Map<String, String>.from(kvs);

    var applied = 0;
    svc.onRemoteChangesApplied = () => applied++;
    await svc.debugHandleEvent({
      'reason': 0,
      'changedKeys': ['subtitle_font_size'],
    });
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 60);
    expect(applied, 1);
    // No echo: applying a remote change must not write anything back to KVS.
    expect(kvs, snapshot);
  });

  test('remote removal (key absent in getAll) clears the local value', () async {
    final settings = await SettingsService.getInstance();
    final svc = ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);
    await settings.write(SettingsService.subtitleFontSize, 44);
    await pumpEventQueue();

    // Peer removed the key; changedKeys names it but getAll no longer has it.
    kvs.remove('subtitle_font_size');
    await svc.debugHandleEvent({
      'reason': 0,
      'changedKeys': ['subtitle_font_size'],
    });
    await pumpEventQueue();

    expect(settings.prefs.getInt('subtitle_font_size'), isNull);
  });

  test('enable merges: remote wins on shared keys, local-unique keys uploaded', () async {
    final settings = await SettingsService.getInstance();
    // Seed local state directly (no hook yet).
    await settings.prefs.setInt('subtitle_font_size', 30);
    await settings.prefs.setInt('seek_time_small', 5);
    // Remote state: conflicting font size + a remote-only key.
    kvs['subtitle_font_size'] = enc('int', 99);
    kvs['volume'] = enc('double', 50.0);

    final svc = ICloudSyncService.debugCreate(settings: settings);
    await svc.enable();
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 99, reason: 'remote wins');
    expect(settings.prefs.getDouble('volume'), 50.0, reason: 'remote-only applied locally');
    expect(kvs['seek_time_small'], enc('int', 5), reason: 'local-unique uploaded');
    expect(kvs[ICloudSyncService.metaVersionKey], enc('int', ICloudSyncService.formatVersion));
  });

  test('transient getAll failure during a remote event does not delete local settings', () async {
    final settings = await SettingsService.getInstance();
    final svc = ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);
    await settings.write(SettingsService.subtitleFontSize, 44);
    await pumpEventQueue();

    // Channel read fails while a change notification names the key — must not
    // be read as "removed remotely".
    failGetAll = true;
    await svc.debugHandleEvent({
      'reason': 0,
      'changedKeys': ['subtitle_font_size'],
    });
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 44);
  });

  test('pushAll with no signed-in user does not delete another account\'s user-scoped cloud keys', () async {
    final settings = await SettingsService.getInstance();
    kvs['hidden_libraries'] = enc('string', '["lib1"]'); // from another device's user
    await settings.prefs.setInt('seek_time_small', 8);

    final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => null);
    await svc.pushAll();
    await pumpEventQueue();

    expect(kvs.containsKey('hidden_libraries'), isTrue, reason: 'no user → cannot own or delete it');
    expect(kvs['seek_time_small'], enc('int', 8));
  });

  test('pushAll removes KVS keys that no longer exist locally, keeps meta', () async {
    final settings = await SettingsService.getInstance();
    await settings.prefs.setInt('seek_time_small', 8);
    kvs['stale_key'] = enc('int', 1);
    kvs[ICloudSyncService.metaVersionKey] = enc('int', 1);

    final svc = ICloudSyncService.debugCreate(settings: settings);
    await svc.pushAll();
    await pumpEventQueue();

    expect(kvs.containsKey('stale_key'), isFalse);
    expect(kvs['seek_time_small'], enc('int', 8));
    expect(kvs.containsKey(ICloudSyncService.metaVersionKey), isTrue);
  });
}
