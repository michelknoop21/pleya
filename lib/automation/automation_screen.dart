import 'package:flutter/widgets.dart';

import 'automation_event_log.dart';
import 'automation_registry.dart';
import 'pleya_verify.dart';

enum AutomationReadinessState { loading, ready, error }

/// Whether a registered screen is ready for an agent to act on, and — when
/// it isn't — why. `reason` is free text (e.g. `'metadata'`,
/// `'seasons'`) for a report to show, not a machine-matched enum.
@immutable
class AutomationReadiness {
  final AutomationReadinessState state;
  final String? reason;

  const AutomationReadiness.ready() : state = AutomationReadinessState.ready, reason = null;

  const AutomationReadiness.loading([this.reason]) : state = AutomationReadinessState.loading;

  const AutomationReadiness.error([this.reason]) : state = AutomationReadinessState.error;

  bool get isReady => state == AutomationReadinessState.ready;

  Map<String, Object?> toJson() => {'state': state.name, 'ready': isReady, if (reason != null) 'reason': reason};
}

/// Registry backing `GET /v1/screens` — one entry per mounted
/// [AutomationScreen], polled lazily (only when a snapshot is actually
/// requested), never on a timer.
class AutomationScreenRegistry {
  AutomationScreenRegistry._();

  static AutomationScreenRegistry instance = AutomationScreenRegistry._();

  @visibleForTesting
  static void debugSetInstance(AutomationScreenRegistry? registry) {
    instance = registry ?? AutomationScreenRegistry._();
  }

  final Map<int, ({String id, ValueGetter<AutomationReadiness> readiness})> _screens = {};
  int _nextToken = 0;

  int register(String id, ValueGetter<AutomationReadiness> readiness) {
    final token = _nextToken++;
    _screens[token] = (id: id, readiness: readiness);
    return token;
  }

  void unregister(int token) => _screens.remove(token);

  List<Map<String, Object?>> snapshot() => [
    for (final entry in _screens.values) {'id': entry.id, ...entry.readiness().toJson()},
  ];
}

/// Wraps a screen with a stable automation id and a lazily-invoked readiness
/// callback. Pure pass-through in the render tree — never changes what's
/// built, only observes it — so wrapping a screen with this cannot change
/// real behavior, on any platform, regardless of what [readiness] returns.
///
/// Readiness transitions are detected off the screen's own rebuild cadence
/// (`didUpdateWidget` fires whenever the parent — which already rebuilds on
/// its own loading-state changes — recreates this widget), not an
/// independent poll: a `screen.ready` event fires the moment a rebuild
/// reveals the flip from not-ready to ready.
class AutomationScreen extends StatefulWidget {
  final String id;
  final ValueGetter<AutomationReadiness> readiness;
  final Widget child;

  const AutomationScreen({super.key, required this.id, required this.readiness, required this.child});

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  int? _token;
  int? _nodeToken;
  bool? _lastReady;

  @override
  void initState() {
    super.initState();
    _register();
    _checkReadiness();
  }

  @override
  void didUpdateWidget(AutomationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _unregister();
      _register();
    }
    _checkReadiness();
  }

  void _register() {
    if (!kPleyaVerify) return;
    // An indirection through this State, not the closure `widget.readiness`
    // happens to be at registration time. Screens build that closure inline
    // over their own loading fields, so every rebuild produces a new one
    // over new values; registering the first would freeze `/v1/screens` at
    // the readiness this screen had when it mounted — permanently "loading"
    // for a screen that has since finished, which is exactly what a
    // `wait_until: {id: screen.…}` step blocks on.
    _token = AutomationScreenRegistry.instance.register(widget.id, () => widget.readiness());
    // The same id as a node in `/v1/ui_tree`, so a scenario can ask where a
    // screen is and whether it is being drawn. Readiness alone cannot answer
    // the second question: the shell keeps every tab mounted in an
    // `IndexedStack`, and a tab parked behind the one on show reports itself
    // ready — and, being laid out, with a full-viewport rect as well.
    _nodeToken = AutomationRegistry.instance.register(
      AutomationDeclaredNode(id: widget.id, role: 'screen', contextGetter: () => mounted ? context : null),
    );
  }

  void _unregister() {
    final token = _token;
    if (token != null) AutomationScreenRegistry.instance.unregister(token);
    _token = null;
    final nodeToken = _nodeToken;
    if (nodeToken != null) AutomationRegistry.instance.unregister(nodeToken);
    _nodeToken = null;
  }

  void _checkReadiness() {
    if (!kPleyaVerify) return;
    final isReady = widget.readiness().isReady;
    if (_lastReady == isReady) return;
    _lastReady = isReady;
    if (isReady) {
      AutomationEventLog.instance.emit('screen.ready', {'id': widget.id});
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
