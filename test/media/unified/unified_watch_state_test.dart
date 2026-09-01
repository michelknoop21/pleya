/// Covers docs/qa/tvos-unified-edge-cases.md register G1-G8 — hoofdstuk 13.2's
/// representative watch-state selection — at the level the contract is written
/// at: which source's progress speaks for a group, and which comparisons are
/// allowed to decide that.
///
/// Tier 1 (ownership/local-write authority) is deliberately absent here. It
/// runs upstream in `WatchStateStore`, which has already applied this
/// session's own writes to the items these tests hand in, and is covered by
/// `test/providers/watch_state_store_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/media/watch_progress.dart';

const _hour = 90 * 60 * 1000;

/// One source's item. [lastViewedAt] is epoch **seconds**, as every backend
/// reports it.
MediaItem _source({
  required String server,
  int? lastViewedAt,
  int? viewOffsetMs,
  int durationMs = _hour,
  int viewCount = 0,
}) => MediaItem(
  id: 'sintel',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  serverId: server,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
  viewCount: viewCount,
  lastViewedAt: lastViewedAt,
);

/// A source that finished the film.
MediaItem _watched({required String server, int? lastViewedAt, int durationMs = _hour}) =>
    _source(server: server, lastViewedAt: lastViewedAt, durationMs: durationMs, viewCount: 1);

const _base = 1_756_000_000;

