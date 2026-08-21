import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/diagnostics/select_trace.dart';
import 'package:pleya/diagnostics/select_trace_recorder.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';

/// The recorder's job is correlation, and the failure it is built against is
/// subtle: a second Select press starting while the first is still resolving.
/// Everything here is about the id leaving the recorder exactly once, at the
/// right moment, and never being looked up again afterwards.
void main() {
  MediaItem item(String id) => MediaItem.plex(id: id, kind: MediaKind.movie, serverId: 's1', title: 'Title $id');

  late List<String> info;
  late List<String> warnings;

  SelectTraceRecorder build({int maxOpenTraces = 4, int maxTimelineEntries = 24}) {
    info = [];
    warnings = [];
    return SelectTraceRecorder(
      enabled: true,
      now: () => DateTime(2026),
      maxOpenTraces: maxOpenTraces,
      maxTimelineEntries: maxTimelineEntries,
      emitInfo: info.add,
      emitWarning: warnings.add,
    );
  }

  void completeChain(SelectTraceRecorder recorder, String? id, MediaItem target) {
    recorder
      ..link(id, SelectTraceLink.activatedTarget, target)
      ..link(id, SelectTraceLink.expectedNavigationTarget, target)
      ..link(id, SelectTraceLink.actualNavigationTarget, target)
      ..link(id, SelectTraceLink.detailTarget, target)
      ..link(id, SelectTraceLink.metadataTarget, target);
  }

  test('is inert when tracing is off, so the desktop path carries null ids', () {
    final recorder = SelectTraceRecorder(
      enabled: false,
      emitInfo: (_) => fail('nothing should be emitted'),
      emitWarning: (_) => fail('nothing should be emitted'),
    );
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    expect(recorder.beginSelect(source: 'native'), isNull);
    expect(recorder.consumeActiveSelectTrace(), isNull);
  });

  test('hands the latched id to the first claimant and to nobody after that', () {
    // The rule from the review: after an async gap nothing may ask "which press
    // is open". Consuming clears the latch, so a later lookup gets nothing
    // rather than the wrong press.
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final id = recorder.beginSelect(source: 'native');
    recorder.dispatchSelect(id);

    expect(recorder.consumeActiveSelectTrace(), id);
    expect(recorder.consumeActiveSelectTrace(), isNull);
  });

  test('a press nobody claimed is dropped without noise', () {
    // Select on a button, a settings row or the sidebar opens a trace that no
    // row ever claims. Warning about those would bury the ones that matter.
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final first = recorder.beginSelect(source: 'native');
    recorder.dispatchSelect(first);

    recorder.beginSelect(source: 'native');

    expect(warnings, isEmpty);
    expect(info, isEmpty);
    expect(recorder.debugOpenTraceIds, isNot(contains(first)));
  });

  test('a press that got somewhere and then died is reported', () {
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final id = recorder.beginSelect(source: 'native');
    recorder.link(id, SelectTraceLink.activatedTarget, item('a'));

    recorder.abandon(id, 'rail-unmounted');

    expect(warnings, hasLength(1));
    expect(warnings.single, contains('rail-unmounted'));
  });

  test('a complete chain closes as a single info line', () {
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'recentlyAdded', index: 3, item: item('41215'));
    final id = recorder.beginSelect(source: 'native');
    completeChain(recorder, id, item('41215'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings, isEmpty);
    expect(info, hasLength(1));
    expect(info.single, contains('surface=tv-rail hub=recentlyAdded'));
    expect(info.single, contains('selected=s1:41215'));
  });

  test('a chain that opens somebody else closes as a warning naming the break', () {
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'recentlyAdded', index: 3, item: item('41215'));
    final id = recorder.beginSelect(source: 'native');
    completeChain(recorder, id, item('9082'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(info, isEmpty);
    expect(warnings.single, contains('break=activated!=selected'));
    expect(warnings.single, contains('s1:9082'));
  });

  test('a press that legitimately opens nothing is not a warning', () {
    // Music, a still-loading trailing card, a person row: all close with
    // `none` and all are perfectly ordinary. Warning about them would bury the
    // reports this whole subsystem exists to make findable.
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final id = recorder.beginSelect(source: 'native');
    recorder.link(id, SelectTraceLink.activatedTarget, item('a'));
    recorder.close(id, SelectTraceOutcome.none);

    expect(warnings, isEmpty);
    expect(info, hasLength(1));
    expect(info.single, contains('outcome=none'));
  });

  test('a replacement under the cursor lands in every open trace', () {
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 3, item: item('41215'));
    final id = recorder.beginSelect(source: 'native');

    recorder.noteFocusedTargetChanged(
      surface: 'tv-rail',
      hubId: 'h',
      index: 3,
      was: 's1:41215',
      occupant: 's1:9082',
      disposition: SelectTraceDisposition.replaced,
    );
    completeChain(recorder, id, item('9082'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings.single, contains('focused_target_changed disposition=replaced'));
  });

  test('a replacement is carried into a press that starts after it', () {
    // The rebuild happens while no key is down; the user presses a beat later.
    // Without carrying it, the log would show the swap and the press as two
    // unrelated facts.
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 3, item: item('41215'));
    recorder.noteFocusedTargetChanged(
      surface: 'tv-rail',
      hubId: 'h',
      index: 3,
      was: 's1:41215',
      occupant: 's1:9082',
      disposition: SelectTraceDisposition.replaced,
    );

    final id = recorder.beginSelect(source: 'native');
    completeChain(recorder, id, item('9082'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings.single, contains('focused_target_changed'));
  });

  test('a deliberate move clears a carried replacement', () {
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 3, item: item('41215'));
    recorder.noteFocusedTargetChanged(
      surface: 'tv-rail',
      hubId: 'h',
      index: 3,
      was: 's1:41215',
      occupant: 's1:9082',
      disposition: SelectTraceDisposition.replaced,
    );
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 4, item: item('7'));

    final id = recorder.beginSelect(source: 'native');
    completeChain(recorder, id, item('7'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings, isEmpty);
    expect(info, hasLength(1));
  });

  test('a reorder that the row corrects for is recorded but does not warn', () {
    final recorder = build();
    recorder.noteFocus(surface: 'hub-section', hubId: 'h', index: 3, item: item('41215'));
    final id = recorder.beginSelect(source: 'native');
    recorder.noteFocusedTargetChanged(
      surface: 'hub-section',
      hubId: 'h',
      index: 3,
      was: 's1:41215',
      occupant: 's1:9082',
      disposition: SelectTraceDisposition.moved,
    );
    completeChain(recorder, id, item('41215'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings, isEmpty);
    expect(info, hasLength(1));
  });

  test('a change in another row cannot mark this press abnormal', () {
    // Every row rebuilds on every refresh. Without keying the report on the row
    // it came from, a background hub nobody is looking at would hand this press
    // a cause that has nothing to do with the title that opened, and the whole
    // point of the trace is that its warnings mean something.
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'recentlyAdded', index: 3, item: item('41215'));
    final id = recorder.beginSelect(source: 'native');

    recorder.noteFocusedTargetChanged(
      surface: 'tv-rail',
      hubId: 'someOtherHub',
      index: 0,
      was: 's1:aaa',
      occupant: 's1:bbb',
      disposition: SelectTraceDisposition.replaced,
    );
    completeChain(recorder, id, item('41215'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings, isEmpty);
    expect(info, hasLength(1));
  });

  test('a benign change elsewhere leaves this row pending explanation alone', () {
    final recorder = build();
    recorder.noteFocus(surface: 'tv-rail', hubId: 'recentlyAdded', index: 3, item: item('41215'));
    recorder.noteFocusedTargetChanged(
      surface: 'tv-rail',
      hubId: 'recentlyAdded',
      index: 3,
      was: 's1:41215',
      occupant: 's1:9082',
      disposition: SelectTraceDisposition.replaced,
    );
    recorder.noteFocusedTargetChanged(
      surface: 'hub-section',
      hubId: 'someOtherHub',
      index: 0,
      was: 's1:aaa',
      occupant: 's1:bbb',
      disposition: SelectTraceDisposition.moved,
    );

    recorder.noteFocus(surface: 'tv-rail', hubId: 'recentlyAdded', index: 3, item: item('9082'));
    final id = recorder.beginSelect(source: 'native');
    completeChain(recorder, id, item('9082'));
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings.single, contains('focused_target_changed'));
  });

  test('holds more than one press, because a route transition overlaps them', () {
    final recorder = build(maxOpenTraces: 2);
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final first = recorder.beginSelect(source: 'native');
    final second = recorder.beginSelect(source: 'native');

    expect(recorder.debugOpenTraceIds, containsAll([first, second]));
  });

  test('evicts the oldest press rather than growing without bound', () {
    final recorder = build(maxOpenTraces: 2);
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final first = recorder.beginSelect(source: 'native');
    recorder.link(first, SelectTraceLink.activatedTarget, item('a'));
    recorder.beginSelect(source: 'native');
    recorder.beginSelect(source: 'native');

    expect(recorder.debugOpenTraceIds, hasLength(2));
    expect(recorder.debugOpenTraceIds, isNot(contains(first)));
    expect(warnings.single, contains('evicted'));
  });

  test('an evicted press that reached nothing is dropped in silence', () {
    // A key-down whose release never arrives, because a native text-input
    // session opened over it, ends up here. It never reached a widget, so the
    // eviction must not turn it into a warning about an unfinished press.
    final recorder = build(maxOpenTraces: 1);
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    recorder.beginSelect(source: 'native');
    recorder.beginSelect(source: 'native');

    expect(recorder.debugOpenTraceIds, hasLength(1));
    expect(warnings, isEmpty);
    expect(info, isEmpty);
  });

  test('bounds the timeline of one press', () {
    final recorder = build(maxTimelineEntries: 3);
    recorder.noteFocus(surface: 'tv-rail', hubId: 'h', index: 0, item: item('a'));
    final id = recorder.beginSelect(source: 'native');
    for (var i = 0; i < 40; i++) {
      recorder.noteFocusedTargetChanged(
        surface: 'tv-rail',
        hubId: 'h',
        index: i,
        was: 's1:a',
        occupant: 's1:b',
        disposition: SelectTraceDisposition.replaced,
      );
    }
    recorder.close(id, SelectTraceOutcome.detail);

    expect(warnings.single, contains('lines dropped'));
  });
}
