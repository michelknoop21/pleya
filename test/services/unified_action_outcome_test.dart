import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/unified_action_outcome.dart';

/// The one sentence a multi-membership write ends on.
///
/// It lives in its own file because the rule outgrew the TV context menu that
/// first needed it: since [DEC-075](../../docs/DECISIONS.md#dec-075) a rating
/// fans out from the detail screen too, and reports through this same
/// function. Guarding it here rather than under `test/widgets/tv/` is what
/// keeps that from reading as a TV rule other surfaces borrowed.
void main() {
  // G10: the message the fan-out ends on. Hoofdstuk 13.4 point 5 fixes both
  // halves of it — the denominator and the retry clause — and both were wrong
  // before fase 9: the count read only the reachable sources, and the retry
  // clause was shown for actions that queue nothing.
  group('the outcome message tells the truth about what landed', () {
    test('a single write that worked says nothing at all', () {
      expect(unifiedActionOutcomeMessage(done: 1, total: 1, queued: 0), isNull);
    });

    test('everything landing on several sources is a tally', () {
      expect(unifiedActionOutcomeMessage(done: 3, total: 3, queued: 0), t.tvContextMenu.doneOnAll(count: 3));
    });

    test('two of three, with the third queued, promises the retry', () {
      expect(unifiedActionOutcomeMessage(done: 2, total: 3, queued: 1), t.tvContextMenu.doneOnSome(done: 2, total: 3));
      expect(t.tvContextMenu.doneOnSome(done: 2, total: 3), contains('3'));
    });

    test('two of three with nothing queued drops the retry clause', () {
      // The promise "the rest will be retried" may only appear when a queue
      // entry exists. An action that queues nothing must not borrow it.
      final message = unifiedActionOutcomeMessage(done: 2, total: 3, queued: 0);

      expect(message, t.tvContextMenu.doneOnSomeNoRetry(done: 2, total: 3));
      expect(message, isNot(t.tvContextMenu.doneOnSome(done: 2, total: 3)));
      expect(message, isNot(contains(t.tvContextMenu.doneOnSome(done: 2, total: 3).split('. ').last)));
    });

    test('a removal held on every membership reads as held, not as failed', () {
      // Nothing was written, but the user's intent is safely recorded and the
      // card is gone. Reporting a failure here would be the opposite of what
      // happened.
      expect(unifiedActionOutcomeMessage(done: 0, total: 2, queued: 2), t.tvContextMenu.doneOnSome(done: 0, total: 2));
    });

    test('nothing landed and nothing held is a plain failure', () {
      expect(unifiedActionOutcomeMessage(done: 0, total: 2, queued: 0), t.tvContextMenu.failed);
    });
  });

  // DEC-075: rating reuses this function with `queued: 0`, and two of its four
  // branches become structurally unreachable in the process. That is the
  // argument for reuse rather than a second set of strings, so it is worth a
  // test rather than a comment.
  group('a rating fan-out reaches exactly the branches it should', () {
    test('one of two sources drops the retry clause', () {
      // A rating holds nothing back for a reconnect, so the sentence must not
      // promise one.
      expect(
        unifiedActionOutcomeMessage(done: 1, total: 2, queued: 0),
        t.tvContextMenu.doneOnSomeNoRetry(done: 1, total: 2),
      );
    });

    test('the plain-failure branch cannot be reached by a rating at all', () {
      // The mirror only exists once the sheet's own write returned, so its
      // `doneCount` starts at one. `done: 0` is therefore not a rating state,
      // which is what makes the failure branch safe to leave in place.
      expect(unifiedActionOutcomeMessage(done: 0, total: 2, queued: 0), t.tvContextMenu.failed);
      expect(unifiedActionOutcomeMessage(done: 1, total: 2, queued: 0), isNot(t.tvContextMenu.failed));
    });
  });
}
