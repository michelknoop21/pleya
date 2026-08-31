import 'dart:typed_data';

import '../transport/verify_client.dart';
import 'instance_discovery.dart';

/// What `doctor()` reports — printable, and machine-readable enough for a
/// future `--json` (Fase 10 gives `tvos_sim.sh doctor --json` the same
/// shape).
class DriverDoctorReport {
  final bool ready;
  final Map<String, Object?> checks;

  const DriverDoctorReport({required this.ready, required this.checks});

  Map<String, Object?> toJson() => {'ready': ready, 'checks': checks};
}

/// One target's control surface: build the app, run it, drive it, tear it
/// down. `pleya_verify/runner/lib/src/engine/run_scenario.dart` is the only
/// caller — it never talks to a platform tool directly, so a new target is
/// exactly one new implementation of this interface.
///
/// [uiTree]/[focus]/[eventsSince]/[logs] always go through [client] (the
/// same transport contract every target implements identically); [press]/
/// [typeText]/[tap]/[screenshot] are where drivers diverge — tvOS's
/// (Fase 10) never touch [client] for input, per the tvOS-invoerroute-
/// invariant ([C2]).
abstract class VerificationDriver {
  /// The scenario `target:` value this driver handles, e.g. `'macos'`.
  String get target;

  /// The transport client bound to this driver's running instance. Only
  /// valid after [launch] — null before that or after [terminate].
  VerifyClient? get client;

  /// Which app instance [launch] bound to — the port it actually announced
  /// and how that was discovered. Null before a successful [launch]. A
  /// driver must never assume the base port here; see
  /// `instance_discovery.dart` for why that assumption silently produces a
  /// PASS against the wrong process.
  VerifyInstance? get instance;

  Future<DriverDoctorReport> doctor();

  /// Compiles (or otherwise prepares) the artifact [launch] will run.
  /// Idempotent to call more than once; a driver may skip recompiling if
  /// nothing changed, but must not silently run a stale artifact from a
  /// previous, unrelated build.
  Future<void> build();

  /// Wipes this driver's own persisted app state (never the developer's
  /// real one — see [MacosDriver]'s isolation doc) so the next [launch]
  /// starts from a blank slate.
  Future<void> installFresh();

  /// Starts the app and blocks until its `/v1/health` responds, or throws
  /// after [timeout].
  Future<void> launch({Duration timeout = const Duration(seconds: 20)});

  Future<void> terminate();

  Future<Map<String, Object?>> uiTree();

  Future<Map<String, Object?>> focus();

  /// `/v1/viewport` — the live view's size and safe-area insets, the frame
  /// geometry assertions measure against. `{'available': false}` when the
  /// app has no `WidgetsBinding` yet.
  Future<Map<String, Object?>> viewport();

  /// `/v1/screens`'s `screens` list — one entry per mounted
  /// `AutomationScreen`, `{id, state, ready}`.
  Future<List<Map<String, Object?>>> screensSnapshot();

  Future<List<Map<String, Object?>>> eventsSince(int since);

  Future<List<Map<String, Object?>>> focusLogSince(int since);

  Future<List<Map<String, Object?>>> logsSince(int since);

  /// A platform/compositor screenshot — the [C5] authoritative kind, never
  /// `/v1/screenshot`. Returns PNG bytes.
  Future<Uint8List> screenshot();

  /// `input_route` this call will record in the manifest — `'transport'`
  /// for a driver whose [press]/[tap] go through [client], `'idb'` for
  /// tvOS (Fase 10), which never does.
  String get inputRoute;

  Future<void> press(String key);

  Future<void> typeText(String text);

  Future<void> tap(double x, double y);

  /// The driver's own operational log (build/launch/terminate events,
  /// captured process stdout/stderr) — `driver.log` in the evidence
  /// bundle, distinct from [logsSince] (the app's own `/v1/logs`).
  List<String> get driverLog;
}
