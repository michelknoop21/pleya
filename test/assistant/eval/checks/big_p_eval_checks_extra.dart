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

/// The titles an answer names, as title keys.
Iterable<String> _namedKeys(AssistantRunResult r) => [
  for (final n in evalNamed(r.text)) _key(n.fixture?.title ?? n.named.title),
];

Iterable<String> _cardKeys(AssistantRunResult r) => [for (final c in evalCards(r)) _key(c.title)];

/// No title twice among the cards of a turn. The key holds the year, so two
/// remakes with one name are two titles. Prose is left alone: an answer may
/// name a title twice.
class EvalNoDuplicates extends EvalHard {
  const EvalNoDuplicates({super.fromTurn});
  @override
  String get id => 'no-duplicates';

  @override
  List<String> check(EvalOutcome o) {
    final out = <String>[];
    for (final (i, turn) in turnsOf(o)) {
      final seen = <String>{};
      for (final c in evalCards(turn.result)) {
        if (!seen.add('${_key(c.title)}:${c.year ?? ''}')) out.add('$id: turn $i shows card «${c.title}» twice');
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

/// A question the sources cannot answer (new episodes, a release date, with
/// no feed) gets an honest "I do not know" and no claim. Every turn must
/// admit it, and no sentence may state a status or a date for new episodes
/// or seasons unless that sentence itself says it does not know.
class EvalHonestMissing extends EvalHard {
  const EvalHonestMissing({super.fromTurn});
  @override
  String get id => 'honest-missing';

  static final _admits = RegExp(
    r"\b((ik )?weet (het |dat )?(ik )?niet|kan ik niet|geen (bron|informatie|zicht|idee)|niet bekend|onbekend|ik zie (alleen )?(wat|niet)|i don.t know|no source|cannot (tell|see))\b",
    caseSensitive: false,
  );

  /// Words that announce something new or upcoming: any status word then
  /// makes the sentence a claim ("er is een nieuwe aflevering").
  static final _newSubject = RegExp(
    r'\b(nieuwe? aflevering(en)?|nieuw seizoen|volgende seizoen|new episodes?|new season|next season)\b',
    caseSensitive: false,
  );
  static final _newStatus = RegExp(
    r'\b(is|zijn|staat|staan|komt|komen|verschijnt|verschijnen|verschenen|uit|uitgekomen|beschikbaar|begint|start|available|out|released|arrives?)\b|\b\d{1,2} (januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december)\b|\b(januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december) \d{4}\b',
    caseSensitive: false,
  );

  /// A numbered season or an episode only counts as a claim next to a
  /// release verb or date, so "je bibliotheek heeft seizoen 3" stays a fact.
  static final _plainSubject = RegExp(r'\b(seizoen \d+|aflevering|afleveringen)\b', caseSensitive: false);
  static final _release = RegExp(
    r'\b(komt|komen|verschijnt|verschijnen|verschenen|uit|uitgekomen|begint|start|released|arrives?|out)\b|\b\d{1,2} (januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december)\b|\b(januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december) \d{4}\b',
    caseSensitive: false,
  );

  /// A sentence that itself says it does not know. A bare "niet" or "geen"
  /// does not excuse a claim ("seizoen 4 is uit, je hebt het nog niet gezien").
  static final _denied = RegExp(
    r"\b((ik )?(weet|kan) (het |dat )?(ik )?(niet|geen)|ik zie (alleen )?(wat|niet)|(niet|geen)\b.{0,40}\bbekend|onbekend|geen (bron|zicht|idee)|i don.t know|cannot (tell|see)|unknown)\b",
    caseSensitive: false,
  );

  static bool _claims(String s) =>
      (_newSubject.hasMatch(s) && _newStatus.hasMatch(s) || _plainSubject.hasMatch(s) && _release.hasMatch(s)) &&
      !_denied.hasMatch(s);

  @override
  List<String> check(EvalOutcome o) => [
    for (final (i, turn) in turnsOf(o)) ...[
      if (!_admits.hasMatch(turn.result.text)) '$id: turn $i never admits it does not know',
      for (final s in turn.result.text.split(RegExp(r'(?<=[.!?])\s+|\n')))
        if (_claims(s)) '$id: turn $i claims "${s.trim()}"',
    ],
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

/// After Pleya refused a confirmation card the answer must not say the task
/// was done (contract zero tolerance 6): no "aangevraagd", "gemaakt",
/// "toegevoegd" unless the same sentence says it is not (yet) so.
class EvalNoFalseSuccess extends EvalHard {
  const EvalNoFalseSuccess({super.fromTurn});
  @override
  String get id => 'no-false-success';

  static final _participle =
      r'(aangevraagd|gemaakt|toegevoegd|verstuurd|opgeslagen|verwijderd|gewist|aangemaakt|requested|created|added|sent|saved|deleted)';
  static final _done = RegExp(
    r'\b(is|zijn|heb ik|ik heb|heb|hebben|staat|staan|werd|werden|has been|have been|i have|i.ve)\b.{0,40}\b' +
        _participle +
        r'\b|^\W*' +
        _participle +
        r'\b|\bis gelukt\b',
    caseSensitive: false,
  );
  static final _not = RegExp(
    r"\b(niet|nog niet|pas|geen|wacht|zodra|klaar om|staat klaar|would|not)\b",
    caseSensitive: false,
  );

  /// A sentence is cut at commas and semicolons too: a negation excuses only
  /// the clause it stands in, not a claim next to it.
  static final _clause = RegExp(r'(?<=[.!?])\s+|\n|[,;:]\s+');

  @override
  List<String> check(EvalOutcome o) => o.confirms == 0
      ? const []
      : [
          for (final (i, turn) in turnsOf(o))
            for (final s in turn.result.text.split(_clause))
              if (_done.hasMatch(s) && !_not.hasMatch(s)) '$id: turn $i says "${s.trim()}" after a refused card',
        ];
}

/// Where the tools showed an empty watch history, no sentence claims the
/// user watched a named title (contract zero tolerance 5).
class EvalNoInventedHistory extends EvalHard {
  const EvalNoInventedHistory({super.fromTurn});
  @override
  String get id => 'no-invented-history';

  static final _watched = RegExp(
    r'\b(keek je|je keek|je zag|zag je|heb je\b.{0,60}\b(gekeken|gezien)|je hebt\b.{0,60}\b(gekeken|gezien)|you (watched|saw))\b',
    caseSensitive: false,
  );

  @override
  List<String> check(EvalOutcome o) => [
    for (final (i, turn) in turnsOf(o))
      if (turn.toolResults.any((r) => r.tool == 'my_watching' && r.content.contains('"watched_recently":[]')))
        for (final s in turn.result.text.split(RegExp(r'(?<=[.!?])\s+|\n')))
          if (_watched.hasMatch(s) && evalNamed(s).isNotEmpty) '$id: turn $i claims "${s.trim()}"',
  ];
}

/// The answer names [word] (an offline server): a result that left a server
/// out must not read as complete (DEC-142, "named, never skipped").
class EvalAnswerNames extends EvalHard {
  const EvalAnswerNames(this.word, {super.fromTurn});
  final String word;
  @override
  String get id => 'answer-names';

  @override
  List<String> check(EvalOutcome o) => [
    for (final (i, turn) in turnsOf(o))
      if (!turn.result.text.toLowerCase().contains(word.toLowerCase())) '$id: turn $i never names $word',
  ];
}
