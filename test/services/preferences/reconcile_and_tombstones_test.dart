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

  group('a removed family key against a live record', () {
    late PreferenceSyncCoordinator coordinator;
    late String key;
    late String cloudKey;

    Future<void> removeHeldList() async {
      coordinator = await build();
      coordinator.serverIdPortability = (id) => id == 'plex';
      key = 'user_${homeUuid}_hidden_libraries';
      cloudKey = coordinator.cloudKeyFor(key)!;
      await settings.prefs.setString(key, json.encode(['plex:1']));
      await coordinator.apply(PreferenceMutation.set(key, json.encode(['plex:1'])));
      await settings.prefs.remove(key);
      await coordinator.apply(PreferenceMutation.remove(key));
    }

    test('an older write-back does not flip the removal across two reconciles', () async {
      await removeHeldList();
      transport.store[cloudKey] = bare('string', json.encode(['plex:1'])); // the released build
      transport.writes.clear();

      await coordinator.requestReconcile(ReconcileTrigger.foreground);
      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getString(key), isNull);
      expect(decode(transport.store[cloudKey]!)['x'], isTrue);
      expect(transport.writes.where((k) => k == cloudKey).length, 1, reason: 'tombstoned again once, then quiet');
    });

    test('a newer live record beats the removal and its stamp is adopted', () async {
      await removeHeldList();
      final later = future();
      transport.store[cloudKey] = stamped('string', json.encode(['plex:2']), later, 'appletv');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getString(key), json.encode(['plex:2']));
      final stamp = coordinator.localRevision('hidden_libraries')!;
      expect(stamp.updatedAt, later);
      expect(stamp.deleted, isFalse);
    });
  });

  group('a failed read', () {
    test('sends nothing, reports an error, and the next trigger sends it', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.failReadAll = true;

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.writes, isEmpty, reason: 'nothing can be compared against a read that failed');
      expect(coordinator.status.value.state, PreferenceSyncState.error);

      transport.failReadAll = false;
      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.writes, contains(cloudKey));
      expect(coordinator.status.value.state, isNot(PreferenceSyncState.error));
    });
  });

  group('a device back after months offline', () {
    test('pulls first, loses where others changed later, and sends only its own later change', () async {
      final coordinator = await build(deviceId: 'appletv');
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final monthsAgo = now - 90 * 24 * 60 * 60 * 1000;
      final lastWeek = now - 7 * 24 * 60 * 60 * 1000;
      final subtitle = coordinator.cloudKeyFor('subtitle_font_size')!;
      final theme = coordinator.cloudKeyFor('theme_mode')!;
      final seek = coordinator.cloudKeyFor('seek_time_small')!;
      await settings.prefs.setInt('subtitle_font_size', 30);
      await settings.prefs.setString('theme_mode', 'light');
      await settings.prefs.setInt('seek_time_small', 15);
      await settings.prefs.setString(
        PreferenceSyncCoordinator.revisionStoreKey,
        json.encode({
          'subtitle_font_size': {'t': monthsAgo, 'd': 'appletv'},
          'theme_mode': {'t': monthsAgo, 'd': 'appletv'},
          'seek_time_small': {'t': future(), 'd': 'appletv'}, // changed after everyone else
        }),
      );
      transport.store[subtitle] = stamped('int', 44, lastWeek, 'macbook');
      transport.store[theme] = json.encode({'x': true, 't': lastWeek, 'd': 'macbook'});
      transport.store[seek] = stamped('int', 5, lastWeek, 'macbook');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
      expect(settings.prefs.getString('theme_mode'), isNull, reason: 'the newer tombstone applied');
      expect(settings.prefs.getInt('seek_time_small'), 15);
      expect(transport.writes, isNot(contains(subtitle)));
      expect(transport.writes, isNot(contains(theme)));
      expect(decode(transport.store[seek]!)['value'], 15);
    });
  });

  group('a released v2 client beside this build', () {
    /// The released v2 reconcile, reduced to what it does to the store: it
    /// pulls every record it can read (a tombstone has no type, so it skips
    /// it), writes back everything it holds without a stamp, and prunes the
    /// namespace keys it does not hold.
    void releasedV2Reconcile(FakeTransport store, Map<String, (String, Object?)> held) {
      for (final e in Map.of(store.store).entries) {
        final m = decode(e.value);
        if (m['type'] is String) held[e.key] = (m['type'] as String, m['value']);
      }
      for (final e in held.entries) {
        store.store[e.key] = bare(e.value.$1, e.value.$2);
      }
      for (final k in store.store.keys.toList()) {
        if (k.startsWith(PreferenceSyncScope.cloudNamespacePrefix) && !held.containsKey(k)) store.store.remove(k);
      }
    }

    test('its bare write-backs lose, and this build restores its stamps and tombstones', () async {
      final coordinator = await build();
      final subtitle = coordinator.cloudKeyFor('subtitle_font_size')!;
      final theme = coordinator.cloudKeyFor('theme_mode')!;
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      await coordinator.apply(const PreferenceMutation.remove('theme_mode'));
      // The old client saw 'dark' before the removal and never learns of it.
      final held = <String, (String, Object?)>{theme: ('string', 'dark')};

      releasedV2Reconcile(transport, held);
      expect(decode(transport.store[subtitle]!).containsKey('t'), isFalse, reason: 'the old build strips the stamp');
      expect(decode(transport.store[theme]!)['value'], 'dark');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
      expect(settings.prefs.getString('theme_mode'), isNull);
      expect(decode(transport.store[subtitle]!)['t'], isNotNull, reason: 'the stamp is back');
      expect(decode(transport.store[theme]!)['x'], isTrue, reason: 'and so is the tombstone');
    });
  });

  group('a remote event and a reconcile never overlap', () {
    test('an event that arrives mid-reconcile waits for it to finish', () async {
      final gated = _ReadGate();
      final coordinator = await build(shared: gated);
      coordinator.listen();
      final theme = coordinator.cloudKeyFor('theme_mode')!;

      final reconciling = coordinator.requestReconcile(ReconcileTrigger.foreground);
      while (gated.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      // Lands after the reconcile's pull read the store, so only the event can
      // bring it to this device: the reconcile itself only pushes after that.
      gated.store[theme] = stamped('string', 'dark', future(), 'appletv');
      gated.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [theme]));
      await pumpEventQueue();

      expect(gated.reads, 1, reason: 'the event may not read the store while the reconcile holds it');
      expect(settings.prefs.getString('theme_mode'), isNull);

      gated.gate.complete();
      await reconciling;
      await pumpEventQueue();

      expect(settings.prefs.getString('theme_mode'), 'dark', reason: 'the event ran after the reconcile');
    });

    test('a reconcile that hangs holds events and later reconciles back for a bounded time only', () async {
      final gated = _ReadGate(); // its gate never opens: a native read that never answers
      final coordinator = await build(shared: gated);
      coordinator.turnTimeout = const Duration(milliseconds: 50);
      coordinator.listen();
      final theme = coordinator.cloudKeyFor('theme_mode')!;

      unawaited(coordinator.requestReconcile(ReconcileTrigger.foreground));
      while (gated.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      gated.store[theme] = stamped('string', 'dark', future(), 'appletv');
      gated.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [theme]));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(settings.prefs.getString('theme_mode'), 'dark');
      expect(coordinator.scheduler.runCount, 1, reason: 'the hung run was let go');
      expect(coordinator.status.value.state, PreferenceSyncState.error, reason: 'and not left on syncing');

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(coordinator.scheduler.runCount, 2, reason: 'the next reconcile runs');
    });

    test('an event that timed out and lands late does not undo a newer turn', () async {
      final gated = _ReadGate(); // the first read snapshots the store, then hangs past the timeout
      final coordinator = await build(shared: gated);
      coordinator.turnTimeout = const Duration(milliseconds: 50);
      coordinator.listen();
      final theme = coordinator.cloudKeyFor('theme_mode')!;

      // The first event's snapshot has no record for the key: a bare removal.
      gated.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [theme]));
      while (gated.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      gated.store[theme] = stamped('string', 'dark', future(), 'appletv');
      gated.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [theme]));
      await pumpEventQueue();
      expect(settings.prefs.getString('theme_mode'), 'dark');

      gated.gate.complete(); // the stale turn finally answers
      await pumpEventQueue();

      expect(settings.prefs.getString('theme_mode'), 'dark', reason: 'the stale snapshot was dropped');
    });

    test('turns waiting behind a hung one start one at a time', () async {
      final slow = _SlowReads(); // the first read hangs, every later one takes 40 ms
      final coordinator = await build(shared: slow);
      coordinator.turnTimeout = const Duration(milliseconds: 50);
      coordinator.listen();
      final theme = coordinator.cloudKeyFor('theme_mode')!;
      final subtitle = coordinator.cloudKeyFor('subtitle_font_size')!;

      unawaited(coordinator.requestReconcile(ReconcileTrigger.foreground));
      while (slow.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      slow.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [theme]));
      slow.controller.add(RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: [subtitle]));
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(slow.reads, 3, reason: 'both events ran');
      expect(slow.mostAtOnce, 1, reason: 'the two queued events never overlapped');
    });
  });

  group('a value under a removal stamp', () {
    Future<(PreferenceSyncCoordinator, String)> holding(Map<String, Object> stamp) async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await settings.prefs.setString(
        PreferenceSyncCoordinator.revisionStoreKey,
        json.encode({'subtitle_font_size': stamp}),
      );
      return (coordinator, coordinator.cloudKeyFor('subtitle_font_size')!);
    }

    test('under a legacy removal travels like an unstamped value', () async {
      final (coordinator, cloudKey) = await holding({'t': 0, 'd': '', 'x': true});

      await coordinator.reconcile();

      expect(decode(transport.store[cloudKey]!)['value'], 44);
    });

    test('under a real removal stays home, so the removal does not flip', () async {
      final (coordinator, cloudKey) = await holding({'t': 5000, 'd': 'macbook', 'x': true});

      await coordinator.reconcile();

      expect(transport.store.containsKey(cloudKey), isFalse);
    });
  });
}

/// A transport whose first read never answers and whose later reads each take
/// a while, counting how many of those later reads run at once.
class _SlowReads extends FakeTransport {
  int reads = 0;
  int _active = 0;
  int mostAtOnce = 0;

  @override
  Future<Map<String, String>?> readAll() async {
    reads++;
    if (reads == 1) return Completer<Map<String, String>?>().future;
    _active++;
    if (_active > mostAtOnce) mostAtOnce = _active;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _active--;
    return super.readAll();
  }
}

/// A transport whose first store read takes its snapshot and then waits until
/// the test says so.
class _ReadGate extends FakeTransport {
  final Completer<void> gate = Completer<void>();
  int reads = 0;

  @override
  Future<Map<String, String>?> readAll() async {
    reads++;
    final snapshot = await super.readAll();
    if (reads == 1) await gate.future;
    return snapshot;
  }
}
