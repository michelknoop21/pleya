/// Whether a question is after one specific title ("die film met Tom Hanks
/// over death row"), so its answer is one card and not the whole search.
library;

import 'assistant_recommend_constraints.dart';

// A word and the gap after it; up to three may stand between the pointer and
// the kind word ("die tom hanks film").
const _word = r"(?:[\w'-]+\s+)";
const _kind =
    r'(?:(?:tv-)?\w*film|(?:tv-)?\w*serie|aflevering|documentaire|docu|anime|programma|show|ding'
    r'|movie|episode|documentary|cartoon|program(?:me)?)';
// What makes the kind word a description to search on ("die film met", "the
// show about"). A title that is only referred to has its name there instead
// ("de film Heat", "de serie Friends") and is no search.
const _described =
    r'[\s,]+(?:met|over|van|uit|waarin|waarbij|waarvan|waar|die|dat|gaat|ging|speelt|heeft'
    r'|with|about|where|in which|that|from|by|starring|featuring|has|had'
    r'|(?:is|was)\s+(?:dat|het|die|that|it|about|set))\b';

// One film or series, pointed at and described. A plural ("films", "welke
// series") does not match. The English "series" is singular and plural alike,
// so only "that", "this" and "the" make it one.
final _oneKind = RegExp(
  '\\b(?:(?:die|dat|deze|welke|that|this|which|what)\\s+$_word{0,3}?$_kind'
  '|(?:de|het|the)\\s+(?:ene\\s+|one\\s+)?$_kind'
  '|(?:that|this|the)\\s+(?:one\\s+)?(?:tv\\s+)?series)$_described',
);
// Pointed at without a kind word: "die ene met", "the one where", "the tom
// hanks one about", "weet je welke ik bedoel".
final _oneMeant = RegExp(
  '\\b(?:(?:die|dat)\\s+ene\\s+(?:met|over|van|waar\\w*)'
  '|(?:the|that)\\s+$_word{0,3}?one\\s+(?:where|with|about)|welke ik bedoel)\\b',
);
// "Een film met" is one title only after a verb of searching, and with an
// actor only when a second detail follows: "ik zoek een film met Tom Hanks"
// may as well be a wish for a few of his films.
final _oneSought = RegExp(
  '\\b(?:ik zoek|zoek ik|ik bedoel|op zoek naar|looking for|i mean|trying to find|searching for)\\s+'
  '(?:naar\\s+)?(?:een|an?)\\s+$_word{0,2}?$_kind[\\s,]+(?:(?:over|waarin|waar|about|where)\\b'
  '|(?:met|with)\\b.*\\b(?:in|over|op|als|die|waar\\w*|about|on|as|who|where|that)\\b)',
);
// Asking for a name is asking for one title, whatever the kind word.
final _nameAsked = RegExp(
  r"\b(?:hoe hee+t(?:te)?|wat (?:is|was) de (?:naam|titel)|welke (?:was|is) (?:dat|het)"
  r"|what(?:'s| is| was) (?:it|that one) called|what(?:'s| is| was) the (?:name|title)|the (?:name|title) of"
  "|what(?:'s| is| was) (?:that|the|this)\\s+$_word{0,4}called)\\b",
);
// The name asked is a person's: the title is known, not searched.
final _whoAsked = RegExp(
  '\\b(?:hoe hee+t(?:te)?|(?:naam|name) (?:van|of))\\s+$_word{0,2}'
  r'(?:regisseur|acteur|actrice|maker|schrijver|hoofdrolspeler|personage|director|actor|actress|writer|creator'
  r'|character)\b',
);
// A list, a tip or the rest is asked for: several titles are welcome. "Niet
// meer weten" and "any more" ask for nothing more.
final _severalAsked = RegExp(
  r'\b(?:\w*films|movies|shows|titels|titles|tips?|suggesties?|aanraders?|opties|options|voorstellen'
  r'|recommendations?|suggestions?|(?<!niet )meer|(?<!any )more|alles|alle|allemaal|andere?|overige|meerdere|paar'
  r'|afleveringen|seizoenen|resultaten|lijst|overzicht|everything|all|else|others?|several|episodes|seasons'
  r'|results|list'
  // The title and what follows or surrounds it: its parts, the rest, something besides.
  r'|vervolg\w*|delen|deel\s+(?:\d+|een|twee|drie|vier|i+)|parts?\s+(?:\d+|one|two|three|four|i+)|sequels?|prequels?'
  r'|trilog\w+|spin-?offs?|franchise|reeks|rest|verder|ook|also|plus|as well|too)\b',
);
// A second title pointed at after "en" or "and": "en die met", "and the one
// with", "en die serie over". A plain "en" inside one description ("met tom
// hanks en die grote gevangene") has no such word after it and stays one
// title. A second question ("en wat is er nieuw") is left to the run, which
// narrows only the result that holds the named title.
final _secondAsked = RegExp(
  '\\b(?:en|and|of|or)\\s+(?:die|dat|deze|de|het|iets|een|that|this|the|something|an?)\\s+(?:ene\\s+|one\\s+)?'
  '(?:$_kind\\s+)?(?:met|van|over|uit|waar\\w*|with|about|by|from|where)\\b',
);
// "Welke film", "which movie": one title only when the question goes on to
// describe it. With an actor alone ("welke film met Tom Hanks") it asks which
// of his films, and with owning or watching ("heb ik", "can I watch") it asks
// what is there: both are lists.
final _whichKind = RegExp('\\b(?:welke|which|what)\\s+$_word{0,3}?$_kind\\b');
const _whichBy =
    '\\b(?:welke|which|what)\\s+$_word{0,3}?$_kind[\\s,]+(?:met|van|uit|with|by|from|starring|featuring)\\b';
