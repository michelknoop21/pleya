import 'package:flutter/material.dart';
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

      expect(find.text('This product uses the TMDB API but is not endorsed or certified by TMDB.'), findsOneWidget);
      expect(find.textContaining('Wikidata (CC0)'), findsOneWidget);
      expect(find.textContaining('TVmaze (CC BY-SA)'), findsOneWidget);
      expect(find.textContaining('Trakt'), findsOneWidget);
    });
  }
}
