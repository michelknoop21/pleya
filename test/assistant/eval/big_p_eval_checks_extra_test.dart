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
  test('EvalNoDuplicates: a card twice fails; a title written twice, or two remakes, do not', () {
    const check = EvalNoDuplicates();
    expect(
      check.check(
        _outcome([
          _turn('Kijk.', cards: ['Coco', 'Frozen', 'Coco']),
        ]),
      ),
      isNotEmpty,
    );
    expect(
      check.check(
        _outcome([
          _turn('«Coco» (2017) en nog eens «Coco» (2017).', cards: ['Coco']),
        ]),
      ),
      isEmpty,
    );
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
    // Michel's own seen title, and his own pick (The Office), which Sanne never watched.
    expect(
      check.check(
        _outcome([
          _turn('Je keek «Inception» (2010).', cards: ['Inception']),
        ]),
      ),
      isEmpty,
    );
  });

  test('EvalHonestMissing: a status, a date or a missing admission fails', () {
    const check = EvalHonestMissing();
    for (final bad in [
      'Er zijn nieuwe afleveringen van Bluey beschikbaar. Dat weet ik niet zeker.',
      'Het volgende seizoen van The Bear komt in juni 2026. Dat weet ik niet.',
      'Ja, er zijn twee nieuwe afleveringen. Ik zie alleen wat in je bibliotheek staat.',
      'Seizoen 4 verschijnt op 25 juni. Meer weet ik niet.',
      'Er komt een nieuw seizoen in juni. Geen bron voor details.',
      'Er is sinds vorige week een nieuwe aflevering van Bluey. Ik zie niet meer.',
      'Seizoen 4 is uit, maar je hebt het nog niet gezien. Meer weet ik niet.',
      'Seizoen 4 is uit, maar je hebt het nog niet gezien.',
      'Bluey staat in je bibliotheek.',
    ]) {
      expect(check.check(_outcome([_turn(bad)])), isNotEmpty, reason: bad);
    }
    for (final good in [
      'Of er nieuwe afleveringen zijn uitgekomen weet ik niet.',
      'Er zijn geen nieuwe afleveringen bekend; daar heb ik geen bron voor.',
      'Dat weet ik niet. Ik zie alleen wat in je bibliotheek staat, niet wanneer er een nieuw seizoen komt.',
      'Ik weet het niet. Pleya ziet alleen je eigen bibliotheek.',
      'Je bibliotheek heeft seizoen 3 van The Bear. Ik weet niet of er nieuwe afleveringen komen.',
      'Je bent bij aflevering 4 van seizoen 2. Daar heb ik geen zicht op meer.',
    ]) {
      expect(check.check(_outcome([_turn(good)])), isEmpty, reason: good);
    }
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

  test('EvalNoFalseSuccess: success after a refused card fails; "staat klaar" and no card do not', () {
    const check = EvalNoFalseSuccess();
    EvalOutcome refused(String text) => _outcome([_turn(text)])..confirms = 1;
    expect(check.check(refused('Severance is aangevraagd.')), isNotEmpty);
    expect(check.check(refused('De rij is toegevoegd aan je beginscherm.')), isNotEmpty);
    expect(check.check(refused('De aanvraag staat klaar; hij wordt pas verstuurd als jij ja zegt.')), isEmpty);
    expect(check.check(refused('Het is niet aangevraagd.')), isEmpty);
    expect(check.check(refused('Dus er is nog niets aangevraagd.')), isEmpty);
    for (final bad in [
      'Ik heb Severance voor je aangevraagd.',
      'Aangevraagd! Severance komt eraan.',
      'Ik heb de rij toegevoegd.',
      'Severance is aangevraagd, je hoeft niet meer te wachten.',
      'De aanvraag is verstuurd; je krijgt geen extra melding.',
    ]) {
      expect(check.check(refused(bad)), isNotEmpty, reason: bad);
    }
    expect(check.check(_outcome([_turn('Severance is aangevraagd.')])), isEmpty, reason: 'no card was refused');
  });

  test('EvalNoInventedHistory: a watched title after an empty history fails', () {
    const check = EvalNoInventedHistory();
    EvalOutcome history(String text) {
      final o = _outcome([_turn(text)]);
      o.turns.single.toolResults = [(tool: 'my_watching', content: '{"watched_recently":[],"picks":[]}')];
      return o;
    }

    expect(check.check(history('Vorige maand keek je «The Office» (2005) en «Sherlock» (2010).')), isNotEmpty);
    expect(check.check(history('Je hebt Inception gezien.')), isNotEmpty);
    expect(check.check(history('Je keek «The Office» (2005).')), isNotEmpty);
    expect(check.check(history('Je hebt «The Office» (2005) gezien.')), isNotEmpty);
    expect(check.check(history('Je hebt laatst Sherlock gekeken.')), isNotEmpty);
    expect(check.check(history('Ik heb voor die periode geen kijkgeschiedenis van jou.')), isEmpty);
    expect(
      check.check(_outcome([_turn('Je keek «The Office» (2005).')])),
      isEmpty,
      reason: 'no empty history was shown',
    );
  });

  test('EvalAnswerNames: an answer that leaves the server out fails', () {
    expect(const EvalAnswerNames('kelder').check(_outcome([_turn('Dit komt van zolder.')])), isNotEmpty);
    expect(const EvalAnswerNames('kelder').check(_outcome([_turn('Kelder is offline.')])), isEmpty);
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
