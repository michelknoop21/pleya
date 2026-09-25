import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/preferences/preference_sync_status.dart';
import 'package:pleya/services/preferences/preference_transport.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// A10. Three axes, because one `state` field lost information: a single
/// successful write set `success` and the quota stop, the transport error and
/// the legacy-peer warning that were still true vanished from the UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime.utc(2026, 8, 21, 12);
  final later = DateTime.utc(2026, 8, 21, 13);

  group('a success cannot erase a condition', () {
    test('quota survives a successful single write', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);
      final quota = start.raise(PreferenceSyncHealth.quota);

      final after = quota.writeSucceeded(at);

      expect(after.state, PreferenceSyncState.quota);
      expect(after.lastSuccess, at);
    });

    test('an error and its category survive a successful single write', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);
      final failed = start.raise(PreferenceSyncHealth.error, errorCategory: 'PlatformException');

      final after = failed.writeSucceeded(at);

      expect(after.state, PreferenceSyncState.error);
      expect(after.errorCategory, 'PlatformException');
    });

    test('a legacy peer survives every success', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      final after = start
          .sawLegacyPeer()
          .writeSucceeded(at)
          .reconcileSucceeded(later, pushedCount: 3, skippedCount: 0, oversizeCount: 0);

      expect(after.legacyPeerDetected, isTrue);
      expect(after.state, PreferenceSyncState.warning);
    });

    test('raising a lighter condition does not lower a heavier one', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      final after = start.raise(PreferenceSyncHealth.quota).raise(PreferenceSyncHealth.warning);

      expect(after.health, PreferenceSyncHealth.quota);
    });

    test('a reconcile does not clear a quota stop: the store never reports that it was lifted', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      final after = start
          .raise(PreferenceSyncHealth.quota)
          .reconcileSucceeded(at, pushedCount: 3, skippedCount: 0, oversizeCount: 0);

      expect(after.state, PreferenceSyncState.quota);
    });

    test('a single write cannot promote a signed-out store to ready', () {
      const signedOut = PreferenceSyncStatus(availability: PreferenceSyncAvailability.unavailable);

      final after = signedOut.starting(at).writeSucceeded(at);

      expect(after.availability, PreferenceSyncAvailability.unavailable);
    });
  });

  group('a full pass is what clears health', () {
    test('a reconcile clears an earlier error', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);
      final failed = start.raise(PreferenceSyncHealth.error, errorCategory: 'StateError');

      final after = failed.reconcileSucceeded(at, pushedCount: 2, skippedCount: 0, oversizeCount: 0);

      expect(after.state, PreferenceSyncState.success);
      expect(after.errorCategory, isNull);
    });

    test('a reconcile that skipped an oversize value stays a warning', () {
      const start = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      final after = start.reconcileSucceeded(at, pushedCount: 2, skippedCount: 0, oversizeCount: 1);

      expect(after.state, PreferenceSyncState.warning);
      expect(after.oversize, 1);
    });
  });

  group('the eight states derive from the axes', () {
    test('every combination produces exactly one state, and availability wins', () {
      for (final availability in PreferenceSyncAvailability.values) {
        for (final activity in PreferenceSyncActivity.values) {
          for (final health in PreferenceSyncHealth.values) {
            for (final legacy in [false, true]) {
              final status = PreferenceSyncStatus(
                availability: availability,
                activity: activity,
                health: health,
                legacyPeerDetected: legacy,
                lastSuccess: at,
              );
              final state = status.state;
              switch (availability) {
                case PreferenceSyncAvailability.disabled:
                  expect(state, PreferenceSyncState.disabled);
                case PreferenceSyncAvailability.unknown:
                  expect(state, PreferenceSyncState.idle);
                case PreferenceSyncAvailability.unavailable:
                  expect(state, PreferenceSyncState.unavailable);
                case PreferenceSyncAvailability.ready:
                  if (activity == PreferenceSyncActivity.syncing) {
                    expect(state, PreferenceSyncState.syncing);
                  } else {
                    expect(state, isNot(PreferenceSyncState.disabled));
                    expect(state, isNot(PreferenceSyncState.unavailable));
                    expect(state, isNot(PreferenceSyncState.syncing));
                  }
              }
            }
          }
        }
      }
    });

    test('idle means nothing has succeeded yet; success needs a real one', () {
      const ready = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      expect(ready.state, PreferenceSyncState.idle);
      expect(ready.writeSucceeded(at).state, PreferenceSyncState.success);
    });

    test('needsAttention is exactly warning, error and quota', () {
      const ready = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);

      expect(ready.needsAttention, isFalse);
      expect(ready.writeSucceeded(at).needsAttention, isFalse);
      expect(ready.raise(PreferenceSyncHealth.warning).needsAttention, isTrue);
      expect(ready.raise(PreferenceSyncHealth.error).needsAttention, isTrue);
      expect(ready.raise(PreferenceSyncHealth.quota).needsAttention, isTrue);
    });
  });

  group('through the engine', () {
    const homeUuid = '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e';
    final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: homeUuid);

    late SettingsService settings;
    late FakeTransport transport;
    var enabled = true;

    Future<PreferenceSyncCoordinator> build() async {
      settings = await SettingsService.getInstance();
      transport = FakeTransport();
      return PreferenceSyncCoordinator(
        prefs: settings.prefs,
        activeProfileId: () => profile,
        enabled: () => enabled,
        deviceId: 'macbook',
        transport: transport,
      );
    }

    setUp(() {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      enabled = true;
    });

    tearDown(() => BaseSharedPreferencesService.onMutation = null);

    test('a quota event is not wiped by the next successful write', () async {
      final coordinator = await build();
      coordinator.listen();
      transport.controller.add(const RemotePreferenceChange(reason: RemoteChangeReason.quotaExceeded));
      await Future<void>.value();
      expect(coordinator.status.value.state, PreferenceSyncState.quota);

      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      expect(coordinator.status.value.state, PreferenceSyncState.quota);
      expect(coordinator.status.value.pushed, 1);
    });

    test('a transport error is not wiped by the next successful write, but a reconcile clears it', () async {
      final coordinator = await build();
      transport.throwOnWrite = StateError('down');
      await coordinator.apply(const PreferenceMutation.set('theme_mode', 'dark'));
      expect(coordinator.status.value.state, PreferenceSyncState.error);

      transport.throwOnWrite = null;
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      expect(coordinator.status.value.state, PreferenceSyncState.error);

      await coordinator.reconcile();
      expect(coordinator.status.value.state, PreferenceSyncState.success);
    });

    test('switching the toggle off reports disabled rather than a failure', () async {
      final coordinator = await build();
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));
      expect(coordinator.status.value.state, PreferenceSyncState.success);

      enabled = false;
      await coordinator.refreshAvailability();

      expect(coordinator.status.value.state, PreferenceSyncState.disabled);
    });

    test('a signed-out store reports unavailable, not error', () async {
      final coordinator = await build();
      transport.available = false;

      await coordinator.refreshAvailability();

      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
    });

    test('a write while iCloud is signed out does not report a send', () async {
      final coordinator = await build();
      transport.available = false;
      await coordinator.refreshAvailability();

      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
      expect(coordinator.status.value.lastSuccess, isNull);
      expect(transport.writes, isEmpty);
    });

    test('before availability answers the status is unknown, not signed out, and nothing is sent', () async {
      final coordinator = await build();
      coordinator.markAvailabilityUnknown();

      expect(coordinator.status.value.availability, PreferenceSyncAvailability.unknown);
      expect(coordinator.status.value.state, isNot(PreferenceSyncState.unavailable));

      await settings.prefs.setInt('subtitle_font_size', 44);
      await coordinator.apply(const PreferenceMutation.set('subtitle_font_size', 44));

      expect(transport.writes, isEmpty);
      expect(coordinator.status.value.lastSuccess, isNull);
      expect(coordinator.localRevision('subtitle_font_size'), isNotNull, reason: 'stamped all the same');
    });

    test('a reconcile while iCloud is signed out writes nothing and stays unavailable', () async {
      final coordinator = await build();
      await settings.prefs.setInt('subtitle_font_size', 44);
      transport.available = false;

      await coordinator.requestReconcile(ReconcileTrigger.foreground);

      expect(transport.writes, isEmpty);
      expect(coordinator.status.value.state, PreferenceSyncState.unavailable);
    });
  });
}
