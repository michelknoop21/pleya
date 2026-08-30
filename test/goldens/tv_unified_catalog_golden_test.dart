import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_panel.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/tv_catalog_artwork.dart';
import '../test_helpers/tv_catalog_fixtures.dart';

/// Visual acceptance for the fase-5 Films and Series pages
/// (docs/tvos-unified-experience.md hoofdstuk 10, 33.2, 33.3, 34).
///
/// These render the **real** header, grid, card and panels at the tvOS logical
/// canvas DEC-028 produces (1038x584 — see [kTvGoldenSurfaceSize]), with the
/// production `monoTheme` and the app's own fonts. That is what makes them
/// useful as pictures rather than only as assertions: the column count, the
/// gutters, the card proportions, the type hierarchy and the focus ring are all
/// decided by the same code an Apple TV runs.
///
/// What they are not: pixel truth for tvOS. Hoofdstuk 29 is explicit that font
/// rasterization, render scale and HDR differ on the device. They catch a
/// composition regression on this platform; they do not replace hardware
/// verification, which stays outstanding until after fase 10A.
///
/// Artwork is synthetic, and that is a deliberate reversal. The first version
/// of this file rendered every card's placeholder, on the reasoning that a
/// golden depending on a network image would be a golden about the network.
/// True, but it cost more than it saved: twelve identical grey tiles cannot
/// show whether Pleya's dark chrome *presents* colourful content or flattens
/// it, and that question is most of what this phase's art direction is about.
/// `TvGoldenArtwork` fills the seam with deterministic panels spanning the
/// range a real library holds — sunny, neon, green, pastel, muted, near-black.
/// No network, same bytes everywhere, and the composition is finally judged
/// against content rather than against grey.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_unified_catalog_golden_test.dart`

/// The production shell: `InputModeTracker` (which is what makes TV default to
/// keyboard mode, and therefore what makes the focus ring paint at all) and
/// `OverlaySheetHost` — the same host `MainScreen` mounts, so a panel's scrim,
/// centring and constraints in the image are the real ones.
Widget _shell(Widget child) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: InputModeTracker(
        child: OverlaySheetHost(
          child: Scaffold(backgroundColor: theme.extension<MonoTokens>()!.bg, body: child),
        ),
      ),
    ),
  );
}

