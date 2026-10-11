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

final RegExp _rawCommandStart = RegExp(_commandStart.pattern, caseSensitive: false);

/// The user's own words after the command form as they were typed: trimmed,
/// with a capital first letter and without the closing full stop. Null when
/// [prompt] is no explicit request ([assistantMemoryCommandTail]) or names no
/// fact of its own: fewer than three words. "Onthoud dat ook" and "onthoud
/// dat maar" name no fact; the model would fill it in from the conversation.
String? assistantMemoryTypedFact(String prompt) {
  if (assistantMemoryCommandTail(prompt) == null) return null;
  final raw = prompt.trim();
  final match = _rawCommandStart.firstMatch(raw);
  if (match == null) return null;
  final tail = raw.substring(match.end).trim().replaceAll(RegExp(r'[.\s]+$'), '');
  if (_words(tail).length < 3) return null;
  return tail[0].toUpperCase() + tail.substring(1);
}

/// The subject a stored sentence leaves out.
const _subjects = {'ik', 'wij', 'we', 'i'};

/// What a finite verb may gain or lose between the first and the third person.
const _verbEndings = {'', 't', 's', 'es', 'en'};

final RegExp _lettersOnly = RegExp(r'^\p{L}+$', unicode: true);

/// Whether [a] and [b] are one finite verb in two persons: the same word, or
/// the same first four letters followed by nothing but a verb ending ("houd"
/// and "houdt", "kijken" and "kijkt", "like" and "likes"). A number never is.
bool _sameVerb(String a, String b) {
  if (a == b) return true;
  if (!_lettersOnly.hasMatch(a) || !_lettersOnly.hasMatch(b)) return false;
  var same = 0;
  while (same < a.length && same < b.length && a[same] == b[same]) {
    same++;
  }
  return same >= 4 && _verbEndings.contains(a.substring(same)) && _verbEndings.contains(b.substring(same));
}

/// Whether [value], the sentence the model wants stored, says exactly what
/// [tail] says, the user's typed words after the command form. Only then is
/// the model's wording stored at once; otherwise the typed words themselves
/// are ([assistantMemoryTypedFact]).
///
/// The comparison is strict and runs both ways: after folding, both hold the
/// same words in the same order. Three differences are allowed and no other:
///
/// * the subject at the start of [tail] is left out (ik, wij, we, I);
/// * the finite verb, the first word of [value], gains or loses a verb ending
///   ([_sameVerb]);
/// * that verb stands at the end of [tail], as a Dutch subordinate clause puts
///   it: "ik niet van horror houd" and "Houdt niet van horror".
///
/// Any other difference fails: a word more or less (also niet, geen, nooit,
/// alleen, als, dan, met, zonder, not, never, only, if, than, without),
/// another number, another order of the remaining words.
///
/// Known limit: the category of a fact stored at once is the model's choice.
bool assistantMemoryValueIsTyped(String value, String tail) {
  final said = _words(value);
  final typed = _words(tail);
  if (said.isEmpty || typed.length < 3) return false;
  bool same(List<String> words) {
    if (words.length != said.length || !_sameVerb(said.first, words.first)) return false;
    for (var i = 1; i < words.length; i++) {
      if (words[i] != said[i]) return false;
    }
    return true;
  }

  for (final words in [typed, if (_subjects.contains(typed.first)) typed.sublist(1)]) {
    if (same(words) || same([words.last, ...words.sublist(0, words.length - 1)])) return true;
  }
  return false;
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
/// spoiler word behind the command form keeps the fence. A typed request of
/// that kind gets no model call at all: Pleya answers with its own line and
/// offers the typed words on a card ([assistantMemoryTypedFact]).
String? assistantMemoryQuestionTail(String prompt) {
  final command = assistantMemoryCommandTail(prompt);
  if (command != null) return command;
  final text = foldText(prompt).trim().replaceAll(RegExp(r'[\s?.!]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
  if (_readForms.any((form) => form.hasMatch(text))) return '';
  final change = _changeForm.firstMatch(text);
  if (change == null) return null;
  return change.group(change.groupCount) ?? '';
}
