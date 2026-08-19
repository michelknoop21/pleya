import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../widgets/hub_activation.dart';
import 'select_trace.dart';

/// The current semantic focus of a TV row: what the user is aimed at, as an
/// identity rather than a widget.
@immutable
class _FocusSnapshot {
  const _FocusSnapshot({required this.surface, required this.hubId, required this.index, required this.target});

  final String surface;
  final String hubId;
  final int index;
  final SelectTraceTarget target;
}

/// A rebuild that put a different item under a row's cursor, kept until the
/// press it explains arrives.
///
/// Carries the row it happened in: a change reported by one row must never
/// attach itself to a press that came from another, or the warning would name
/// a cause that has nothing to do with the title that opened.
@immutable
class _PendingFocusChange {
  const _PendingFocusChange({required this.surface, required this.hubId, required this.occupant, required this.entry});

  final String surface;
  final String hubId;

  /// Identity that took the cursor's slot. While the cursor still sits on it,
  /// this change keeps explaining the next press.
  final String occupant;

  final SelectTraceEntry entry;

  bool matches(String surface, String hubId) => surface == this.surface && hubId == this.hubId;
}

/// Correlates one Select press across the row, the navigation helper, the route
/// and the detail screen.
///
/// Three things this deliberately is not, because each of them was tried on
/// paper and is worse here:
///
/// - Not a Zone. The press crosses async gaps that a Zone would follow into
///   unrelated work, and a trace that follows everything answers nothing.
/// - Not an app-wide focus registry. Only rows report, and only their current
///   focus is kept: one field, no history.
/// - Not keyed on `FocusNode` identity. Nodes are recycled across rebuilds, so
///   node identity says nothing about item identity.
///
/// The correlation id leaves this class exactly once, at the Select key-up
/// edge, and from there it travels as an explicit parameter. Nothing downstream
/// may ask "which press is open right now": by the time a detail screen loads
/// its metadata a second press can already be in flight.
class SelectTraceRecorder {
  SelectTraceRecorder({
    DateTime Function()? now,
    bool? enabled,
    this.maxOpenTraces = 4,
    this.maxTimelineEntries = 24,
    void Function(String)? emitInfo,
    void Function(String)? emitWarning,
  }) : _now = now ?? DateTime.now,
       _forcedEnabled = enabled,
       // Wrapped, not torn off: `setLoggerLevel` replaces the `appLogger`
       // instance wholesale, so a captured tear-off would keep writing into
       // the logger that existed at construction time.
       _emitInfo = emitInfo ?? ((String line) => appLogger.i(line)),
       _emitWarning = emitWarning ?? ((String line) => appLogger.w(line));

  /// Process-wide recorder. Global for the same reason `HubFocusMemory` and
  /// `SelectKeyUpSuppressor` are: the reporters sit in unrelated widgets and
  /// threading an instance through every row would be its own refactor.
  static SelectTraceRecorder instance = SelectTraceRecorder();

  @visibleForTesting
  static void debugSetInstance(SelectTraceRecorder? recorder) {
    instance = recorder ?? SelectTraceRecorder();
  }

  final DateTime Function() _now;
  final bool? _forcedEnabled;
  final void Function(String) _emitInfo;
  final void Function(String) _emitWarning;

  /// A route transition can leave a previous press still resolving while the
  /// next one starts, so more than one trace may legitimately be open.
  final int maxOpenTraces;

  final int maxTimelineEntries;

  final Map<String, SelectTrace> _open = {};

  _FocusSnapshot? _focus;

  /// The last replacement or removal under the cursor, kept so a press that
  /// starts *after* the rebuild still carries the explanation.
  _PendingFocusChange? _pendingFocusChange;

  String? _pendingDispatchId;

  int _sequence = 0;

  /// Off outside TV, so the desktop and mobile paths carry null ids and every
  /// call here is a no-op. Same gate as `TextInputDiagnostics`.
  bool get _enabled => _forcedEnabled ?? PlatformDetector.isTV();

  @visibleForTesting
  Iterable<String> get debugOpenTraceIds => _open.keys;

  /// Records the row cursor's current position. Overwrites; no history is kept.
  void noteFocus({required String surface, required String hubId, required int index, required MediaItem item}) {
    if (!_enabled) return;
    final identity = hubItemIdentity(item);
    _focus = _FocusSnapshot(
      surface: surface,
      hubId: hubId,
      index: index,
      target: SelectTraceTarget(identity: identity, title: item.title ?? item.displayTitle),
    );
    // Only a move *away* from the card that took the slot drops the pending
    // explanation, and only the row that reported it may drop it. Re-notifying
    // the same position, which happens whenever the row regains focus or
    // rebuilds, must not erase it: that is precisely the moment the user is
    // still aimed at the swapped-in card.
    final pending = _pendingFocusChange;
    if (pending == null) return;
    if (!pending.matches(surface, hubId) || identity != pending.occupant) {
      _pendingFocusChange = null;
    }
  }