final _whichByAsked = RegExp(_whichBy);
final _whichByTold = RegExp(
  '$_whichBy.*\\b(?:gaat|ging|speelt|speelde|over|waarin|waar|als|about|where|as|takes place'
  '|(?:is|was)\\s+(?:dat|het|that|it|set))\\b',
);
final _available = RegExp(
  r"\b(?:heb ik|ik heb|hebben we|heb je|hebben jullie|kan ik|kunnen we|staa[nt] er\s?op|is er|zijn er|do i have"
  r"|do we have|have i|have we|can i|can we|should i|is there|are there|niet gezien|haven't seen|have not seen"
  r"|not seen|not watched|vanavond|vandaag|tonight|today|kijken|to watch|beschikbaar|available)\b",
);
// "Iets zoals die film": that film is the example, not the answer.
final _likeIt = RegExp(
  r'\b(?:zoals|net als|lijk\w* op|vergelijkbaar\w*|soortgelijk\w*|similar|'
  r'(?:something|anything|one|more) like|zoiets|in die stijl|in that style)\b',
);

/// True when [prompt] describes one film or series to find, or asks what it is
/// called, and asks for no list, no tip, nothing more, no sequel or second
/// thing, no number above one and nothing "like" it. "Welke film met X" counts
/// only with a description after it, never as a question what there is. A title that is only referred to ("de regisseur van de
/// film Heat") is no search. Anything unclear is false: the cards then stay as
/// the search left them.
bool assistantAsksOneTitle(String prompt) {
  final text = prompt.toLowerCase();
  final one = _oneKind.hasMatch(text) || _oneMeant.hasMatch(text) || _oneSought.hasMatch(text);
  if (!one && !_nameAsked.hasMatch(text)) return false;
  if (_severalAsked.hasMatch(text) || _likeIt.hasMatch(text) || _whoAsked.hasMatch(text)) return false;
  if (_secondAsked.hasMatch(text)) return false;
  if (_whichKind.hasMatch(text)) {
    if (_available.hasMatch(text)) return false;
    if (_whichByAsked.hasMatch(text) && !_whichByTold.hasMatch(text)) return false;
  }
  return (assistantAskedCount(prompt) ?? 1) <= 1;
}
