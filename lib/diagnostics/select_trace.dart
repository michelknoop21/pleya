import 'package:flutter/foundation.dart';

/// One link in the chain a single Select press walks, from the card the user
/// was looking at to the metadata the detail screen ends up showing.
///
/// The chain exists because "the wrong title opened" is not answerable from a
/// log that only records HTTP: every one of these steps can legitimately change
/// the target, and only the pairwise comparison says which one changed it
/// wrongly. See [evaluateSelectTrace] for which pairs must agree.
enum SelectTraceLink {
  /// Where the row cursor pointed when Select went down.
  selectedTarget,

  /// What the row's activation resolved to when Select came up.
  activatedTarget,

  /// `mediaDetailNavigationTargetFor(activated).metadata`, computed at the
  /// activation site. An episode legitimately maps to its show or season here.
  expectedNavigationTarget,

  /// The metadata actually handed to `mediaDetailRoute`.
  actualNavigationTarget,

  /// `widget.metadata` as the detail screen received it.
  detailTarget,

  /// The metadata the server returned for that item.
  metadataTarget,
}

extension SelectTraceLinkLabel on SelectTraceLink {
  /// Short name used in the log line. Kept separate from [name] so the log
  /// stays scannable without shortening the enum itself.
  String get label => switch (this) {
    SelectTraceLink.selectedTarget => 'selected',
    SelectTraceLink.activatedTarget => 'activated',
    SelectTraceLink.expectedNavigationTarget => 'expected',
    SelectTraceLink.actualNavigationTarget => 'actual',
    SelectTraceLink.detailTarget => 'detail',
    SelectTraceLink.metadataTarget => 'metadata',
  };
}

/// What happened to the item under the cursor when a row rebuilt.
///
/// One anomaly with three dispositions rather than three anomalies: a log that
/// only says "the item is gone" cannot show that a refresh put a *different*
/// card under the same index, and that replacement is the original defect.
enum SelectTraceDisposition {
  /// The item is still in the row, at another position. Normal bookkeeping;
  /// Continue Watching reorders on every finished episode.
  moved,

  /// The item is still in the row, but another item now sits at the index the
  /// cursor points at.
  replaced,

  /// The item is no longer in the row at all.
  removed,
}

extension SelectTraceDispositionSeverity on SelectTraceDisposition {
  /// Whether this disposition makes a trace worth a warning on its own.
  ///
  /// [SelectTraceDisposition.moved] happens constantly and says nothing; the
  /// other two mean the cursor and the item it stood on have come apart.
  bool get isAnomalous => this != SelectTraceDisposition.moved;
}

/// Something that happened during a trace which is not a link in the chain.
enum SelectTraceAnomaly {
  /// The item under the cursor was replaced or removed by a rebuild.
  focusedTargetChanged,

  /// The row refused to activate a stale identity, so nothing opened.
  activationDropped,

  /// Two links that must agree do not.
  linkMismatch,

  /// The trace never reached an outcome and was closed to stay within budget.
  unterminated,
}

/// How a trace ended.
enum SelectTraceOutcome {
  /// A media detail screen opened and loaded its metadata.
  detail,

  /// Playback started directly.
  player,

  /// A whole-hub screen opened (View All, or a rail's trailing card).
  hubDetail,

  /// The long-press context menu opened instead of an activation.
  contextMenu,

  /// The host of the row claimed the activation and did its own thing with it
  /// (the TV detail rail routes some kinds itself).
  handledByHost,

  /// The activation was refused because the focused item was stale.
  dropped,

  /// Nothing opened.
  none,
}

/// An item as a trace records it: identity plus the title a human recognises.
@immutable
class SelectTraceTarget {
  const SelectTraceTarget({required this.identity, required this.title});

  /// `MediaItem.globalKey`, i.e. `serverId:id`.
  final String identity;

  final String title;

  @override
  bool operator ==(Object other) => other is SelectTraceTarget && other.identity == identity && other.title == title;

  @override
  int get hashCode => Object.hash(identity, title);

  @override
  String toString() => '$identity "$title"';
}

/// One line of a trace's timeline.
@immutable
class SelectTraceEntry {
  const SelectTraceEntry({required this.atMs, required this.kind, required this.detail, this.repeats = 1});

  final int atMs;

  /// `selected`, `activated`, `anomaly`, `abandoned`, and so on.
  final String kind;

  final String detail;

  /// How many identical consecutive occurrences this line stands for.
  final int repeats;

