import 'assistant_plot_index.dart' show foldText;

// What the user's own words say about the memory, decided by code: whether a
// typed question is an explicit request to remember, and whether a question
// is about the memory at all. No model has a say in either.

final RegExp _commandStart = RegExp(r'^(onthoud\s+dat\s|onthoud\s*:|remember\s+that\s|remember\s*:)');

/// A question mark in any of the scripts a keyboard offers: ASCII, the
/// inverted Spanish one, the Greek and Arabic ones and the full-width one.
final RegExp _questionMark = RegExp('[?¿;؟？]');

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _words(String text) => foldText(text).split(_notWord).where((w) => w.isNotEmpty).toList();

/// The user's own words after the command form, folded, or null when
/// [prompt] is no explicit request to remember something. It is one when it
/// opens with `onthoud dat`, `onthoud:`, `remember that` or `remember:` and
/// holds no question mark. A title such as "Remember the Titans" further on,
/// or "Remember that film with the heist?", is not a request.
String? assistantMemoryCommandTail(String prompt) {
  final text = foldText(prompt).trim();
  final match = _commandStart.firstMatch(text);
  if (match == null || _questionMark.hasMatch(text)) return null;
  return text.substring(match.end).trim();
}

/// Whether [value], the sentence the model wants stored, demonstrably comes
/// from [tail], the user's typed words after the command form. Only then may
/// a fact be stored without a card.
///
/// The rule, decided by code:
///
/// * [tail] is a fact of its own: at least three words. "Onthoud dat ook" and
///   "onthoud dat maar" name no fact; the model would fill it in from the
///   conversation or a tool result.
/// * Every content word of [value] (folded, at least four letters) occurs in
///   [tail], exactly or as the same stem: the first four letters are equal,
///   which covers conjugation ("houd" and "houdt", "kijken" and "kijkt").
/// * At most one content word may be missing, and only when at least two
///   others were found. A sentence with an added claim falls through.
bool assistantMemoryValueIsTyped(String value, String tail) {
  final typed = _words(tail);
  if (typed.length < 3) return false;
  bool said(String word) => typed.any((t) => t == word || (t.length >= 4 && t.substring(0, 4) == word.substring(0, 4)));
  var found = 0;
  var missing = 0;
  for (final word in _words(value).where((w) => w.length >= 4)) {
    said(word) ? found++ : missing++;
  }
  return found > 0 && (missing == 0 || (missing == 1 && found >= 2));
}

/// How a follow-up question can open as an instruction to store, change or
/// drop something, with or without a polite lead-in ("please", "kun je").
final RegExp _writeStart = RegExp(
  r'^\W*((please|kindly|kun je|kan je|wil je|zou je|graag|can you|could you|would you|will you)\s+)*'
  r'(onthoud\w*|onthou|vergeet|wis|verwijder|bewaar|vervang|noteer\s+dat|sla\s+op\s+dat|'
  r'remember|forget|delete|remove|erase|clear|replace|note\s+that|save\s+that)\b',
);

/// Whether [text] opens as an instruction to store or drop something. A
/// follow-up question the model wrote must never read as one.
bool assistantOpensAsMemoryWrite(String text) => _writeStart.hasMatch(foldText(text).trim());

const String _about = r'(over|van|about|of)\s+(mij|me|ons|mezelf|us|myself)';
const String _mine = r'(de|het|die|dat|deze|mijn|je|jouw|alle|al mijn|the|that|this|my|your|all|all my)';
const String _memoryWord = r'(herinnering|herinneringen|geheugen|memory|memories)';

final List<RegExp> _readForms = [
  RegExp('^(wat|what)\\s+(herinner|weet|onthoud|onthield)\\s+je(\\s+je)?(\\s+(nog|allemaal|al))*\\s+$_about\$'),
  RegExp('^(wat|what)\\s+heb\\s+je(\\s+(allemaal|al))?(\\s+$_about)?\\s+onthouden(\\s+$_about)?\$'),
  RegExp('^what\\s+(do|did|can)\\s+you\\s+(remember|know|recall)(\\s+$_about)?\$'),
  RegExp('^what\\s+have\\s+you\\s+(remembered|stored|saved)(\\s+$_about)?\$'),
  RegExp('^(welke|which|what)\\s+$_memoryWord\\s+(heb|bewaar|do|have)\\s+(je|you)(\\s+have)?(\\s+$_about)?\$'),
  RegExp(
    '^(wat|what)\\s+(staat|zit|is)(\\s+er)?\\s+in\\s+(je|jouw|mijn|het|your|my|the)\\s+$_memoryWord(\\s+$_about)?\$',
  ),
  RegExp('^(toon|laat|show|list)(\\s+(me|mij))?(\\s+zien)?\\s+$_mine\\s+$_memoryWord(\\s+zien)?(\\s+$_about)?\$'),
];

final RegExp _changeForm = RegExp(
  '^(vergeet|wis|verwijder|wijzig|verander|vervang|corrigeer|forget|delete|remove|erase|change|replace|correct|edit|update)'
  '\\s+($_mine\\s+)?$_memoryWord'
  r'(\s+(over|aan|dat|about|of|that|on)\s+(.{1,80}))?$',
);

/// The free part of a question about the user's own memory, or null when
/// [prompt] is not such a question. "Wat herinner je je over mij?" gives the
/// empty string; "Vergeet de herinnering over horror" gives `horror`, and so
/// does a request to change or replace a memory. An explicit request to
/// remember gives everything after the command form.
///
/// The spoiler classifier reads words such as "herinner" and "remind" as a
/// story question. A question in one of these bounded forms is about the
/// memory instead, and only its free part can still call for the fence. For
/// "onthoud dat ..." that free part is the rest of the sentence: a story or
/// spoiler question behind the command form keeps the fence, and the request
/// to remember is then left alone (the fenced run offers no memory tool). A
/// spoiler leak weighs more than a missed request to remember.
String? assistantMemoryQuestionTail(String prompt) {
  final command = assistantMemoryCommandTail(prompt);
  if (command != null) return command;
  final text = foldText(prompt).trim().replaceAll(RegExp(r'[\s?.!]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
  if (_readForms.any((form) => form.hasMatch(text))) return '';
  final change = _changeForm.firstMatch(text);
  if (change == null) return null;
  return change.group(change.groupCount) ?? '';
}
