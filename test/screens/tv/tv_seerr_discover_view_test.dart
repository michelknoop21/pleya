/// Ontdekken op Aanvragen on TV, pumped on its own (DEC-108, mockup 35 A and
/// 35 B).
///
/// The screen behind it needs a live Seerr session; the view takes finished
/// shelves and callbacks, which is what lets the composition and the traversal
/// be asserted without one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/seerr/seerr_tv_search_row.dart';
import 'package:pleya/navigation/tv/tv_nested_back_owner.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/screens/seerr/seerr_discover_filter_bar.dart';
import 'package:pleya/screens/tv/tv_seerr_discover_view.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/seerr_poster_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_rail_scaffold.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_seerr_card.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

SeerrMedia _media(int id, {String title = 'Gladiator II', SeerrMediaStatus status = SeerrMediaStatus.unknown}) =>
    SeerrMedia(tmdbId: id, mediaType: 'movie', title: title, year: '2024', status: status);

TvSeerrShelf _shelf(String id, {int count = 6, String? title}) => TvSeerrShelf(
  id: id,
  title: title ?? id,
  items: [for (var i = 0; i < count; i++) _media(id.hashCode.abs() + i, title: '$id $i')],
  hasMore: false,
  isLoadingMore: false,
  onLoadMore: () {},
  onShowAll: () {},
);

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpView(
    WidgetTester tester, {
    List<TvSeerrShelf> shelves = const [],
    TvSeerrGridPage? grid,
    SeerrDiscoverType type = SeerrDiscoverType.all,
    List<SeerrDiscoverGenre> genres = const [],
    int? genreId,
    List<TvSeerrProviderOption> providers = const [],
    int? providerId,
    bool isLoading = false,
    String? error,
    void Function(SeerrDiscoverType)? onTypeSelected,
    void Function(int?)? onGenreSelected,
    VoidCallback? onLeaveGrid,
  }) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvSeerrDiscoverView(
              searchField: const SizedBox(height: 40, key: ValueKey('searchField')),
              shelves: shelves,
              grid: grid,
              type: type,
              onTypeSelected: onTypeSelected ?? (_) {},
              genres: genres,
              genreId: genreId,
              onGenreSelected: onGenreSelected ?? (_) {},
              providers: providers,
              providerId: providerId,
              onProviderSelected: providers.isEmpty ? null : (_) {},
              isLoading: isLoading,
              onReload: () {},
              onActivate: (_) {},
              onLeaveGrid: onLeaveGrid,
              error: error,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a shelf is a rail of catalog cards, not the seerr poster card (CAT11)', (tester) async {
    await pumpView(tester, shelves: [_shelf('Populaire films')]);

    expect(find.byType(TvCatalogCardRail), findsOneWidget);
    expect(find.byType(TvSeerrMediaCard), findsWidgets);
    expect(find.byType(TvCatalogCard), findsWidgets);
    expect(
      find.byType(SeerrPosterCard),
      findsNothing,
      reason: 'the density-driven poster card is exactly what CAT11 reported',
    );
  });

  testWidgets('and its cards are the width Alle films uses', (tester) async {
    tester.view.physicalSize = const Size(1038, 584);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpView(tester, shelves: [_shelf('Populaire films')]);

    final grid = TvCatalogGrid.forWidth(1038, scale: 0.85);
    expect(
      tester.widgetList<TvSeerrMediaCard>(find.byType(TvSeerrMediaCard)).first.width,
      closeTo(grid.cardWidth, 0.01),
    );
  });

  testWidgets('a title nobody has asked for carries no capsule at all', (tester) async {
    // `unknown` is the state of most of a discover row. A capsule on all twelve
    // would say only that the page loaded.
    await pumpView(
      tester,
      shelves: [
        TvSeerrShelf(
          id: 'films',
          title: 'Populaire films',
          items: [
            _media(1, title: 'Wicked'),
            _media(2, title: 'Gladiator II', status: SeerrMediaStatus.pending),
            _media(3, title: 'Nosferatu', status: SeerrMediaStatus.available),
          ],
          hasMore: false,
          isLoadingMore: false,
          onLoadMore: () {},
          onShowAll: () {},
        ),
      ],
    );

    final badges = tester.widgetList<TvCatalogArtworkBadge>(find.byType(TvCatalogArtworkBadge)).toList();
    expect(badges.map((badge) => badge.label), [t.seerr.requested, t.seerr.available]);
  });

  group('the rail', () {
    Future<void> openRail(WidgetTester tester) async {
      tester.widgetList<TvSeerrMediaCard>(find.byType(TvSeerrMediaCard)).first.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('carries Soort, and Genre only once there are genres to pick', (tester) async {
      await pumpView(tester, shelves: [_shelf('films')]);
      await openRail(tester);

      var rows = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).rows;
      expect(rows.map((row) => row.label), [t.seerr.railKind]);

      await pumpView(
        tester,
        shelves: [_shelf('films')],
        type: SeerrDiscoverType.movies,
        genres: const [(id: 28, name: 'Actie')],
      );
      await openRail(tester);
      rows = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).rows;
      expect(rows.map((row) => row.label), [t.seerr.railKind, t.seerr.railGenre]);
    });

    testWidgets('and Streamingdienst when the region reports any', (tester) async {
      await pumpView(tester, shelves: [_shelf('films')], providers: const [(id: 8, name: 'Netflix')]);
      await openRail(tester);

      final rows = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).rows;
      expect(rows.map((row) => row.label), [t.seerr.railKind, t.seerr.byStreamingService]);
    });

    testWidgets('picking a type reports it and closes the subview', (tester) async {
      SeerrDiscoverType? chosen;
      await pumpView(tester, shelves: [_shelf('films')], onTypeSelected: (type) => chosen = type);
      await openRail(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byKey(tvCatalogFilterRailSubviewKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(chosen, SeerrDiscoverType.movies);
      expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
    });

    testWidgets('the genre subview offers Alle genres first, so it can be cleared', (tester) async {
      await pumpView(
        tester,
        shelves: [_shelf('films')],
        type: SeerrDiscoverType.movies,
        genres: const [(id: 28, name: 'Actie'), (id: 18, name: 'Drama')],
        genreId: 28,
      );
      await openRail(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      final subview = tester.widget<TvCatalogFilterRailSubview>(find.byKey(tvCatalogFilterRailSubviewKey));
      expect(subview.options.map((option) => option.label), [t.seerr.allGenres, 'Actie', 'Drama']);
      expect(subview.options[1].isSelected, isTrue);
    });
  });

  group('the heading', () {
    testWidgets('rests on "Populair nu", muted, because that is not a narrowing', (tester) async {
      await pumpView(tester, shelves: [_shelf('films')]);

      final strip = tester.widget<TvCatalogSelectionTagStrip>(find.byType(TvCatalogSelectionTagStrip));
      expect(strip.tags.map((tag) => tag.label), [t.seerr.discoverNow]);
      expect(strip.tags.single.muted, isTrue);
    });

    testWidgets('and names the type and the genre once they are chosen', (tester) async {
      await pumpView(
        tester,
        shelves: [_shelf('films')],
        type: SeerrDiscoverType.movies,
        genres: const [(id: 28, name: 'Actie')],
        genreId: 28,
      );

      final strip = tester.widget<TvCatalogSelectionTagStrip>(find.byType(TvCatalogSelectionTagStrip));
      expect(strip.tags.map((tag) => tag.label), [t.seerr.kindMovie, 'Actie']);
    });

    testWidgets('in grid mode it is the expanded row, not the page (35 B)', (tester) async {
      await pumpView(
        tester,
        grid: TvSeerrGridPage(
          title: 'Populaire films',
          items: [_media(1)],
          hasMore: false,
          isLoadingMore: false,
          onLoadMore: () {},
        ),
      );

      expect(find.text('Populaire films'), findsOneWidget);
    });
  });

  testWidgets('grid mode draws a wall and no rails', (tester) async {
    await pumpView(
      tester,
      grid: TvSeerrGridPage(
        title: 'Populaire films',
        items: [for (var i = 0; i < 10; i++) _media(i, title: 'Film $i')],
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
      ),
    );

    expect(find.byType(TvCatalogCardRail), findsNothing);
    expect(find.byType(TvSeerrMediaCard), findsNWidgets(10));
  });

  testWidgets('Menu in grid mode leaves the mode, and is unbound on the shelves', (tester) async {
    var left = 0;
    await pumpView(
      tester,
      grid: TvSeerrGridPage(
        title: 'Populaire films',
        items: [_media(1)],
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
      ),
      onLeaveGrid: () => left++,
    );
    tester.widget<TvSeerrMediaCard>(find.byType(TvSeerrMediaCard)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(left, 1);

    await pumpView(tester, shelves: [_shelf('films', count: 1)]);
    tester.widget<TvSeerrMediaCard>(find.byType(TvSeerrMediaCard)).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TvCatalogCard>(find.byType(TvCatalogCard)).onBack,
      isNull,
      reason: 'on the shelves Menu belongs to the route, or Aanvragen is the one section you cannot back out of',
    );
  });

  testWidgets('LAND4: a step between shelves keeps its column, whatever the lower shelf remembers', (tester) async {
    // A rail keeps focus memory — that is what makes returning from a detail
    // page land where you left. It must not decide a vertical step: standing on
    // the third card of one shelf, the third card of the next is where DOWN
    // goes, however far right that shelf happens to be parked.
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpView(tester, shelves: [_shelf('films', count: 8), _shelf('series', count: 8)]);
    final rails = tester.stateList<TvCatalogCardRailState>(find.byType(TvCatalogCardRail)).toList();
    expect(rails, hasLength(2), reason: 'sanity: two shelves are laid out at once');

    String? focusedId() {
      final label = FocusManager.instance.primaryFocus?.debugLabel;
      final match = RegExp(r'^TvSeerrShelfCard\((.+)\)$').firstMatch(label ?? '');
      return match?.group(1);
    }

    expect(rails.last.focusColumn(6), isTrue);
    await tester.pumpAndSettle();
    expect(focusedId(), rails.last.widget.itemIds[6], reason: 'sanity: the lower shelf is parked far right');

    expect(rails.first.focusColumn(2), isTrue);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedId(), rails.last.widget.itemIds[2]);
  });

  testWidgets('an empty shelf between two others does not throw off which shelf DOWN reaches', (tester) async {
    // `_focusShelf`/`_restoreShelf` used to index `widget.shelves` — the
    // unfiltered list — while every caller (the shelf below, the "Alles tonen"
    // action above) hands over an index into the *visible* list `_buildBody`
    // actually draws. A shelf whose first page failed, or an endpoint that
    // legitimately answers with zero items, is filtered out of that visible
    // list and never mounts a `TvCatalogCardRail` at all. With one such shelf
    // between two real ones, DOWN off the first landed back on the rail it was
    // already on, or resolved a rail that was never built.
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpView(tester, shelves: [_shelf('films', count: 6), _shelf('empty', count: 0), _shelf('series', count: 6)]);

    final rails = tester.stateList<TvCatalogCardRailState>(find.byType(TvCatalogCardRail)).toList();
    expect(rails, hasLength(2), reason: 'the empty shelf draws nothing at all — sanity on the fixture');

    String? focusedId() {
      final label = FocusManager.instance.primaryFocus?.debugLabel;
      final match = RegExp(r'^TvSeerrShelfCard\((.+)\)$').firstMatch(label ?? '');
      return match?.group(1);
    }

    expect(rails.first.focusColumn(1), isTrue);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      focusedId(),
      rails.last.widget.itemIds[1],
      reason: 'DOWN must reach the Series shelf, not park on Films or land nowhere',
    );
  });

  // ---------------------------------------------------------------------------
  // SEARCH2b: this shelf viewport carries the same construction as Zoeken's
  // SEARCH2, and the same defect. See tv_search_view_test.dart's SEARCH2 group.
  // ---------------------------------------------------------------------------

  group('SEARCH2b, the shelf viewport', () {
    testWidgets('clips at its own top edge', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpView(tester, shelves: [_shelf('films', count: 12), _shelf('series', count: 12)]);

      final viewport = tester.widget<SingleChildScrollView>(
        find.descendant(of: find.byType(TvCatalogRailScaffold), matching: find.byType(SingleChildScrollView)),
      );

      // Clip.none switches clipping off on every edge, not just the two the
      // focus ring needs. The header bar and search field sit above this
      // viewport in the same Column and paint first, so a shelf scrolled past
      // the top edge paints over them.
      expect(viewport.clipBehavior, isNot(Clip.none));
    });

    testWidgets('the clip starts exactly where the search field ends, leaving no seam to scroll through', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpView(tester, shelves: [_shelf('films', count: 12), _shelf('series', count: 12)]);

      final scrollViewFinder = find.descendant(
        of: find.byType(TvCatalogRailScaffold),
        matching: find.byType(SingleChildScrollView),
      );
      final field = tester.getRect(find.byKey(const ValueKey('searchField')));
      final viewport = tester.getRect(scrollViewFinder);

      // A card's own position does not move when clipBehavior changes:
      // clipping is a paint-time effect, not a layout one. The actual
      // guarantee is structural: the viewport that owns the clip has to start
      // exactly where the search field ends, with no gap a scrolled shelf
      // could paint through.
      expect(viewport.top, field.bottom);

      // The interaction itself still has to hold up: scrolling a shelf list
      // long enough to run its first shelf clean off the top must not throw
      // or leave the tree broken.
      expect(find.byType(TvCatalogCard), findsWidgets);
      await tester.drag(scrollViewFinder, const Offset(0, -600));
      await tester.pumpAndSettle();
    });
  });

  // REQ-SEARCH-ROUTE: the field and the inbox button, wired the way
  // `SeerrDiscoverScreen._buildSearchField` wires them on TV, with a stand-in
  // for the top navigation above and the nested route's Back owner around.
  group('REQ-SEARCH-ROUTE, the search field route', () {
    late FocusNode topnav;
    late FocusNode field;
    late FocusNode inbox;
    late TextEditingController controller;
    late GlobalKey<TvSeerrDiscoverViewState> viewKey;
    late int shellBacks;
    late int requestsOpened;

    setUp(() {
      topnav = FocusNode(debugLabel: 'topnav');
      field = FocusNode(debugLabel: 'field');
      inbox = FocusNode(debugLabel: 'inbox');
      controller = TextEditingController();
      viewKey = GlobalKey<TvSeerrDiscoverViewState>();
      shellBacks = 0;
      requestsOpened = 0;
    });
    tearDown(() {
      topnav.dispose();
      field.dispose();
      inbox.dispose();
      controller.dispose();
    });

    Future<void> pumpRoute(WidgetTester tester, {bool dark = true}) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: dark),
            home: InputModeTracker(
              // The shell: it owns Back inside a nested route.
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                    shellBacks++;
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TvNestedBackOwner(
                  child: Scaffold(
                    body: Column(
                      children: [
                        FocusableButton(
                          focusNode: topnav,
                          onPressed: () {},
                          onNavigateDown: field.requestFocus,
                          child: const Text('topnav'),
                        ),
                        Expanded(
                          child: TvSeerrDiscoverView(
                            key: viewKey,
                            searchField: SeerrTvSearchRow(
                              controller: controller,
                              fieldFocusNode: field,
                              inboxFocusNode: inbox,
                              decoration: const InputDecoration(),
                              onChanged: (_) {},
                              onClear: controller.clear,
                              onFocusContent: () => viewKey.currentState?.focusFirstContent() ?? false,
                              onExitUp: topnav.requestFocus,
                              onOpenRequests: () => requestsOpened++,
                            ),
                            shelves: [_shelf('films'), _shelf('series')],
                            type: SeerrDiscoverType.all,
                            onTypeSelected: (_) {},
                            genres: const [],
                            genreId: null,
                            onGenreSelected: (_) {},
                            isLoading: false,
                            onReload: () {},
                            onActivate: (_) {},
                            onExitTop: field.requestFocus,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    bool onFirstCard(WidgetTester tester) =>
        tester.widget<TvCatalogCard>(find.byType(TvCatalogCard).first).focusNode!.hasFocus;

    testWidgets('topnav, field, first card, and back up the same way', (tester) async {
      await pumpRoute(tester);
      topnav.requestFocus();
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(field.hasFocus, isTrue, reason: 'DOWN from the top navigation lands on the field');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(onFirstCard(tester), isTrue, reason: 'DOWN from the field lands on the first card');

      // The first shelf's heading carries "Alles tonen", one stop above its
      // cards; UP from there leaves the content for the field.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrShowAll(films)');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(field.hasFocus, isTrue, reason: 'UP from the first shelf returns to the field, not the top navigation');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(topnav.hasFocus, isTrue, reason: 'only UP from the field reaches the top navigation');
    });

    // Review FIX 3 and D2: the focused field shows the white ring, and the
    // field starts on the page title's x.
    for (final dark in [true, false])
      testWidgets('the focused field carries the ring, and sits on the title x (dark: $dark)', (tester) async {
        await pumpRoute(tester, dark: dark);
        topnav.requestFocus();
        await tester.pumpAndSettle();
        Color ringColor() {
          final box = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('seerrSearchField.ring')));
          return ((box.foregroundDecoration! as ShapeDecoration).shape as FocusRingBorder).ring.color;
        }

        expect(ringColor().a, 0, reason: 'no ring while the field does not hold the focus');
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(field.hasFocus, isTrue);
        expect(ringColor(), Colors.white);

        final title = tester.getRect(find.text(t.seerr.title));
        final pill = tester.getRect(find.byKey(const ValueKey('seerrSearchField.ring')));
        expect(pill.left, closeTo(title.left, 0.5));
      });

    testWidgets('RIGHT to the inbox button, which has the same UP and DOWN, and LEFT back', (tester) async {
      await pumpRoute(tester);
      field.requestFocus();
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(inbox.hasFocus, isTrue);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(field.hasFocus, isTrue);

      inbox.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(onFirstCard(tester), isTrue);

      inbox.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(topnav.hasFocus, isTrue);

      inbox.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.select);
      expect(requestsOpened, 1);
    });

    testWidgets('Menu clears the text first, and on an empty field leaves Aanvragen', (tester) async {
      await pumpRoute(tester);
      field.requestFocus();
      controller.text = 'dune';
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.escape);
      expect(controller.text, isEmpty, reason: 'the first Menu clears the search');
      expect(shellBacks, 0);
      expect(field.hasFocus, isTrue);

      await press(tester, LogicalKeyboardKey.escape);
      expect(shellBacks, 1, reason: 'Menu on an empty field reaches the nested route, which closes Aanvragen');
      expect(topnav.hasFocus, isFalse, reason: 'and does not jump to the top navigation instead');
    });
  });
}
