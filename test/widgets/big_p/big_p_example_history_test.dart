import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_capabilities.dart';
import 'package:pleya/screens/profile/profile_delete_flow.dart';
import 'package:pleya/services/preferences/preference_sync_policy.dart';
import 'package:pleya/services/base_shared_preferences_service.dart' show StringListPref;
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_example_history.dart';

import '../../test_helpers/prefs.dart';

BigPShownExample _e(AssistantCapability c, [int phrasing = 0]) => (capability: c, phrasing: phrasing);

void main() {
  late StorageService storage;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    storage = await StorageService.getInstance();
    await SettingsService.getInstance();
  });

  /// Writes are fire and forget: wait until the store holds [count] entries.
  Future<void> flush() => pumpEventQueue(times: 50);

  test('kept per profile and read back in order', () async {
    await storage.setActiveProfileId('parent');
    final first = BigPExampleHistory.stored();
    await first.load();
    first.note([_e(AssistantCapability.tonight, 1), _e(AssistantCapability.scan), _e(AssistantCapability.servers)]);
    await flush();

    await storage.setActiveProfileId('other');
    final other = BigPExampleHistory.stored();
    await other.load();
    expect(other.shown, isEmpty, reason: 'another profile starts empty');

    await storage.setActiveProfileId('parent');
    final again = BigPExampleHistory.stored();
    await again.load();
    expect(again.shown, [
      _e(AssistantCapability.tonight, 1),
      _e(AssistantCapability.scan),
      _e(AssistantCapability.servers),
    ]);
    expect(again.summonsSince(AssistantCapability.scan), 0);
    expect(again.showed(AssistantCapability.tonight, 1), isTrue);
    expect(again.showed(AssistantCapability.tonight, 0), isFalse);
  });

  test('a note made before the read finished stays the newest', () async {
    await storage.setActiveProfileId('parent');
    final seed = BigPExampleHistory.stored();
    await seed.load();
    seed.note([_e(AssistantCapability.tonight), _e(AssistantCapability.scan), _e(AssistantCapability.servers)]);
    await flush();

    final history = BigPExampleHistory.stored();
    final loading = history.load();
    history.note([_e(AssistantCapability.jobs), _e(AssistantCapability.users), _e(AssistantCapability.doctor)]);
    await loading;
    await flush();
    expect(history.shown.map((e) => e.capability), [
      AssistantCapability.tonight,
      AssistantCapability.scan,
      AssistantCapability.servers,
      AssistantCapability.jobs,
      AssistantCapability.users,
      AssistantCapability.doctor,
    ]);

    // And what the store holds is the same list, not only the new entries.
    final reread = BigPExampleHistory.stored();
    await reread.load();
    expect(reread.shown, history.shown);
  });

  test('a write after a profile switch stays with the profile it was read for', () async {
    await storage.setActiveProfileId('parent');
    final history = BigPExampleHistory.stored();
    await history.load();
    await storage.setActiveProfileId('other');
    history.note([_e(AssistantCapability.tonight), _e(AssistantCapability.scan), _e(AssistantCapability.servers)]);
    await flush();

    final other = BigPExampleHistory.stored();
    await other.load();
    expect(other.shown, isEmpty);
    await storage.setActiveProfileId('parent');
    final parent = BigPExampleHistory.stored();
    await parent.load();
    expect(parent.shown, hasLength(3));
  });

  test('unknown or malformed entries are dropped, the rest is kept', () async {
    await storage.setActiveProfileId('parent');
    final settings = await SettingsService.getInstance();
    final prefix = PreferenceSyncScope.forProfile(
      settings.prefs.getString(PreferenceSyncScope.activeProfileIdKey),
    ).localPrefix;
    await settings.write(StringListPref('${prefix}assistant_example_history'), [
      'gone#0',
      'tonight',
      'tonight#x',
      'tonight#-1',
      'scan#1',
    ]);
    final history = BigPExampleHistory.stored();
    await history.load();
    expect(history.shown, [_e(AssistantCapability.scan, 1)]);
  });

  test('without an active profile nothing is kept', () async {
    final history = BigPExampleHistory.stored();
    await history.load();
    history.note([_e(AssistantCapability.tonight), _e(AssistantCapability.scan), _e(AssistantCapability.servers)]);
    await flush();
    final again = BigPExampleHistory.stored();
    await again.load();
    expect(again.shown, isEmpty);
  });

  test('deleting a profile drops its history and nobody else\'s', () async {
    await storage.setActiveProfileId('child');
    final child = BigPExampleHistory.stored();
    await child.load();
    child.note([_e(AssistantCapability.tonight), _e(AssistantCapability.scan), _e(AssistantCapability.servers)]);
    await storage.setActiveProfileId('parent');
    final parent = BigPExampleHistory.stored();
    await parent.load();
    parent.note([_e(AssistantCapability.jobs), _e(AssistantCapability.users), _e(AssistantCapability.doctor)]);
    await flush();

    await clearProfileScopedStores(storage, 'child');

    final keptParent = BigPExampleHistory.stored();
    await keptParent.load();
    expect(keptParent.shown, hasLength(3));
    await storage.setActiveProfileId('child');
    final gone = BigPExampleHistory.stored();
    await gone.load();
    expect(gone.shown, isEmpty);
  });

  test('the policy keeps the history on this device and out of exports', () {
    const key = 'assistant_example_history';
    expect(PreferenceSyncPolicyRegistry.isProfileScoped(key), isTrue);
    expect(PreferenceSyncPolicyRegistry.maySync(key), isFalse);
    expect(PreferenceSyncPolicyRegistry.isExportable(key), isFalse);
  });

  test('summonsSince counts whole summons of three', () {
    final history = BigPExampleHistory();
    history.note([_e(AssistantCapability.tonight), _e(AssistantCapability.scan), _e(AssistantCapability.servers)]);
    history.note([_e(AssistantCapability.jobs), _e(AssistantCapability.users), _e(AssistantCapability.doctor)]);
    expect(history.summonsSince(AssistantCapability.jobs), 0);
    expect(history.summonsSince(AssistantCapability.tonight), 1);
  });
}
