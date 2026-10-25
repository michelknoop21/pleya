/// A-24b: the Studio palette belongs to Instellingen and its subpages only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/theme/tv_switch_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';

const _probe = Key('probe');

ThemeData _theme(String palette) => switch (palette) {
  'light' => monoTheme(dark: false),
  'dark' => monoTheme(dark: true),
  _ => monoTheme(dark: true, oled: true),
};

Future<void> _pump(WidgetTester tester, String palette, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: _theme(palette),
    home: Scaffold(body: child),
  ),
);

MonoTokens _tokensAt(WidgetTester tester, Finder finder) => tokens(tester.element(finder));

void main() {
  group('tokens per palette', () {
    test('Light: warm page, card and hairline', () {
      final studio = settingsStudioTokens(tokensOf(_theme('light')));
      expect(studio.bg, kStudioLightPage);
      expect(studio.surface, kStudioLightCard);
      expect(studio.outline, kStudioLightHairline);
      expect(studio.text, tokensOf(_theme('light')).text, reason: 'ink is not re-tinted');
    });

    test('Dark: the page stays #141414, only the card warms', () {
      final base = tokensOf(_theme('dark'));
      final studio = settingsStudioTokens(base);
      expect(studio.bg, base.bg);
      expect(studio.surface, kStudioDarkCard);
      expect(settingsStudioWash(studio), kStudioWashDark);
    });

    test('OLED: the page stays black and gets no wash', () {
      final studio = settingsStudioTokens(tokensOf(_theme('oled')));
      expect(studio.bg, const Color(0xFF000000));
      expect(studio.surface, kStudioOledCard);
      expect(settingsStudioWash(studio), isNull);
    });
  });

  testWidgets('inside the wrapper the page is warm, beside it monoTheme is untouched', (tester) async {
    await _pump(
      tester,
      'light',
      const Column(
        children: [
          SettingsStudioTheme(child: SizedBox(key: _probe)),
          SizedBox(key: Key('outside')),
        ],
      ),
    );

    expect(_tokensAt(tester, find.byKey(_probe)).bg, kStudioLightPage);
    expect(Theme.of(tester.element(find.byKey(_probe))).scaffoldBackgroundColor, kStudioLightPage);
    expect(_tokensAt(tester, find.byKey(const Key('outside'))).bg, const Color(0xFFF7F7F8));
    expect(SettingsStudioTheme.isActive(tester.element(find.byKey(const Key('outside')))), isFalse);
  });

  testWidgets('an on switch is coral inside Instellingen, Material default outside', (tester) async {
    await _pump(
      tester,
      'dark',
      const Column(
        children: [
          SettingsStudioTheme(child: SizedBox(key: _probe)),
          SizedBox(key: Key('outside')),
        ],
      ),
    );
    const on = {WidgetState.selected};
    final inside = Theme.of(tester.element(find.byKey(_probe))).switchTheme;
    expect(inside.trackColor?.resolve(on), kStudioSwitchDark);
    expect(inside.trackColor?.resolve(const {}), isNull, reason: 'off keeps the theme default');
    final outside = Theme.of(tester.element(find.byKey(const Key('outside')))).switchTheme;
    expect(outside.trackColor?.resolve(on), isNull);
  });

  testWidgets('Light takes the deeper coral', (tester) async {
    await _pump(tester, 'light', const SettingsStudioTheme(child: SizedBox(key: _probe)));
    final track = Theme.of(tester.element(find.byKey(_probe))).switchTheme.trackColor;
    expect(track?.resolve({WidgetState.selected}), kStudioSwitchLight);
  });

  testWidgets('OLED: the settings card is the warm Studio card inside, the lifted grey outside', (tester) async {
    await _pump(
      tester,
      'oled',
      const Column(
        children: [
          SettingsStudioTheme(child: SizedBox(key: _probe)),
          SizedBox(key: Key('outside')),
        ],
      ),
    );
    expect(settingsCardColor(tester.element(find.byKey(_probe))), kStudioOledCard);
    expect(settingsCardColor(tester.element(find.byKey(const Key('outside')))), kSettingsOledCardColor);
  });

  group('a settings row carries the palette to the page it opens', () {
    Widget row() => SettingNavigationTile(
      icon: Symbols.palette_rounded,
      title: 'Weergave',
      destinationBuilder: (_) => const SizedBox(key: _probe),
    );

    testWidgets('from inside Instellingen the next page is warm too', (tester) async {
      await _pump(tester, 'light', SettingsStudioTheme(child: row()));
      await tester.tap(find.text('Weergave'));
      await tester.pumpAndSettle();
      expect(_tokensAt(tester, find.byKey(_probe)).bg, kStudioLightPage);
    });

    testWidgets('the same row elsewhere opens a monoTheme page', (tester) async {
      await _pump(tester, 'light', row());
      await tester.tap(find.text('Weergave'));
      await tester.pumpAndSettle();
      expect(_tokensAt(tester, find.byKey(_probe)).bg, const Color(0xFFF7F7F8));
    });
  });

  group('TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('TvSwitchTheme keeps the Studio coral for an on switch and styles off itself', (tester) async {
      await _pump(
        tester,
        'dark',
        const SettingsStudioTheme(
          child: TvSwitchTheme(child: SizedBox(key: _probe)),
        ),
      );
      final theme = Theme.of(tester.element(find.byKey(_probe))).switchTheme;
      expect(theme.trackColor?.resolve({WidgetState.selected}), kStudioSwitchDark);
      expect(theme.trackColor?.resolve(const {}), isNotNull, reason: 'the TV off track stays its own');
    });

    testWidgets('switching OLED to Dark keeps the page below, so the remote keeps its place', (tester) async {
      Widget app(String palette) => MaterialApp(
        theme: _theme(palette),
        home: const Scaffold(body: SettingsStudioTheme(child: _Counter())),
      );
      await tester.pumpWidget(app('oled'));
      final before = tester.state<_CounterState>(find.byType(_Counter));
      await tester.pumpWidget(app('dark'));
      await tester.pumpAndSettle();
      expect(tokens(tester.element(find.byKey(_probe))).bg, isNot(const Color(0xFF000000)), reason: 'now Dark');
      expect(tester.state<_CounterState>(find.byType(_Counter)), same(before));
    });

    testWidgets('the page is painted with the wash in Dark', (tester) async {
      await _pump(tester, 'dark', const SettingsStudioTheme(child: SizedBox(key: _probe)));
      final gradients = tester
          .widgetList<DecoratedBox>(find.ancestor(of: find.byKey(_probe), matching: find.byType(DecoratedBox)))
          .map((box) => (box.decoration as BoxDecoration).gradient)
          .whereType<RadialGradient>();
      expect(gradients.single.colors.first, kStudioWashDark);
    });
  });
}

MonoTokens tokensOf(ThemeData theme) => theme.extension<MonoTokens>()!;

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox(key: _probe);
}