  SelectTraceEntry incremented() => SelectTraceEntry(atMs: atMs, kind: kind, detail: detail, repeats: repeats + 1);

  /// True when [other] would be an exact repeat of this line.
  bool repeatsWith(SelectTraceEntry other) => other.kind == kind && other.detail == detail;

  @override
  String toString() {
    final suffix = repeats > 1 ? ' x$repeats' : '';
    return '+${atMs}ms $kind $detail$suffix';
  }
}

/// One Select press, from the cursor that was aimed to the screen that opened.
///
/// Mutable on purpose: the recorder owns exactly one of these per open press
/// and fills it in as the press travels. Everything that decides *whether the
/// trace is normal* lives in [evaluateSelectTrace], which is pure.
class SelectTrace {
  SelectTrace({
    required this.id,
    required this.source,
    required this.openedAt,
    this.surface = 'none',
    this.hubId = '',
    this.maxTimelineEntries = 24,
  });

  /// Short correlation id, carried as an explicit parameter from the moment of
  /// activation onwards. Never looked up again from global state.
  final String id;

  /// Which input path opened this trace (`native`, `click_s`, `rail-fallback`).
  final String source;

  final DateTime openedAt;

  /// Which row the cursor sat in when the press started. Kept as fields rather
  /// than one formatted string because a rebuild elsewhere must not be able to
  /// attach itself to this press: a report only lands here when it names the
  /// same surface and hub.
  final String surface;
  final String hubId;

  /// Whether [surface] and [hubId] name the row this press came from.
  bool belongsTo(String surface, String hubId) => surface == this.surface && hubId == this.hubId;

  final int maxTimelineEntries;

  final Map<SelectTraceLink, SelectTraceTarget> links = {};

  final List<SelectTraceEntry> timeline = [];

  SelectTraceOutcome outcome = SelectTraceOutcome.none;

  /// Set when a rebuild replaced or removed the item under the cursor. This is
  /// what turns "activated is not what was selected" from a mystery into an
  /// explanation.
  bool sawFocusedTargetChange = false;

  bool sawActivationDropped = false;

  /// Set when the user deliberately chose a different source in the unified
  /// source picker (hoofdstuk 14 of docs/tvos-unified-experience.md).
  ///
  /// Without this, a source switch would read as the exact defect this trace
  /// exists to catch: `selectedTarget` is the card's representative source,
  /// `activatedTarget` becomes the source the user picked, and the two
  /// `serverId:itemId` values legitimately differ. [evaluateSelectTrace] skips
  /// that one comparison when this is set — every later pair still has to
  /// hold, so a swap *after* the choice is still caught.
  bool sawSourceSelection = false;

  /// Set when a trace was ended because it died rather than because it reached
  /// an outcome. Kept apart from [outcome] being [SelectTraceOutcome.none]:
  /// plenty of presses legitimately open nothing (music, a still-loading
  /// trailing card, a person row), and warning about those would drown the
  /// reports this whole subsystem exists to make findable.
  bool wasAbandoned = false;

  /// Timeline lines dropped because the buffer was full.
  int droppedEntries = 0;

  int elapsedMsAt(DateTime now) => now.difference(openedAt).inMilliseconds;

  /// Appends a line, coalescing an exact repeat of the previous one and
  /// refusing to grow past [maxTimelineEntries].
  void addEntry(SelectTraceEntry entry) {
    if (timeline.isNotEmpty && timeline.last.repeatsWith(entry)) {
      timeline[timeline.length - 1] = timeline.last.incremented();
      return;
    }
    if (timeline.length >= maxTimelineEntries) {
      droppedEntries++;
      return;
    }
    timeline.add(entry);
  }

  /// Records a link and its timeline line in one step.
  void putLink(SelectTraceLink link, SelectTraceTarget target, {required int atMs, String? note}) {
    links[link] = target;
    final suffix = note == null ? '' : ' $note';
    addEntry(SelectTraceEntry(atMs: atMs, kind: link.label, detail: '$target$suffix'));
  }
}

/// Whether a trace's chain holds, and where it breaks if it does not.
@immutable
class SelectTraceVerdict {
  const SelectTraceVerdict.consistent() : isConsistent = true, anomaly = null, brokenAt = null;

  const SelectTraceVerdict.broken({required this.anomaly, this.brokenAt}) : isConsistent = false;

  final bool isConsistent;
  final SelectTraceAnomaly? anomaly;

