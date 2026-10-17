import 'assistant_plot_index.dart' show foldText;

// What the user's own words say about titles they watched or started
// (BP-11d), decided by code. A standing wish ("raad nooit iets aan wat ik al
// gezien heb") leaves those titles out of this question at once and is
// offered for the memory; a one-question override ("laat ook dingen zien die
// ik al gezien heb") lets them through for this question only. A question
// about the history ("wat heb ik al gezien?") is neither.

enum AssistantSeenWish {
  /// Nothing said about watched titles.
  none,

  /// Never suggest what the user watched or started.
  standing,

  /// Include what the user watched, for this question only.
  include,
}

const _seenWord = r'\b(gezien|gekeken|bekeken|begonnen|gestart|watched|seen|saw|started|begun)\b';
final _seen = RegExp(_seenWord);

// A negation, then a verb of suggesting, then a watched-or-started word in
// that order: "ik heb nog niet alles gezien, tip?" has its negation on the
// watching, not on the suggesting, and is no standing wish.
final _negation = RegExp(r"\b(niet|nooit|geen|niks|niets|never|don'?t|do not|stop|no longer|no more|nothing)\b");
// "laat" alone is also "late" and "show" a noun ("that show I started"): they
// count only as a verb with its object ("laat me ...", "show me ...").
final _suggest = RegExp(
  r'\b(aanra\w*|raad\w*|aanbe\w*|voorstel\w*|stel\w*|suggere\w*|tip\w*|toon\w*|tonen|'
  r'laat(?=\s+(?:me|mij|ons)\b)|show(?=\s+(?:me|us)\b)|'
  r'suggest\w*|recommend\w*|propos\w*|offer\w*)\b',
);
final _firstPerson = RegExp(r"\b(ik|i|i've|ive|i'd|me|mij)\b");

final _politeStart = RegExp(r'^(kun|kan|wil|zou)\s+je\b|^(can|could|will|would)\s+you\b|^please\b');
final _questionMark = RegExp('[?¿;؟？]');

final _includeLead = RegExp(r'\b(ook|wel|gerust|include|including|also|even|too)\b');
final _includeVerb = RegExp(
  r'\b(laat|toon\w*|zien|mag|mogen|raad\w*|stel\w*|tip\w*|geef|include\w*|show\w*|suggest\w*|recommend\w*|give|fine|ok|okay)\b',
);
final _noMatter = RegExp(
  r"\b(maakt\s+(niet|niks|geen\s+bal)\s+uit|doesn'?t\s+matter|does\s+not\s+matter|don'?t\s+care)\b[^.?!]*" + _seenWord,
);

final _historyAsk = RegExp(r'^(wat|welke|wie|heb|hebben|ben|what|which|have|did|do|how many|hoeveel)\b');

/// A question about the user's own history ("wat heb ik al gezien?"): the
/// saved preference does not apply, the answer is what they watched.
bool assistantSeenHistoryQuestion(String prompt) {
  final text = foldText(prompt).trim();
  return _seen.hasMatch(text) && _historyAsk.hasMatch(text) && assistantSeenWish(prompt) == AssistantSeenWish.none;
}

/// The wish [prompt] states about watched or started titles.
AssistantSeenWish assistantSeenWish(String prompt) {
  final text = foldText(prompt).trim();
  if (!_seen.hasMatch(text)) return AssistantSeenWish.none;
  if (_noMatter.hasMatch(text)) return AssistantSeenWish.include;
  // "Laat ook dingen zien die ik al gezien heb": the lead word and the verb
  // come before the watched word. "I watched it too, show me more" does not.
  final lead = _includeLead.firstMatch(text);
  final verb = _includeVerb.firstMatch(text);
  if (lead != null && verb != null && !_negation.hasMatch(text)) {
    final from = lead.end > verb.end ? lead.end : verb.end;
    if (_seen.hasMatch(text.substring(from))) return AssistantSeenWish.include;
  }
  if (_questionMark.hasMatch(text) && !_politeStart.hasMatch(text)) return AssistantSeenWish.none;
  // A negation next to a verb of suggesting ("raad nooit", "niet dat je
  // aanraadt"), then the user's own watched or started words after both:
  // "ik heb nog niet alles gezien, geef een tip" negates the watching.
  for (final neg in _negation.allMatches(text)) {
    final near = _suggest
        .allMatches(text)
        .where((m) => (m.start >= neg.end ? m.start - neg.end : neg.start - m.end) <= 60)
        .firstOrNull;
    if (near == null) continue;
    final rest = text.substring(near.end > neg.end ? near.end : neg.end);
    final seen = _seen.firstMatch(rest);
    if (seen == null) continue;
    final gap = rest.substring(0, seen.start);
    // The user's own words come in the same clause as the suggesting ("ik heb
    // geen tip nodig, ik heb dit al gezien" is two), and a second negation
    // ("toon geen films die ik niet gezien heb") turns the wish round.
    if (_firstPerson.hasMatch(gap) && !RegExp(r'[,;.]').hasMatch(gap) && !_negation.hasMatch(gap)) {
      return AssistantSeenWish.standing;
    }
  }
  return AssistantSeenWish.none;
}
