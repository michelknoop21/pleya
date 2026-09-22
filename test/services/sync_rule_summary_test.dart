import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/sync_rule_executor.dart';

/// The number in "Synced N new episodes for X" has to be episodes.
///
/// It was the number of *rules* that queued anything, and the title was the
/// first of them. Three rules queueing five, two and one episodes announced
/// "Synced 3 new episodes for Breaking Bad": wrong count, and two shows the
/// user was never told about. The targeted variant hardcoded the count to 1 and
/// smuggled the real number into the title instead.
SyncRuleResult _result(String title, int queued) =>
    SyncRuleResult(globalKey: 's:$title', title: title, queuedCount: queued);

void main() {
  group('the summary counts episodes, not rules', () {
    test('several rules add up, and no single title may be claimed', () {
      final summary = summariseSyncRuleResults([
        _result('Breaking Bad', 5),
        _result('The Wire', 2),
        _result('Severance', 1),
      ]);

      expect(summary.episodes, 8, reason: 'five plus two plus one, not "three rules"');
      expect(summary.rules, 3);
      expect(summary.soleTitle, isNull, reason: 'naming one of three shows tells the user something untrue');
    });

    test('one rule keeps its title, and reports its own count', () {
      final summary = summariseSyncRuleResults([_result('Breaking Bad', 5)]);

      expect(summary.episodes, 5);
      expect(summary.rules, 1);
      expect(summary.soleTitle, 'Breaking Bad');
    });

    test('rules that queued nothing are not counted and do not suppress a title', () {
      final summary = summariseSyncRuleResults([_result('Breaking Bad', 3), _result('The Wire', 0)]);

      expect(summary.episodes, 3);
      expect(summary.rules, 1);
      expect(summary.soleTitle, 'Breaking Bad', reason: 'only one rule actually did anything');
    });

    test('a rule without a title reports none rather than inventing one', () {
      final summary = summariseSyncRuleResults([const SyncRuleResult(globalKey: 's:1', queuedCount: 4)]);

      expect(summary.episodes, 4);
      expect(summary.soleTitle, isNull, reason: 'the caller substitutes its own "unknown" wording');
    });

    test('nothing queued is nothing to announce', () {
      final summary = summariseSyncRuleResults([_result('Breaking Bad', 0)]);

      expect(summary.episodes, 0);
      expect(summary.rules, 0);
      expect(summary.soleTitle, isNull);
    });

    test('an empty pass is empty', () {
      final summary = summariseSyncRuleResults(const []);

      expect(summary.episodes, 0);
      expect(summary.rules, 0);
      expect(summary.soleTitle, isNull);
    });
  });
}
