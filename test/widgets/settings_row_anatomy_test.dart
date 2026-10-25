/// A-24b row anatomy: inside Instellingen a row draws a line icon instead of
/// the tinted square, the subtitle stays optional, and the title keeps its
/// place whichever icon is drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/settings_page.dart';
import 'package:pleya/widgets/settings_rows.dart';

import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';

import '../test_helpers/prefs.dart';

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

  testWidgets('inside Instellingen a row is one line of the series height, its description the hint', (tester) async {
    await _pump(tester, SettingsStudioTheme(child: SettingsGroup(children: [_row()])));
    final oneLine = tester.getSize(find.byType(ListTile)).height;
    await _pump(
      tester,
      SettingsStudioTheme(
        child: SettingsGroup(children: [_row(subtitle: 'Thema en dichtheid')]),
      ),
    );

    expect(oneLine, inInclusiveRange(48, 52), reason: 'the series row, and a tap target above 44 pt');
    expect(tester.getSize(find.byType(ListTile)).height, oneLine);
    expect(find.text('Thema en dichtheid'), findsNothing);
  });

  testWidgets('outside Instellingen the description stays on screen', (tester) async {
    await _pump(tester, SettingsGroup(children: [_row(subtitle: 'Thema en dichtheid')]));
    expect(find.text('Thema en dichtheid'), findsOneWidget);
  });

  group('A-24b Studio subpage rows', () {
    Widget subpage(List<Widget> rows, {bool hide = true}) => SettingsStudioTheme(
      child: SettingsPage(title: const Text('Weergave'), hideDescriptions: hide, children: rows),
    );

    testWidgets('a subpage row draws no icon; its title and separator start at the row inset', (tester) async {
      await _pump(tester, subpage([_row(), _row(subtitle: 'x')]));

      expect(find.byType(SettingsIconBadge), findsNothing);
      final card = tester.getRect(find.byType(SettingsGroup).first);
      expect(tester.getTopLeft(find.text('Weergave').last).dx - card.left, closeTo(16 + 16, 0.5));
      final rows = tester.renderObject<RenderSettingsRows>(find.byType(SettingsRows).first);
      expect(rows.separatorRects.single.left, 16);
    });

    testWidgets('the description is off screen and read as the VoiceOver hint', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        subpage([
          SettingNavigationTile(
            icon: Symbols.palette_rounded,
            title: 'Thema',
            subtitle: 'Licht of donker',
            onTap: () {},
          ),
        ]),
      );

      expect(find.text('Licht of donker'), findsNothing);
      expect(tester.getSemantics(find.text('Thema')), containsSemantics(hint: 'Licht of donker'));
      semantics.dispose();
    });

    testWidgets('a switch row driven by a value also reads its hidden description as the hint', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        subpage([
          SettingSwitchRow(
            value: true,
            onChanged: (_) {},
            icon: Symbols.wifi_rounded,
            title: 'Alleen via wifi',
            subtitle: 'Synchroniseer niet over mobiele data',
          ),
        ]),
      );

      expect(find.text('Synchroniseer niet over mobiele data'), findsNothing);
      expect(
        tester.getSemantics(find.text('Alleen via wifi')),
        containsSemantics(hint: 'Synchroniseer niet over mobiele data'),
      );
      semantics.dispose();
    });

    testWidgets('a preference switch reads its hidden description as the hint, with the switch', (tester) async {
      final semantics = tester.ensureSemantics();
      resetSharedPreferencesForTest();
      await tester.runAsync(() => SettingsService.getInstance());
      await _pump(
        tester,
        subpage([
          SettingSwitchTile(
            pref: SettingsService.focusGlow,
            icon: Symbols.light_mode_rounded,
            title: 'Focusgloed',
            subtitle: 'Een zachte gloed rond wat de afstandsbediening kiest',
          ),
        ]),
      );

      expect(
        tester.getSemantics(find.text('Focusgloed')),
        containsSemantics(hint: 'Een zachte gloed rond wat de afstandsbediening kiest', hasToggledState: true),
      );
      semantics.dispose();
    });

    testWidgets('a page that does not opt in keeps its descriptions', (tester) async {
      await _pump(tester, subpage([_row(subtitle: 'Thema en dichtheid')], hide: false));
      expect(find.text('Thema en dichtheid'), findsOneWidget);
    });

    testWidgets('a disabled row keeps its line, because there it says why', (tester) async {
      resetSharedPreferencesForTest();
      await tester.runAsync(() => SettingsService.getInstance());
      await _pump(
        tester,
        subpage([
          SettingSwitchTile(
            pref: SettingsService.icloudSyncEnabled,
            icon: Symbols.cloud_sync_rounded,
            title: 'iCloud',
            subtitle: 'iCloud is niet beschikbaar',
            enabled: false,
          ),
          SettingSwitchTile(
            pref: SettingsService.crashReporting,
            icon: Symbols.monitoring_rounded,
            title: 'Crashrapportage',
            subtitle: 'Stuurt crashes',
          ),
        ]),
      );

      expect(find.text('iCloud is niet beschikbaar'), findsOneWidget);
      expect(find.text('Stuurt crashes'), findsNothing);
    });

    testWidgets('a Studio row title is the semibold 14 pt line of the series', (tester) async {
      await _pump(tester, subpage([_row()]));
      final style = tester
          .widget<RichText>(find.descendant(of: find.byType(ListTile), matching: find.byType(RichText)).first)
          .text
          .style!;
      expect(style.fontSize, kSettingsStudioRowTitleSize);
      expect(style.fontWeight, FontWeight.w600);
      expect(tester.getSize(find.byType(ListTile)).height, inInclusiveRange(48, 52));
    });

    for (final (name, dark, oled, coral) in [
      ('light', false, false, kStudioTextCoralLight),
      ('dark', true, false, kStudioSwitchDark),
      ('OLED', true, true, kStudioSwitchDark),
    ]) {
      testWidgets('a destructive row takes the Studio coral in $name, the section heading the muted ink', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: dark, oled: oled),
            home: Scaffold(
              body: SettingsStudioTheme(
                child: SettingsGroup(
                  title: 'Onderhoud',
                  children: [
                    SettingNavigationTile(
                      icon: Symbols.cleaning_services_rounded,
                      title: 'Cache wissen',
                      destructive: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final title = tester.widget<Text>(find.text('Cache wissen'));
        expect(title.style?.color, coral);
        final heading = tester.widget<Text>(find.text('ONDERHOUD'));
        final muted = tokens(tester.element(find.text('ONDERHOUD'))).textMuted;
        expect(heading.style?.color, muted);
      });
    }

    for (final dark in [false, true]) {
      testWidgets('the card edge and separators are the faint Studio hairline (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: dark),
            home: Scaffold(
              body: SettingsStudioTheme(child: SettingsGroup(children: [_row(), _row()])),
            ),
          ),
        );
        final hairline = tokens(tester.element(find.byType(SettingsRows))).outline;
        expect(hairline.a, lessThan(0.2), reason: 'the Studio hairline carries its own faint alpha');
        final card = tester.widget<Container>(
          find.descendant(of: find.byType(SettingsGroup), matching: find.byType(Container)).first,
        );
        expect(((card.foregroundDecoration! as BoxDecoration).border! as Border).top.color, hairline);
        expect(tester.widget<SettingsRows>(find.byType(SettingsRows)).separatorColor, hairline);
      });
    }

    testWidgets('a section heading is the series 11 pt small caps off TV', (tester) async {
      await _pump(
        tester,
        SettingsStudioTheme(
          child: SettingsGroup(title: 'Onderhoud', children: [_row()]),
        ),
      );
      expect(tester.widget<Text>(find.text('ONDERHOUD')).style?.fontSize, 11);
    });

    testWidgets('outside Instellingen a light section heading keeps the brick', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: false),
          home: const Scaffold(
            body: SettingsGroup(title: 'Onderhoud', children: [SizedBox(height: 40)]),
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('ONDERHOUD')).style?.color, kSettingsSectionInkLight);
    });
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
