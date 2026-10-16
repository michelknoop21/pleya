import 'package:pleya/assistant/assistant_named_titles.dart';
import 'package:pleya/assistant/assistant_run.dart';

import '../big_p_eval_checks.dart';
import '../big_p_eval_fixtures.dart';
import '../big_p_eval_world.dart';

// More hard checks of the Big P evaluation set (BP-11a2). Same rules as
// big_p_eval_checks: each reads only the cards and the answer text the user
// sees, plus the tools Pleya ran, so the scripted and the live runner share
// them. Each one has a negative control in big_p_eval_checks_extra_test.

String _key(String title) => assistantTitleKey(title);

/// Titles an answer names beyond its cards, as `title (year)` keys.
Iterable<String> _namedKeys(AssistantRunResult r) => [
  for (final n in evalNamed(r.text)) _key(n.fixture?.title ?? n.named.title),
];

Iterable<String> _cardKeys(AssistantRunResult r) => [for (final c in evalCards(r)) _key(c.title)];

/// No title twice among the cards of a turn, and no «title» (year) written
/// twice in its text.
class EvalNoDuplicates extends EvalHard {
  const EvalNoDuplicates({super.fromTurn});
  @override
  String get id => 'no-duplicates';

  @override
  List<String> check(EvalOutcome o) {
    final out = <String>[];
    for (final (i, turn) in turnsOf(o)) {
      final seen = <String>{};
      for (final k in _cardKeys(turn.result)) {
        if (!seen.add(k)) out.add('$id: turn $i shows card «$k» twice');
      }
      final written = <String>{};
      // assistantNamedTitles lists each title once, so count the marks here.
      for (final m in RegExp(r'«([^»\n]{1,80})»(?:\s*\((\d{4})\))?').allMatches(turn.result.text)) {
        if (!written.add('${_key(m[1]!)}:${m[2] ?? ''}')) out.add('$id: turn $i writes «${m[1]}» twice');
      }
    }
    return out;
  }
}

/// A "what did I watch" answer never names what only the other profile of
/// the household watched, and never repeats one of the other profile's
/// remembered facts.
class EvalOnlyProfile extends EvalHard {
  const EvalOnlyProfile(this.me, this.other, {this.otherFacts = const [], super.fromTurn});
  final EvalProfile me;
  final EvalProfile other;

  /// Words of the other profile's memory that must not surface.
  final List<String> otherFacts;
  @override
  String get id => 'only-profile';

  @override
  List<String> check(EvalOutcome o) {
    final foreign = {
      for (final id in other.seenIds.difference(me.seenIds)) _key(evalTitles.firstWhere((t) => t.id == id).title),
    };
    return [
      for (final (i, turn) in turnsOf(o)) ...[
        for (final k in {..._cardKeys(turn.result), ..._namedKeys(turn.result)})
          if (foreign.contains(k)) '$id: turn $i shows «$k» that only ${other.name} watched',
        for (final f in otherFacts)
          if (turn.result.text.toLowerCase().contains(f.toLowerCase())) '$id: turn $i repeats ${other.name}\'s «$f»',
      ],
    ];
  }
}

/// A question the sources cannot answer (new episodes with no feed) gets no
/// confirming claim. The honest answer says it does not know; a claim that
/// something is out, new or available is a violation unless it is negated.
class EvalHonestMissing extends EvalHard {
  const EvalHonestMissing({super.fromTurn});
  @override
  String get id => 'honest-missing';

  static final _claim = RegExp(
    r'\b(nieuwe afleveringen?|nieuw seizoen|seizoen \d+|aflevering \d+|new episodes?|new season)\b.{0,40}\b(is|zijn|staat|staan|verschenen|uit|beschikbaar|available|out|released)\b',
    caseSensitive: false,
  );
  static final _negated = RegExp(
    r'\b(geen|niet|kan ik niet|weet ik niet|onbekend|no |not |cannot|unknown|don.t know)\b',
    caseSensitive: false,
  );

  @override
  List<String> check(EvalOutcome o) => [
    for (final (i, turn) in turnsOf(o))
      for (final s in turn.result.text.split(RegExp(r'(?<=[.!?])\s+|\n')))
        if (_claim.hasMatch(s) && !_negated.hasMatch(s)) '$id: turn $i claims "${s.trim()}"',
  ];
}

/// The answer names no more titles than it shows cards. Apply it only where
/// the question names no count: a count caps the cards on purpose.
class EvalCardsMatchText extends EvalHard {
  const EvalCardsMatchText({super.fromTurn});
  @override
  String get id => 'cards-match-text';

  @override
  List<String> check(EvalOutcome o) => [
    for (final (i, turn) in turnsOf(o))
      if (_namedKeys(turn.result).toSet().length case final named when named > _cardKeys(turn.result).toSet().length)
        '$id: turn $i names $named titles beside ${_cardKeys(turn.result).toSet().length} cards',
  ];
}

/// A follow-up shows no title (card or named) from an earlier turn.
class EvalNotRepeated extends EvalHard {
  const EvalNotRepeated({super.fromTurn = 1});
  @override
  String get id => 'not-repeated';

  @override
  List<String> check(EvalOutcome o) {
    final before = <String>{};
    final out = <String>[];
    for (final (i, turn) in o.turns.indexed) {
      final now = {..._cardKeys(turn.result), ..._namedKeys(turn.result)};
      if (i >= fromTurn) {
        for (final k in now.intersection(before)) {
          out.add('$id: turn $i shows «$k» again');
        }
      }
      before.addAll(now);
    }
    return out;
  }
}

/// A route that only one tool serves was taken (a Trakt question reads the
/// Trakt tool). Use only where no other tool can answer.
class EvalToolUsed extends EvalHard {
  const EvalToolUsed(this.tool, {this.turn = 0});
  final String tool;
  final int turn;
  @override
  String get id => 'tool-used-$tool';

  @override
  List<String> check(EvalOutcome o) =>
      o.turns.length > turn && o.turns[turn].tools.contains(tool) ? const [] : ['$id: turn $turn never called $tool'];
}

/// The number of cards in a turn lies in [min]..[max].
class EvalCardCount extends EvalHard {
  const EvalCardCount({this.min, this.max, this.turn = 0});
  final int? min;
  final int? max;
  final int turn;
  @override
  String get id => 'card-count';

  @override
  List<String> check(EvalOutcome o) {
    final n = o.turns.length > turn ? evalCards(o.turns[turn].result).length : 0;
    return [
      if (min != null && n < min!) '$id: turn $turn has $n cards, wanted at least $min',
      if (max != null && n > max!) '$id: turn $turn has $n cards, wanted at most $max',
    ];
  }
}