  /// Which comparison failed, as `activated!=selected`.
  final String? brokenAt;
}

/// The pairs that must agree, in the order they are reported.
///
/// `activated` versus `expected` is deliberately absent: the mapping from an
/// episode to its show or season runs through `mediaDetailNavigationTargetFor`,
/// so a difference there is correct behaviour and not a false alarm. That is
/// exactly why `expected` is computed at the activation site and `actual` at the
/// route boundary; comparing those two is what catches a swap in between.
const List<(SelectTraceLink, SelectTraceLink)> selectTraceComparisons = [
  (SelectTraceLink.selectedTarget, SelectTraceLink.activatedTarget),
  (SelectTraceLink.expectedNavigationTarget, SelectTraceLink.actualNavigationTarget),
  (SelectTraceLink.actualNavigationTarget, SelectTraceLink.detailTarget),
  (SelectTraceLink.detailTarget, SelectTraceLink.metadataTarget),
];

/// Decides whether one press behaved normally.
///
/// Pure, for the same reason `resolveHubActivation` is: the rule that matters
/// here is "did the target survive the trip", and it should be checkable without
/// a widget tree, a navigator or a device.
SelectTraceVerdict evaluateSelectTrace(SelectTrace trace) {
  for (final (from, to) in selectTraceComparisons) {
    // The one pair a user is allowed to break, and only by choosing a source
    // by hand. Narrowed to exactly this pair rather than short-circuiting the
    // whole loop: the picker changes which source opens, it does not license
    // a mismatch between the route boundary and what the detail screen shows.
    if (trace.sawSourceSelection && from == SelectTraceLink.selectedTarget && to == SelectTraceLink.activatedTarget) {
      continue;
    }
    final before = trace.links[from];
    final after = trace.links[to];
    if (before == null || after == null) continue;
    if (before.identity != after.identity) {
      return SelectTraceVerdict.broken(
        anomaly: SelectTraceAnomaly.linkMismatch,
        brokenAt: '${to.label}!=${from.label}',
      );
    }
  }

  if (trace.sawFocusedTargetChange) {
    return const SelectTraceVerdict.broken(anomaly: SelectTraceAnomaly.focusedTargetChanged);
  }
  if (trace.sawActivationDropped) {
    return const SelectTraceVerdict.broken(anomaly: SelectTraceAnomaly.activationDropped);
  }
  if (trace.wasAbandoned) {
    return const SelectTraceVerdict.broken(anomaly: SelectTraceAnomaly.unterminated);
  }
  return const SelectTraceVerdict.consistent();
}

/// The one-line form, emitted when a press behaved normally.
String formatSelectTraceLine(SelectTrace trace, {required int elapsedMs}) {
  final buffer = StringBuffer('Select trace ${trace.id}: outcome=${trace.outcome.name} source=${trace.source}');
  buffer.write(' surface=${trace.surface} hub=${trace.hubId}');
  for (final link in SelectTraceLink.values) {
    final target = trace.links[link];
    if (target != null) buffer.write(' ${link.label}=${target.identity}');
  }
  // Without this a reader of a *consistent* line would see `selected` and
  // `activated` naming different servers and have nothing to explain it.
  if (trace.sawSourceSelection) buffer.write(' sourcePick=user');
  final headline = trace.links[SelectTraceLink.activatedTarget] ?? trace.links[SelectTraceLink.selectedTarget];
  if (headline != null) buffer.write(' title="${headline.title}"');
  buffer.write(' ms=$elapsedMs');
  return buffer.toString();
}

/// The multi-line form, emitted when a press did not behave normally. The
/// timeline is already bounded by [SelectTrace.maxTimelineEntries].
String formatSelectTraceReport(SelectTrace trace, SelectTraceVerdict verdict, {required int elapsedMs}) {
  final reason = verdict.brokenAt ?? verdict.anomaly?.name ?? 'unknown';
  final buffer = StringBuffer(
    'Select trace ${trace.id} ABNORMAL break=$reason outcome=${trace.outcome.name} '
    'source=${trace.source} ms=$elapsedMs',
  );
  buffer.write(' surface=${trace.surface} hub=${trace.hubId}');
  for (final entry in trace.timeline) {
    buffer.write('\n  $entry');
  }
  if (trace.droppedEntries > 0) {
    buffer.write('\n  (${trace.droppedEntries} more lines dropped)');
  }
  return buffer.toString();
}
