import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_legacy_bootstrap.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_quarantine.dart';
import 'package:pleya/services/preferences/preference_revision.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_scope.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// The v2-only cutover contract.
///
/// Dual-write was considered and rejected. v1 has no shared revision, no
/// tombstones and no profile namespace, so a client writing both formats could
/// not tell a newer user action in v1 from an older snapshot of one: exactly the
/// ambiguity the envelope removes, rebuilt in a more complicated shape. The
/// price is that an old and a new client stop exchanging settings. That is a
/// compatibility limit, not data loss, and it is surfaced rather than hidden.
String enc(String type, Object? value) => json.encode({'type': type, 'value': value});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

  late SettingsService settings;
  late FakeTransport transport;

  Future<PreferenceSyncCoordinator> build({String? activeProfile}) async {
    settings = await SettingsService.getInstance();
    transport = FakeTransport();
    return PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => activeProfile,
      enabled: () => true,
      deviceId: 'macbook',
      isServerIdPortable: (_) => true,
      transport: transport,
    );
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  test('the cutover is on: v2 is the writable format', () async {
    expect(PreferenceSyncCoordinator.v2CloudFormatEnabled, isTrue);
    final coordinator = await build();
    expect(coordinator.usesV2CloudFormat, isTrue);
  });

  group('a v2 client never writes v1', () {
    test('a single mutation lands only in the owned namespace', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      expect(transport.writes, isNotEmpty);
      for (final key in transport.writes) {
        expect(
          PreferenceSyncScope.ownsCloudKey(key),
          isTrue,
          reason: '$key is outside __pleya_pref_v2/, so it would be a v1 write',
        );
      }
    });

    test('a reconcile writes no flat key and no v1 meta key', () async {
      final coordinator = await build(activeProfile: profile);
      await settings.prefs.setInt('subtitle_font_size', 44);
      await settings.prefs.setString('user_${homeUuid}_hidden_libraries', json.encode(['srv:1']));

      await coordinator.reconcile();

      final flat = transport.writes.where((k) => !k.startsWith('__')).toList();
      expect(flat, isEmpty, reason: 'a flat key is a v1 record');
      expect(transport.writes, isNot(contains(PreferenceSyncCoordinator.metaVersionKey)));
      expect(transport.writes, contains(PreferenceSyncCoordinator.v2MetaVersionKey));
    });

    test('a removal is a v2 removal', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.remove('theme_mode'));

      expect(transport.removes, ['${PreferenceSyncScope.cloudNamespacePrefix}global/theme_mode']);
    });
  });

  group('the v1 global bootstrap', () {
    test('imports an unambiguous global value once, with a legacy revision', () async {
      final coordinator = await build();
      transport.store['subtitle_font_size'] = enc('int', 60);

      await coordinator.bootstrapFromLegacyV1();

      expect(settings.prefs.getInt('subtitle_font_size'), 60);
      final revision = coordinator.localRevision('subtitle_font_size');
      expect(revision?.updatedAt, PreferenceSyncCoordinator.legacyRevisionAt);
    });

    test('runs at most once, and a restart neither repeats it nor mutates revisions', () async {
      final coordinator = await build();
      transport.store['subtitle_font_size'] = enc('int', 60);

      await coordinator.bootstrapFromLegacyV1();
      final afterFirst = coordinator.localRevision('subtitle_font_size');
      expect(PreferenceLegacyBootstrap.hasRun(settings.prefs), isTrue);

      // The user changes it for real, then restarts.
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      final chosen = coordinator.localRevision('subtitle_font_size')!;

      await coordinator.bootstrapFromLegacyV1();

      expect(settings.prefs.getInt('subtitle_font_size'), 44, reason: 'the import must not run again');
      expect(coordinator.localRevision('subtitle_font_size')!.updatedAt, chosen.updatedAt);
      expect(chosen.updatedAt, greaterThan(afterFirst!.updatedAt));
    });

    test('does not overwrite a local value this device already has', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.store['subtitle_font_size'] = enc('int', 60);

      await coordinator.bootstrapFromLegacyV1();

      expect(settings.prefs.getInt('subtitle_font_size'), 44);
    });

    test('a failed read leaves the marker unset so the import can retry', () async {
      final coordinator = await build();
      transport.failReadAll = true;

      await coordinator.bootstrapFromLegacyV1();

      expect(PreferenceLegacyBootstrap.hasRun(settings.prefs), isFalse);
    });

    test('imports nothing from v1 back into v1: the store is untouched', () async {
      final coordinator = await build();
      transport.store['subtitle_font_size'] = enc('int', 60);

      await coordinator.bootstrapFromLegacyV1();

      expect(transport.writes, isEmpty);
      expect(transport.removes, isEmpty);
      expect(transport.store['subtitle_font_size'], enc('int', 60), reason: 'frozen, not consumed');
    });
  });

  group('quarantined profile state', () {
    test('a profile-scoped v1 value is not imported by the bootstrap', () async {
      final coordinator = await build(activeProfile: profile);
      transport.store['hidden_libraries'] = enc('string', json.encode(['srv:1']));

      await coordinator.bootstrapFromLegacyV1();

      expect(settings.prefs.getString('user_${homeUuid}_hidden_libraries'), isNull);
    });

    test('quarantined state does not become active because a profile is selected', () async {
      final coordinator = await build(activeProfile: profile);
      await PreferenceQuarantine.quarantine(
        settings.prefs,
        'hidden_libraries',
        reason: 'v1 cloud key carries no profile identity',
        seenAt: 1,
      );
      transport.store['hidden_libraries'] = enc('string', json.encode(['srv:1']));

      await coordinator.applyAllRemote();
      await coordinator.bootstrapFromLegacyV1();

      expect(settings.prefs.getString('user_${homeUuid}_hidden_libraries'), isNull);
      expect(PreferenceQuarantine.isQuarantined(settings.prefs, 'hidden_libraries'), isTrue);
    });

    test('a later real v2 mutation beats a bootstrapped value', () async {
      final coordinator = await build();
      transport.store['theme_mode'] = enc('string', 'dark');
      await coordinator.bootstrapFromLegacyV1();
      final legacy = coordinator.localRevision('theme_mode')!;

      await settings.prefs.setString('theme_mode', 'light');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'light'));
      final chosen = coordinator.localRevision('theme_mode')!;

      expect(chosen.winsOver(legacy), isTrue);
      expect(PreferenceRevision.resolve(legacy, chosen), chosen);
    });
  });

  group('a v1 event after cutover', () {
    test('cannot overwrite v2 state', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      // An old device writes the flat key.
      transport.store['subtitle_font_size'] = enc('int', 99);
      await coordinator.applyRemoteKeys(['subtitle_font_size']);

      expect(settings.prefs.getInt('subtitle_font_size'), 44, reason: 'v1 is never merged into v2');
    });

    test('does not delete the frozen v1 record either', () async {
      final coordinator = await build();
      transport.store['subtitle_font_size'] = enc('int', 99);
      transport.store[PreferenceSyncCoordinator.metaVersionKey] = enc('int', 1);
      await settings.prefs.setInt('subtitle_font_size', 44);

      await coordinator.reconcile();

      expect(transport.store['subtitle_font_size'], enc('int', 99));
      expect(transport.store.containsKey(PreferenceSyncCoordinator.metaVersionKey), isTrue);
      expect(transport.removes, isEmpty);
    });
  });

  group('the compatibility warning', () {
    test('post-cutover activity on a known v1 key raises it', () async {
      final coordinator = await build();
      transport.store['subtitle_font_size'] = enc('int', 99);

      await coordinator.applyRemoteKeys(['subtitle_font_size']);

      expect(coordinator.status.value.legacyPeerDetected, isTrue);
      expect(coordinator.status.value.state, PreferenceSyncState.warning);
    });

    test('it is not raised by an unrelated key somebody else owns', () async {
      final coordinator = await build();
      transport.store['a_key_nobody_registered'] = enc('int', 1);

      await coordinator.applyRemoteKeys(['a_key_nobody_registered']);

      expect(coordinator.status.value.legacyPeerDetected, isFalse);
    });

    test('it is a warning, not a failure: v2 records in the same batch still apply', () async {
      final coordinator = await build();
      final v2Key = '${PreferenceSyncScope.cloudNamespacePrefix}global/subtitle_font_size';
      transport.store['theme_mode'] = enc('string', 'dark'); // v1 peer activity
      transport.store[v2Key] = enc('int', 60);

      await coordinator.applyAllRemote();

      expect(settings.prefs.getInt('subtitle_font_size'), 60, reason: 'the v2 record still lands');
      expect(settings.prefs.getString('theme_mode'), isNull, reason: 'the v1 record still does not');
      expect(coordinator.status.value.legacyPeerDetected, isTrue);
    });
  });
}
