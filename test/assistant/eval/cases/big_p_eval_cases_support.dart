export '../checks/big_p_eval_checks_extra.dart';

import '../big_p_eval_checks.dart';
import '../checks/big_p_eval_checks_extra.dart';

// Shared pieces of the per-area case files (BP-11a2).

const evalMutation = EvalNoMutationWithoutYes();
const evalFromFixture = EvalCardsFromFixture();
const evalNoDup = EvalNoDuplicates();

/// What every case must hold: cards from the catalogue, nothing changed
/// without a yes, no title twice.
const evalBase = <EvalHard>[evalFromFixture, evalMutation, evalNoDup];

/// A find_title call for [titles]; the first and last also serve as variants.
Map<String, Object?> evalFindArgs(List<String> titles, {String? kind}) => {
  'candidates': [
    for (final t in titles) {'title': t},
  ],
  'kind': ?kind,
  'variants': [titles.first, titles.last],
};
