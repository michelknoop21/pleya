import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/tv/tv_catalog_row_alignment.dart';

/// The 1920 x 1080 catalog: cards of 488.4 with a gutter of 22 and a ring of
/// 14.65, in the viewport a folded page leaves (1080 minus a margin of 26).
const double _card = 488.4;
const double _gutter = 22;
const double _growth = 14.652;
const double _viewport = 1054;
const double _pitch = _card + _gutter;

double _offset({required int row, required double pixels, double max = 10000}) => tvCatalogRowAlignedOffset(
  row: row,
  pixels: pixels,
  viewport: _viewport,
  cardHeight: _card,
  gutter: _gutter,
  growth: _growth,
  minScrollExtent: 0,
  maxScrollExtent: max,
);

void main() {
  test('two whole rows fit in the folded viewport, three do not', () {
    expect(tvCatalogWholeRowsThatFit(viewport: _viewport, cardHeight: _card, gutter: _gutter, growth: _growth), 2);
  });

  test('a row already in the window does not move it', () {
    expect(_offset(row: 3, pixels: 2 * _pitch), 2 * _pitch);
    expect(_offset(row: 2, pixels: 2 * _pitch), 2 * _pitch);
  });

  test('DOWN past the window makes the focused row the bottom one', () {
    expect(_offset(row: 4, pixels: 2 * _pitch), 3 * _pitch);
  });

  test('UP past the window makes the focused row the top one', () {
    expect(_offset(row: 1, pixels: 2 * _pitch), _pitch);
  });

  test('an offset between rows settles on the nearest row', () {
    expect(_offset(row: 3, pixels: 2 * _pitch + 40), 2 * _pitch);
    expect(_offset(row: 3, pixels: 3 * _pitch - 40), 3 * _pitch);
  });

  test('the end of the content wins over the row line', () {
    expect(_offset(row: 9, pixels: 7 * _pitch, max: 8 * _pitch - 100), 8 * _pitch - 100);
  });
}
