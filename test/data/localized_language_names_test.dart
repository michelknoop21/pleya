import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/data/iso_639_data.dart';
import 'package:pleya/data/language_names/localized_language_names.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/utils/language_codes.dart';

void main() {
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

  test('every locale covers exactly the ISO 639-1 codes the app knows', () {
    final expected = languageEntries.keys.toSet();
    for (final entry in localizedLanguageNames.entries) {
      expect(entry.value.keys.toSet(), expected, reason: entry.key);
    }
  });

  test('a locale is offered for every UI language except the base one', () {
    final ui = AppLocale.values.map((l) => l.languageCode).toSet()..remove('en');
    expect(localizedLanguageNames.keys.toSet(), ui);
  });

  test('no name is left empty', () {
    for (final entry in localizedLanguageNames.entries) {
      for (final name in entry.value.entries) {
        expect(name.value.trim(), isNotEmpty, reason: '${entry.key}/${name.key}');
      }
    }
  });

  group('display name follows the UI language', () {
    // Non-base locales are deferred, so they have to be awaited into memory
    // before setLocaleSync can see them.
    setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

    test('Dutch renders as Nederlands in Dutch and Dutch in English', () {
      LocaleSettings.setLocaleSync(AppLocale.nl);
      expect(LanguageCodes.getDisplayName('nl'), 'Nederlands');
      expect(LanguageCodes.getDisplayName('nld'), 'Nederlands');

      LocaleSettings.setLocaleSync(AppLocale.en);
      expect(LanguageCodes.getDisplayName('nl'), 'Dutch');
    });

    test('a locale code keeps its region suffix', () {
      LocaleSettings.setLocaleSync(AppLocale.nl);
      expect(LanguageCodes.getDisplayName('pt-BR'), 'Portugees (Brazil)');
    });

    // Matching and normalisation must not drift with the UI language.
    test('the English name stays available for matching', () {
      LocaleSettings.setLocaleSync(AppLocale.nl);
      expect(LanguageCodes.getLanguageName('nl'), 'Dutch');
    });
  });
}
