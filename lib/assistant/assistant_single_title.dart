/// Whether a question is after one specific title ("die film met Tom Hanks
/// over death row") and whether the answer gives just that one, so the cards
/// are that title and not the whole search.
///
/// Both are closed forms. A question or an answer outside them keeps every
/// card, as before; taking one wrongly would cost a right card.
library;

// Lock one, the question: an optional lead-in, a pointer, at most three words,
// a kind word, a describing word, the description, an optional tail. Nothing
// else: a comma, a digit or a second sentence already falls outside, because
// the words hold letters, apostrophes and hyphens only.
const _lead =
    r"(?:hoe hee+t(?:te)?|wat (?:is|was) de (?:naam|titel) van|wat (?:is|was)|ken je|weet je|ik zoek|ik bedoel"
    r"|what(?:'s| is| was) the (?:name|title) of|what(?:'s| is| was)|do you know|i(?:'m| am) looking for|i mean) ";
const _between = r"(?<between>(?:[\p{L}'-]+ ){0,3}?)";
const _rest = r"(?<told>[\p{L}'-]+(?: [\p{L}'-]+)*?)";
const _kindNl = '(?:film|(?:tv[- ])?serie|anime|programma|documentaire|docu|show|movie)';
const _toldNl = '(?:met|over|waar|waarin|van)';
// "Series" is one or several in English and several in Dutch ("die series
// over draken"), so it is a kind word after an English pointer only.
const _kindEn = '(?:movie|film|(?:tv )?show|(?:tv )?series|anime|documentary|docu)';
const _toldEn = '(?:with|about|where|in which)';

final _dutch = RegExp(
  '^(?:$_lead)?(?:(?:die|dat|deze) $_between$_kindNl $_toldNl|die ene $_toldNl|welke $_kindNl (?:gaat|ging) over)'
  ' $_rest(?: (?:ook alweer|alweer|heet|heette))?[?.!]*\$',
  unicode: true,
);
final _english = RegExp(
  '^(?:$_lead)?(?:(?:that|this) $_between$_kindEn $_toldEn|the one $_toldEn|which $_kindEn (?:is|was) about)'
  ' $_rest(?: (?:again|called))?[?.!]*\$',
  unicode: true,
);

// A word between the pointer and the kind word, or in the description, that
// can bring in a second thing: joining and comparing, numbers and ranks, the
// rest of a series, a list or a tip, another kind word, what there is to watch.
const _second = {
  // Dutch.
  'en', 'of', 'maar', 'behalve', 'niet', 'geen', 'na', 'bij', 'zoals', 'dan', 'ook', 'plus', 'nog', 'meer', 'net',
  'alles', 'alle', 'allemaal', 'ander', 'andere', 'anders', 'overige', 'meerdere', 'verschillende', 'paar', 'beide',
  'allebei', 'één', 'eentje', 'twee', 'drie', 'vier', 'vijf', 'zes', 'zeven', 'acht', 'negen', 'tien', 'eerste',
  'tweede', 'derde', 'vierde', 'laatste', 'volgende', 'vorige', 'nummer', 'deel', 'delen', 'reeks', 'rest', 'verder',
  'erna', 'daarna', 'erbij', 'daarbij', 'daarnaast', 'bijbehorende', 'hele', 'elke', 'iedere', 'lijst', 'overzicht',
  'tip', 'tips', 'suggestie', 'suggesties', 'aanrader', 'aanraders', 'optie', 'opties', 'voorstel', 'voorstellen',
  'resultaten', 'aflevering', 'afleveringen', 'seizoen', 'seizoenen', 'titels', 'zoiets', 'lijkt', 'lijken', 'erop',
  'past', 'passen', 'sfeer', 'trant', 'stijl', 'genre', 'eerst', 'vervolgens', 'plaats', 'naast', 'samen', 'zonder',
  'versus', 'vs', 'vanavond', 'vandaag', 'kijken', 'beschikbaar', 'gezien', 'nieuw', 'nieuwe', 'nieuwste', 'beste',
  'beter', 'leukste', 'leukst', 'dezelfde', 'hetzelfde', 'zelfde', 'tegenover', 'gevolgd', 'inclusief', 'vergeleken',
  // English.
  'and', 'or', 'but', 'except', 'not', 'no', 'after', 'like', 'than', 'also', 'too', 'more', 'all', 'everything',
  'else', 'other', 'others', 'another', 'several', 'multiple', 'various', 'few', 'couple', 'both', 'either',
  'neither', 'one', 'ones', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'first', 'second',
  'third', 'fourth', 'last', 'next', 'previous', 'number', 'part', 'parts', 'franchise', 'whole', 'entire', 'every',
  'each', 'list', 'suggestion', 'suggestions', 'recommendation', 'recommendations', 'option', 'options', 'results',
  'episode', 'episodes', 'season', 'seasons', 'titles', 'similar', 'same', 'vein', 'style', 'goes', 'instead',
  'besides', 'along', 'together', 'without', 'rather', 'before', 'then', 'tonight', 'today', 'watch', 'available',
  'seen', 'watched', 'new', 'newest', 'best', 'better', 'those', 'these', 'any', 'anything', 'well', 'followed',
  'alongside', 'including', 'compared',
  // Kind words: a second one is a second thing ("de hele serie", "the movies").
  'film', 'films', 'serie', 'series', 'tv-serie', 'movie', 'movies', 'show', 'shows', 'anime', 'programma',
  "programma's", 'documentaire', 'documentaires', 'docu', "docu's", 'documentary', 'documentaries',
};
final _secondStem = RegExp(
  '^(?:vervolg|opvolg|trilog|vergelijkba|soortgelijk|sequel|prequel|spin-?off|follow-?up|remake|reboot)',
);

/// True when [prompt] is, as a whole, one film or series pointed at and
/// described ("die film met tom hanks over deathrow", "hoe heet die serie
/// over draken ook alweer", "which movie is about death row") and no word in
/// it can bring in a second thing. Everything else is false, also many honest
/// questions for one title: the cards then stay as the search left them.
bool assistantAsksOneTitle(String prompt) {
  final text = prompt.trim().toLowerCase().replaceAll('’', "'").replaceAll(RegExp('[ \t]+'), ' ');
  final dutch = _dutch.firstMatch(text);
  final match = dutch ?? _english.firstMatch(text);
  if (match == null) return false;
  final words = '${match.namedGroup('between') ?? ''}${match.namedGroup('told')}'.split(' ');
  // "Of" joins two things in Dutch and sits inside one English description
  // ("the end of the world").
  bool second(String w) => (_second.contains(w) && (dutch != null || w != 'of')) || _secondStem.hasMatch(w);
  return !words.any(second);
}

// Lock two, the answer.
final _titleMarks = RegExp('«[^»]*»');
final _moreTold = RegExp(
  r'\b(?:meerdere|verschillende|andere?|ook|nog|meer|hieronder|eronder|onderstaande|lijst|rest|vervolg\w*|deel|delen'
  r'|several|multiple|others?|another|also|more|below|list|sequels?|parts?)\b',
);
final _listLine = RegExp(r'^\s*(?:[-*\u2022\u2013]|\d+[.)])\s', multiLine: true);

/// True when [answer] points past the one title it names: a word for more
/// ("meerdere", "ook", "hieronder", "het tweede deel", "others", "below") or
/// a list of two or more lines. The words of the title itself do not count.
bool assistantAnswerPointsAtMore(String answer) =>
    _moreTold.hasMatch(answer.toLowerCase().replaceAll(_titleMarks, ' ')) || _listLine.allMatches(answer).length > 1;
