import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';

import '../../test_helpers/prefs.dart';

const _rowTitles = ['First row', 'Middle row', 'Last row'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<FocusNode> nodes;
  late List<String> taps;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    // Also puts InputModeTracker in keyboard mode, which is what gates the
    // focus visuals.
    TvDetectionService.debugSetAppleTVOverride(true);
    await SettingsService.getInstance();
    nodes = [for (var i = 0; i < _rowTitles.length; i++) FocusNode(debugLabel: _rowTitles[i])];
    taps = [];
  });

  tearDown(() {
    for (final node in nodes) {
      node.dispose();
    }
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  Future<void> pumpRows(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: dark),
          home: Scaffold(
            body: SettingsWidthLimit(
              child: SettingsGroup(
                title: 'Section',
                children: [
                  for (var i = 0; i < _rowTitles.length; i++)
                    SettingNavigationTile(
                      icon: Symbols.settings_rounded,
                      title: _rowTitles[i],
                      subtitle: 'Subtitle $i',
                      focusNode: nodes[i],
                      onTap: () => taps.add(_rowTitles[i]),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The row's focus surface: the [AnimatedContainer] the row wrapper paints
  /// around the tile. One per row, so `.first` is unambiguous.
  AnimatedContainer surfaceOf(WidgetTester tester, int index) {
    final row = find.byType(SettingNavigationTile).at(index);
    return tester.widget<AnimatedContainer>(find.descendant(of: row, matching: find.byType(AnimatedContainer)).first);
  }

  /// The fill: `decoration`, painted behind the tile.
  BoxDecoration fillOf(WidgetTester tester, int index) => surfaceOf(tester, index).decoration! as BoxDecoration;

  /// The marker: `foregroundDecoration`'s border, painted on top of the tile.
  /// Never affects layout, unlike the border this replaced.
  Border markerOf(WidgetTester tester, int index) {
    final decoration = surfaceOf(tester, index).foregroundDecoration! as BoxDecoration;
    return decoration.border! as Border;
  }

  bool looksFocused(WidgetTester tester, int index, MonoTokens t) {
    final fill = fillOf(tester, index);
    final marker = markerOf(tester, index);
    return fill.color == t.surfaceElevated && marker.left.color.a != 0;
  }

  MonoTokens tokensOf(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsGroup))).extension<MonoTokens>()!;

  for (final dark in [true, false]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('the focused row is visibly different from its neighbours ($mode)', (tester) async {
      await pumpRows(tester, dark: dark);
      final t = tokensOf(tester);

      for (var focusedIndex = 0; focusedIndex < _rowTitles.length; focusedIndex++) {
        nodes[focusedIndex].requestFocus();
        await tester.pumpAndSettle();

        for (var i = 0; i < _rowTitles.length; i++) {
          expect(
            looksFocused(tester, i, t),
            i == focusedIndex,
            reason:
                'with "${_rowTitles[focusedIndex]}" focused, row "${_rowTitles[i]}" should '
                '${i == focusedIndex ? 'carry' : 'not carry'} the focus surface',
          );
        }

        final restingIndex = (focusedIndex + 1) % _rowTitles.length;
        final focusedFill = fillOf(tester, focusedIndex);
        final restingFill = fillOf(tester, restingIndex);
        expect(
          focusedFill.color,
          isNot(restingFill.color),
          reason: 'focus must not resolve to the card surface itself',
        );
        expect(focusedFill.color, isNot(t.surface), reason: 'a focused row the colour of the card is invisible');
        expect(focusedFill.borderRadius, isNull, reason: 'the fill must not clip a pill inside the card');

        final focusedMarker = markerOf(tester, focusedIndex);
        expect(
          focusedMarker.left.color.a,
          greaterThan(0.5),
          reason: 'the focused row carries a solid marker on its leading edge',
        );
        expect(
          focusedMarker.top.width,
          0,
          reason: 'the marker must not draw a top perimeter, that is SettingsRows\' separator to own',
        );
        expect(focusedMarker.right.width, 0, reason: 'the marker must not draw a right perimeter');
        expect(
          focusedMarker.bottom.width,
          0,
          reason: 'the marker must not draw a bottom perimeter, that is the next separator\'s to own',
        );

        final restingMarker = markerOf(tester, restingIndex);
        expect(restingMarker.left.color.a, 0, reason: 'a resting row must carry no visible marker at all');
      }
    });
  }

  testWidgets('moving focus does not leave the marker behind on the previous row', (tester) async {
    await pumpRows(tester, dark: true);
    final t = tokensOf(tester);

    nodes[0].requestFocus();
    await tester.pumpAndSettle();
    expect(looksFocused(tester, 0, t), isTrue);

    nodes[2].requestFocus();
    await tester.pumpAndSettle();

    expect(looksFocused(tester, 0, t), isFalse, reason: 'the marker stayed on the row focus left');
    expect(looksFocused(tester, 2, t), isTrue);
    expect([for (var i = 0; i < _rowTitles.length; i++) looksFocused(tester, i, t)].where((f) => f).length, 1);
  });

  testWidgets('focus does not move or resize the rows', (tester) async {
    await pumpRows(tester, dark: true);

    final titlesBefore = [for (final title in _rowTitles) tester.getRect(find.text(title))];
    final iconsBefore = [
      for (var i = 0; i < _rowTitles.length; i++) tester.getRect(find.byType(SettingsIconBadge).at(i)),
    ];

    nodes[1].requestFocus();
    await tester.pumpAndSettle();

    final titlesAfter = [for (final title in _rowTitles) tester.getRect(find.text(title))];
    final iconsAfter = [
      for (var i = 0; i < _rowTitles.length; i++) tester.getRect(find.byType(SettingsIconBadge).at(i)),
    ];
    for (var i = 0; i < _rowTitles.length; i++) {
      expect(titlesAfter[i], titlesBefore[i], reason: 'row "${_rowTitles[i]}" text shifted when a row took focus');
      expect(iconsAfter[i], iconsBefore[i], reason: 'row "${_rowTitles[i]}" icon shifted when a row took focus');
    }
  });

  testWidgets('select on the focused row still runs the row action', (tester) async {
    await pumpRows(tester, dark: true);

    nodes[1].requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(taps, ['Middle row']);

    // The pointer path is untouched by the focus wrapper.
    await tester.tap(find.text('Last row'));
    await tester.pumpAndSettle();
    expect(taps, ['Middle row', 'Last row']);
  });

  testWidgets('focusing a row does not change how many separators the group paints', (tester) async {
    await pumpRows(tester, dark: true);
    final render = tester.renderObject<RenderSettingsRows>(find.byType(SettingsRows));
    final atRest = render.separatorRects.length;
    expect(atRest, _rowTitles.length - 1);

    for (final node in nodes) {
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(render.separatorRects.length, atRest, reason: 'a focused row must not add or remove a separator');
    }
  });

  testWidgets('each row is a single focus stop', (tester) async {
    await pumpRows(tester, dark: true);

    nodes[0].requestFocus();
    await tester.pumpAndSettle();

    // One step down lands on the next row, not on something inside the current
    // one: a focusable tile under the wrapper would swallow this press.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(nodes[1].hasFocus, isTrue, reason: 'DOWN skipped a row or stopped inside one');
    expect(nodes[0].hasFocus, isFalse);
  });
}
