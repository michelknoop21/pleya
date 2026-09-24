import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// DEC-131 (4), (5) and (6). A reconcile writes what is newer here and nothing
/// else; a removal is a tombstone the other device honours; nothing is pruned
/// under v2; a local write during a remote batch is ordered by its stamp.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String deviceId = 'macbook', FakeTransport? shared}) async {
    settings = await SettingsService.getInstance();
    transport = shared ?? FakeTransport();
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
  Map<String, dynamic> decode(String raw) => json.decode(raw) as Map<String, dynamic>;
  int future() => DateTime.now().toUtc().millisecondsSinceEpoch + 60 * 60 * 1000;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('a reconcile compares before it writes', () {
    test('a second reconcile over an unchanged store writes nothing at all', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await coordinator.reconcile();
      transport.writes.clear();

      await coordinator.reconcile();

      expect(transport.writes, isEmpty, reason: 'the meta record and every value were already there');
    });

    test('an older local value is not pushed over a newer remote one', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await settings.prefs.setInt('subtitle_font_size', 30);
      transport.store[cloudKey] = stamped('int', 99, future(), 'appletv');

      await coordinator.reconcile();

      expect(transport.writes, isNot(contains(cloudKey)));
      expect(decode(transport.store[cloudKey]!)['value'], 99);
    });

    test('a newer local value is pushed over an older remote one', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      transport.store[cloudKey] = stamped('int', 99, 1000, 'appletv');

      await coordinator.reconcile();

      expect(decode(transport.store[cloudKey]!)['value'], 44);
    });

    test('a merge family is rewritten only when the merged value differs', () async {
      final coordinator = await build();
      coordinator.serverIdPortability = (id) => id == 'plex';
      final key = 'user_${homeUuid}_hidden_libraries';
      final cloudKey = coordinator.cloudKeyFor(key)!;
      await settings.prefs.setString(key, json.encode(['plex:1']));
      transport.store[cloudKey] = stamped('string', json.encode(['plex:1']), 1000, 'appletv');

      await coordinator.reconcile();

      expect(transport.writes, isNot(contains(cloudKey)));
    });
  });

  group('a removal is a tombstone', () {
    test('a local removal writes a tombstone instead of removing the record', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      await coordinator.apply(const PreferenceMutation.remove('subtitle_font_size'));

      expect(transport.removes, isEmpty);
      final r = decode(transport.store[cloudKey]!);
      expect(r['x'], isTrue);
      expect(r.containsKey('value'), isFalse);
      expect(r['d'], 'macbook');
    });

    test('the other device honours the tombstone and does not push its value back', () async {
      // Device A sets and removes.
      final a = await build(deviceId: 'macbook');
      await settings.prefs.setInt('subtitle_font_size', 44);
      await a.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await a.apply(const PreferenceMutation.remove('subtitle_font_size'));
      final shared = transport;

      // Device B still holds the value it received earlier, unstamped.
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      final b = await build(deviceId: 'appletv', shared: shared);
      await settings.prefs.setInt('subtitle_font_size', 44);

      await b.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getInt('subtitle_font_size'), isNull, reason: 'B applies the tombstone');
      final r = decode(shared.store[b.cloudKeyFor('subtitle_font_size')!]!);
      expect(r['x'], isTrue, reason: 'B did not resurrect the value');
      expect(b.localRevision('subtitle_font_size')!.deleted, isTrue);
    });

    test('a live record the previous build wrote back over a tombstone is tombstoned again', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await coordinator.apply(const PreferenceMutation.remove('subtitle_font_size'));
      transport.store[cloudKey] = bare('int', 44); // the old build's reconcile

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(decode(transport.store[cloudKey]!)['x'], isTrue);
      expect(settings.prefs.getInt('subtitle_font_size'), isNull, reason: 'and it did not come back locally');
    });

    test('a reset removal is a tombstone too', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;

      await coordinator.apply(const PreferenceMutation.remove('theme_mode', source: PreferenceSource.reset));

      expect(decode(transport.store[cloudKey]!)['x'], isTrue);
    });
  });

  group('nothing is pruned under v2', () {
    test('a record this device never had is adopted, not deleted', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('theme_mode')!;
      transport.store[cloudKey] = bare('string', 'dark');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.removes, isEmpty);
      expect(settings.prefs.getString('theme_mode'), 'dark');
    });

    test('a record for a key this build does not know survives a reconcile', () async {
      final coordinator = await build();
      const futureKey = '${PreferenceSyncScope.cloudNamespacePrefix}global/a_pref_from_a_newer_build';
      transport.store[futureKey] = stamped('int', 1, 5, 'iphone');
      // Flat keys an older build still writes, one this build knows and one it
      // does not. Neither is this device's to delete.
      transport.store['theme_mode'] = bare('string', 'dark');
      transport.store['a_pref_this_build_never_heard_of'] = bare('int', 3);

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.removes, isEmpty);
      expect(transport.store.containsKey(futureKey), isTrue);
      expect(transport.store.containsKey('theme_mode'), isTrue);
      expect(transport.store.containsKey('a_pref_this_build_never_heard_of'), isTrue);
    });

    test('ownsCloudKey claims nothing under v2', () async {
      final coordinator = await build();

      expect(coordinator.ownsCloudKey('${PreferenceSyncScope.cloudNamespacePrefix}global/theme_mode'), isFalse);
    });
  });

  group('a local write during a remote batch', () {
    test('still reaches the store', () async {
      final coordinator = await build();
      final applying = coordinator.applyEntries({
        coordinator.cloudKeyFor('theme_mode')!: stamped('string', 'dark', 1000, 'appletv'),
      });
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await applying;

      expect(transport.store.containsKey(coordinator.cloudKeyFor('subtitle_font_size')!), isTrue);
    });
  });

  group('a tombstone in a merge family passes the stamp comparison', () {
    late PreferenceSyncCoordinator coordinator;
    late String key;
    late String cloudKey;

    Future<void> hold(List<String> entries) async {
      coordinator = await build();
      coordinator.serverIdPortability = (id) => id == 'plex';
      key = 'user_${homeUuid}_hidden_libraries';
      cloudKey = coordinator.cloudKeyFor(key)!;
      await settings.prefs.setString(key, json.encode(entries));
      await coordinator.apply(PreferenceMutation.set(key, json.encode(entries)));
    }

    test('an older tombstone loses to a newer local value', () async {
      await hold(['plex:1', 'local:3']);

      await coordinator.applyEntries({
        cloudKey: json.encode({'x': true, 't': 1000, 'd': 'appletv'}),
      });

      expect(settings.prefs.getString(key), json.encode(['plex:1', 'local:3']));
      expect(coordinator.localRevision(key.replaceFirst('user_${homeUuid}_', ''))?.deleted ?? false, isFalse);
    });

    test('a newer tombstone removes the shared entries and keeps the local-folder ones', () async {
      await hold(['plex:1', 'local:3']);

      await coordinator.applyEntries({
        cloudKey: json.encode({'x': true, 't': future(), 'd': 'appletv'}),
      });

      expect(settings.prefs.getString(key), json.encode(['local:3']));
    });

    test('a newer tombstone over shared entries only removes the value', () async {
      await hold(['plex:1']);

      await coordinator.applyEntries({
        cloudKey: json.encode({'x': true, 't': future(), 'd': 'appletv'}),
      });

      expect(settings.prefs.containsKey(key), isFalse);
    });
  });

  group('a remote event and a reconcile never overlap', () {
    test('an event that arrives mid-reconcile waits for it to finish', () async {
      final gated = _ReadGate();
      final coordinator = await build(shared: gated);
      coordinator.listen();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      gated.store[cloudKey] = stamped('int', 61, future(), 'appletv');

      final reconciling = coordinator.requestReconcile(ReconcileTrigger.foreground);
      while (gated.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      gated.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [cloudKey]));
      await pumpEventQueue();

      expect(gated.reads, 1, reason: 'the event may not read the store while the reconcile holds it');

      gated.gate.complete();
      await reconciling;
      await pumpEventQueue();

      expect(gated.reads, greaterThan(2), reason: 'the event ran after the reconcile');
      expect(settings.prefs.getInt('subtitle_font_size'), 61);
    });
  });
}

/// A transport whose first store read waits until the test says so.
class _ReadGate extends FakeTransport {
  final Completer<void> gate = Completer<void>();
  int reads = 0;

  @override
  Future<Map<String, String>?> readAll() async {
    reads++;
    if (reads == 1) await gate.future;
    return super.readAll();
  }
}
