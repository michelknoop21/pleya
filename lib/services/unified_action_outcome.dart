import '../i18n/strings.g.dart';

/// The one sentence the user gets after a write that targeted more than one
/// membership of the same title, or null when there is nothing worth saying.
///
/// Pure and top-level so the honesty rule is testable without a server, a
/// queue and a widget tree — the rule *is* the feature, and it was wrong in
/// two different ways before fase 9: the denominator counted only the sources
/// that happened to be reachable, and the message promised a retry for actions
/// that queue nothing.
///
/// - Everything landed: a tally only when there was more than one target. A
///   single write either worked or it did not, and "klaar op alle 1 bronnen"
///   is noise.
/// - Nothing landed and nothing was held: a plain failure.
/// - Something is held: hoofdstuk 13.4 point 5's message, retry clause and
///   all — there is a queue entry behind it. This is also the branch a fully
///   deferred removal takes (done 0, queued 3), which is a success the user
///   should see rather than the failure it would otherwise read as.
/// - Something landed but nothing is held: the same tally without the retry
///   clause, because nothing is going to be retried.
///
/// It lives here rather than with the TV context menu because it is no longer
/// a TV rule. Since [DEC-075](../../docs/DECISIONS.md#dec-075) a rating fans
/// out from the detail screen too, and a detail screen importing a TV context
/// menu to obtain a string is the kind of dependency that gets a helper copied
/// instead of shared.
String? unifiedActionOutcomeMessage({required int done, required int total, required int queued}) {
  if (done == total) return total > 1 ? t.tvContextMenu.doneOnAll(count: total) : null;
  if (done == 0 && queued == 0) return t.tvContextMenu.failed;
  if (queued > 0) return t.tvContextMenu.doneOnSome(done: done, total: total);
  return t.tvContextMenu.doneOnSomeNoRetry(done: done, total: total);
}
