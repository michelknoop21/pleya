/// The grid's own contracts: how a focus move drives the artwork warm-up
/// (hoofdstuk 10.2 and DEC-039's viewport-plus-margin rule).
///
/// The prefetcher's *policy* — margins, ordering, de-duplication, bounding — is
/// proven in `test/services/unified_catalog/unified_artwork_prefetcher_test.dart`
/// without a widget tree at all. What can only be proven here is the wiring:
/// that the grid actually calls it, that it calls it with the row the user is
/// standing in, and that it never asks for the whole catalog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';

import '../../test_helpers/golden.dart';

/// A self-contained artwork URL, so `getOptimizedImageUrl` needs no client to
/// size it and the fixtures stay honest about where the URLs come from.
UnifiedMediaGroup _group(int index) {
  final item = MediaItem(
    id: 'i$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Title $index',
    thumbPath: 'https://jf.test/Items/$index/Images/Primary?api_key=secret',
    serverId: 'nas',
    serverName: 'NAS',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'g$index',
    identity: CanonicalMediaIdentity.movie(title: 'Title $index', year: 2010),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// Records what the grid asked to warm, instead of hitting the network.
  final warmed = <String>[];

  Future<void> pumpGrid(
    WidgetTester tester, {
    required int count,
    Size? surfaceSize,
    bool hasMore = false,
    bool isLoadingMore = false,
    VoidCallback? onLoadMore,
  }) async {
    warmed.clear();
    if (surfaceSize != null) setGoldenSurfaceSize(tester, size: surfaceSize);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvUnifiedMediaGrid(
                groups: [for (var i = 0; i < count; i++) _group(i)],
                onActivate: (_) {},
                hasMore: hasMore,
                isLoadingMore: isLoadingMore,
                onLoadMore: onLoadMore ?? () {},
                precache: (request, context) async => warmed.add(request.groupId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The column count the grid actually resolved, so a test can name a row
  /// rather than guess an index — five to seven depending on the surface.
  int columnsOf(WidgetTester tester) =>
      TvCatalogGrid.forWidth(tester.view.physicalSize.width / tester.view.devicePixelRatio, scale: 1.0).columns;

  testWidgets('nothing is warmed until the user is somewhere', (tester) async {
    await pumpGrid(tester, count: 40);
    expect(warmed, isEmpty, reason: 'a grid nobody has entered has no viewport to warm around');
  });

  testWidgets('focusing a card warms that card and its neighbourhood', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();

    expect(warmed, isNotEmpty);
    expect(warmed, contains('g0'), reason: 'the focused card first of all');
    // The prefetcher's own margin, not the whole catalog: hoofdstuk 39's
    // "viewport + kleine marge", and the reason a grid of forty titles must not
    // turn into forty image requests the moment focus lands.
    expect(warmed.length, lessThan(40));
  });

  testWidgets('moving deeper into the grid warms around the new row, not the old one', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    final afterFirst = {...warmed};

    Focus.of(tester.element(find.text('Title 30'))).requestFocus();
    await tester.pumpAndSettle();

    expect(warmed, contains('g30'));
    expect(
      warmed.toSet().difference(afterFirst),
      isNotEmpty,
      reason: 'a move to the far end of the catalog must warm something new',
    );
  });

  testWidgets('walking back over warmed cards asks for nothing twice', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Title 1'))).requestFocus();
    await tester.pumpAndSettle();

    expect(warmed.length, warmed.toSet().length, reason: 'no poster is fetched twice');
  });

  testWidgets('a grid leaving the tree mid-warm neither throws nor keeps working', (tester) async {
    await pumpGrid(tester, count: 40);
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    final before = warmed.length;

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(warmed.length, before);
    expect(tester.takeException(), isNull);
  });

  // Hoofdstuk 10.2b: focus on the complete catalogus is "ruimtelijk stabiel".
  // The grid is a Column of `Row`s, and a `Row` is as tall as its tallest
  // child — so any part of the card that grows on focus grows the whole row and
  // pushes every row under it down, while the user is looking at it. That makes
  // this a property of the grid, not of the card: the only place it is visible
  // is with neighbours present.
  testWidgets('focus moves nothing but the focused card', (tester) async {
    await pumpGrid(tester, count: 40);
    // Every card except the one about to take focus. That one is excluded on
    // purpose: `FocusableWrapper` scales it, and a scale transform moves the
    // text it paints without moving anything in the layout.
    final before = {for (var i = 1; i < 40; i++) i: tester.getTopLeft(find.text('Title $i'))};

    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();

    final after = {for (var i = 1; i < 40; i++) i: tester.getTopLeft(find.text('Title $i'))};
    expect(after, before, reason: 'a card that grows on focus lifts its whole row and shifts the rows beneath it');
  });

  // Pleya ships sixteen locales and not one of them is right-to-left (see
  // `AppLocale` in `strings.g.dart`: en, bg, da, de, es, fr, it, ja, ko, nb,
  // nl, pl, pt, ru, sv, zh). So there is no RTL *acceptance render* to make —
  // it would picture a state no user can reach — and claiming one would be
  // claiming coverage that does not exist.
  //
  // What is worth having is this: the grid resolves its own columns, gutters
  // and insets from the viewport and wires LEFT and RIGHT by hand, so it is
  // exactly the kind of widget that throws or mirrors badly the first time a
  // right-to-left locale is added. One assertion now is much cheaper than
  // finding out during that translation.
  testWidgets('builds under a right-to-left directionality without breaking', (tester) async {
    warmed.clear();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          // Directionality straight from the widget tree rather than from a
          // locale plus `GlobalMaterialLocalizations`: what this test asserts
          // is that the grid survives RTL, and imposing the direction directly
          // states that without pulling `flutter_localizations` — an
          // undeclared, transitive-only package here — into a test dependency.
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: InputModeTracker(
              child: Scaffold(
                body: TvUnifiedMediaGrid(
                  groups: [for (var i = 0; i < 12; i++) _group(i)],
                  onActivate: (_) {},
                  hasMore: false,
                  isLoadingMore: false,
                  onLoadMore: () {},
                  precache: (request, context) async => warmed.add(request.groupId),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(find.text('Title 0'))), TextDirection.rtl);
    // The same twelve cards, laid out on the same grid: the column count comes
    // from the viewport width, which has no handedness.
    expect(find.text('Title 11'), findsOneWidget);

    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    expect(warmed, contains('g0'));
  });

  // The seam itself: production passes nothing, and the grid must then still
  // build and warm through the real `precacheImage` path without complaint.
  testWidgets('the default prefetcher is used when no seam is injected', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvUnifiedMediaGrid(
                groups: [for (var i = 0; i < 8; i++) _group(i)],
                onActivate: (_) {},
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // P11: the next page is asked for before the viewer reaches the end
  // ---------------------------------------------------------------------------

  group('P11: paging', () {
    testWidgets('the focus crossing into the last rows asks for the next page', (tester) async {
      // The old trigger was DOWN on the last row and nothing else: no scroll
      // listener, no threshold, no background prefetch. The viewer had to
      // navigate into the end of what was loaded and *then* wait, on every
      // page — which is the stall that was reported.
      var loads = 0;
      await pumpGrid(tester, count: 40, hasMore: true, onLoadMore: () => loads++);
      final columns = columnsOf(tester);

      Focus.of(tester.element(find.text('Title 0'))).requestFocus();
      await tester.pumpAndSettle();
      expect(loads, 0, reason: 'the top of the grid is nowhere near the end');

      // Two rows short of the end, which is the threshold.
      final rows = (40 / columns).ceil();
      final target = (rows - TvUnifiedMediaGridState.loadMoreRowThreshold) * columns;
      Focus.of(tester.element(find.text('Title $target'))).requestFocus();
      await tester.pumpAndSettle();
      expect(loads, greaterThan(0), reason: 'the page is requested while there is still a row to walk');
    });

    testWidgets('and it does so without moving the focus', (tester) async {
      // Hoofdstuk 28 forbids a reflow, and moving focus to a card that does not
      // exist yet is the reset this whole widget is built to avoid.
      var loads = 0;
      await pumpGrid(tester, count: 40, hasMore: true, onLoadMore: () => loads++);
      final columns = columnsOf(tester);
      final rows = (40 / columns).ceil();
      final target = (rows - 1) * columns;

      Focus.of(tester.element(find.text('Title $target'))).requestFocus();
      await tester.pumpAndSettle();

      expect(loads, greaterThan(0));
      expect(Focus.of(tester.element(find.text('Title $target'))).hasFocus, isTrue);
    });

    testWidgets('a load already in flight is not asked for again', (tester) async {
      var loads = 0;
      await pumpGrid(tester, count: 40, hasMore: true, isLoadingMore: true, onLoadMore: () => loads++);
      final columns = columnsOf(tester);
      final rows = (40 / columns).ceil();

      Focus.of(tester.element(find.text('Title ${(rows - 1) * columns}'))).requestFocus();
      await tester.pumpAndSettle();

      expect(loads, 0, reason: 'the duplicate-request guard a layer down should never have to earn its keep here');
    });

    testWidgets('the end of a complete library asks for nothing at all', (tester) async {
      var loads = 0;
      await pumpGrid(tester, count: 40, onLoadMore: () => loads++);
      final columns = columnsOf(tester);
      final rows = (40 / columns).ceil();

      Focus.of(tester.element(find.text('Title ${(rows - 1) * columns}'))).requestFocus();
      await tester.pumpAndSettle();

      expect(loads, 0, reason: '`hasMore` false means there is no page to fetch, whatever the focus does');
    });
  });

  group('I18: a focused card that disappears (hoofdstuk 7.6)', () {
    Widget gridOf(List<int> indexes, {VoidCallback? onExitTop}) => TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Scaffold(
            body: TvUnifiedMediaGrid(
              groups: [for (final i in indexes) _group(i)],
              onActivate: (_) {},
              hasMore: false,
              isLoadingMore: false,
              onLoadMore: () {},
              onExitTop: onExitTop,
            ),
          ),
        ),
      ),
    );

    testWidgets('focus moves to the next surviving neighbour, not nowhere', (tester) async {
      await tester.pumpWidget(gridOf([0, 1, 2, 3]));
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Title 1'))).requestFocus();
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('Title 1'))).hasPrimaryFocus, isTrue);

      // A filter/removal drops card 1 out from under the focus.
      await tester.pumpWidget(gridOf([0, 2, 3]));
      await tester.pumpAndSettle();

      expect(find.text('Title 1'), findsNothing, reason: 'the card is really gone');
      expect(
        Focus.of(tester.element(find.text('Title 2'))).hasPrimaryFocus,
        isTrue,
        reason: 'the card that was next after the removed one, forward-first per _nearestSurvivor',
      );
    });

    testWidgets('focus moves to the nearest remaining neighbour when the forward side is also gone', (tester) async {
      await tester.pumpWidget(gridOf([0, 1, 2, 3]));
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Title 2'))).requestFocus();
      await tester.pumpAndSettle();

      // Everything after the focused card is gone too — only a card before it survives.
      await tester.pumpWidget(gridOf([0, 1]));
      await tester.pumpAndSettle();

      expect(
        Focus.of(tester.element(find.text('Title 1'))).hasPrimaryFocus,
        isTrue,
        reason: 'nothing forward survived, so the nearest neighbour behind it gets the focus',
      );
    });

    testWidgets('nothing survives the change: focus goes back up to the controls, not into the void', (tester) async {
      var exitedTop = 0;
      await tester.pumpWidget(gridOf([0, 1], onExitTop: () => exitedTop++));
      await tester.pumpAndSettle();
      Focus.of(tester.element(find.text('Title 0'))).requestFocus();
      await tester.pumpAndSettle();

      // A filter change that empties the grid entirely.
      await tester.pumpWidget(gridOf(const [], onExitTop: () => exitedTop++));
      await tester.pumpAndSettle();

      expect(exitedTop, 1, reason: 'nothing left to focus, so control goes back to whatever can still act');
    });
  });

  testWidgets('J3: the grid renders and focuses without overflow at the lowest supported TV surface', (tester) async {
    // 918 logical px is TvLayoutConstants.scaleForHeight's own floor (0.85x
    // of the 1080p canvas) — nothing on a real TV output scales the UI
    // smaller than this. 1280 wide keeps a plausible (720p-ish) aspect
    // rather than testing an unrealistically narrow sliver at that height.
    await pumpGrid(tester, count: 24, surfaceSize: const Size(1280, 918));

    expect(tester.takeException(), isNull, reason: 'the grid itself must lay out cleanly at the floor scale');

    Focus.of(tester.element(find.text('Title 0'))).requestFocus();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'focusing (which widens a card) must not overflow at the floor');
  });

  // ---------------------------------------------------------------------------
  // CAT1: the top row's focus ring against the top of the scroll viewport
  // ---------------------------------------------------------------------------

  /// The rect the white focus ring is drawn on, in the state it is in now.
  ///
  /// The card's outer `SizedBox` is *above* `FocusableWrapper`'s
  /// `Transform.scale`, so `getRect` on the card reports the resting box whether
  /// or not it holds the focus, which is exactly how the clipping this group
  /// guards went unnoticed. The ring lives on the poster block inside the
  /// transform, and its top edge is the top edge of the whole scaled card.
  Rect ringOf(WidgetTester tester, String title) {
    final card = find.ancestor(of: find.text(title), matching: find.byType(TvUnifiedMediaCard));
    return tester.getRect(find.descendant(of: card, matching: find.byType(AnimatedContainer)).first);
  }

  Rect viewportOf(WidgetTester tester) => tester.getRect(
    find.descendant(of: find.byType(TvUnifiedMediaGrid), matching: find.byType(SingleChildScrollView)),
  );

  Future<void> focusCard(WidgetTester tester, String title) async {
    Focus.of(tester.element(find.text(title))).requestFocus();
    await tester.pumpAndSettle();
  }

  group('CAT1', () {
    // The canonical canvas of DEC-028, so the numbers in the masterlist entry
    // and the numbers here are the same numbers.
    const canvas = Size(1038, 584);

    testWidgets('a focused card in the top row keeps its whole ring inside the viewport', (tester) async {
      await pumpGrid(tester, count: 40, surfaceSize: canvas);
      final columns = columnsOf(tester);

      // First, middle and last column of row one. The row shares one top edge,
      // but a fix that only lands on the column the grid happens to focus first
      // would pass a test that only asks about card zero.
      for (final column in {0, columns ~/ 2, columns - 1}) {
        await focusCard(tester, 'Title $column');
        final ring = ringOf(tester, 'Title $column');
        final viewport = viewportOf(tester);
        expect(
          ring.top,
          greaterThanOrEqualTo(viewport.top),
          reason:
              'column $column: the ring is drawn at ${ring.top}, the viewport clips at '
              '${viewport.top}, so ${viewport.top - ring.top} logical pixels of ring, corners '
              'included, are cut off flat against the header',
        );
      }
    });

    testWidgets('it holds however the remote arrived at the top row', (tester) async {
      await pumpGrid(tester, count: 40, surfaceSize: canvas);
      final columns = columnsOf(tester);
      final viewport = viewportOf(tester);

      // Vertical arrival: down into row two and back up. LAND3 is the standing
      // reminder that a reveal computed while something else is expanded can be
      // right on the way there and wrong on the way back.
      await focusCard(tester, 'Title $columns');
      await focusCard(tester, 'Title 0');
      expect(ringOf(tester, 'Title 0').top, greaterThanOrEqualTo(viewport.top), reason: 'after arriving from below');

      // Horizontal arrival: along row one, which is the path that leaves a
      // neighbour expanded while the next card grows.
      await focusCard(tester, 'Title 1');
      expect(ringOf(tester, 'Title 1').top, greaterThanOrEqualTo(viewport.top), reason: 'after a step sideways');
    });

    testWidgets('and at the scale floor, where the card is a different shape', (tester) async {
      // The same surface J3 uses: TvLayoutConstants' own floor, and a card
      // proportioned differently from the canonical one.
      await pumpGrid(tester, count: 40, surfaceSize: const Size(1280, 918));
      await focusCard(tester, 'Title 0');
      expect(ringOf(tester, 'Title 0').top, greaterThanOrEqualTo(viewportOf(tester).top));
    });

    testWidgets('the computed card height bounds the height the card lays out', (tester) async {
      // What keeps [TvCatalogLayout.cardHeight] and the card from drifting.
      // Bounds rather than equals: the engine rounds the meta line's font
      // metrics up, and the token arithmetic rounds with it. See there.
      for (final size in const [Size(1038, 584), Size(1280, 918), Size(1920, 1080)]) {
        await pumpGrid(tester, count: 12, surfaceSize: size);
        final context = tester.element(find.byType(TvUnifiedMediaGrid));
        final scale = TvLayoutConstants.scaleOf(context);
        final grid = TvCatalogGrid.forWidth(size.width, scale: scale);
        final rendered = tester.getRect(find.byType(TvUnifiedMediaCard).first).height;
        final computed = TvCatalogLayout.cardHeight(grid.cardWidth, scale);
        expect(computed, greaterThanOrEqualTo(rendered), reason: 'at $size the reservation must not be short');
        expect(computed - rendered, lessThan(1.5), reason: 'at $size it must not be padding either');
      }
    });
  });
}
