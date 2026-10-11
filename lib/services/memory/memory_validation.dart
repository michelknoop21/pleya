import 'memory_models.dart';

final RegExp _lineBreaks = RegExp(r'[\n\r\u000B\u000C\u0085\u2028\u2029]');

/// C0 and C1 controls, plus the direction overrides and marks that can make a
/// stored sentence read differently from what it holds.
final RegExp _controls = RegExp(r'[\u0000-\u001F\u007F-\u009F\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

final RegExp _notWordOrSpace = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);
final RegExp _spaces = RegExp(r'\s+');

/// A checked sentence: [value] as it will be stored, [key] as it is compared.
typedef MemoryValue = ({String value, String key});

/// Trims [raw] and checks the shape of a fact: one line, no control
/// characters, 1 to [kMemoryValueMaxLength] code points, and at least one
/// letter or digit. Returns the code that refuses it, or the checked value.
({MemoryCode code, MemoryValue? value}) checkMemoryValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return (code: MemoryCode.empty, value: null);
  if (_lineBreaks.hasMatch(value)) return (code: MemoryCode.notSingleLine, value: null);
  if (_controls.hasMatch(value)) return (code: MemoryCode.controlCharacters, value: null);
  if (value.runes.length > kMemoryValueMaxLength) return (code: MemoryCode.tooLong, value: null);
  final key = memoryValueKey(value);
  if (key.isEmpty) return (code: MemoryCode.empty, value: null);
  final owned = ownedFactCode(value);
  if (owned != null) return (code: owned, value: null);
  return (code: MemoryCode.ok, value: (value: value, key: key));
}

/// [value] lowercased, without punctuation and with single spaces.
String memoryValueKey(String value) =>
    value.toLowerCase().replaceAll(_notWordOrSpace, '').replaceAll(_spaces, ' ').trim();

/// [text] lowercased with punctuation turned into spaces, so `8-jarige` and
/// `sci-fi` split into words.
String memoryWordText(String text) =>
    text.toLowerCase().replaceAll(_notWordOrSpace, ' ').replaceAll(_spaces, ' ').trim();

const Set<String> _stopWords = {
  // Dutch
  'aan', 'als', 'bij', 'dan', 'dat', 'deze', 'die', 'dit', 'door', 'een', 'eens', 'gaan', 'geen', 'heb', 'hebben',
  'heeft', 'het', 'hij', 'hoe', 'iets', 'ik', 'kan', 'kun', 'maar', 'meer', 'met', 'mij', 'mijn', 'naar', 'niet',
  'nog', 'ons', 'ook', 'over', 'van', 'voor', 'waar', 'wat', 'welke', 'wel', 'wie', 'wij', 'wil', 'worden', 'zijn',
  'zij', 'zou',
  // English
  'about', 'and', 'any', 'are', 'but', 'can', 'for', 'from', 'has', 'have', 'her', 'his', 'how', 'into', 'not',
  'our', 'some', 'that', 'the', 'their', 'them', 'there', 'this', 'was', 'what', 'when', 'which', 'who', 'with',
  'would', 'you', 'your',
};

/// The words of [text] that can carry a match: three characters or more and
/// not a function word.
Set<String> memoryMatchWords(String text) => {
  for (final word in memoryWordText(text).split(' '))
    if (word.length >= 3 && !_stopWords.contains(word)) word,
};

final RegExp _childWord = RegExp(
  r'\b(kind|kinderen|kindje|kindjes|kids?|zoon|zoons|zonen|zoontje|dochter|dochters|dochtertje|kleinkind|'
  r'kleinkinderen|peuter|kleuter|baby|child|children|sons?|daughters?|toddler|grandchild|grandchildren|'
  r'jongste|oudste|youngest|oldest)\b',
);

final RegExp _ageExpression = RegExp(
  r'\d{1,2} ?(jaar|jr|jarige?|years?|yrs?|yo|maand|maanden|months?)\b'
  r'|\b(jaar|years?) (oud|old)\b'
  r'|[a-z]jarige?\b'
  r'|\b(is|zijn|are|wordt|turns|turned|van|aged?) \d{1,2}\b'
  r'|\b(leeftijd|leeftijden|ages?)\b',
);

final RegExp _subtitleWord = RegExp(r'\b(ondertitel\w*|ondertiteling\w*|subtitles?|subs|captions?)\b');

const String _languageNames =
    'nederlands|nederlandse|engels|engelse|duits|duitse|frans|franse|spaans|spaanse|italiaans|italiaanse|'
    'japans|japanse|koreaans|koreaanse|dutch|english|german|french|spanish|italian|japanese|korean';

final RegExp _languageName = RegExp('\\b($_languageNames|originele|original)\\b');
final RegExp _audioWord = RegExp(
  r'\b(audio|audiospoor|audiotaal|taal|talen|language|languages|gesproken|spoken|dubbed|dub|'
  r'nagesynchroniseerd|nasynchronisatie)\b',
);
final RegExp _inLanguage = RegExp('\\bin (het |the )?($_languageNames)\\b');

// Conservative on purpose. Ages: a child word together with an age expression
// ("onze dochter is 8"); an age beside a bare name is not caught. Language: any
// subtitle word, a listed language (or "original") beside an audio or language
// word, and "in (het) <language>"; unlisted languages and "Franse films" pass.
MemoryCode? ownedFactCode(String value) {
  final text = memoryWordText(value);
  if (_childWord.hasMatch(text) && _ageExpression.hasMatch(text)) return MemoryCode.ownedKidsAges;
  if (_subtitleWord.hasMatch(text) ||
      _inLanguage.hasMatch(text) ||
      (_audioWord.hasMatch(text) && _languageName.hasMatch(text))) {
    return MemoryCode.ownedLanguage;
  }
  return null;
}
