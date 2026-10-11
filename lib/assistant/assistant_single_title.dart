/// Whether a question is after one specific title ("die film met Tom Hanks
/// over death row"), so its answer is one card and not the whole search.
library;

import 'assistant_recommend_constraints.dart';

// One film or series, pointed at: "die film", "de serie", "welke film", "that
// movie", "the show". A plural ("films", "welke series") does not match. The
// English "series" is singular and plural alike, so only "that", "this" and
// "the" make it one.
final _oneKind = RegExp(
  r'\b(?:(?:die|dat|de|deze|welke)\s+(?:ene\s+)?(?:\w*film|\w*serie|aflevering|documentaire|docu)'
  r'|(?:that|the|this|which|what)\s+(?:one\s+)?(?:movie|film|show|episode|documentary)'
  r'|(?:that|the|this)\s+(?:one\s+)?series)\b',
);
// Asking for a name is asking for one title, whatever the kind word.
final _nameAsked = RegExp(
  r"\b(?:hoe hee+t(?:te)?|wat (?:is|was) de (?:naam|titel)|welke (?:was|is) (?:dat|het)"
  r"|what(?:'s| is| was) (?:it|that one) called|what(?:'s| is| was) the (?:name|title)|the (?:name|title) of)\b",
);
// A list or a tip is asked for: several titles are welcome.
final _severalAsked = RegExp(
  r'\b(?:\w*films|movies|shows|titels|titles|tips?|suggesties?|aanraders?|opties|options|voorstellen'
  r'|recommendations?|suggestions?)\b',
);
// "Iets zoals die film": that film is the example, not the answer.
final _likeIt = RegExp(
  r'\b(?:zoals|net als|lijk\w* op|vergelijkbaar\w*|soortgelijk\w*|similar|'
  r'(?:something|anything|one|more) like)\b',
);

/// True when [prompt] points at one film or series, or asks what it is called,
/// and asks for no list, no tip, no number above one and nothing "like" it.
/// Anything unclear is false: the cards then stay as the search left them.
bool assistantAsksOneTitle(String prompt) {
  final text = prompt.toLowerCase();
  if (!_oneKind.hasMatch(text) && !_nameAsked.hasMatch(text)) return false;
  if (_severalAsked.hasMatch(text) || _likeIt.hasMatch(text)) return false;
  return (assistantAskedCount(prompt) ?? 1) <= 1;
}
