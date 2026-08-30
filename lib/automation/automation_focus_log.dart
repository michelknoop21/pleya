import 'package:flutter/widgets.dart';

import 'automation_event_log.dart';

/// One line of the focus timeline `GET /v1/focus/log?since=N` reads.
@immutable
class AutomationFocusLogEntry {
  final int seq;
  final DateTime at;
  final String? from;
  final String? to;

  /// What the app last saw as an early key event before this change — best
  /// effort causality, same idea as `SelectTraceRecorder`'s dispatch latch,
  /// just coarser (a key label, not a correlation id).
  final String? cause;

  const AutomationFocusLogEntry({required this.seq, required this.at, this.from, this.to, this.cause});

  Map<String, Object?> toJson() => {
    'seq': seq,
    'at': at.toIso8601String(),
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (cause != null) 'cause': cause,
  };
}

/// App-wide focus-change tracer.
///
/// `FocusManager.addListener` is *not* the hook: its signature
/// (`ValueChanged<FocusHighlightMode>`) only fires on highlight-mode changes
/// (mouse vs. keyboard/D-pad), never on the focus target moving. What does
/// fire reliably is each individual [FocusNode]'s own `ChangeNotifier`
/// listeners — `applyFocusChangesIfNeeded` marks *both* the node losing focus
/// and the one gaining it dirty and notifies them. So this keeps exactly one
/// listener attached to whichever node is currently primary, re-pointing it
/// every time that node's own notification fires (which happens right when
/// it loses focus to someone else).
///
/// **That listener alone is not enough, and the gap was silent.** It can only
/// be re-pointed by a notification from the node it is *already* attached to,
/// and [start] runs from `AutomationBootstrap` before the first frame — when
/// `primaryFocus` is null. So it attached to nothing, had nothing to hear
/// from, and never re-attached: every evidence bundle written up to Fase 11
/// contained an empty `focus-trace.json`, on iOS, macOS and tvOS alike, while
/// focus was demonstrably moving (a Left press visibly expanded the tvOS rail
/// from 48 to 220 logical pixels in the same run). Nothing failed; the
/// evidence was simply absent.
///
/// A per-frame re-check closes it. It costs one identity comparison per
/// frame, runs only under `kPleyaVerify`, and catches focus moving for
/// reasons no key event precedes — a programmatic `requestFocus` after a tab
/// switch, for instance, which is exactly what the TV navigation rail does.
/// The node listener stays as the fast path: it reports within the same
/// frame, the callback is the net underneath it.
class AutomationFocusLog {
  AutomationFocusLog._();

  static AutomationFocusLog instance = AutomationFocusLog._();

  @visibleForTesting
  static void debugSetInstance(AutomationFocusLog? log) {
    instance.stop();
    instance = log ?? AutomationFocusLog._();
  }

  static const int _maxEntries = 200;

  final List<AutomationFocusLogEntry> _entries = [];
  int _nextSeq = 1;
  FocusNode? _observedNode;
  String? _pendingCause;
  bool _started = false;
  bool _frameWatchInstalled = false;

  /// Gated by callers (`AutomationBootstrap` only calls this under
  /// `kPleyaVerify`) rather than internally, so this class stays directly
  /// unit-testable without a build define — same pattern as
  /// `AutomationRegistry`.
  void start() {
    if (_started) return;
    _started = true;
    FocusManager.instance.addEarlyKeyEventHandler(_captureCause);
    _reattach(initial: true);
    _installFrameWatch();
  }

  /// Re-checks the primary focus once per frame.
  ///
  /// A persistent frame callback cannot be removed once registered, so it
  /// guards on [_started] instead — [stop] therefore still fully disables
  /// this, which matters for tests that swap the instance out. Registered
  /// at most once per binding.
  ///
  /// Degrades silently without a `WidgetsBinding`, in the same shape as
  /// `AutomationRegistry._discoveredFocusables()`: this is diagnostic
  /// infrastructure and must never be the reason something else fails.
  void _installFrameWatch() {
    if (_frameWatchInstalled) return;
    try {
      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        if (!_started) return;
        _reattach();
      });
      _frameWatchInstalled = true;
    } catch (_) {
      // No binding (a plain unit test) — the node listener still works for
      // anything that focuses after a node is already primary.
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    FocusManager.instance.removeEarlyKeyEventHandler(_captureCause);
    try {
      _observedNode?.removeListener(_onObservedNodeNotified);
    } catch (_) {
      // Node may already be disposed — nothing to clean up in that case.
    }
    _observedNode = null;
  }

  KeyEventResult _captureCause(KeyEvent event) {
    _pendingCause = 'key:${event.logicalKey.keyLabel}';
    // Sees every real key event as it enters Flutter's normal pipeline —
    // including a genuine tvOS HID press via the geswizzelde `sendEvent:`
    // layer (see the tvOS-invoerroute-invariant, [C2]) — which is why this
    // has to be a *second* producer alongside dispatchAutomationKey's: a
    // scenario step injected via `/v1/input/key` never reaches here.
    AutomationEventLog.instance.emit('input.received', {'source': 'hardware', 'key': event.logicalKey.keyLabel});
    return KeyEventResult.ignored;
  }

  void _onObservedNodeNotified() => _reattach();

  void _reattach({bool initial = false}) {
    final current = FocusManager.instance.primaryFocus;
    if (identical(current, _observedNode) && !initial) return;

    String? from;
    try {
      from = _observedNode?.debugLabel;
      _observedNode?.removeListener(_onObservedNodeNotified);
    } catch (_) {
      from = null;
    }

    _observedNode = current;
    try {
      _observedNode?.addListener(_onObservedNodeNotified);
    } catch (_) {
      _observedNode = null;
    }

    if (initial) return; // Establishes the baseline; not a change worth logging.

    final to = current?.debugLabel;
    if (from == to) return;
    final cause = _pendingCause;
    _pendingCause = null;

    _entries.add(AutomationFocusLogEntry(seq: _nextSeq++, at: DateTime.now(), from: from, to: to, cause: cause));
    if (_entries.length > _maxEntries) _entries.removeAt(0);

    AutomationEventLog.instance.emit('focus.changed', {'from': ?from, 'to': ?to});
  }

  /// Entries with `seq > since`, oldest first.
  List<AutomationFocusLogEntry> since(int since) => _entries.where((e) => e.seq > since).toList();
}
