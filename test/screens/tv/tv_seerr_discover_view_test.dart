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
}
