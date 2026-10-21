/// A-06b: a grid under a fixed heading (Kijklijst, collections, person, the
/// library catalogue) fits two rows only down to a floor, so its cards keep a
/// two-word title on one line (Michel, 21 October 2026, after the Aanvragen
/// screenshot with 86-wide cards).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/golden.dart';

/// The Apple TV canvas, without the root scale: geometry only.
const Size _canvas = Size(1038, 584);

/// A grid box the height a page under the top bar and a page heading leaves.
const double _gridHeight = 440;

void main() {
  // The real typeface: the test font sets every glyph a full em wide.
  setUpAll(loadAppFontsForGoldens);

  testWidgets('cards under a fixed heading stay wide enough for a one-line title', (tester) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const scale = 0.85;

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _canvas.width,
                height: _gridHeight,
                child: TvCatalogCardGrid(
                  fitTwoRows: true,
                  fitScale: 1,
                  itemIds: [for (var i = 0; i < 12; i++) 'm$i'],
                  cardHeight: (width) => TvCatalogLayout.cardHeight(width, scale),
                  hasMore: false,
                  isLoadingMore: false,
                  onLoadMore: () {},
                  itemBuilder: (context, cell) => TvCatalogCard(
                    width: cell.width,
                    artwork: const SizedBox(),
                    title: 'Harbor Light',
                    meta: '2022 · Film',
                    focusNode: cell.focusNode,
                    onSelect: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final natural = TvCatalogGrid.forWidth(_canvas.width, scale: scale);
    final card = tester.getSize(find.byType(TvCatalogCard).first);
    expect(card.width, greaterThanOrEqualTo(natural.cardWidth * TvCatalogCardGrid.minFitFraction - 0.5));

    final title = tester.renderObject<RenderParagraph>(find.text('Harbor Light').first);
    final lines = title.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 12));
    final rows = {for (final box in lines) box.top.round()};
    expect(rows, hasLength(1), reason: 'a two-word title on one line');
  });
}
