import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tools.dart';

import 'big_p_eval_checks.dart';
import 'big_p_eval_fixtures.dart';
import 'big_p_eval_world.dart';
import 'checks/big_p_eval_checks_extra.dart';

// Negative control of every extra hard check (BP-11a2): a hand-built bad
// answer must fail it, and a good one must pass. A check that cannot fail
// would let a whole group of cases pass for the wrong reason.

AssistantMediaGrid _grid(List<String> titles) =>
    AssistantMediaGrid([for (final t in titles) (item: evalTitle(t)!.item, group: null)]);

EvalOutcome _outcome(List<({String text, List<String> cards, List<String> tools})> turns) {
  final o = EvalOutcome();
  for (final t in turns) {
    o.turns.add(
      EvalTurnOutcome(
        prompt: 'q',
        result: AssistantRunResult(
          end: AssistantRunEnd.answered,
          text: t.text,
          displays: t.cards.isEmpty ? const [] : [_grid(t.cards)],
        ),
      )..tools.addAll(t.tools),
    );
  }
  return o;
}

({String text, List<String> cards, List<String> tools}) _turn(
  String text, {
  List<String> cards = const [],
  List<String> tools = const [],
}) => (text: text, cards: cards, tools: tools);

void main() {
  test('EvalNoDuplicates: a card twice or a title written twice fails', () {
    const check = EvalNoDuplicates();
    expect(
      check.check(
        _outcome([
          _turn('Kijk.', cards: ['Coco', 'Frozen', 'Coco']),
        ]),
      ),
      isNotEmpty,
    );
    expect(check.check(_outcome([_turn('«Coco» (2017) en nog eens «Coco» (2017).')])), isNotEmpty);
    expect(
      check.check(
        _outcome([
          _turn('Kijk «Coco» (2017).', cards: ['Coco', 'Frozen']),
        ]),
      ),
      isEmpty,
    );
  });

  test('EvalOnlyProfile: a title or fact of the other profile fails', () {
    const check = EvalOnlyProfile(evalMichel, evalSanne, otherFacts: ['geen horror']);
    // Sanne alone watched Coco, Moana, Mary Poppins and Gilmore Girls.
    expect(
      check.check(
        _outcome([
          _turn('Je keek Moana.', cards: ['Moana']),
        ]),
      ),
      isNotEmpty,
    );
    expect(check.check(_outcome([_turn('Je keek «Gilmore Girls» (2000).')])), isNotEmpty);
    expect(check.check(_outcome([_turn('Je wilde geen horror zien.')])), isNotEmpty);
    // Michel's own, and the one title both watched (The Office is Sanne's pick, not Michel's seen).
    expect(
      check.check(
        _outcome([
          _turn('Je keek «Inception» (2010).', cards: ['Inception']),
        ]),
      ),
      isEmpty,
    );
  });

  test('EvalHonestMissing: a confirmed status fails, "weet ik niet" passes', () {
    const check = EvalHonestMissing();
    expect(check.check(_outcome([_turn('Er zijn nieuwe afleveringen van Bluey beschikbaar.')])), isNotEmpty);
    expect(check.check(_outcome([_turn('Seizoen 3 is uit.')])), isNotEmpty);
    expect(check.check(_outcome([_turn('Of er nieuwe afleveringen zijn uitgekomen weet ik niet.')])), isEmpty);
    expect(check.check(_outcome([_turn('Er zijn geen nieuwe afleveringen bekend.')])), isEmpty);
  });

  test('EvalCardsMatchText: more titles named than cards fails', () {
    const check = EvalCardsMatchText();
    expect(
      check.check(
        _outcome([
          _turn('Kijk «Coco» (2017), «Frozen» (2013) of «Moana» (2016).', cards: ['Coco']),
        ]),
      ),
      isNotEmpty,
    );
    expect(
      check.check(
        _outcome([
          _turn('Kijk «Coco» (2017).', cards: ['Coco', 'Frozen']),
        ]),
      ),
      isEmpty,
    );
    expect(check.check(_outcome([_turn('Geen titels hier.')])), isEmpty);
  });

  test('EvalNotRepeated: a title shown again in a follow-up fails', () {
    const check = EvalNotRepeated();
    expect(
      check.check(
        _outcome([
          _turn('Kijk Coco.', cards: ['Coco']),
          _turn('Of Coco.', cards: ['Coco', 'Up']),
        ]),
      ),
      isNotEmpty,
    );
    expect(check.check(_outcome([_turn('Kijk «Coco» (2017).'), _turn('Of «Coco» (2017).')])), isNotEmpty);
    expect(
      check.check(
        _outcome([
          _turn('Kijk Coco.', cards: ['Coco']),
          _turn('Of Up.', cards: ['Up']),
        ]),
      ),
      isEmpty,
    );
    expect(
      const EvalNotRepeated(fromTurn: 2).check(
        _outcome([
          _turn('x', cards: ['Coco']),
          _turn('x', cards: ['Coco']),
        ]),
      ),
      isEmpty,
    );
  });

  test('EvalToolUsed and EvalCardCount: the wrong tool or count fails', () {
    final o = _outcome([
      _turn('Kijk.', cards: ['Coco', 'Up'], tools: ['search_catalog']),
    ]);
    expect(const EvalToolUsed('trakt_watchlist').check(o), isNotEmpty);
    expect(const EvalToolUsed('search_catalog').check(o), isEmpty);
    expect(const EvalCardCount(min: 3).check(o), isNotEmpty);
    expect(const EvalCardCount(max: 1).check(o), isNotEmpty);
    expect(const EvalCardCount(min: 1, max: 2).check(o), isEmpty);
  });
}
