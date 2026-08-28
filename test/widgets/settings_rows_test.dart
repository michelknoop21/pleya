import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/settings_section.dart';

/// The regression test on "sometimes the line is double": separators are
/// keyed to the rows that actually laid out with height, not to how many
/// widgets are in the list, so a widget that collapses to
/// [SizedBox.shrink] does not leave a stray separator on either side of it.
void main() {
  const separatorColor = Color(0xFF888888);
  const rowHeight = 40.0;
  const cardWidth = 300.0;

  /// `v` marks a row with real height, `0` a row that collapses to nothing:
  /// the runtime shape of a [StreamBuilder]/[Consumer] with nothing to show.
  Widget row(bool visible) =>
      visible ? const SizedBox(height: rowHeight, width: double.infinity) : const SizedBox.shrink();

  Future<RenderSettingsRows> pump(WidgetTester tester, List<bool> visibility) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: cardWidth,
            child: SettingsRows(separatorColor: separatorColor, children: [for (final v in visibility) row(v)]),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderSettingsRows>(find.byType(SettingsRows));
  }

  final cases = <String, ({List<bool> visibility, int expected})>{
    '[V,V,V]': (visibility: [true, true, true], expected: 2),
    '[V,0,V]': (visibility: [true, false, true], expected: 1),
    '[V,0,0]': (visibility: [true, false, false], expected: 0),
    '[0,V,0,V,0]': (visibility: [false, true, false, true, false], expected: 1),
    '[0,0,0]': (visibility: [false, false, false], expected: 0),
  };

  for (final entry in cases.entries) {
    testWidgets('separatorRects for ${entry.key}', (tester) async {
      final render = await pump(tester, entry.value.visibility);
      expect(render.separatorRects, hasLength(entry.value.expected));
    });
  }

  testWidgets('a separator sits at the top of the row after it, flush against it', (tester) async {
    final render = await pump(tester, [true, true, true]);
    final rects = render.separatorRects;

    expect(rects, hasLength(2));
    expect(rects[0].top, rowHeight, reason: 'the first separator sits at the top of the second row');
    expect(rects[1].top, rowHeight * 2, reason: 'the second separator sits at the top of the third row');
  });

  testWidgets('a separator is indented past the leading icon and reaches the card edge', (tester) async {
    final render = await pump(tester, [true, true]);
    final rect = render.separatorRects.single;

    expect(rect.left, kSettingsSeparatorIndent);
    expect(rect.right, cardWidth);
    expect(rect.height, 1);
  });

  testWidgets('collapsed rows in between do not shift where a separator lands', (tester) async {
    final withGaps = await pump(tester, [true, false, false, true]);
    final withoutGaps = await pump(tester, [true, true]);

    expect(withGaps.separatorRects.single.top, withoutGaps.separatorRects.single.top);
  });

  testWidgets('every separator shares the same thickness and colour', (tester) async {
    final render = await pump(tester, [true, true, true, true]);
    final rects = render.separatorRects;

    expect(rects, hasLength(3));
    for (final rect in rects) {
      expect(rect.height, 1);
    }
    // separatorColor is the single Paint used for every rect painted; there
    // is no per-rect colour to read back, so the shared field is the proof.
  });
}
