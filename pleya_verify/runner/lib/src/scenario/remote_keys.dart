/// The semantic remote vocabulary a `press:` step may use, and the parser
/// that turns a step's `args` into one.
///
/// One vocabulary, three consumers. `lib/automation/automation_input.dart`'s
/// `automationKeyNames` is the app's copy (the transport route, used by the
/// macOS and iOS drivers), `scripts/tvos_sim.sh`'s `hid_code_for` is the idb
/// HID copy (the tvOS route), and this is the runner's — which cannot import
/// either, being a separate package from the app and a Dart file rather than
/// bash. `remote_keys_sync_test.dart` parses both of the others and fails
/// when any of the three drifts, because a key that validates here and dies
/// at `die "onbekende toets"` three minutes into a booted simulator is
/// exactly the failure the validator exists to move forward in time.
const Set<String> remoteKeys = {'up', 'down', 'left', 'right', 'select', 'menu', 'delete', 'play_pause'};

/// A parsed `press:` step.
///
/// [hold] is what separates a long press from a short one, and it is not a
/// convenience: a long SELECT is a single HID press held between keyDown and
/// keyUp, whereas SELECT-sleep-SELECT is two activations, which tvOS opens no
/// context menu on and which would instead fire the tile's normal action
/// twice. Only the tvOS driver can express it — `/v1/input/key` synthesizes
/// one indivisible `simulateKeyPress` with no down/up split — so a `holdMs`
/// on any other target is rejected by the validator rather than silently
/// degraded into a short press.
class PressStep {
  final String key;
  final Duration? hold;

  const PressStep({required this.key, this.hold});

  bool get isLongPress => hold != null;

  @override
  String toString() => hold == null ? 'press($key)' : 'press($key, hold: ${hold!.inMilliseconds}ms)';
}

/// Thrown by [parsePressArgs] on anything the grammar does not accept. The
/// message is the one a scenario author reads next to `file:line`, so it
/// names the offending value and the accepted shape.
class PressArgsException implements Exception {
  final String message;

  const PressArgsException(this.message);

  @override
  String toString() => message;
}

/// `press: down` (the canonical short form, unchanged) or
/// `press: {key: select, holdMs: 1200}`.
///
/// The scalar form stays the primary spelling — every existing scenario uses
/// it and there is no reason to churn them — and the map form exists only
/// because a hold needs somewhere to live.
PressStep parsePressArgs(Object? args) {
  if (args is String) {
    _requireKnownKey(args);
    return PressStep(key: args);
  }
  if (args is Map) {
    final unknown = args.keys.where((k) => k != 'key' && k != 'holdMs').toList();
    if (unknown.isNotEmpty) {
      throw PressArgsException(
        "press does not accept ${unknown.map((k) => "'$k'").join(', ')} — only 'key' and 'holdMs'",
      );
    }
    final key = args['key'];
    if (key is! String) {
      throw const PressArgsException("press needs a 'key' field naming a remote key, e.g. {key: select, holdMs: 1200}");
    }
    _requireKnownKey(key);
    final holdRaw = args['holdMs'];
    if (holdRaw == null) return PressStep(key: key);
    if (holdRaw is! int || holdRaw <= 0) {
      throw PressArgsException("press holdMs must be a positive whole number of milliseconds, got '$holdRaw'");
    }
    return PressStep(
      key: key,
      hold: Duration(milliseconds: holdRaw),
    );
  }
  throw PressArgsException(
    'press takes a key name (`press: down`) or a map (`press: {key: select, holdMs: 1200}`), got: $args',
  );
}

void _requireKnownKey(String key) {
  if (remoteKeys.contains(key)) return;
  final known = (remoteKeys.toList()..sort()).join(', ');
  throw PressArgsException("unknown remote key '$key' — known keys: $known");
}
