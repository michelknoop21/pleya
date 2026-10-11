import 'assistant_plot_index.dart' show foldText;

// What the user's own words say about the memory, decided by code: whether a
// typed question is an explicit request to remember, and whether a question
// is about the memory at all. No model has a say in either.

final RegExp _commandStart = RegExp(r'^(onthoud\s+dat\s|onthoud\s*:|remember\s+that\s|remember\s*:)');

/// Whether [prompt] is an explicit request to remember something: it opens
/// with `onthoud dat`, `onthoud:`, `remember that` or `remember:` and holds
/// no question. Only then may one new fact be stored without a card. A title
/// such as "Remember the Titans" further on, or "Remember that film with the
/// heist?", is not a request.
bool assistantIsMemoryCommand(String prompt) {
  final text = foldText(prompt).trim();
  return _commandStart.hasMatch(text) && !text.contains('?');
}

final RegExp _writeStart = RegExp(r'^\W*(onthoud|onthou|vergeet|wis|verwijder|remember|forget|delete|remove|erase)\b');

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
/// [prompt] is not such a question. "Wat herinner je je over mij?" and an
/// explicit request to remember give the empty string; "Vergeet de
/// herinnering over horror" gives `horror`, and so does a request to change
/// or replace a memory.
///
/// The spoiler classifier reads words such as "herinner" and "remind" as a
/// story question. A question in one of these bounded forms is about the
/// memory instead, and only its free part can still call for the fence.
String? assistantMemoryQuestionTail(String prompt) {
  if (assistantIsMemoryCommand(prompt)) return '';
  final text = foldText(prompt).trim().replaceAll(RegExp(r'[\s?.!]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
  if (_readForms.any((form) => form.hasMatch(text))) return '';
  final change = _changeForm.firstMatch(text);
  if (change == null) return null;
  return change.group(change.groupCount) ?? '';
}
