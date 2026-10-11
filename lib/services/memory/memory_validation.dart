import 'dart:convert';

import 'memory_models.dart';
import 'memory_owned_facts.dart';

final RegExp _lineBreaks = RegExp(r'[\n\r\u000B\u000C\u0085\u2028\u2029]');

/// C0 and C1 controls, plus the direction overrides and marks that can make a
/// stored sentence read differently from what it holds.
final RegExp _controls = RegExp(r'[\u0000-\u001F\u007F-\u009F\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

/// Format characters that show nothing: soft hyphen, Arabic letter mark, zero
/// width space, non-joiner and joiner, word joiner and the variation
/// selectors. Dropped from a fact before it is checked, so two sentences that
/// read the same are stored and compared the same.
final RegExp _invisible = RegExp(r'[\u00AD\u061C\u200B-\u200D\u2060\uFE00-\uFE0F\u{E0100}-\u{E01EF}]', unicode: true);

final RegExp _combiningMarks = RegExp(r'[\u0300-\u036F]');

// Lowercase Latin-1 and Latin Extended-A letters that are a plain letter with
// an accent, and the letter each one folds to in the comparison key.
const String _accented = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżž';
const String _unaccented = 'aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzz';
final Map<int, int> _folds = {
  for (var i = 0; i < _accented.length; i++) _accented.codeUnitAt(i): _unaccented.codeUnitAt(i),
};

final RegExp _notWordOrSpace = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);
final RegExp _spaces = RegExp(r'\s+');

/// A checked sentence: [value] as it will be stored, [key] as it is compared.
typedef MemoryValue = ({String value, String key});

/// Drops invisible format characters from [raw], trims it and checks the
/// shape of a fact: one line, no control characters, 1 to
/// [kMemoryValueMaxLength] code points, and at least one letter or digit.
/// Returns the code that refuses it, or the checked value.
///
/// The value is stored as typed apart from that: Dart has no Unicode
/// normalisation and none is added here, so NFC and NFD spellings are stored
/// as given. Only the key folds them, see [memoryValueKey].
({MemoryCode code, MemoryValue? value}) checkMemoryValue(String raw) {
  final value = raw.replaceAll(_invisible, '').trim();
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

/// [value] lowercased, without invisible characters, accents and punctuation,
/// and with single spaces. Accents fold for the Latin letters of [_accented]
/// and for the combining marks U+0300 to U+036F, so the composed and the
/// decomposed spelling of `Café` share a key, and so do `Café` and `Cafe`.
/// Known limit: accented letters outside that table (Vietnamese, Greek,
/// Cyrillic) still differ between NFC and NFD.
String memoryValueKey(String value) {
  final lowered = value.replaceAll(_invisible, '').toLowerCase();
  final folded = String.fromCharCodes([for (final unit in lowered.codeUnits) _folds[unit] ?? unit]);
  return folded.replaceAll(_combiningMarks, '').replaceAll(_notWordOrSpace, '').replaceAll(_spaces, ' ').trim();
}

/// Whether [body] can be kept as the body of a written overview: a JSON object
/// of at most [kMemoryOverviewMaxBytes] in UTF-8.
bool isMemoryOverviewBody(String body) {
  if (utf8.encode(body).length > kMemoryOverviewMaxBytes) return false;
  try {
    return jsonDecode(body) is Map<String, dynamic>;
  } on FormatException {
    // The message quotes the body, so it is dropped here and never logged.
    return false;
  }
}

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
