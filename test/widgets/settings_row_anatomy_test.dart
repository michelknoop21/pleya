/// A-24b row anatomy: inside Instellingen a row draws a line icon instead of
/// the tinted square, the subtitle stays optional, and the title keeps its
/// place whichever icon is drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';

Widget _row({String? subtitle}) => SettingNavigationTile(
  icon: Symbols.palette_rounded,
  title: 'Weergave',
  subtitle: subtitle,
  destinationBuilder: (_) => const SizedBox(),
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(body: SizedBox(width: 375, child: child)),
  ),
);

/// The tinted square: a Container with a filled BoxDecoration around the glyph.
Finder _square() => find.descendant(
  of: find.byType(SettingsIconBadge),
  matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
);

Icon _glyph(WidgetTester tester) =>
    tester.widget<Icon>(find.descendant(of: find.byType(SettingsIconBadge), matching: find.byType(Icon)));

void main() {
  testWidgets('inside Instellingen the row draws an outline glyph without the square', (tester) async {
    await _pump(tester, SettingsStudioTheme(child: SettingsGroup(children: [_row()])));

    expect(_square(), findsNothing);
    expect(_glyph(tester).fill, 0);
    expect(_glyph(tester).size, kSettingsLineIconSize);
  });

  testWidgets('outside Instellingen the badge stays', (tester) async {
    await _pump(tester, SettingsGroup(children: [_row()]));

    expect(_square(), findsOneWidget);
    expect(_glyph(tester).fill, 1);
  });

  testWidgets('the title starts at the same x with either icon, so separators still line up', (tester) async {
    await _pump(tester, SettingsGroup(children: [_row()]));
    final badgeTitle = tester.getTopLeft(find.text('Weergave')).dx;
    await _pump(tester, SettingsStudioTheme(child: SettingsGroup(children: [_row()])));
    final lineTitle = tester.getTopLeft(find.text('Weergave')).dx;

    expect(lineTitle, badgeTitle);
    expect(tester.getSize(find.byType(SettingsIconBadge)).width, kSettingsIconBox);
  });

  testWidgets('without a subtitle the row is one line of a native height', (tester) async {
    await _pump(tester, SettingsStudioTheme(child: SettingsGroup(children: [_row()])));
    final oneLine = tester.getSize(find.byType(ListTile)).height;
    await _pump(
      tester,
      SettingsStudioTheme(
        child: SettingsGroup(children: [_row(subtitle: 'Thema en dichtheid')]),
      ),
    );
    final twoLines = tester.getSize(find.byType(ListTile)).height;

    expect(oneLine, inInclusiveRange(44, 56));
    expect(twoLines, greaterThan(oneLine));
    expect(find.text('Thema en dichtheid'), findsOneWidget);
  });

  group('TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('keeps the badge until its own rows are redrawn', (tester) async {
      await _pump(tester, SettingsStudioTheme(child: SettingsGroup(children: [_row()])));
      expect(_square(), findsOneWidget);
    });
  });
}
