import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/media_card_grid_layout.dart';

/// Pins the arithmetic so a later change to a font size or an inset breaks
/// here, in one line, instead of on a television.
void main() {
  Future<BuildContext> pumpContext(WidgetTester tester, {TextScaler? textScaler}) async {
    late BuildContext captured;
    Widget child = Builder(
      builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      },
    );
    if (textScaler != null) {
      child = MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: child,
      );
    }
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: child));
    return captured;
  }

  test('the poster is 2:3 measured on the poster, not on the cell', () {
    expect(MediaCardGridLayout.posterWidthFor(120), 114);
    expect(MediaCardGridLayout.posterHeightFor(120), 171);
    expect(MediaCardGridLayout.posterHeightFor(120) / MediaCardGridLayout.posterWidthFor(120), closeTo(1.5, 0.001));
  });

  testWidgets('the caption reserve covers one title line plus one subtitle line', (tester) async {
    final context = await pumpContext(tester, textScaler: TextScaler.noScaling);

    // 13 * 1.1 + 11 * 1.1 = 26.4, rounded up so the box is never short.
    expect(MediaCardGridLayout.captionExtentFor(context), 27);
    // 3 top + 2 gap + 27 caption + 1 bottom.
    expect(MediaCardGridLayout.textExtentFor(context), 33);
    expect(MediaCardGridLayout.cardHeightFor(context, 120), 171 + 33);
  });

  testWidgets('the reserve grows with the system text size', (tester) async {
    final context = await pumpContext(tester, textScaler: const TextScaler.linear(2));

    // The poster is fixed, so unlike the app's other grids the caption cannot
    // borrow height from it. If the reserve did not scale, a large text
    // setting would put the caption back on the row below.
    expect(MediaCardGridLayout.captionExtentFor(context), 53);
    expect(MediaCardGridLayout.cardHeightFor(context, 120), 171 + 59);
  });

  testWidgets('the card height is exactly the poster plus the text reserve', (tester) async {
    final context = await pumpContext(tester);

    for (final width in [104.0, 120.0, 187.5]) {
      expect(
        MediaCardGridLayout.cardHeightFor(context, width),
        MediaCardGridLayout.posterHeightFor(width) + MediaCardGridLayout.textExtentFor(context),
      );
    }
  });
}
