/// The open rail's own geometry (CAT5 / DEC-093, mockup 28 D2).
///
/// `test/screens/tv/tv_catalog_filter_rail_test.dart` drives the rail through
/// the real catalog and proves the traversal. This file is the panel on its
/// own, for the one thing that is awkward to reach that way: the heading caps
/// its tags and the panel deliberately does not, so the panel is the widget
/// that has to survive a selection longer than the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// The panel in the band the screen positions it in: the page inset on the
  /// left, the grid's overscan margin at the bottom, aligned to the top.
  Future<List<FocusNode>> pumpPanel(
    WidgetTester tester, {
    required List<TvCatalogSelectionTag> tags,
    Size surface = const Size(1038, 584),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final nodes = [for (var i = 0; i < 4; i++) FocusNode(debugLabel: 'rail$i')];
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final scale = TvLayoutConstants.scaleOf(context);
                  final width = MediaQuery.sizeOf(context).width;
                  final grid = TvCatalogGrid.forWidth(width, scale: scale);
                  return Stack(
                    children: [
                      Positioned(
                        left: grid.inset,
                        top: 0,
                        bottom: grid.bottomSafeMargin,
                        width: width * (TvCatalogLayout.railWidth / TvCatalogGrid.referenceWidth),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: TvCatalogFilterRailPanel(
                            key: tvCatalogFilterRailKey,
                            scale: scale,
                            tags: tags,
                            onClear: () {},
                            clearFocusNode: nodes[3],
                            rows: [
                              TvCatalogFilterRailRow(
                                icon: Symbols.dns_rounded,
                                label: t.unifiedCatalog.rail.sources,
                                value: t.unifiedCatalog.allSources,
                                focusNode: nodes[0],
                                onPressed: () {},
                              ),
                              TvCatalogFilterRailRow(
                                icon: Symbols.filter_list_rounded,
                                label: t.unifiedCatalog.filters.title,
                                value: t.unifiedCatalog.rail.filtersActive(count: 3),
                                focusNode: nodes[1],
                                onPressed: () {},
                              ),
                              TvCatalogFilterRailRow(
                                icon: Symbols.swap_vert_rounded,
                                label: t.unifiedCatalog.sort.title,
                                value: 'Titel A-Z',
                                focusNode: nodes[2],
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return nodes;
  }

  testWidgets('a short selection leaves the panel shrink-wrapped to its rows', (tester) async {
    await pumpPanel(tester, tags: const [TvCatalogSelectionTag('Titel A-Z', muted: true)]);

    final panel = tester.getRect(find.byKey(tvCatalogFilterRailKey));
    expect(tester.takeException(), isNull);
    // Mockup 28 D2 draws a panel as tall as its content, not a full-height
    // column. Half the canvas is a generous ceiling for three rows, Wissen and
    // one tag; the point is that it is nowhere near the band it stands in.
    expect(panel.height, lessThan(584 * 0.5), reason: 'height was ${panel.height}');
  });

  testWidgets('a selection longer than the page scrolls inside the panel instead of overflowing it', (tester) async {
    await pumpPanel(
      tester,
      tags: [
        for (final genre in [
          'Actie',
          'Animatie',
          'Avontuur',
          'Comedy',
          'Documentaire',
          'Drama',
          'Fantasy',
          'Historisch',
          'Horror',
          'Misdaad',
          'Muziek',
          'Mysterie',
          'Oorlog',
          'Romantiek',
          'Sciencefiction',
          'Thriller',
          'Western',
        ])
          TvCatalogSelectionTag(genre),
        const TvCatalogSelectionTag('Titel A-Z', muted: true),
      ],
    );

    expect(tester.takeException(), isNull, reason: 'eighteen tags must not overflow the panel');
    final panel = tester.getRect(find.byKey(tvCatalogFilterRailKey));
    expect(panel.bottom, lessThanOrEqualTo(584.0), reason: 'panel bottom was ${panel.bottom}');
    // And the rows are still operable: a scroll view that clipped them away
    // would satisfy the assertion above while making the rail useless.
    expect(find.text(t.unifiedCatalog.rail.sources), findsOneWidget);
  });
}
