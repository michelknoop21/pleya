/// PB-10 (MOC-20): "titels onder posters" aan of uit. `TvCatalogCard` sits
/// behind every TV catalog surface (DEC-108: grid, kijklijst, Aanvragen,
/// Zoeken), so proving it here proves it everywhere at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';

import '../../test_helpers/prefs.dart';

const _title = 'The Long Way Home';

Widget _card() => MaterialApp(
  theme: monoTheme(dark: true),
  home: Scaffold(
    body: Center(
      child: TvCatalogCard(
        width: 200,
        artwork: const ColoredBox(color: Colors.black),
        title: _title,
        meta: '2024 · Sciencefiction',
        onSelect: () {},
      ),
    ),
  ),
);

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  testWidgets('an uninitialized SettingsService still shows the title (unchanged default)', (tester) async {
    await tester.pumpWidget(_card());

    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('the default shows the title under the poster', (tester) async {
    await SettingsService.getInstance();

    await tester.pumpWidget(_card());

    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('turning tvShowTitlesUnderPosters off hides the title but keeps the meta line', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.tvShowTitlesUnderPosters, false);

    await tester.pumpWidget(_card());

    expect(find.text(_title), findsNothing);
    expect(find.text('2024 · Sciencefiction'), findsOneWidget);
  });
}
