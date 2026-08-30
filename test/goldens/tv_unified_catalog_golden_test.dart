import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
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
/// Artwork is deliberately absent. `OptimizedMediaImage` needs a live client to
/// sign a URL, and a golden that depended on a network image would be a golden
/// about the network. Every card therefore renders its placeholder, which is
/// also the honest picture of a first frame and of an offline server — and it
/// puts the whole weight of the composition on the things this phase decides:
/// rhythm, density, type and focus.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_unified_catalog_golden_test.dart`

MediaItem _movie({
  required String id,
  required String title,
  int? year = 2024,
  String? genre = 'Science fiction',
  int? viewOffsetMs,
  int? viewCount,
  String serverId = 'nas',
  String serverName = 'NAS',
  MediaBackend backend = MediaBackend.plex,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.movie,
  title: title,
  year: year,
  durationMs: 9960000,
  viewOffsetMs: viewOffsetMs,
  viewCount: viewCount,
  genres: genre == null ? null : [genre],
  serverId: serverId,
  serverName: serverName,
);

UnifiedMediaGroup _group(
  String id,
  List<MediaItem> items, {
  bool watched = false,
  bool inProgress = false,
}) {
  final sources = [for (final item in items) UnifiedMediaSource.fromItem(item)];
  return UnifiedMediaGroup(
    groupId: id,
    identity: CanonicalMediaIdentity.movie(title: items.first.title, year: items.first.year),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(
      representativeSourceKey: sources.first.sourceKey,
      isWatched: watched,
      hasActiveProgress: inProgress,
      lastViewedAt: inProgress || watched ? 1 : null,
    ),
  );
}

/// A page's worth of groups: a mix of single and multi source, watched,
/// in-progress and untouched, plus one title long enough to hit the two-line
/// cap. That mix is the point — a grid of identical cards proves nothing about
/// whether the badge, the tick and the resume bar can coexist in one row.
List<UnifiedMediaGroup> _catalog() {
  final titles = <({String title, int sources, bool watched, bool progress, int? offset})>[
    (title: 'Dune: Part Two', sources: 2, watched: false, progress: true, offset: 2538000),
    (title: 'Oppenheimer', sources: 3, watched: true, progress: false, offset: null),
    (title: 'The Batman', sources: 1, watched: false, progress: true, offset: 6400000),
    (title: 'Godzilla Minus One', sources: 2, watched: false, progress: false, offset: null),
    (title: 'Poor Things', sources: 1, watched: true, progress: false, offset: null),
    (title: 'Everything Everywhere All at Once', sources: 2, watched: false, progress: false, offset: null),
    (title: 'The Last House', sources: 1, watched: false, progress: false, offset: null),
    (title: 'Mutiny', sources: 2, watched: false, progress: true, offset: 3100000),
    (title: 'A Quiet Place', sources: 1, watched: true, progress: false, offset: null),
    (title: 'Blade Runner 2049', sources: 3, watched: false, progress: false, offset: null),
    (title: 'Arrival', sources: 1, watched: false, progress: false, offset: null),
    (title: 'Sicario', sources: 2, watched: false, progress: false, offset: null),
  ];
  return [
    for (var i = 0; i < titles.length; i++)
      _group(
        'g$i',
        [
          for (var s = 0; s < titles[i].sources; s++)
            _movie(
              id: 'i$i-$s',
              title: titles[i].title,
              year: 2017 + (i % 8),
              viewOffsetMs: s == 0 ? titles[i].offset : null,
              viewCount: s == 0 && titles[i].watched ? 1 : null,
              serverId: ['nas', 'attic', 'shed'][s],
              serverName: ['NAS', 'Zolder', 'Schuur'][s],
              backend: s == 1 ? MediaBackend.jellyfin : MediaBackend.plex,
            ),
        ],
        watched: titles[i].watched,
        inProgress: titles[i].progress,
      ),
  ];
}

final _libraries = <CatalogLibrary>[
  (serverId: ServerId('nas'), serverName: 'NAS', libraryId: '1', libraryTitle: 'Films 4K', backend: MediaBackend.plex),
  (
    serverId: ServerId('attic'),
    serverName: 'Zolder',
    libraryId: '2',
    libraryTitle: 'Movies',
    backend: MediaBackend.jellyfin,
  ),
  (
    serverId: ServerId('shed'),
    serverName: 'Schuur',
    libraryId: '3',
    libraryTitle: 'Archief',
    backend: MediaBackend.pleyaServer,
  ),
];

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
  bool isComplete = false,
  bool isLoadingMore = false,
  int failedLibraries = 0,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    TvCatalogHeaderBar(
      title: t.unifiedCatalog.moviesTitle,
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
            value: sortLabel(UnifiedCatalogSort.titleAsc),
            focusNode: actionNodes[2],
            onPressed: () {},
          ),
        ),
      ],
    ),
    Expanded(
      child: TvUnifiedMediaGrid(
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
  });

  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

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
    await tester.pumpWidget(_shell(_page(groups: _catalog(), actionNodes: nodes(tester))));
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_default');
  });

  // Focus is the primary design layer of hoofdstuk 26, so it gets its own
  // picture: the ring has to win the page without the card jumping or eating
  // its neighbours.
  testWidgets('films, a card focused', (tester) async {
    setGoldenSurfaceSize(tester);
    final actionNodes = nodes(tester);
    await tester.pumpWidget(_shell(_page(groups: _catalog(), actionNodes: actionNodes)));
    await tester.pumpAndSettle();
    final card = find.byType(TvUnifiedMediaGrid);
    expect(card, findsOneWidget);
    Focus.of(tester.element(find.text('Oppenheimer'))).requestFocus();
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
          groups: _catalog(),
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
  testWidgets('films, complete with one library missing', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(_page(groups: _catalog(), actionNodes: nodes(tester), isComplete: true, failedLibraries: 1)),
    );
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_films_partial');
  });

  // Hoofdstuk 25's long translations, on the one element that cannot shrink to
  // fit: a card title is capped at two lines and the grid's baseline has to
  // survive it.
  testWidgets('films, long titles', (tester) async {
    setGoldenSurfaceSize(tester);
    final groups = [
      _group('long1', [
        _movie(id: 'l1', title: 'The Assassination of Jesse James by the Coward Robert Ford'),
        _movie(id: 'l1b', title: 'The Assassination of Jesse James by the Coward Robert Ford', serverId: 'attic'),
      ]),
      _group('long2', [_movie(id: 'l2', title: 'Birdman or (The Unexpected Virtue of Ignorance)')]),
      _group('long3', [
        _movie(id: 'l3', title: 'Everything Everywhere All at Once', genre: 'Wetenschappelijke fictie'),
      ]),
      ..._catalog().take(9),
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
              _page(groups: _catalog(), actionNodes: nodes(tester)),
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
              _page(groups: _catalog(), actionNodes: nodes(tester)),
              Center(
                child: ElevatedButton(
                  onPressed: () => showTvCatalogFilterPanel(
                    context,
                    selection: const UnifiedCatalogFilterSelection(serverIds: {'nas'}),
                    capabilities: unifiedFilterCapabilitiesFor(_libraries.map((l) => l.backend)),
                    libraries: _libraries,
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
    final supported = _libraries.take(2).toList();
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: _catalog(), actionNodes: nodes(tester)),
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
    final supported = _libraries.take(2).toList();
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: _catalog(), actionNodes: nodes(tester)),
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
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_filter_panel_libraries');
  });

  // Several categories narrowing at once, which is what the count chips are
  // for: the rail has to say where the filters are without the user opening
  // each category to find out.
  testWidgets('filter panel, several categories active at once', (tester) async {
    setGoldenSurfaceSize(tester);
    final supported = _libraries.take(2).toList();
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => Stack(
            children: [
              _page(groups: _catalog(), actionNodes: nodes(tester)),
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
}
