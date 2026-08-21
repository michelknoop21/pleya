import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_merge_strategies.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// A14. The engine dispatches a merge by the family name in the policy, and
/// knows nothing about what the values mean. Before this there was one
/// hardcoded `if` on a key list, so nothing else could ever need a merge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);
  const mine = 'plex-machine';
  const theirs = 'other-machine';

  bool isPortable(String serverId) => serverId == mine;

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: 'macbook',
      isServerIdPortable: isPortable,
      transport: transport,
    );
  }

  String hiddenKey() => 'user_${homeUuid}_hidden_libraries';
  String encList(List<String> entries) => json.encode({'type': 'string', 'value': json.encode(entries)});
  List<String> cloudList(PreferenceSyncCoordinator c) {
    final raw = transport.store[c.cloudKeyFor(hiddenKey())!]!;
    return (json.decode(json.decode(raw)['value'] as String) as List).cast<String>();
  }

  List<String> localList() => (json.decode(settings.prefs.getString(hiddenKey())!) as List).cast<String>();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('the registry', () {
    test('a replace preference has no family', () async {
      final coordinator = await build();
      expect(coordinator.mergeRegistry.familyFor('theme_mode'), isNull);
    });

    test('a preference that claims a family gets it', () async {
      final coordinator = await build();
      expect(coordinator.mergeRegistry.familyFor('hidden_libraries')?.name, PreferenceMergeFamilies.serverScopedList);
      expect(coordinator.mergeRegistry.familyFor('library_order')?.name, PreferenceMergeFamilies.serverScopedList);
    });

    test('the built-in families are registered by name', () async {
      final coordinator = await build();
      expect(
        coordinator.mergeRegistry.registeredNames,
        containsAll([
          PreferenceMergeFamilies.serverScopedList,
          PreferenceMergeFamilies.progressMap,
          PreferenceMergeFamilies.watchedMap,
        ]),
      );
    });

    test('the engine dispatches by name: swapping the implementation changes the result', () async {
      final coordinator = await build();
      var called = 0;
      coordinator.mergeRegistry.register(
        PreferenceMergeFamily(
          name: PreferenceMergeFamilies.serverScopedList,
          inbound: (local, remote) {
            called++;
            return json.encode(['replaced-by-the-family']);
          },
        ),
      );

      await coordinator.applyEntries({
        coordinator.cloudKeyFor(hiddenKey())!: encList(['$mine:1']),
      });

      expect(called, 1);
      expect(localList(), ['replaced-by-the-family']);
    });
  });

  group('inbound', () {
    test('keeps the entries the sender never saw', () async {
      final coordinator = await build();
      await settings.prefs.setString(hiddenKey(), json.encode(['$theirs:local-only']));

      await coordinator.applyEntries({
        coordinator.cloudKeyFor(hiddenKey())!: encList(['$mine:1']),
      });

      expect(localList(), containsAll(['$mine:1', '$theirs:local-only']));
    });

    test('the progress family takes the maximum, the watched family ORs', () {
      final progress = buildProgressMapFamily(watchedMap: false);
      final watched = buildProgressMapFamily(watchedMap: true);

      expect(progress.inbound('{"a":10}', '{"a":20,"b":5}'), '{"a":20,"b":5}');
      expect(watched.inbound('{"a":true}', '{"a":false}'), '{"a":true}');
    });

    test('the progress families do not merge outgoing', () {
      expect(buildProgressMapFamily(watchedMap: false).mergesOutgoing, isFalse);
      expect(buildProgressMapFamily(watchedMap: true).mergesOutgoing, isFalse);
    });
  });

  group('outbound', () {
    test('a local change keeps the entries in the store this device cannot speak for', () async {
      final coordinator = await build();
      transport.store[coordinator.cloudKeyFor(hiddenKey())!] = encList(['$theirs:9']);

      await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$mine:1'])));

      expect(cloudList(coordinator), containsAll(['$mine:1', '$theirs:9']));
    });

    test('a deliberate removal on a known server still propagates: this is not a union', () async {
      final coordinator = await build();
      transport.store[coordinator.cloudKeyFor(hiddenKey())!] = encList(['$mine:1', '$mine:2']);

      await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$mine:1'])));

      expect(cloudList(coordinator), ['$mine:1']);
    });

    test('a store that cannot be read holds the write back instead of overwriting it', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor(hiddenKey())!;
      transport.store[cloudKey] = encList(['$theirs:9']);
      transport.failReadAll = true;

      await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$mine:1'])));

      expect(transport.writes, isEmpty);
      expect(cloudList(coordinator), ['$theirs:9']);
      expect(coordinator.status.value.state, PreferenceSyncState.warning);
    });

    test('reconcile holds a merge family back when the store cannot be read, and still pushes the rest', () async {
      final coordinator = await build();
      await settings.prefs.setString(hiddenKey(), json.encode(['$mine:1']));
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.failReadAll = true;

      await coordinator.reconcile();

      expect(transport.store.containsKey(coordinator.cloudKeyFor(hiddenKey())!), isFalse);
      expect(transport.store.containsKey(coordinator.cloudKeyFor('subtitle_font_size')!), isTrue);
    });

    test('a list with nothing portable in it sends nothing and deletes nothing', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor(hiddenKey())!;
      transport.store[cloudKey] = encList(['$theirs:9']);

      await coordinator.apply(PreferenceMutation.set(hiddenKey(), json.encode(['$theirs:local'])));

      expect(transport.removes, isEmpty);
      expect(cloudList(coordinator), ['$theirs:9']);
    });
  });

  group('the prune protects what is present locally', () {
    test('a list that holds only non-portable entries is not deleted from the store', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor(hiddenKey())!;
      // Present locally, but nothing in it may travel, so the reconcile has
      // nothing to push. Under v2 the prune compared a namespaced cloud key
      // against a bare base key, so this record was deleted from every other
      // device instead of being left alone.
      await settings.prefs.setString(hiddenKey(), json.encode(['$theirs:local']));
      transport.store[cloudKey] = encList(['$mine:1']);

      await coordinator.reconcile();

      expect(transport.removes, isNot(contains(cloudKey)));
      expect(transport.store.containsKey(cloudKey), isTrue);
    });

    test('a key that is genuinely gone locally is still pruned', () async {
      final coordinator = await build();
      final cloudKey = coordinator.cloudKeyFor('subtitle_font_size')!;
      transport.store[cloudKey] = json.encode({'type': 'int', 'value': 44});

      await coordinator.reconcile();

      expect(transport.removes, contains(cloudKey));
    });
  });
}
