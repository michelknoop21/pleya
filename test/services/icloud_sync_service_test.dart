import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/icloud_sync_service.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';
import 'preferences/fake_transport.dart';

// The native KVS plugin is faked with an in-memory store behind a mock method
// channel. These tests exercise the pure Dart logic: eligibility filtering,
// typed encode/decode, remote-apply (with no echo back to KVS), the enable
// merge order, and that pushAll prunes nothing under v2.

String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

/// After the v2 cutover the store key is namespaced. These helpers keep the
/// tests about behaviour rather than about string shapes.
String g(String key) => '${PreferenceSyncScope.cloudNamespacePrefix}global/$key';
String p(String scope, String key) => '${PreferenceSyncScope.cloudNamespacePrefix}profile/$scope/$key';

/// The value inside a wire record, whatever else the record carries.
Object? valueOf(String? raw) => raw == null ? null : (json.decode(raw) as Map)['value'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pleya/icloud_kvs');
  const eventsChannel = MethodChannel('com.pleya/icloud_kvs/events');
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
    messenger.setMockMethodCallHandler(eventsChannel, (call) async => null); // 'listen' and 'cancel'
  });

  tearDown(() {
    ICloudSyncService.debugReset();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(eventsChannel, null);
  });

  test('eligible write mirrors to KVS as typed JSON; the toggle itself never syncs', () async {
    final settings = await SettingsService.getInstance();
    ICloudSyncService.debugCreate(settings: settings);

    await settings.write(SettingsService.icloudSyncEnabled, true);
    await settings.write(SettingsService.subtitleFontSize, 44);
    await pumpEventQueue();

    expect(valueOf(kvs[g('subtitle_font_size')]), 44);
    expect(kvs.containsKey(g('icloud_sync_enabled')), isFalse);
  });

  test('denylisted key (plex_token) is never pushed', () async {
    final settings = await SettingsService.getInstance();
    ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);

    // plex_token is written by StorageService via raw prefs; drive the pipeline
    // directly to prove the filter drops it even if it ever flowed through.
    await settings.prefs.setString('plex_token', 'secret');
    await BaseSharedPreferencesService.notifyMutation(const PreferenceMutation.set('plex_token', 'secret'));
    await pumpEventQueue();

    expect(kvs.containsKey(g('plex_token')), isFalse);
  });

  test('remote change applies to prefs without echoing back to KVS', () async {
    final settings = await SettingsService.getInstance();
    final svc = ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);
    kvs.clear(); // drop the toggle-driven meta churn; isolate the apply

    kvs[g('subtitle_font_size')] = enc('int', 60);
    final snapshot = Map<String, String>.from(kvs);

    var applied = 0;
    svc.onRemoteChangesApplied = () => applied++;
    await svc.debugHandleEvent({
      'reason': 0,
      'changedKeys': [g('subtitle_font_size')],
    });
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 60);
    expect(applied, 1);
    // No echo: applying a remote change must not write anything back to KVS.
    expect(kvs, snapshot);
  });

  test('adopting a stamped remote record through the real hook sends nothing back', () async {
    final settings = await SettingsService.getInstance();
    final fake = FakeTransport();
    final svc = ICloudSyncService.debugCreate(settings: settings, transport: fake);
    await svc.enable();
    await settings.write(SettingsService.subtitleFontSize, 44);
    await pumpEventQueue();
    fake.writes.clear();

    final later = DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 1000;
    fake.store[g('subtitle_font_size')] = json.encode({'type': 'int', 'value': 61, 't': later, 'd': 'appletv'});
    fake.controller.add(
      RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [g('subtitle_font_size')]),
    );
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 61);
    expect(
      svc.coordinator.localRevision('subtitle_font_size')!.updatedAt,
      later,
      reason: 'the remote stamp is adopted',
    );
    expect(fake.writes, isEmpty, reason: 'an adopted record must not echo');
  });

  test('remote removal (key absent in getAll) clears the local value', () async {
    final settings = await SettingsService.getInstance();
    final svc = ICloudSyncService.debugCreate(settings: settings);
    await settings.write(SettingsService.icloudSyncEnabled, true);
    await settings.write(SettingsService.subtitleFontSize, 44);
    await pumpEventQueue();

    // Peer removed the key; changedKeys names it but getAll no longer has it.
    kvs.remove(g('subtitle_font_size'));
    await svc.debugHandleEvent({
      'reason': 0,
      'changedKeys': [g('subtitle_font_size')],
    });
    await pumpEventQueue();

    expect(settings.prefs.getInt('subtitle_font_size'), isNull);
  });

  test('enable merges: remote wins on shared keys, local-unique keys uploaded', () async {
    final settings = await SettingsService.getInstance();
    // Seed local state directly (no hook yet).
    await settings.prefs.setInt('subtitle_font_size', 30);
    await settings.prefs.setInt('seek_time_small', 5);
    // Remote state: conflicting font size, a syncable remote-only key, and a
    // device-local one that must be ignored however it got into the store.
    kvs[g('subtitle_font_size')] = enc('int', 99);
    kvs[g('sleep_timer_duration')] = enc('int', 45);
    kvs[g('volume')] = enc('double', 50.0);

    final svc = ICloudSyncService.debugCreate(settings: settings);
    await svc.enable();
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 99, reason: 'remote wins');
    expect(settings.prefs.getInt('sleep_timer_duration'), 45, reason: 'remote-only applied locally');
    expect(
      settings.prefs.getDouble('volume'),
      isNull,
      reason: 'volume describes the speakers in front of this device, not a preference to share',
    );
    expect(valueOf(kvs[g('seek_time_small')]), 5, reason: 'local-unique uploaded');
    expect(kvs[PreferenceSyncCoordinator.v2MetaVersionKey], enc('int', PreferenceSyncCoordinator.v2FormatVersion));
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
      'changedKeys': [g('subtitle_font_size')],
    });
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 44);
  });

  test('pushAll with no signed-in user does not delete another account\'s user-scoped cloud keys', () async {
    final settings = await SettingsService.getInstance();
    kvs[p('someone-else', 'hidden_libraries')] = enc('string', '["lib1"]'); // another profile
    await settings.prefs.setInt('seek_time_small', 8);
    await settings.write(SettingsService.icloudSyncEnabled, true);

    final svc = ICloudSyncService.debugCreate(settings: settings, activeUserScope: () => null);
    await svc.pushAll();
    await pumpEventQueue();

    expect(
      kvs.containsKey(p('someone-else', 'hidden_libraries')),
      isTrue,
      reason: 'not our profile, so not ours to delete',
    );
    expect(valueOf(kvs[g('seek_time_small')]), 8);
  });

  test('pushAll leaves keys this device lacks in the store, and keeps meta and foreign keys', () async {
    final settings = await SettingsService.getInstance();
    await settings.prefs.setInt('seek_time_small', 8);
    // A registered preference this device does not hold. Since DEC-131 a
    // removal travels as a tombstone, so absence here means "not seen yet".
    kvs[g('theme_mode')] = enc('string', 'dark');
    // A key nobody registered. It might belong to another feature or a newer
    // Pleya; deleting it because we do not recognise it is not the coordinator's
    // call.
    kvs['stale_key'] = enc('int', 1);
    kvs[PreferenceSyncCoordinator.v2MetaVersionKey] = enc('int', 2);
    await settings.write(SettingsService.icloudSyncEnabled, true);

    final svc = ICloudSyncService.debugCreate(settings: settings);
    await svc.pushAll();
    await pumpEventQueue();

    expect(
      kvs.containsKey(g('theme_mode')),
      isTrue,
      reason: 'an import is local-first, and nothing is pruned since DEC-131',
    );
    expect(kvs.containsKey('stale_key'), isTrue);
    expect(valueOf(kvs[g('seek_time_small')]), 8);
    expect(kvs.containsKey(PreferenceSyncCoordinator.v2MetaVersionKey), isTrue);
  });

  test('start() subscribes to the transport, so a remote change lands without a reconcile', () async {
    final settings = await SettingsService.getInstance();
    final storage = await StorageService.getInstance();
    await settings.write(SettingsService.icloudSyncEnabled, true);
    final fake = FakeTransport();
    ICloudSyncService.debugForceSupported = true;
    await ICloudSyncService.start(settings: settings, storage: storage, transport: fake);
    fake.store[g('subtitle_font_size')] = enc('int', 61);

    fake.controller.add(
      RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [g('subtitle_font_size')]),
    );
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 61, reason: 'the production wiring must listen');
  });

  test('disable followed by enable keeps syncing in the same session, both ways', () async {
    final settings = await SettingsService.getInstance();
    final fake = FakeTransport();
    final svc = ICloudSyncService.debugCreate(settings: settings, transport: fake);
    await svc.enable();
    await svc.disable();
    await svc.enable();

    await settings.write(SettingsService.subtitleFontSize, 52);
    await pumpEventQueue();

    expect(svc.status.value.availability, PreferenceSyncAvailability.ready);
    expect(valueOf(fake.store[g('subtitle_font_size')]), 52, reason: 'outgoing still reaches the store');

    // Another device's later change. A stamp-less record would lose to the
    // stamped local 52, so it carries one, as this build writes it.
    final later = DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 1000;
    fake.store[g('subtitle_font_size')] = json.encode({'type': 'int', 'value': 63, 't': later, 'd': 'appletv'});
    fake.controller.add(
      RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [g('subtitle_font_size')]),
    );
    await pumpEventQueue();

    expect(settings.read(SettingsService.subtitleFontSize), 63, reason: 'incoming still reaches this device');
  });

  test('switching sync off clears a quota stop, so the next session starts clean', () async {
    final settings = await SettingsService.getInstance();
    final fake = FakeTransport();
    final svc = ICloudSyncService.debugCreate(settings: settings, transport: fake);
    await svc.enable();
    fake.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.quotaExceeded));
    await pumpEventQueue();
    expect(svc.status.value.state, PreferenceSyncState.quota);

    await svc.disable();
    await svc.enable();

    expect(svc.status.value.state, PreferenceSyncState.success);
  });

  test('a write during start-up cannot report a send from a signed-out device', () async {
    final settings = await SettingsService.getInstance();
    final storage = await StorageService.getInstance();
    await settings.write(SettingsService.icloudSyncEnabled, true);
    final fake = _GatedTransport()..available = false;
    ICloudSyncService.debugForceSupported = true;

    final starting = ICloudSyncService.start(settings: settings, storage: storage, transport: fake);
    // Park start() inside its first availability check, then write.
    while (!fake.asked) {
      await Future<void>.delayed(Duration.zero);
    }
    await settings.write(SettingsService.subtitleFontSize, 47);
    fake.gate.complete();
    await starting;
    await pumpEventQueue();

    expect(fake.writes, isEmpty);
    expect(ICloudSyncService.instance!.status.value.lastSuccess, isNull);
    expect(ICloudSyncService.instance!.status.value.state, PreferenceSyncState.unavailable);
  });

  test('a write during start-up is stamped, and only its send waits for availability', () async {
    final settings = await SettingsService.getInstance();
    final storage = await StorageService.getInstance();
    await settings.write(SettingsService.icloudSyncEnabled, true);
    final fake = _GatedTransport();
    ICloudSyncService.debugForceSupported = true;

    final starting = ICloudSyncService.start(settings: settings, storage: storage, transport: fake);
    while (!fake.asked) {
      await Future<void>.delayed(Duration.zero);
    }
    await settings.write(SettingsService.subtitleFontSize, 47);
    expect(fake.writes, isEmpty, reason: 'availability is not known yet');
    fake.gate.complete();
    await starting;
    await pumpEventQueue();

    final stamp = ICloudSyncService.instance!.coordinator.localRevision('subtitle_font_size');
    expect(stamp, isNotNull, reason: 'an unstamped value would lose to any stamped remote record');
    expect(stamp!.updatedAt, greaterThan(PreferenceSyncCoordinator.legacyRevisionAt));
    expect(valueOf(fake.store[g('subtitle_font_size')]), 47, reason: 'the boot reconcile carries it');
    expect(fake.writes, contains(g('subtitle_font_size')));
    final sent = json.decode(fake.store[g('subtitle_font_size')]!) as Map;
    expect(sent['t'], stamp.updatedAt, reason: 'the held-back send goes out with its stamp');
    expect(sent['d'], stamp.deviceId);
  });
}

/// A transport whose first availability answer waits until the test says so.
class _GatedTransport extends FakeTransport {
  final Completer<void> gate = Completer<void>();
  bool asked = false;

  @override
  Future<bool> isAvailable() async {
    asked = true;
    await gate.future;
    return available;
  }
}