  /// Reports that a rebuild moved, replaced or removed the item the cursor
  /// pointed at. Reporting only: correcting the index is the row's business.
  void noteFocusedTargetChanged({
    required String surface,
    required String hubId,
    required int index,
    required String was,
    required String occupant,
    required SelectTraceDisposition disposition,
  }) {
    if (!_enabled) return;
    final detail =
        'focused_target_changed disposition=${disposition.name} surface=$surface hub=$hubId '
        'index=$index was=$was occupant=$occupant';
    for (final trace in _open.values) {
      // Only the row the press came from. A background refresh of an unrelated
      // hub would otherwise mark an in-flight press abnormal and hand the log a
      // cause that had nothing to do with the title that opened.
      if (!trace.belongsTo(surface, hubId)) continue;
      trace.addEntry(SelectTraceEntry(atMs: trace.elapsedMsAt(_now()), kind: 'anomaly', detail: detail));
      if (disposition.isAnomalous) trace.sawFocusedTargetChange = true;
    }

    final pending = _pendingFocusChange;
    if (!disposition.isAnomalous) {
      // A benign reorder clears this row's own pending change and leaves
      // another row's alone.
      if (pending != null && pending.matches(surface, hubId)) _pendingFocusChange = null;
      return;
    }
    _pendingFocusChange = _PendingFocusChange(
      surface: surface,
      hubId: hubId,
      occupant: occupant,
      entry: SelectTraceEntry(atMs: 0, kind: 'anomaly', detail: detail),
    );
  }

  /// Opens a trace at the Select key-down edge and returns its id.
  ///
  /// Returns null when tracing is off, which is what keeps every downstream
  /// signature inert on non-TV platforms.
  String? beginSelect({required String source}) {
    if (!_enabled) return null;
    _abandonUnclaimedLatch('superseded-by-new-select');

    final id = 's${(_sequence++).toRadixString(36)}';
    final focus = _focus;
    final trace = SelectTrace(
      id: id,
      source: source,
      openedAt: _now(),
      surface: focus?.surface ?? 'none',
      hubId: focus?.hubId ?? '',
      maxTimelineEntries: maxTimelineEntries,
    );
    if (focus != null) {
      trace.putLink(SelectTraceLink.selectedTarget, focus.target, atMs: 0, note: 'index=${focus.index}');
    }
    final pending = _pendingFocusChange;
    if (pending != null && focus != null && pending.matches(focus.surface, focus.hubId)) {
      trace.addEntry(pending.entry);
      trace.sawFocusedTargetChange = true;
    }

    _open[id] = trace;
    while (_open.length > maxOpenTraces) {
      // Through [abandon], so an evicted press that never reached a second link
      // stays silent. Those are the ordinary ones: a Select on a button leaves a
      // trace nobody claims, and warning about it would drown the real reports.
      abandon(_open.keys.first, 'evicted');
    }
    return id;
  }

  /// Latches [id] for the synchronous key-up dispatch window.
  ///
  /// Called from the input service *before* it clears its own pressed flag, so
  /// the flag never doubles as the correlation carrier.
  void dispatchSelect(String? id) {
    if (!_enabled) return;
    _abandonUnclaimedLatch('superseded-by-dispatch');
    _pendingDispatchId = id;
  }

  /// Hands the latched id to the row that is activating, exactly once.
  String? consumeActiveSelectTrace() {
    if (!_enabled) return null;
    final id = _pendingDispatchId;
    _pendingDispatchId = null;
    return id;
  }

  /// Records one link of the chain. A null [id] is a no-op, so callers never
  /// need to branch on whether tracing is on.
  void link(String? id, SelectTraceLink link, MediaItem item, {String? note}) {
    if (!_enabled || id == null) return;
    final trace = _open[id];
    if (trace == null) return;
    trace.putLink(
      link,
      SelectTraceTarget(identity: hubItemIdentity(item), title: item.title ?? item.displayTitle),
      atMs: trace.elapsedMsAt(_now()),
      note: note,
    );
  }

  /// Records that a row refused a stale activation.
  void noteActivationDropped(String? id, {required String detail}) {
    if (!_enabled || id == null) return;
    final trace = _open[id];
    if (trace == null) return;
    trace.sawActivationDropped = true;
    trace.addEntry(SelectTraceEntry(atMs: trace.elapsedMsAt(_now()), kind: 'anomaly', detail: detail));
  }

  /// Ends a trace and emits it: one info line when the chain held, one warning
  /// with the bounded timeline when it did not.
  void close(String? id, SelectTraceOutcome outcome) {
    if (!_enabled || id == null) return;
    _closeTrace(id, outcome);
  }

  /// Ends a trace that never reached an outcome.
  ///
  /// Silent when the press never got past its own starting point: a Select on a
  /// button, a settings row or the sidebar opens a trace and nothing claims it,
  /// and warning about that would drown the log. A trace that did reach a later
  /// link and then died is worth seeing.
  void abandon(String? id, String reason) {
    if (!_enabled || id == null) return;
    final trace = _open[id];
    if (trace == null) return;
    if (trace.links.length < 2) {
      _open.remove(id);
      if (_pendingDispatchId == id) _pendingDispatchId = null;
      return;
    }
    _closeTrace(id, SelectTraceOutcome.none, note: reason);
  }

  void _abandonUnclaimedLatch(String reason) {
    final pending = _pendingDispatchId;
    _pendingDispatchId = null;
    if (pending != null) abandon(pending, reason);
  }

  void _closeTrace(String id, SelectTraceOutcome outcome, {String? note}) {
    final trace = _open.remove(id);
    if (trace == null) return;
    if (_pendingDispatchId == id) _pendingDispatchId = null;
    trace.outcome = outcome;
    final elapsedMs = trace.elapsedMsAt(_now());
    if (note != null) {
      trace.wasAbandoned = true;
      trace.addEntry(SelectTraceEntry(atMs: elapsedMs, kind: 'abandoned', detail: note));
    }
    final verdict = evaluateSelectTrace(trace);
    if (verdict.isConsistent) {
      _emitInfo(formatSelectTraceLine(trace, elapsedMs: elapsedMs));
    } else {
      _emitWarning(formatSelectTraceReport(trace, verdict, elapsedMs: elapsedMs));
    }
  }
}
