import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_intent.dart';
import 'package:pleya/i18n/strings.g.dart';

// Pleya's own follow-up chips are questions the user may tap: none of them may
// be answered with a "whose watching?" question back.
void main() {
  for (final locale in [AppLocale.en, AppLocale.nl]) {
    test('no ${locale.languageCode} follow-up chip is asked back', () async {
      await LocaleSettings.setLocale(locale);
      addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
      final f = t.assistant.followUp;
      final all = <String>[
        f.watchNow,
        f.watchMonth,
        f.watchWeek,
        f.watchToday,
        f.watchYesterday,
        ...f.tonight,
        ...f.recent,
        ...f.unwatched,
        ...f.popular,
        f.missingMovies,
        f.missingShows,
        f.jobs,
        f.failedJobs,
      ];
      for (final q in all) {
        expect(AssistantIntent.audienceChoiceNeeded(q), isFalse, reason: q);
      }
    });
  }
}
