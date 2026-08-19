import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/diagnostics/select_trace.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/media_navigation_helper.dart';

/// The rule that decides whether one Select press behaved.
///
/// Pure for the same reason `resolveHubActivation` is: "did the target survive
/// the trip from the card to the screen" should be answerable without a device,
/// a navigator or a frame. What it must not do is cry wolf about the one hop
/// that legitimately changes the target, an episode opening its series.
void main() {
  SelectTraceTarget target(String identity) => SelectTraceTarget(identity: identity, title: 'Title $identity');

  SelectTrace traceWith(Map<SelectTraceLink, String> links, {SelectTraceOutcome outcome = SelectTraceOutcome.detail}) {
    final trace = SelectTrace(id: 's0', source: 'native', openedAt: DateTime(2026));
    links.forEach((link, identity) => trace.putLink(link, target(identity), atMs: 0));
    trace.outcome = outcome;
    return trace;
  }

  const fullChain = {
    SelectTraceLink.selectedTarget: 's1:41215',
    SelectTraceLink.activatedTarget: 's1:41215',
    SelectTraceLink.expectedNavigationTarget: 's1:41215',
    SelectTraceLink.actualNavigationTarget: 's1:41215',
    SelectTraceLink.detailTarget: 's1:41215',
    SelectTraceLink.metadataTarget: 's1:41215',
  };

  group('evaluateSelectTrace', () {
    test('a chain that holds end to end is consistent', () {
      expect(evaluateSelectTrace(traceWith(fullChain)).isConsistent, isTrue);
    });

    test('an episode opening its series is not an alarm', () {
      // The whole reason `expected` runs through mediaDetailNavigationTargetFor:
      // activating an episode is supposed to land on the show. Comparing
      // activated against expected directly would flag every episode press.
      final episode = MediaItem.plex(
        id: '900',
        kind: MediaKind.episode,
        serverId: 's1',
        title: 'The One With The Trace',
        grandparentId: '41215',
        grandparentTitle: 'Joey',
      );
      final show = mediaDetailNavigationTargetFor(episode).metadata;
      expect(show.id, '41215', reason: 'the mapping is what makes the two differ');

      final trace = traceWith({
        SelectTraceLink.selectedTarget: 's1:900',
        SelectTraceLink.activatedTarget: 's1:900',
        SelectTraceLink.expectedNavigationTarget: 's1:41215',
        SelectTraceLink.actualNavigationTarget: 's1:41215',
        SelectTraceLink.detailTarget: 's1:41215',
        SelectTraceLink.metadataTarget: 's1:41215',
      });

      expect(evaluateSelectTrace(trace).isConsistent, isTrue);
    });

    test('names the first broken comparison', () {
      final cases = {
        'activated!=selected': SelectTraceLink.activatedTarget,
        'actual!=expected': SelectTraceLink.actualNavigationTarget,
        'detail!=actual': SelectTraceLink.detailTarget,
        'metadata!=detail': SelectTraceLink.metadataTarget,
      };

      cases.forEach((expectedBreak, brokenLink) {
        final links = Map<SelectTraceLink, String>.from(fullChain);
        for (final link in SelectTraceLink.values) {
          if (link.index >= brokenLink.index) links[link] = 's1:9082';
        }
        final verdict = evaluateSelectTrace(traceWith(links));
        expect(verdict.isConsistent, isFalse, reason: expectedBreak);
        expect(verdict.brokenAt, expectedBreak);
        expect(verdict.anomaly, SelectTraceAnomaly.linkMismatch);
      });
    });

    test('missing links are skipped rather than treated as a break', () {
      // A press that ended in the player never records a detail target. That is
      // not a mismatch, and warning about it would bury the real ones.
      final trace = traceWith({
        SelectTraceLink.selectedTarget: 's1:41215',
        SelectTraceLink.activatedTarget: 's1:41215',
      }, outcome: SelectTraceOutcome.player);
      expect(evaluateSelectTrace(trace).isConsistent, isTrue);
    });

    test('a replaced or removed focus target is abnormal even when the chain holds', () {
      // This is what a chain-only check cannot say: the log would show that the
      // press opened what it activated, and stay silent about the refresh that
      // put a different card under the cursor first.
      final trace = traceWith(fullChain)..sawFocusedTargetChange = true;
      final verdict = evaluateSelectTrace(trace);
      expect(verdict.isConsistent, isFalse);
      expect(verdict.anomaly, SelectTraceAnomaly.focusedTargetChanged);
    });

    test('a dropped activation is abnormal', () {
      final trace = traceWith({SelectTraceLink.selectedTarget: 's1:41215'}, outcome: SelectTraceOutcome.dropped)
        ..sawActivationDropped = true;
      expect(evaluateSelectTrace(trace).anomaly, SelectTraceAnomaly.activationDropped);
    });

    test('a press that died is abnormal, one that simply opened nothing is not', () {
      // The difference is why `wasAbandoned` exists next to the outcome: a
      // press that resolved to nothing is ordinary, a press that never got an
      // answer at all is the one worth a line.
      expect(evaluateSelectTrace(traceWith(fullChain, outcome: SelectTraceOutcome.none)).isConsistent, isTrue);

      final died = traceWith(fullChain, outcome: SelectTraceOutcome.none)..wasAbandoned = true;
      expect(evaluateSelectTrace(died).anomaly, SelectTraceAnomaly.unterminated);
    });
  });

  group('disposition', () {
    test('only a replacement or a removal is worth a warning', () {
      // Continue Watching reorders on every finished episode. If `moved` were
      // anomalous, every second press would produce a warning and the ones that
      // matter would drown.
      expect(SelectTraceDisposition.moved.isAnomalous, isFalse);
      expect(SelectTraceDisposition.replaced.isAnomalous, isTrue);
      expect(SelectTraceDisposition.removed.isAnomalous, isTrue);
    });
  });

  group('timeline', () {
    test('coalesces an exact repeat instead of appending it', () {
      final trace = SelectTrace(id: 's0', source: 'native', openedAt: DateTime(2026));
      for (var i = 0; i < 5; i++) {
        trace.addEntry(const SelectTraceEntry(atMs: 1, kind: 'anomaly', detail: 'same'));
      }
      expect(trace.timeline, hasLength(1));
      expect(trace.timeline.single.repeats, 5);
    });

    test('stops growing at its budget and counts what it dropped', () {
      final trace = SelectTrace(id: 's0', source: 'native', openedAt: DateTime(2026), maxTimelineEntries: 3);
      for (var i = 0; i < 10; i++) {
        trace.addEntry(SelectTraceEntry(atMs: i, kind: 'anomaly', detail: 'line $i'));
      }
      expect(trace.timeline, hasLength(3));
      expect(trace.droppedEntries, 7);
    });
  });

  group('formatting', () {
    test('the normal form is one line naming every link it has', () {
      final line = formatSelectTraceLine(traceWith(fullChain), elapsedMs: 812);
      expect(line, contains('outcome=detail'));
      expect(line, contains('selected=s1:41215'));
      expect(line, contains('metadata=s1:41215'));
      expect(line, contains('ms=812'));
      expect(line.split('\n'), hasLength(1));
    });

    test('the abnormal form names the break and prints the timeline', () {
      final trace = traceWith(fullChain)..sawFocusedTargetChange = true;
      trace.addEntry(const SelectTraceEntry(atMs: 140, kind: 'anomaly', detail: 'focused_target_changed'));
      final report = formatSelectTraceReport(trace, evaluateSelectTrace(trace), elapsedMs: 812);
      expect(report, contains('ABNORMAL'));
      expect(report, contains('focused_target_changed'));
      expect(report.split('\n').length, greaterThan(1));
    });
  });
}