/// A whole page: header plus grid, exactly as `TvUnifiedCatalogScreen`
/// composes them.
///
/// Built here rather than by pumping the screen itself because the screen reads
/// four providers and a settings store; what these pictures are about is the
/// composition, and the composition is entirely in these two widgets.
Widget _page({
  required List<UnifiedMediaGroup> groups,
  required List<FocusNode> actionNodes,
  int filterBadge = 0,
  String? sourcesValue,
  String? title,
  String? sortValue,
  bool isComplete = false,
  bool isLoadingMore = false,
  int failedLibraries = 0,
  ScrollController? controller,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    TvCatalogHeaderBar(
      title: title ?? t.unifiedCatalog.moviesTitle,
      actions: [
        TvCatalogHeaderAction(
          icon: Symbols.dns_rounded,
          action: LibraryHeaderAction(
            label: t.unifiedCatalog.allSources,
            value: sourcesValue,
            focusNode: actionNodes[0],
            onPressed: () {},
          ),
        ),
        TvCatalogHeaderAction(
          icon: Symbols.filter_list_rounded,
          badgeCount: filterBadge,
          action: LibraryHeaderAction(
            label: t.unifiedCatalog.filters.title,
            focusNode: actionNodes[1],
            onPressed: () {},
          ),
        ),
        TvCatalogHeaderAction(
          icon: Symbols.swap_vert_rounded,
          action: LibraryHeaderAction(
            label: t.unifiedCatalog.sort.title,
            value: sortValue ?? sortLabel(UnifiedCatalogSort.titleAsc),
            focusNode: actionNodes[2],
            onPressed: () {},
          ),
        ),
      ],
    ),
    Expanded(
      child: TvUnifiedMediaGrid(
        controller: controller,
        groups: groups,
        onActivate: (_) {},
        hasMore: !isComplete,
        isLoadingMore: isLoadingMore,
        onLoadMore: () {},
        footer: TvUnifiedGridFooter(
          loadedCount: groups.length,
          isComplete: isComplete,
          isLoadingMore: isLoadingMore,
          failedLibraryCount: failedLibraries,
        ),
      ),
    ),
  ],
);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
    TvGoldenArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvGoldenArtwork.remove();
  });

  List<FocusNode> nodes(WidgetTester tester) {
    final list = [for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'action$i')];
    addTearDown(() {
      for (final node in list) {
        node.dispose();
      }
    });
    return list;
  }

  // The page as it is nine times out of ten. Nothing is focused, so the only
  // things carrying the picture are the grid rhythm, the card proportions and
  // the type hierarchy — which is exactly what should be able to carry it.
  testWidgets('films, default state', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(_shell(_page(groups: tvGoldenCatalog(), actionNodes: nodes(tester))));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_default');
  });

  // Focus is the primary design layer of hoofdstuk 26, so it gets its own
  // picture: the ring has to win the page without the card jumping or eating
  // its neighbours.
  testWidgets('films, a card focused', (tester) async {
    setGoldenSurfaceSize(tester);
    final actionNodes = nodes(tester);
    await tester.pumpWidget(_shell(_page(groups: tvGoldenCatalog(), actionNodes: actionNodes)));
    await tester.pumpAndSettle();
    final card = find.byType(TvUnifiedMediaGrid);
    expect(card, findsOneWidget);
    // A bright card on purpose: a white focus ring over near-white artwork is
    // the case where focus is most at risk of vanishing, and it is the one a
    // grid of grey placeholders could never have tested.
    Focus.of(tester.element(find.text('Inside Out 2'))).requestFocus();
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_card_focused');
  });

  // Hoofdstuk 7.4's other end of the traversal, and the state the Filters badge
  // of 10.6 is actually seen in.
  testWidgets('films, a header action focused with filters active', (tester) async {
    setGoldenSurfaceSize(tester);
    final actionNodes = nodes(tester);
    await tester.pumpWidget(
      _shell(
        _page(
          groups: tvGoldenCatalog(),
          actionNodes: actionNodes,
          filterBadge: 3,
          sourcesValue: t.unifiedCatalog.sources(count: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    actionNodes[1].requestFocus();
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_header_focused');
  });

  // Hoofdstuk 10.7 and 29 together: an exhausted catalog states its exact
  // total, and a library that did not answer says so quietly under the grid
  // instead of over it.
  //
  // **Scrolled to the bottom, and that is the whole point of the test.** The
  // footer this state exists to picture lives under the last row, which on the
  // canonical 584-high canvas is well below the fold. Captured unscrolled, this
  // golden was byte-identical to `films_default` — it would have passed while
  // the count line and the amber notice were broken, missing or absent.
  testWidgets('films, complete with one library missing', (tester) async {
    setGoldenSurfaceSize(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _shell(
        _page(
          groups: tvGoldenCatalog(),
          actionNodes: nodes(tester),
          isComplete: true,
          failedLibraries: 1,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_partial');
  });

  // Hoofdstuk 25's long translations, on the one element that cannot shrink to
  // fit: a card title is capped at two lines and the grid's baseline has to
  // survive it.
  testWidgets('films, long titles', (tester) async {
    setGoldenSurfaceSize(tester);
    final groups = [
      tvGoldenGroup('long1', [
        tvGoldenMovie(id: 'l1', title: 'The Assassination of Jesse James by the Coward Robert Ford', artwork: 8),
        tvGoldenMovie(
          id: 'l1b',
          title: 'The Assassination of Jesse James by the Coward Robert Ford',
          serverId: 'attic',
          artwork: 8,
        ),
      ]),
      tvGoldenGroup('long2', [
        tvGoldenMovie(id: 'l2', title: 'Birdman or (The Unexpected Virtue of Ignorance)', artwork: 6),
      ]),
      tvGoldenGroup('long3', [
        tvGoldenMovie(
          id: 'l3',
          title: 'Everything Everywhere All at Once',
          genre: 'Wetenschappelijke fictie',
          artwork: 5,
        ),
      ]),
      ...tvGoldenCatalog().take(9),
    ];
    await tester.pumpWidget(_shell(_page(groups: groups, actionNodes: nodes(tester))));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_long_titles');
  });

  testWidgets('sort panel', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: tvGoldenCatalog(), actionNodes: nodes(tester)),
              Center(
                child: ElevatedButton(
                  onPressed: () => showTvCatalogSortPanel(context, selected: UnifiedCatalogSort.recentlyAdded),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_sort_panel');
  });

  // The panel with every section in a different state at once: Status and
  // Servers usable, Genre and Year suppressed because a Pleya Server library
  // takes part and cannot execute them (hoofdstuk 10.4), and Libraries showing
  // the server under each name.
  testWidgets('filter panel with suppressed sections', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: tvGoldenCatalog(), actionNodes: nodes(tester)),
              Center(
                child: ElevatedButton(
                  onPressed: () => showTvCatalogFilterPanel(
                    context,
                    selection: const UnifiedCatalogFilterSelection(serverIds: {'nas'}),
                    capabilities: unifiedFilterCapabilitiesFor(tvGoldenLibraries.map((l) => l.backend)),
                    libraries: tvGoldenLibraries,
                    initialSection: TvCatalogFilterSection.servers,
                    clientFor: (_) => null,
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_filter_panel_suppressed');
  });

  // The same panel with Plex and Jellyfin only, which is the common case and
  // the one where every section is live.
  testWidgets('filter panel with every section available', (tester) async {
    setGoldenSurfaceSize(tester);
    final supported = tvGoldenLibraries.take(2).toList();
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: tvGoldenCatalog(), actionNodes: nodes(tester)),
              Center(
                child: ElevatedButton(
                  onPressed: () => showTvCatalogFilterPanel(
                    context,
                    selection: const UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched),
                    capabilities: unifiedFilterCapabilitiesFor(supported.map((l) => l.backend)),
                    libraries: supported,
                    initialSection: TvCatalogFilterSection.status,
                    clientFor: (_) => null,
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_filter_panel_available');
  });

  // The Libraries category, with the focus moved into the options column.
  //
  // This is the picture the rail exists to be judged on: the white ring is on
  // the right, so the only thing still saying which list is on screen is the
  // active category's own fill. An earlier build had that fill at 0.10 and the
  // rail went blank here.
  testWidgets('filter panel, libraries category with focus in the options', (tester) async {
    setGoldenSurfaceSize(tester);
    final supported = tvGoldenLibraries.take(2).toList();
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: tvGoldenCatalog(), actionNodes: nodes(tester)),
              Center(
                child: ElevatedButton(
                  onPressed: () => showTvCatalogFilterPanel(
                    context,
                    selection: const UnifiedCatalogFilterSelection(libraryKeys: {'attic:2'}),
                    capabilities: unifiedFilterCapabilitiesFor(supported.map((l) => l.backend)),
                    libraries: supported,
                    initialSection: TvCatalogFilterSection.libraries,
                    clientFor: (_) => null,
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // RIGHT out of the rail is the production gesture into the options column.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_filter_paneltvGoldenLibraries');
  });

  // Several categories narrowing at once, which is what the count chips are
  // for: the rail has to say where the filters are without the user opening
  // each category to find out.
  testWidgets('filter panel, several categories active at once', (tester) async {
    setGoldenSurfaceSize(tester);
    final supported = tvGoldenLibraries.take(2).toList();
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: tvGoldenCatalog(), actionNodes: nodes(tester)),
              Center(
                child: ElevatedButton(
                  onPressed: () => showTvCatalogFilterPanel(
                    context,
                    selection: const UnifiedCatalogFilterSelection(
                      serverIds: {'nas', 'attic'},
                      libraryKeys: {'nas:1'},
                      watchState: UnifiedWatchFilter.unwatched,
                    ),
                    capabilities: unifiedFilterCapabilitiesFor(supported.map((l) => l.backend)),
                    libraries: supported,
                    initialSection: TvCatalogFilterSection.servers,
                    clientFor: (_) => null,
                  ),
                  child: const Text('open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_filter_panel_multi');
  });

  // ## Series
  //
  // Same widget, same tokens, same grid — `TvSeriesScreen` is a thin wrapper
  // around the very screen Films uses, and hoofdstuk 10.2 puts 2:3 posters on
  // both pages. So what these two pictures are for is precisely to be held next
  // to the Films ones: if anything but the title and the content differs, the
  // two pages have drifted apart.
  //
  // The content does differ, and should. A shelf of series skews lighter and
  // warmer than a shelf of films, and Pleya's job is to present that rather
  // than to grade both pages to the same mood.
  testWidgets('series, default state', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(_page(groups: tvGoldenSeriesCatalog(), actionNodes: nodes(tester), title: t.unifiedCatalog.seriesTitle)),
    );
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_series_default');
  });

  testWidgets('series, a card focused', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(_page(groups: tvGoldenSeriesCatalog(), actionNodes: nodes(tester), title: t.unifiedCatalog.seriesTitle)),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Ted Lasso'))).requestFocus();
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_series_card_focused');
  });

  // Hoofdstuk 25's long translations, on the page as a whole rather than on one
  // card: the page title, all three header capsules and the card titles are
  // under pressure in the same frame. The header is the part with nowhere to go
  // — it is one line by design — so this is where a layout that only works in
  // English shows.
  //
  // **The long labels are passed in rather than reached by switching locale,
  // and that is a limitation, not a preference.** Every locale but the base one
  // is deferred-loaded here, and a deferred library does not load inside
  // `flutter test`: `setLocaleSync` throws `_DeferredNotLoadedError`, and
  // awaiting `setLocale` never returns — in fake async or inside `runAsync`.
  // No test in this repository renders a non-base locale, for that reason. The
  // strings below are the real German ones from `de.i18n.json`, so what this
  // golden proves is that the composition survives labels of that length. What
  // it cannot prove is that the German file says what it should; a render of a
  // genuinely switched locale stays outstanding alongside hardware
  // verification.
  testWidgets('films, labels at the length a long locale produces', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        _page(
          groups: tvGoldenCatalog(),
          actionNodes: nodes(tester),
          title: 'Filme',
          filterBadge: 2,
          sourcesValue: 'Alle Quellen',
          sortValue: 'Zuletzt hinzugefügt',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_long_locale');
  });
}