void main() {
  group('hoofdstuk 13.2 representative watch state', () {
    test('G1: one source with active progress speaks for the group', () {
      final state = selectRepresentativeWatchState({
        'a': _source(server: 'a', viewOffsetMs: 20 * 60 * 1000, lastViewedAt: _base),
        'b': _source(server: 'b'),
      });

      expect(state.representativeSourceKey, 'a');
      expect(state.hasActiveProgress, isTrue);
      expect(state.isWatched, isFalse);
    });

    test('G2: two different positions are decided by the newer reliable timestamp', () {
      // Both are in progress; nothing but recency separates them, and the gap
      // is well beyond the margin.
      final state = selectRepresentativeWatchState({
        'a': _source(server: 'a', viewOffsetMs: 50 * 60 * 1000, lastViewedAt: _base),
        'b': _source(server: 'b', viewOffsetMs: 10 * 60 * 1000, lastViewedAt: _base + 3600),
      });

      expect(state.representativeSourceKey, 'b', reason: 'newest reliable state wins, not the highest offset');
      expect(state.lastViewedAt, _base + 3600);
    });

    test('G3: an older source with higher progress does not outrank a newer one', () {
      // "Gebruik niet blind de hoogste voortgang" — 13.2's opening sentence.
      final state = selectRepresentativeWatchState({
        'far-but-old': _source(server: 'a', viewOffsetMs: 80 * 60 * 1000, lastViewedAt: _base),
        'near-but-new': _source(server: 'b', viewOffsetMs: 2 * 60 * 1000, lastViewedAt: _base + 86400),
      });

      expect(state.representativeSourceKey, 'near-but-new');
    });

    test('G4: a demonstrably newer watched state beats older active progress', () {
      // Tier 2 settles this before tier 3 is ever consulted, which is what
      // stops the active-progress preference from undoing a real later
      // viewing on another device.
      final state = selectRepresentativeWatchState({
        'in-progress': _source(server: 'a', viewOffsetMs: 30 * 60 * 1000, lastViewedAt: _base),
        'watched': _watched(server: 'b', lastViewedAt: _base + 7200),
      });

      expect(state.representativeSourceKey, 'watched');
      expect(state.isWatched, isTrue);
    });

    test('G4: a stale watched bit does not bury a position the viewer is sitting at', () {
      // The mirror case. Within the margin the timestamps order nothing, so
      // tier 3 decides and resumable progress wins.
      final state = selectRepresentativeWatchState({
        'watched': _watched(server: 'b', lastViewedAt: _base + 5),
        'in-progress': _source(server: 'a', viewOffsetMs: 30 * 60 * 1000, lastViewedAt: _base),
      });

      expect(state.representativeSourceKey, 'in-progress');
      expect(state.hasActiveProgress, isTrue);
    });

    test('G5: a difference inside the reliability margin does not order the sources', () {
      final skew = watchStateReliabilityMargin.inSeconds - 1;
      final state = selectRepresentativeWatchState({
        'ahead-by-a-blink': _source(server: 'a', viewOffsetMs: 5 * 60 * 1000, lastViewedAt: _base + skew),
        'further-in': _source(server: 'b', viewOffsetMs: 40 * 60 * 1000, lastViewedAt: _base),
      });

      // Both survive tier 2, so the progress tiers get to speak — and they
      // pick the further position rather than the marginally newer clock.
      expect(state.representativeSourceKey, 'further-in');
    });

    test('G5: one second past the margin the newer source is believed', () {
      final beyond = watchStateReliabilityMargin.inSeconds + 1;
      final state = selectRepresentativeWatchState({
        'newer': _source(server: 'a', viewOffsetMs: 5 * 60 * 1000, lastViewedAt: _base + beyond),
        'further-in': _source(server: 'b', viewOffsetMs: 40 * 60 * 1000, lastViewedAt: _base),
      });

      expect(state.representativeSourceKey, 'newer');
    });

    test('G5: the margin is the one WatchStateStore already uses', () {
      // Two thresholds for one question is how the two halves drift apart.
      expect(watchStateReliabilityMargin, const Duration(seconds: 30));
    });

    test('G6: with no timestamps anywhere the progress tiers decide', () {
      final state = selectRepresentativeWatchState({
        'idle': _source(server: 'a'),
        'in-progress': _source(server: 'b', viewOffsetMs: 12 * 60 * 1000),
      });

      expect(state.representativeSourceKey, 'in-progress');
    });

    test('G6: a source with no timestamp loses to one that has any', () {
      // Not a skew question but an information one.
      final state = selectRepresentativeWatchState({
        'untimed': _source(server: 'a', viewOffsetMs: 70 * 60 * 1000),
        'timed': _source(server: 'b', viewOffsetMs: 60 * 1000, lastViewedAt: _base),
      });

      expect(state.representativeSourceKey, 'timed');
    });

    test('G6: no timestamps and no progress is still deterministic', () {
      final sources = {'a': _source(server: 'a'), 'b': _source(server: 'b')};

      expect(selectRepresentativeWatchState(sources).representativeSourceKey, 'a');
      expect(selectRepresentativeWatchState(sources).representativeSourceKey, 'a');
    });

    test('G8: a scrobble race lands inside the margin and is not resolved by the clock', () {
      // Two servers recording the same viewing seconds apart. Believing the
      // marginally later clock would make the card flip between two copies
      // for no reason a viewer can see.
      final a = _source(server: 'a', viewOffsetMs: 45 * 60 * 1000, lastViewedAt: _base + 2);
      final b = _source(server: 'b', viewOffsetMs: 45 * 60 * 1000, lastViewedAt: _base);

      expect(selectRepresentativeWatchState({'a': a, 'b': b}).representativeSourceKey, 'a');
      expect(
        selectRepresentativeWatchState({'b': b, 'a': a}).representativeSourceKey,
        'b',
        reason: 'a true tie keeps iteration order rather than inventing a winner',
      );
    });

    group('G7: runtime compatibility gate', () {
      test('runtimes within tolerance stay comparable', () {
        // A PAL transfer runs 4% short of its source; that is one cut, not two.
        final pal = _source(server: 'a', durationMs: (_hour * 0.96).round(), viewOffsetMs: 10 * 60 * 1000);
        final film = _source(server: 'b', durationMs: _hour, viewOffsetMs: 10 * 60 * 1000);

        expect(runtimesAreComparable(pal, film), isTrue);
        expect(selectRepresentativeWatchState({'a': pal, 'b': film}).runtimesDiffer, isFalse);
      });

      test('an extended cut is not comparable to the theatrical one', () {
        final extended = _source(server: 'a', durationMs: 3 * _hour);
        final theatrical = _source(server: 'b', durationMs: _hour);

        expect(runtimesAreComparable(extended, theatrical), isFalse);
      });

      test('a higher raw offset on an incompatible cut never wins on progress', () {
        // The sentence the gate exists to stop: "A is at 1:20:00 and B at
        // 0:40:00, so A is further" is not a fact about the title when A is a
        // three-hour cut.
        final longCut = _source(server: 'a', durationMs: 3 * _hour, viewOffsetMs: 80 * 60 * 1000);
        final shortCut = _source(server: 'b', durationMs: _hour, viewOffsetMs: 40 * 60 * 1000);

        final state = selectRepresentativeWatchState({'short': shortCut, 'long': longCut});

        expect(state.representativeSourceKey, 'short', reason: 'iteration order, not the longer cut\'s bigger number');
        expect(state.runtimesDiffer, isTrue);
      });

      test('active progress on an incompatible cut is not projected onto the other either', () {
        final other = _watched(server: 'a', durationMs: _hour);
        final incompatible = _source(server: 'b', durationMs: 3 * _hour, viewOffsetMs: 30 * 60 * 1000);

        final state = selectRepresentativeWatchState({'watched': other, 'in-progress': incompatible});

        expect(state.representativeSourceKey, 'watched');
        expect(state.runtimesDiffer, isTrue);
      });

      test('recency still decides across incompatible runtimes', () {
        // A timestamp is not progress: it orders viewings, not positions, so
        // the gate has no business blocking it.
        final older = _source(server: 'a', durationMs: 3 * _hour, viewOffsetMs: 80 * 60 * 1000, lastViewedAt: _base);
        final newer = _source(server: 'b', durationMs: _hour, viewOffsetMs: 60 * 1000, lastViewedAt: _base + 86400);

        final state = selectRepresentativeWatchState({'older': older, 'newer': newer});

        expect(state.representativeSourceKey, 'newer');
      });

      test('an unknown runtime is not a conflict', () {
        // Missing metadata must not silently disable the tier for a backend
        // that ships a slim field set; such an item can never report active
        // progress anyway.
        final unknown = MediaItem(
          id: 'sintel',
          backend: MediaBackend.jellyfin,
          kind: MediaKind.movie,
          title: 'Sintel',
          serverId: 'a',
          viewOffsetMs: 10 * 60 * 1000,
        );
        final known = _source(server: 'b', viewOffsetMs: 40 * 60 * 1000);

        expect(runtimesAreComparable(unknown, known), isTrue);
        expect(selectRepresentativeWatchState({'unknown': unknown, 'known': known}).representativeSourceKey, 'known');
      });

      test('one incompatible pair makes the whole group source-bound', () {
        // Comparability is not transitive, and a group that is coherent for
        // one pair and not another has no single answer. The honest reading
        // is the conservative one.
        final a = _source(server: 'a', durationMs: _hour, viewOffsetMs: 10 * 60 * 1000);
        final b = _source(server: 'b', durationMs: _hour, viewOffsetMs: 50 * 60 * 1000);
        final extended = _source(server: 'c', durationMs: 3 * _hour, viewOffsetMs: 20 * 60 * 1000);

        final state = selectRepresentativeWatchState({'a': a, 'b': b, 'c': extended});

        expect(state.runtimesDiffer, isTrue);
        expect(state.representativeSourceKey, 'a', reason: 'no progress tier ran, so iteration order stands');
      });
    });

    group('tier 4: the remembered choice', () {
      test('breaks a tie every earlier tier judged equal', () {
        final a = _source(server: 'a', viewOffsetMs: 20 * 60 * 1000, lastViewedAt: _base);
        final b = _source(server: 'b', viewOffsetMs: 20 * 60 * 1000, lastViewedAt: _base);

        expect(
          selectRepresentativeWatchState({'a': a, 'b': b}, preferredSourceKey: 'b').representativeSourceKey,
          'b',
        );
      });

      test('never overrules a source an earlier tier already picked', () {
        // "Niet: preferred source wint altijd."
        final stale = _source(server: 'a', viewOffsetMs: 20 * 60 * 1000, lastViewedAt: _base);
        final fresh = _source(server: 'b', viewOffsetMs: 5 * 60 * 1000, lastViewedAt: _base + 86400);

        final state = selectRepresentativeWatchState({'stale': stale, 'fresh': fresh}, preferredSourceKey: 'stale');

        expect(state.representativeSourceKey, 'fresh');
      });

      test('a preference naming no present source changes nothing', () {
        final a = _source(server: 'a', lastViewedAt: _base);
        final b = _source(server: 'b', lastViewedAt: _base);

        final state = selectRepresentativeWatchState({'a': a, 'b': b}, preferredSourceKey: 'server-c:sintel');

        expect(state.representativeSourceKey, 'a');
      });

      test('is not consulted before the progress tiers', () {
        final behind = _source(server: 'a', viewOffsetMs: 60 * 1000, lastViewedAt: _base);
        final ahead = _source(server: 'b', viewOffsetMs: 60 * 60 * 1000, lastViewedAt: _base);

        final state = selectRepresentativeWatchState({'behind': behind, 'ahead': ahead}, preferredSourceKey: 'behind');

        expect(state.representativeSourceKey, 'ahead');
      });
    });
  });
}
