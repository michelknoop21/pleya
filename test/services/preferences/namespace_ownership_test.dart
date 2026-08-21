import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// The coordinator owns one namespace, not the whole `__` space.
///
/// An older client skipping every `__` key is what makes coexistence work, but
/// the reverse does not follow: `__syncFormatVersion` is a sibling, a v3 would
/// be another, and any future feature may add more. Prune is the only
/// destructive operation here, so it acts on a positive claim of ownership.
String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({bool v2 = false, String? activeProfile}) async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => activeProfile,
      enabled: () => true,
      deviceId: 'macbook',
      isServerIdPortable: (_) => true,
      useV2CloudFormat: v2,
      transport: transport,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  group('the namespace is specific', () {
    test('it is not bare `__`', () {
      expect(PreferenceSyncScope.cloudNamespacePrefix, '__pleya_pref_v2/');
      expect(PreferenceSyncScope.ownsCloudKey('__syncFormatVersion'), isFalse);
      expect(PreferenceSyncScope.ownsCloudKey('__some_other_feature/x'), isFalse);
      expect(PreferenceSyncScope.ownsCloudKey('__pleya_pref_v3/global/x'), isFalse);
      expect(PreferenceSyncScope.ownsCloudKey('__pleya_pref_v2/global/x'), isTrue);
    });

    test('a v2 key parses back to its scope and base key', () {
      final global = PreferenceSyncScope.parseCloudKey('__pleya_pref_v2/global/subtitle_font_size');
      expect(global?.kind, PreferenceScopeKind.global);
      expect(global?.baseKey, 'subtitle_font_size');

      final scoped = PreferenceSyncScope.parseCloudKey('__pleya_pref_v2/profile/abc/hidden_libraries');
      expect(scoped?.kind, PreferenceScopeKind.profile);
      expect(scoped?.id, 'abc');
      expect(scoped?.baseKey, 'hidden_libraries');
    });

    test('a malformed or foreign key parses to nothing rather than to a guess', () {
      for (final key in [
        '__pleya_pref_v2/',
        '__pleya_pref_v2/global/',
        '__pleya_pref_v2/profile//x',
        '__pleya_pref_v2/nonsense/x',
        'hidden_libraries',
      ]) {
        expect(PreferenceSyncScope.parseCloudKey(key), isNull, reason: key);
      }
    });
  });

  group('prune only touches what we own', () {
    test('v1: a foreign `__` key and an unregistered key both survive', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.store['__syncFormatVersion'] = enc('int', 1);
      transport.store['__some_other_feature/state'] = enc('string', 'x');
      transport.store['__pleya_pref_v3/global/future'] = enc('string', 'x');
      transport.store['a_key_nobody_registered'] = enc('int', 1);

      await coordinator.reconcile();

      expect(transport.removes, isEmpty);
      expect(transport.store.containsKey('__some_other_feature/state'), isTrue);
      expect(transport.store.containsKey('__pleya_pref_v3/global/future'), isTrue);
      expect(transport.store.containsKey('a_key_nobody_registered'), isTrue);
    });

    test('v1: a registered preference that is genuinely gone locally is pruned', () async {
      final coordinator = await build();
      transport.store['theme_mode'] = enc('string', 'dark');

      await coordinator.reconcile();

      expect(transport.removes, contains('theme_mode'));
    });

    test('v2: only records inside the owned namespace are pruned', () async {
      final coordinator = await build(v2: true, activeProfile: profile);
      transport.store['__pleya_pref_v2/global/theme_mode'] = enc('string', 'dark');
      transport.store['__pleya_pref_v3/global/theme_mode'] = enc('string', 'dark');
      transport.store['theme_mode'] = enc('string', 'dark'); // the v1 record

      await coordinator.reconcile();

      expect(transport.removes, ['__pleya_pref_v2/global/theme_mode']);
      expect(
        transport.store.containsKey('theme_mode'),
        isTrue,
        reason: 'the v1 record still serves older clients; retiring it is a separate decision',
      );
      expect(transport.store.containsKey('__pleya_pref_v3/global/theme_mode'), isTrue);
    });

    test('v2: another profile\'s record is never applied and never pruned', () async {
      final coordinator = await build(v2: true, activeProfile: profile);
      transport.store['__pleya_pref_v2/profile/somebody-else/hidden_libraries'] = enc('string', '["srv:1"]');

      await coordinator.applyAllRemote();
      await coordinator.reconcile();

      expect(settings.prefs.getString('user_${homeUuid}_hidden_libraries'), isNull);
      expect(transport.store.containsKey('__pleya_pref_v2/profile/somebody-else/hidden_libraries'), isTrue);
    });
  });

  test('retired v1 values are left in place, not deleted because policy changed', () async {
    final coordinator = await build();
    // `volume` became device-local when the denylist was inverted. An older
    // client still reads and writes it, so removing it would take a working
    // setting away from that client.
    transport.store['volume'] = enc('double', 50.0);
    await settings.prefs.setDouble('volume', 80.0);

    await coordinator.reconcile();

    expect(transport.store['volume'], enc('double', 50.0));
    expect(transport.removes, isEmpty);
  });
}
