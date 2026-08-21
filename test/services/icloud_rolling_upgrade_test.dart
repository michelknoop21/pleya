import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../test_helpers/prefs.dart';
import 'preferences/fake_transport.dart';

/// Rolling-upgrade contract: what an *older* Pleya does when it meets records
/// written after the v2 cutover.
///
/// This matters because the v1 reconcile prunes every store key it cannot
/// reproduce locally. A new format written into the plain namespace would be
/// deleted by any older build still signed into the same iCloud account, and an
/// Apple TV nobody updated is enough. The escape hatch is that the v1 code skips
/// every key starting with `__`, in both the prune loop and the apply loop, and
/// writes nothing there but its own version marker.
///
/// These tests run the **real v1 code path**, not a hand-written model of it:
/// `useV2CloudFormat: false` is the algorithm the released build runs, still
/// present and still exercised. If a refactor ever stops honouring the reserved
/// namespace, an old client starts eating new records and these go red.
String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late FakeTransport transport;

  /// A coordinator behaving exactly as the pre-cutover client does.
  Future<PreferenceSyncCoordinator> oldClient() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => 'someone',
      enabled: () => true,
      deviceId: 'old-appletv',
      useV2CloudFormat: false,
      transport: transport,
    );
  }

  String v2Global(String key) => '${PreferenceSyncScope.cloudNamespacePrefix}global/$key';
  String v2Profile(String id, String key) => '${PreferenceSyncScope.cloudNamespacePrefix}profile/$id/$key';

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  test('an old client leaves v2 records alone while still pruning its own stale keys', () async {
    final coordinator = await oldClient();
    await settings.prefs.setInt('seek_time_small', 8);

    transport.store[v2Global('subtitle_font_size')] = enc('int', 44);
    transport.store[v2Profile('abc', 'hidden_libraries')] = enc('string', '["srv:1"]');
    // Control: a v1 preference this device no longer has. The prune does reach
    // this one, which is what makes the results above mean something.
    transport.store['theme_mode'] = enc('string', 'dark');

    await coordinator.reconcile();

    expect(
      transport.store.containsKey(v2Global('subtitle_font_size')),
      isTrue,
      reason: 'an old client must not delete a newer format it cannot read',
    );
    expect(transport.store.containsKey(v2Profile('abc', 'hidden_libraries')), isTrue);
    expect(
      transport.store.containsKey('theme_mode'),
      isFalse,
      reason: 'control: the prune really does run, so the results above are not an accident',
    );
  });

  test('an old client never applies a v2 record locally', () async {
    final coordinator = await oldClient();

    transport.store[v2Global('subtitle_font_size')] = enc('int', 99);
    await coordinator.applyRemoteKeys([v2Global('subtitle_font_size')]);

    expect(settings.prefs.getInt(v2Global('subtitle_font_size')), isNull);
    expect(settings.prefs.getInt('subtitle_font_size'), isNull, reason: 'and not under the bare key either');
  });

  test('an old client writes nothing into the reserved namespace but its own marker', () async {
    final coordinator = await oldClient();
    await settings.prefs.setInt('seek_time_small', 8);
    await settings.prefs.setString('user_someone_hidden_libraries', '["srv:1"]');

    await coordinator.reconcile();

    final reserved = transport.writes.where((k) => k.startsWith('__')).toSet().toList()..sort();
    expect(reserved, [PreferenceSyncCoordinator.metaVersionKey]);
  });

  test('the two formats do not collide on a key name', () async {
    // The whole coexistence argument rests on this: a v1 key and its v2
    // counterpart are different strings, so neither client can mistake one for
    // the other.
    expect(v2Global('subtitle_font_size'), isNot('subtitle_font_size'));
    expect(PreferenceSyncScope.ownsCloudKey('subtitle_font_size'), isFalse);
    expect(PreferenceSyncScope.ownsCloudKey(v2Global('subtitle_font_size')), isTrue);
  });
}
