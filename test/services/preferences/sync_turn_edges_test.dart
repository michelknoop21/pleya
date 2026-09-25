import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/preferences/preference_legacy_bootstrap.dart';
import 'package:pleya/services/preferences/preference_mutation.dart';
import 'package:pleya/services/preferences/preference_sync_coordinator.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import 'fake_transport.dart';

/// Final review minors 1, 2 and 5: what a sync turn may still do once it is no
/// longer the current one, and what has to wait for a turn.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final profile = plexHomeProfileId(accountConnectionId: 'conn', homeUserUuid: '6f1d2b3c-4e5a-4b7c-8d9e-0f1a2b3c4d5e');
  late SettingsService settings;
  late _ReadGate transport;
  var enabled = true;

  Future<PreferenceSyncCoordinator> build() async {
    settings = await SettingsService.getInstance();
    transport = _ReadGate();
    final c = PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: () => profile,
      enabled: () => enabled,
      deviceId: 'macbook',
      transport: transport,
      isServerIdPortable: (id) => id == 'plex',
    );
    await c.refreshAvailability();
    return c;
  }

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    enabled = true;
  });
  tearDown(() => BaseSharedPreferencesService.onMutation = null);

  Future<void> untilRead(int n) async {
    while (transport.reads < n) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a reconcile that timed out and lands late neither writes nor clears the timeout error', () async {
    final c = await build();
    c.turnTimeout = const Duration(milliseconds: 50);
    await settings.prefs.setInt('subtitle_font_size', 44);
    transport.writes.clear();

    unawaited(c.requestReconcile(ReconcileTrigger.imported)); // imported: straight to the reconcile's read
    await untilRead(1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.status.value.errorCategory, 'timeout');

    transport.gate.complete();
    await pumpEventQueue();

    expect(transport.writes, isEmpty, reason: 'the late turn works from a stale snapshot');
    expect(c.status.value.state, PreferenceSyncState.error);
    expect(c.status.value.errorCategory, 'timeout');
  });

  test('an account-change turn that hangs before its account branch neither clears stamps nor writes', () async {
    final c = await build();
    c.turnTimeout = const Duration(milliseconds: 50);
    await settings.prefs.setInt('subtitle_font_size', 44);
    await c.apply(const PreferenceMutation.set('subtitle_font_size', 44));
    transport.writes.clear();
    transport.availabilityGate = Completer<void>();

    unawaited(c.requestReconcile(ReconcileTrigger.accountChanged));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.status.value.errorCategory, 'timeout');

    transport.availabilityGate!.complete();
    await pumpEventQueue();

    expect(c.localRevision('subtitle_font_size'), isNotNull, reason: 'the late turn is not the current one');
    expect(transport.writes, isEmpty);

    // The account change is still pending, so the next turn of any kind runs
    // it. The new account's store holds an older value from another device:
    // with the previous account's stamp kept, this device's 44 would win.
    transport.availabilityGate = null;
    transport.gate.complete();
    c.turnTimeout = const Duration(seconds: 30);
    final key = c.cloudKeyFor('subtitle_font_size')!;
    transport.store[key] = json.encode({'type': 'int', 'value': 30, 't': 1000, 'd': 'appletv'});
    await c.requestReconcile(ReconcileTrigger.foreground);
    expect(settings.prefs.getInt('subtitle_font_size'), 30, reason: 'the stamps were cleared, so the store wins');
    expect(c.localRevision('subtitle_font_size')!.deviceId, 'appletv');

    // Handled once: the next turn orders by stamp again.
    await settings.prefs.setInt('subtitle_font_size', 50);
    await c.apply(const PreferenceMutation.set('subtitle_font_size', 50));
    await c.requestReconcile(ReconcileTrigger.foreground);
    expect(settings.prefs.getInt('subtitle_font_size'), 50);
    expect((json.decode(transport.store[key]!) as Map)['value'], 50);
  });

  test('the v1 import of a turn that is no longer current imports nothing and sets no marker', () async {
    final c = await build();
    transport.gate.complete();
    transport.store['subtitle_font_size'] = json.encode({'type': 'int', 'value': 30});

    await c.bootstrapFromLegacyV1(proceed: () => false);

    expect(settings.prefs.getInt('subtitle_font_size'), isNull);
    expect(PreferenceLegacyBootstrap.hasRun(settings.prefs), isFalse);
  });

  test('switching sync off during a reconcile stops its writes', () async {
    final c = await build();
    await settings.prefs.setInt('subtitle_font_size', 44);

    final running = c.requestReconcile(ReconcileTrigger.imported);
    await untilRead(1);
    enabled = false;
    await c.refreshAvailability();
    transport.gate.complete();
    await running;

    expect(transport.writes, isEmpty);
    expect(c.status.value.state, PreferenceSyncState.disabled);
  });

  test('a merge-family send waits for a running reconcile before it reads the store', () async {
    final c = await build();
    final key = 'user_${c.activeUserScope}_hidden_libraries';

    final running = c.requestReconcile(ReconcileTrigger.imported);
    await untilRead(1);
    await settings.prefs.setString(key, json.encode(['plex:1']));
    final sending = c.apply(PreferenceMutation.set(key, json.encode(['plex:1'])));
    await pumpEventQueue();
    expect(transport.reads, 1, reason: 'the send may not read the store while the reconcile holds it');

    transport.gate.complete();
    await running;
    await sending;

    expect(transport.reads, 2);
    expect((json.decode(transport.store[c.cloudKeyFor(key)!]!) as Map)['value'], json.encode(['plex:1']));
  });
}

/// The first store read takes its snapshot and then waits for the test.
class _ReadGate extends FakeTransport {
  final Completer<void> gate = Completer<void>();
  int reads = 0;

  /// When set, the availability check waits for it: the first await of a turn.
  Completer<void>? availabilityGate;

  @override
  Future<bool> isAvailable() async {
    await availabilityGate?.future;
    return super.isAvailable();
  }

  @override
  Future<Map<String, String>?> readAll() async {
    reads++;
    final snapshot = await super.readAll();
    if (reads == 1) await gate.future;
    return snapshot;
  }
}
