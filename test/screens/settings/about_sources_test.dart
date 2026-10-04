import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/about_screen.dart';
import 'package:pleya/theme/mono_theme.dart';

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Pleya',
      packageName: 'nl.michelknoop.pleya',
      version: '2.8.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

  for (final locale in [AppLocale.nl, AppLocale.en]) {
    testWidgets('About carries the TMDB attribution verbatim in ${locale.name}', (tester) async {
      await tester.runAsync(() => LocaleSettings.setLocale(locale));
      tester.view.physicalSize = const Size(402, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(theme: monoTheme(dark: true), home: const AboutScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('This product uses the TMDB API but is not endorsed or certified by TMDB.'),
        findsOneWidget,
      );
      expect(find.byType(SvgPicture), findsOneWidget, reason: 'the TMDB logo next to its notice');
      // What each source really gives Big P.
      expect(find.textContaining(RegExp(r'^TMDB: .*(trending).*\n')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Wikidata \(CC0\): .*\(MPA\)')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^TVmaze \(CC BY-SA\): .*score')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Trakt: .*score')), findsOneWidget);
      // Titles or ids go out, never the account or profile.
      expect(
        t.assistant.settings.factsOnlineNote,
        allOf(isNot(contains('kijkgeschiedenis')), isNot(contains('watch history')), contains('id')),
      );
    });
  }
}
