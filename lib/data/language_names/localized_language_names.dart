import 'bg.dart';
import 'da.dart';
import 'de.dart';
import 'es.dart';
import 'fr.dart';
import 'it.dart';
import 'ja.dart';
import 'ko.dart';
import 'nb.dart';
import 'nl.dart';
import 'pl.dart';
import 'pt.dart';
import 'ru.dart';
import 'sv.dart';
import 'zh.dart';

/// Language display names per UI locale, keyed by ISO 639-1 code.
///
/// Deliberately Dart tables rather than slang keys. This is a lookup table of
/// ~184 rows per locale, not UI copy: putting it through slang would generate
/// close to three thousand extra getters per locale for something no screen
/// ever references by name. English is absent because the base name already
/// lives in `iso_639_data.dart`, which is also the fallback for any code a
/// locale has not translated yet.
const localizedLanguageNames = <String, Map<String, String>>{
  'bg': bgLanguageNames,
  'da': daLanguageNames,
  'de': deLanguageNames,
  'es': esLanguageNames,
  'fr': frLanguageNames,
  'it': itLanguageNames,
  'ja': jaLanguageNames,
  'ko': koLanguageNames,
  'nb': nbLanguageNames,
  'nl': nlLanguageNames,
  'pl': plLanguageNames,
  'pt': ptLanguageNames,
  'ru': ruLanguageNames,
  'sv': svLanguageNames,
  'zh': zhLanguageNames,
};

/// The name of [iso6391Code] as [uiLocale] spells it, or null to fall back to
/// the English name.
String? localizedLanguageName(String uiLocale, String iso6391Code) => localizedLanguageNames[uiLocale]?[iso6391Code];
