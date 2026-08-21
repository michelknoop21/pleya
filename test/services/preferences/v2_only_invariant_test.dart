import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// Review constraint R1. v2-only is a production invariant, not the default of
/// a switch somebody can flip back.
///
/// The v1 writer still exists, and deliberately so: `icloud_rolling_upgrade_test`
/// runs the real old algorithm to prove an older client leaves v2 records alone,
/// and a test that reimplemented that algorithm would prove nothing. What must
/// not exist is a path from the shipped app into it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  /// Built the way the app builds it: no format argument at all.
  Future<PreferenceSyncCoordinator> buildProduction() async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => true,
      deviceId: 'macbook',
      transport: transport,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  test('the shipped constant is v2', () {
    expect(PreferenceSyncCoordinator.v2CloudFormatEnabled, isTrue);
  });

  test('a production-built coordinator is v2 without being told', () async {
    final coordinator = await buildProduction();

    expect(coordinator.usesV2CloudFormat, isTrue);
  });

  test('no production source selects the format at all', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('useV2CloudFormat:')) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the format is not a runtime choice; passing it anywhere in lib/ would make it one',
    );
  });

  test('every key this client writes lives in the v2 namespace', () async {
    final coordinator = await buildProduction();
    await settings.prefs.setInt('subtitle_font_size', 44);
    await settings.prefs.setString('user_${homeUuid}_library_filters', '{}');

    await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));
    await coordinator.reconcile();

    expect(transport.writes, isNotEmpty);
    for (final key in transport.writes) {
      expect(
        key.startsWith(PreferenceSyncScope.cloudNamespacePrefix),
        isTrue,
        reason: '$key was written outside the v2 namespace',
      );
    }
  });

  test('a store full of v1 records survives a full lifecycle untouched', () async {
    final coordinator = await buildProduction();
    final v1 = {
      'theme_mode': json.encode({'type': 'string', 'value': 'dark'}),
      'subtitle_font_size': json.encode({'type': 'int', 'value': 30}),
      'hidden_libraries': json.encode({'type': 'string', 'value': '[]'}),
      PreferenceSyncCoordinator.metaVersionKey: json.encode({'type': 'int', 'value': 1}),
    };
    transport.store.addAll(v1);

    await coordinator.bootstrapFromLegacyV1();
    await coordinator.applyAllRemote();
    await coordinator.reconcile();

    for (final entry in v1.entries) {
      expect(transport.store[entry.key], entry.value, reason: '${entry.key} was rewritten or deleted');
    }
    expect(transport.removes.where((k) => !k.startsWith(PreferenceSyncScope.cloudNamespacePrefix)), isEmpty);
  });

  test('the v1 meta marker is never rewritten by a v2 client', () async {
    final coordinator = await buildProduction();

    await coordinator.reconcile();

    expect(transport.writes, isNot(contains(PreferenceSyncCoordinator.metaVersionKey)));
    expect(transport.writes, contains(PreferenceSyncCoordinator.v2MetaVersionKey));
  });
}
