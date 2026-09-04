/// HERO2 (docs/tvos-fysieke-correctieronde.md): the hero's title band has to
/// fit the number of title lines the card is willing to draw.
///
/// The band is shared with the clearlogo, which is the reason it exists: a
/// slide with a wordmark and a slide with type put the metadata line in the
/// same place. That sharing set the band to the *logo's* height, and the type
/// branch then asked for two lines inside it. One line fits, two do not, so a
/// two-line title lost its bottom edge — "An Extended…" with the feet cut off,
/// reported by Michel on an Apple TV with build 249.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

void main() {
  test('the title band fits every line the title is allowed to use', () {
    final needed = TvHomeLayout.heroTitleFontSize * TvHomeLayout.heroLineHeight * TvHomeLayout.heroTitleMaxLines;
    expect(
      TvHomeLayout.heroTitleBandHeight,
      greaterThanOrEqualTo(needed),
      reason:
          'band is ${TvHomeLayout.heroTitleBandHeight}, a ${TvHomeLayout.heroTitleMaxLines}-line title needs '
          '$needed (${TvHomeLayout.heroTitleFontSize} x ${TvHomeLayout.heroLineHeight} x '
          '${TvHomeLayout.heroTitleMaxLines}); the difference is cut off the bottom of the last line',
    );
  });

  test('the clearlogo keeps its own height inside that band', () {
    // The band grew for the type branch; the logo must not grow with it, or a
    // wordmark that used to sit at 76 would render half again as large.
    expect(TvHomeLayout.heroLogoMaxHeight, 76);
    expect(TvHomeLayout.heroTitleBandHeight, greaterThanOrEqualTo(TvHomeLayout.heroLogoMaxHeight));
  });

  testWidgets('a two-line title paints inside its band', (tester) async {
    // Rendered rather than calculated: the band is a `SizedBox` with an
    // `Align`, and a child taller than its box overflows instead of resizing,
    // which is exactly how the defect stayed invisible to the token maths.
    const scale = 1.0;
    final band = TvHomeLayout.heroTitleBandHeight * scale;
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: TvHomeLayout.heroTextMaxWidth * scale,
              height: band,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  key: key,
                  'Grand Theft Auto VI: An Extended Look At The Next Evolution',
                  maxLines: TvHomeLayout.heroTitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: TvHomeLayout.heroTitleFontSize * scale,
                    height: TvHomeLayout.heroLineHeight,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final textHeight = tester.getSize(find.byKey(key)).height;
    expect(
      textHeight,
      lessThanOrEqualTo(band),
      reason: 'the title paints $textHeight into a band of $band, so the overflow is cut off',
    );
  });
}
