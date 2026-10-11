import 'memory_models.dart';

// Word edges that also hold next to accented letters; `\b` only knows ASCII.
const String _start = r'(?<![\p{L}\p{N}])';
const String _end = r'(?![\p{L}\p{N}])';

RegExp _phrase(String pattern) => RegExp(pattern, unicode: true);
String _word(String alternatives) => '$_start(?:$alternatives)$_end';

final String _child = _word(
  'kind|kinderen|kindje|kindjes|kids?|zoon|zoons|zonen|zoontje|dochter|dochters|dochtertje|kleinkind|'
  'kleinkinderen|peuter|kleuter|baby|child|children|sons?|daughters?|toddler|grandchild|grandchildren|'
  'jongste|oudste|youngest|oldest',
);
final String _children = _word('kinderen|kleinkinderen|kids|children|zoons|zonen|dochters|sons|daughters');

const String _numberWords =
    'één|twee|drie|vier|vijf|zes|zeven|acht|negen|tien|elf|twaalf|dertien|veertien|vijftien|zestien|zeventien|'
    'achttien|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|'
    'seventeen|eighteen';

// A number that counts something else than years of age: a duration, a
// frequency, a clock time, an ordinal or an age rating ("16 en ouder").
const String _countsSomethingElse =
    r'(?![:.,/]\d)(?! ?(?:%|\+|(?:x|keer|maal|dag|dagen|nacht|nachten|uur|uren|min|minuut|minuten|week|weken|'
    r'weekend|weekenden|avond|avonden|seizoen|seizoenen|aflevering|afleveringen|films?|series?|times|days?|'
    r'nights?|hours?|minutes?|mins?|weeks?|weekends?|evenings?|episodes?|seasons?|movies?|shows?|procent|percent|'
    r'en ouder|of ouder|and older|or older|and up)'
    '$_end))';

// What may follow a spelled-out number for it to read as an age.
const String _closesAnAge =
    r'(?= ?(?:$|[.,;!?)]|(?:jaar|jr|years?|oud|old|geworden|en|of|and|or)'
    '$_end))';

final String _age = '(?:(?<!\\d)\\d{1,2}$_end$_countsSomethingElse|$_start(?:$_numberWords)$_end$_closesAnAge)';
const String _is = '(?:is|zijn|wordt|worden|was|are|turns|turned|turning)';
const String _filler = '(?: (?:al|nu|bijna|net|pas|inmiddels|just|now|almost|nearly|already|aged))?';

final List<RegExp> _ageStatements = [
  // "onze dochter is 8", "de kinderen zijn 6 en 9 jaar", "our son just turned eight"
  _phrase('$_child(?: [^ ]+){0,2} $_is$_filler $_age'),
  // "mijn zoon van 12", "a daughter aged nine"
  _phrase('$_child (?:van|of|aged?) $_age'),
  // "een 8-jarige zoon", "een achtjarige dochter", "an 8 year old son"
  _phrase(
    '(?:(?<!\\d)\\d{1,2}[ -]?|$_start(?:$_numberWords)-?)(?:jarige?|jaar oude?|years?[ -]old|yo)$_end'
    '(?: [^ ]+)? $_child',
  ),
  // "zoon (8) en dochter (5)"
  _phrase('$_child ?\\( ?\\d{1,2} ?\\)'),
  // "kinderen: 8 en 5", "twee kinderen, 8 en 5"
  _phrase('$_children ?[:,] ?(?:\\d{1,2}|(?:$_numberWords))(?: jaar)? ?(?:en|and|&|,) ?$_age'),
];

const String _dutchLanguages =
    'nederlands|engels|duits|frans|spaans|italiaans|japans|koreaans|zweeds|deens|noors|chinees|portugees|russisch|'
    'turks|arabisch|pools|fins|vlaams';
const String _englishLanguages =
    'dutch|english|german|french|spanish|italian|japanese|korean|swedish|danish|norwegian|chinese|portuguese|'
    'russian|turkish|arabic|polish|finnish|flemish|mandarin|hindi';

/// A language as a noun ("Engels"), which is how a language preference names
/// it. The inflected adjective ("Engelse films") is not in here.
const String _languageNoun = '(?:$_dutchLanguages|$_englishLanguages)';
const String _languageAnyForm = '(?:(?:$_dutchLanguages)e?|chinese|$_englishLanguages)';

// English has one form for "in English" and "the English countryside", so a
// bare language name only counts when no noun follows it.
const String _closesALanguage =
    r'(?= ?(?:$|[.,;!?)]|(?:en|of|and|or|only|with|met|als|when|if|but|maar|too|ook)'
    '$_end))';

final List<RegExp> _languagePreferences = [
  // Subtitles in any wording. "Subs" is left out: it is also a band.
  _phrase(_word(r'ondertitel\p{L}*|subtitle[sd]?|subtitling|subbed|closed captions?')),
  _phrase(_word('gesproken taal|spoken language|audiotaal|audiospoor|audio ?track|audio language')),
  _phrase(_word('nagesynchroniseerde?|nasynchronisatie|dubbed|dubbing|dubs')),
  _phrase(
    _word('originele (?:versie|taal|audio|geluid|spraak)|original (?:version|language|audio)|origineel gesproken'),
  ),
  // "Engels geluid", "Japanese audio", "Zweeds gesproken"
  _phrase(_word('$_languageAnyForm (?:audio|geluid|spraak|gesproken|spoken|dub|nasynchronisatie)')),
  _phrase(_word('(?:audio|geluid|spraak|gesproken|spoken) (?:in )?(?:het |de |the )?$_languageAnyForm')),
  // "in het Engels"; "in het Franse platteland" has the adjective and passes.
  _phrase(_word('in het (?:$_dutchLanguages)')),
  _phrase('${_word('in (?:the )?$_languageNoun')}$_closesALanguage'),
  // "liever Engels dan Nederlands"; "liever Franse dan Duitse films" passes.
  _phrase(
    '${_word('(?:liever|liefst|prefers?|rather) $_languageNoun (?:dan|than|boven|over|to) $_languageNoun')}'
    '$_closesALanguage',
  ),
];

/// "OV" for the original version, read from the text as typed. Lowercase "ov"
/// and "het OV" are public transport.
final RegExp _originalVersion = RegExp(r'(?<![\p{L}\p{N}-])(?<!het )(?<!de )OV(?![\p{L}\p{N}])', unicode: true);

final RegExp _spaces = RegExp(r'\s+');

/// The code that refuses [value] because the fact has an owner already, or
/// null. When in doubt it lets the fact through: a refusal sends the user to a
/// settings screen where a household fact does not belong.
///
/// Ages: only an outright statement of a child's age. A number that counts
/// something else ("3 dagen per week", "films van 90 minuten", "16 en ouder",
/// "12 Years a Slave") is not one. Language: only an outright preference for
/// spoken language or subtitles. A language beside a genre, a country or a
/// place ("Franse films", "the English countryside") is not one.
///
// Known limits, both let through: an age beside a bare name without a child
// word ("Tim is 8"), and a language that is not in the lists above.
MemoryCode? ownedFactCode(String value) {
  final typed = value.replaceAll(_spaces, ' ').trim();
  final text = typed.toLowerCase();
  if (_ageStatements.any((statement) => statement.hasMatch(text))) return MemoryCode.ownedKidsAges;
  if (_originalVersion.hasMatch(typed) || _languagePreferences.any((preference) => preference.hasMatch(text))) {
    return MemoryCode.ownedLanguage;
  }
  return null;
}
