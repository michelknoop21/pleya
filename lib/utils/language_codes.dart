import '../data/iso_639_data.dart';
import '../data/language_names/localized_language_names.dart';
import '../i18n/strings.g.dart';

/// Helper class for converting between ISO 639-1 (2-letter) and ISO 639-2 (3-letter) language codes
class LanguageCodes {
  static LanguageEntry? _resolve(String code) {
    final normalized = code.toLowerCase().trim();
    final entry = languageEntries[normalized];
    if (entry != null) return entry;
    final key = code2ToCode1[normalized] ?? code2BToCode1[normalized];
    return key != null ? languageEntries[key] : null;
  }

  /// Returns all code variations (639-1, 639-2, 639-2/B) for a given language code.
  static List<String> getVariations(String languageCode) {
    final normalized = languageCode.toLowerCase().trim();
    final variations = <String>{normalized};

    final entry = _resolve(languageCode);
    if (entry != null) {
      variations.add(entry.code1);
      variations.add(entry.code2);
      if (entry.code2B != null) variations.add(entry.code2B!);
    }

    return variations.toList();
  }

  static String? getIso6391Code(String code) {
    final normalized = code.toLowerCase().trim().split(RegExp('[-_]')).first;
    if (normalized.isEmpty) return null;
    return _resolve(normalized)?.code1;
  }

  /// Display name for a language/locale code, in the app's UI language.
  /// Handles plain codes ("en" → "Engels" in Dutch) and locale codes
  /// ("en-US" → "Engels", "en-AU" → "Engels (Australia)").
  ///
  /// Region names stay English for now; only the language half is translated.
  static String getDisplayName(String code) {
    if (code.isEmpty) return code;

    if (!code.contains('-')) {
      return getLocalizedLanguageName(code) ?? code;
    }

    final parts = code.split('-');
    final langName = getLocalizedLanguageName(parts.first) ?? parts.first;
    final region = parts.length > 1 ? _regionNames[parts[1]] : null;
    return region != null ? '$langName ($region)' : langName;
  }

  static const _regionNames = <String, String>{
    'AU': 'Australia',
    'BR': 'Brazil',
    'CA': 'Canada',
    'GB': 'UK',
    'HK': 'Hong Kong',
    'MX': 'Mexico',
    'PT': 'Portugal',
    'TW': 'Taiwan',
  };

  /// Returns all languages as (code, name) pairs, sorted by name.
  static List<({String code, String name})> getAllLanguages() {
    final languages = <({String code, String name})>[];
    for (final entry in languageEntries.values) {
      languages.add((code: entry.code1, name: entry.name));
    }
    languages.sort((a, b) => a.name.compareTo(b.name));
    return languages;
  }

  /// English name, and the value every matching rule compares against.
  /// Display code wants [getLocalizedLanguageName] instead.
  static String? getLanguageName(String languageCode) {
    return _resolve(languageCode)?.name;
  }

  /// The language's name in the app's current UI language, falling back to the
  /// English name for a locale that has not translated that code. Kept apart
  /// from [getLanguageName] on purpose: matching and normalisation must stay
  /// on the English vocabulary regardless of what the user reads.
  static String? getLocalizedLanguageName(String languageCode) {
    final entry = _resolve(languageCode);
    if (entry == null) return null;
    return localizedLanguageName(LocaleSettings.instance.currentLocale.languageCode, entry.code1) ?? entry.name;
  }
}
