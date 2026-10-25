/// A-24 (Apple TV+ Studio on iOS): the shared settings rows off TV show their
/// current value right-aligned before the chevron, keep the subtitle for
/// explanatory text, sit in a 14 pt card that stays visible on OLED, and head
/// each group with a small-caps line that is readable in light. TV keeps the
/// value on the line under the title, as before.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/screens/settings/settings_utils.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings/setting_value_label.dart';
import 'package:pleya/widgets/settings_section.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
  });

  Future<void> pump(WidgetTester tester, Widget child, {ThemeData? theme, Size size = const Size(375, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? monoTheme(dark: true),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  Widget selectionTile({
    String Function(ViewMode)? valueBuilder,
    String? Function(ViewMode)? descriptionBuilder,
    String title = 'Modus',
  }) => SettingSelectionTile<ViewMode, ViewMode>(
    pref: SettingsService.viewMode,
    icon: Symbols.view_list_rounded,
    title: title,
    subtitleBuilder: (v) => v == ViewMode.grid ? 'Raster · lange uitleg' : 'Lijst · lange uitleg',
    valueBuilder: valueBuilder,
    descriptionBuilder: descriptionBuilder,
    options: const [
      DialogOption(value: ViewMode.grid, title: 'Raster'),
      DialogOption(value: ViewMode.list, title: 'Lijst'),
    ],
    decode: (v) => v,
    encode: (v) => v,
  );

  Widget numberTile({String Function(int)? valueBuilder}) => SettingNumberTile(
    pref: SettingsService.autoSkipDelay,
    icon: Symbols.timer_rounded,
    title: 'Vertraging',
    subtitleBuilder: (v) => '$v seconden wachten',
    valueBuilder: valueBuilder,
    labelText: 'Seconden',
    suffixText: 's',
    min: 1,
    max: 30,
  );

  ListTile tileOf(WidgetTester tester) => tester.widget<ListTile>(find.byType(ListTile));

  group('off TV', () {
    // The test font draws every glyph a full em wide, about one and a half
    // times Inter, so titles and values here are short where they must fit.
    testWidgets('a selection row shows its value trailing, without a value subtitle', (tester) async {
      await pump(tester, SettingsGroup(children: [selectionTile(valueBuilder: (v) => v.name)]));

      final value = find.text(ViewMode.grid.name);
      expect(value, findsOneWidget);
      expect(find.ancestor(of: value, matching: find.byType(SettingValueLabel)), findsOneWidget);
      expect(tileOf(tester).subtitle, isNull, reason: 'the value no longer doubles as the subtitle');
      expect(tester.getCenter(value).dx, greaterThan(tester.getCenter(find.text('Modus')).dx));
      expect(tester.getCenter(value).dy, closeTo(tester.getCenter(find.text('Modus')).dy, 1));
      expect(tester.getSize(find.byType(ListTile)).height, 52, reason: 'a one-line row is 52 pt');
    });

    testWidgets('a number row shows its value trailing', (tester) async {
      await pump(tester, SettingsGroup(children: [numberTile(valueBuilder: (v) => '$v s')]));
      final value = find.text('${SettingsService.autoSkipDelay.defaultValue} s');
      expect(find.ancestor(of: value, matching: find.byType(SettingValueLabel)), findsOneWidget);
      expect(tileOf(tester).subtitle, isNull);
    });

    testWidgets('with a description the value ends the title line and the description runs full width', (tester) async {
      const note = 'Een uitleg die over de hele breedte van de tekstkolom mag lopen';
      for (final width in const [375.0, 320.0]) {
        await pump(
          tester,
          SettingsGroup(
            children: [selectionTile(valueBuilder: (v) => v.name, descriptionBuilder: (_) => note)],
          ),
          size: Size(width, 640),
        );
        expect(tester.takeException(), isNull);
        final value = find.text(ViewMode.grid.name);
        final title = tester.getRect(find.text('Modus'));
        expect(find.ancestor(of: value, matching: find.byType(SettingTitleWithValue)), findsOneWidget);
        expect(tester.renderObject<RenderParagraph>(value).didExceedMaxLines, isFalse);
        expect(tester.getRect(value).top, lessThan(title.bottom), reason: 'on the title line at $width');
        // The text column: card (width - 32) less badge side (68) and chevron side (52).
        final column = width - 32 - 68 - 52;
        expect(tester.getRect(find.text(note)).width, greaterThan(column - 2), reason: 'full width at $width');
      }
    });

    testWidgets('a value too long for its line falls back to the old value line, whole', (tester) async {
      const long = 'Een heel lange waarde die nooit op een telefoonregel past';
      await pump(
        tester,
        SettingsGroup(children: [selectionTile(valueBuilder: (_) => long)]),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SettingValueLabel), findsNothing, reason: 'nothing is cut');
      expect((tileOf(tester).subtitle! as Text).data, 'Raster · lange uitleg');
      expect(tester.getRect(find.text('Modus')).height, lessThan(30), reason: 'the title keeps its line');
    });

    testWidgets('a long title keeps priority: the value moves under it instead of squeezing it', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          children: [selectionTile(title: 'Weergave en modus', valueBuilder: (v) => v.name)],
        ),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SettingValueLabel), findsNothing);
      expect(find.text('Raster · lange uitleg'), findsOneWidget);
    });

    testWidgets('a navigation row with a short value shows it trailing', (tester) async {
      await pump(
        tester,
        SettingsGroup(
          children: [
            SettingNavigationTile(icon: Symbols.dns_rounded, title: 'Servers', trailingLabel: 'NAS', onTap: () {}),
          ],
        ),
      );
      expect(find.ancestor(of: find.text('NAS'), matching: find.byType(SettingValueLabel)), findsOneWidget);
      expect(tester.getSize(find.byType(ListTile)).height, greaterThanOrEqualTo(44));
    });

    testWidgets('a navigation row with a long list shows all of it under the title, as before', (tester) async {
      const names = 'NAS Plex, Jellyfin thuis, Emby zolder';
      await pump(
        tester,
        SettingsGroup(
          children: [
            SettingNavigationTile(icon: Symbols.dns_rounded, title: 'Servers', trailingLabel: names, onTap: () {}),
          ],
        ),
      );
      expect(find.byType(SettingValueLabel), findsNothing);
      expect((tileOf(tester).subtitle! as Text).data, names);
      expect(tester.renderObject<RenderParagraph>(find.text(names)).didExceedMaxLines, isFalse);
    });

    testWidgets('a one-word segment label scales down instead of breaking inside the word', (tester) async {
      for (final width in const [375.0, 320.0]) {
        await pump(
          tester,
          SettingsGroup(
            children: [
              SegmentedSetting<int>(
                icon: Symbols.contrast_rounded,
                title: 'Thema',
                segments: const [
                  ButtonSegment(value: 0, label: Text('Systeem')),
                  ButtonSegment(value: 1, label: Text('Licht')),
                  ButtonSegment(value: 2, label: Text('Donker')),
                  ButtonSegment(value: 3, label: Text('OLED')),
                ],
                selected: 3,
                onChanged: (_) {},
              ),
            ],
          ),
          size: Size(width, 640),
        );
        // Untransformed text height: one line of the 14 pt label, two would be 28 or more.
        expect(
          tester.renderObject<RenderParagraph>(find.text('Systeem')).size.height,
          lessThan(25),
          reason: 'one line at $width',
        );
        expect(find.ancestor(of: find.text('Systeem'), matching: find.byType(FittedBox)), findsOneWidget);
      }
    });

    BoxDecoration cardOf(WidgetTester tester) => tester
        .widgetList<Container>(find.descendant(of: find.byType(SettingsGroup), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;

    testWidgets('the card is 14 pt round', (tester) async {
      await pump(tester, SettingsGroup(children: [numberTile()]));
      expect(cardOf(tester).borderRadius, BorderRadius.circular(kSettingsCardRadius));
    });

    testWidgets('on OLED the card is lifted off the black page', (tester) async {
      final oled = monoTheme(dark: true, oled: true);
      await pump(tester, SettingsGroup(children: [numberTile()]), theme: oled);
      final card = cardOf(tester).color!;
      final page = oled.extension<MonoTokens>()!.bg;
      expect(card, kSettingsOledCardColor);
      expect(card, isNot(oled.extension<MonoTokens>()!.surface));
      expect(_contrast(card, page), greaterThan(1.2), reason: 'the card must read as a surface on #000');
    });

    testWidgets('the section heading is warm and AA-readable in light', (tester) async {
      final light = monoTheme(dark: false);
      await pump(tester, const SettingsSectionHeader('Afspelen'), theme: light);
      final ink = tester.widget<Text>(find.text('AFSPELEN')).style!.color!;
      expect(ink, kSettingsSectionInkLight);
      expect(_contrast(ink, light.extension<MonoTokens>()!.bg), greaterThanOrEqualTo(4.5));
    });
  });

  group('on TV nothing changes', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('the value stays the subtitle and there is no trailing value', (tester) async {
      await pump(
        tester,
        TvSettingsDensity(
          child: SettingsGroup(children: [selectionTile(valueBuilder: (v) => v.name)]),
        ),
      );
      expect(find.byType(SettingValueLabel), findsNothing);
      expect(find.text('Raster · lange uitleg'), findsOneWidget);
      expect((tileOf(tester).subtitle! as Text).data, 'Raster · lange uitleg');
    });

    testWidgets('the card keeps radiusMd and the plain surface, the heading stays muted', (tester) async {
      final oled = monoTheme(dark: true, oled: true);
      await pump(
        tester,
        TvSettingsDensity(
          child: SettingsGroup(title: 'Afspelen', children: [numberTile()]),
        ),
        theme: oled,
      );
      final tk = oled.extension<MonoTokens>()!;
      final card = tester
          .widgetList<Container>(find.descendant(of: find.byType(SettingsGroup), matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(card.borderRadius, BorderRadius.circular(tk.radiusMd));
      expect(card.color, tk.surface);
      expect(tester.widget<Text>(find.text('AFSPELEN')).style!.color, tk.textMuted);
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
