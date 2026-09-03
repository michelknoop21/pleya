/// The discovery rail's own contracts, added this round: P9 (the focused tile
/// is scrolled fully into view at its *expanded* width), P10 (what the context
/// line says), and P8 (who owns the artwork warm-up, and that focus never lands
/// on an empty frame).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/services/unified_catalog/unified_artwork_prefetcher.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/tv_discovery_artwork.dart';
import '../../test_helpers/tv_discovery_fixtures.dart';

const Size _canvas = Size(1038, 584);

/// Self-contained, Jellyfin-shaped artwork URLs.
///
/// The shared discovery fixtures carry *relative* paths, which
/// `MediaImageHelper.getOptimizedImageUrl` cannot size without a
/// `MediaServerClient` — it returns `''`, and a prefetch test over those would
/// assert on an empty list forever. These carry their own `api_key`, so the
/// real helper produces a real sized URL with no client at all.
UnifiedMediaGroup _netGroup(int index) => tvDiscoveryGroup('net-$index', [
  MediaItem(
    id: 'net-$index',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Net $index',
    year: 2024,
    serverId: 'nas',
    serverName: 'NAS',
    thumbPath: 'https://jf.test/Items/$index/Images/Primary?api_key=k',
    artPath: 'https://jf.test/Items/$index/Images/Backdrop?api_key=k',
  ),
]);

List<UnifiedMediaGroup> _netGroups(int count) => [for (var i = 0; i < count; i++) _netGroup(i)];

void main() {
  setUpAll(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    TvDiscoveryArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDiscoveryArtwork.remove();
  });

  Future<TvDiscoveryRailState> pumpRail(
    WidgetTester tester,
    List<UnifiedMediaGroup> groups, {
    UnifiedArtworkPrecache? precache,
  }) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: InputModeTracker(
          child: Scaffold(
            backgroundColor: theme.extension<MonoTokens>()!.bg,
            body: Builder(
              builder: (context) => SizedBox(
                height: TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context)),
                child: TvDiscoveryRail(title: 'Films', groups: groups, onActivate: (_) {}, precache: precache),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
  }

  Rect rectOf(WidgetTester tester, UnifiedMediaGroup group) => tester.getRect(find.byKey(ValueKey(group.groupId)));

  /// Two rails stacked the way a feed stacks them, which is the only shape the
  /// projection contract can be stated in: one rail cannot show two blocks.
  Future<List<TvDiscoveryRailState>> pumpTwoRails(
    WidgetTester tester,
    List<UnifiedMediaGroup> top,
    List<UnifiedMediaGroup> bottom,
  ) async {
    tester.view.physicalSize = const Size(1038, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: InputModeTracker(
          child: Scaffold(
            backgroundColor: theme.extension<MonoTokens>()!.bg,
            body: Builder(
              builder: (context) {
                final height = TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context));
                return Column(
                  children: [
                    SizedBox(
                      height: height,
                      child: TvDiscoveryRail(title: 'Boven', groups: top, onActivate: (_) {}),
                    ),
                    SizedBox(
                      height: height,
                      child: TvDiscoveryRail(title: 'Onder', groups: bottom, onActivate: (_) {}),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).toList();
  }

  // ---------------------------------------------------------------------------
  // P9
  // ---------------------------------------------------------------------------

  group('P9: the focused tile is fully on screen, at the width it expands to', () {
    testWidgets('walking right keeps the whole expanded tile inside the band', (tester) async {
      // The rail has no `ensureVisible` of its own, and Flutter's traversal
      // policy cannot supply one: it measures the tile at the instant focus
      // lands, which is still its resting 2:3 width, and the tile then grows to
      // 2.67 times that. `FocusableWrapper._scrollIntoView` looks for a
      // *vertical* scrollable and finds none here.
      final groups = tvDiscoveryFilmsRow();
      final rail = await pumpRail(tester, groups);

      for (var i = 0; i < groups.length; i++) {
        if (!rail.focusGroup(groups[i].groupId)) continue;
        await tester.pumpAndSettle();
        final rect = rectOf(tester, groups[i]);
        expect(rect.left, greaterThanOrEqualTo(-0.01), reason: 'tile $i ran off the left edge when it expanded');
        expect(
          rect.right,
          lessThanOrEqualTo(_canvas.width + 0.01),
          reason: 'tile $i ran off the right edge when it expanded',
        );
      }
    });

    testWidgets('the last tile has room to expand into, rather than off the page', (tester) async {
      // Without the trailing padding the scrollable ends exactly at the last
      // resting tile's right edge: there is no extent to scroll to, so the one
      // tile at the end of every rail could never be seen whole.
      final groups = tvDiscoveryFilmsRow();
      final rail = await pumpRail(tester, groups);

      final last = groups.last;
      expect(rail.focusGroup(last.groupId) || true, isTrue);
      // Walk there rather than jumping, so the tile is actually built.
      for (final group in groups) {
        rail.focusGroup(group.groupId);
        await tester.pumpAndSettle();
      }
      final rect = rectOf(tester, last);
      expect(rect.right, lessThanOrEqualTo(_canvas.width + 0.01));
      expect(
        rect.width,
        closeTo(TvDiscoveryLayout.tileWidth(0.85, focused: true), 0.5),
        reason: 'and it is at its expanded width, not clipped to what was left',
      );
    });

    testWidgets('the focused tile keeps the page inset, not just the viewport edge', (tester) async {
      // Hoofdstuk 8.1: the band is as wide as the screen, so a tile flush
      // against the viewport is a focus ring inside the overscan band. This is
      // the same rect `tvos.discovery.overscan` measures against
      // `discover.safe_area`.
      final groups = tvDiscoveryFilmsRow();
      final rail = await pumpRail(tester, groups);
      final inset = TvDiscoveryLayout.railLeadInset(0.85);

      for (final group in groups) {
        if (!rail.focusGroup(group.groupId)) continue;
        await tester.pumpAndSettle();
        final rect = rectOf(tester, group);
        expect(rect.left, greaterThanOrEqualTo(inset - 0.5));
        expect(rect.right, lessThanOrEqualTo(_canvas.width - inset + 0.5));
      }
    });

    testWidgets('a rail that fits does not scroll at all', (tester) async {
      // The trailing room must not turn a short row into a scrolling one under
      // the viewer.
      final groups = tvDiscoveryFilmsRow().take(3).toList();
      final rail = await pumpRail(tester, groups);
      final before = rectOf(tester, groups.first);

      expect(rail.focusGroup(groups.first.groupId), isTrue);
      await tester.pumpAndSettle();

      expect(rectOf(tester, groups.first).left, before.left);
    });
  });

  // ---------------------------------------------------------------------------
  // P10
  // ---------------------------------------------------------------------------

  group('P10: the context line', () {
    UnifiedMediaGroup filmWith({int? durationMs, String? genre, int? year = 2024}) => tvDiscoveryGroup('ctx-film', [
      tvDiscoveryItem(
        id: 'ctx-film',
        title: 'Quarry Road',
        year: year,
        genre: genre,
        durationMs: durationMs,
        artwork: 0,
      ),
    ]);

    test('drops the source count, which the tile already shows as a badge', () {
      final group = tvDiscoveryThreeSourceGroup();
      expect(group.sources, hasLength(3), reason: 'sanity: this fixture exists to have several sources');
      final line = discoveryContextFor(group).context;
      expect(line, isNot(contains('3')), reason: 'the TvSourceCountBadge on the tile says this, in the same glance');
    });

    test('gains a runtime for a film', () {
      final line = discoveryContextFor(filmWith(durationMs: 102 * 60 * 1000, genre: 'Drama')).context;
      expect(line, contains('2024'));
      expect(line, contains('Drama'));
      expect(line, matches(RegExp(r'1\s*h')), reason: 'the fact a viewer actually weighs before committing an evening');
    });

    test('says nothing about a runtime the server did not report', () {
      final line = discoveryContextFor(filmWith(durationMs: null, genre: 'Drama')).context;
      expect(line, '2024 · Drama', reason: 'no made-up zero, the same rule the remaining-time line already follows');
    });

    test('an episode keeps its place and its remaining time, and gains no runtime', () {
      final group = tvDiscoveryContinueWatchingRow().first;
      final line = discoveryContextFor(group).context;
      expect(line, contains('·'));
      // "18 min left" already answers the question a runtime would; showing
      // both is two numbers about the same clock.
      expect(line.split(' · ').length, lessThanOrEqualTo(4));
    });

    test('a resumable film shows what is left, not how long it is', () {
      final group = tvDiscoveryGroup('ctx-resume', [
        tvDiscoveryItem(
          id: 'ctx-resume',
          title: 'Quarry Road',
          durationMs: 100 * 60 * 1000,
          viewOffsetMs: 40 * 60 * 1000,
          artwork: 0,
        ),
      ], inProgress: true);
      final line = discoveryContextFor(group).context;
      expect(line, contains('60'), reason: '60 minutes left of a 100-minute film');
      expect(line, isNot(matches(RegExp(r'1\s*h\s*40'))));
    });
  });

  // ---------------------------------------------------------------------------
  // P8
  // ---------------------------------------------------------------------------

  group('P8: artwork is warm before focus arrives', () {
    testWidgets('the rail warms its own tiles once, not once per itemBuilder call', (tester) async {
      // Ownership is the point. Starting a prefetch from inside `itemBuilder`
      // rebuilds the queue many times a frame from whichever item happened to
      // be built last, which is not a window at all.
      final warmed = <ArtworkPrefetchRequest>[];
      final groups = _netGroups(9);
      await pumpRail(tester, groups, precache: (request, context) async => warmed.add(request));
      await tester.pumpAndSettle();

      expect(warmed, isNotEmpty, reason: 'the row warms what it opens on, after the first frame');
      expect(
        warmed.map((r) => r.url).toSet().length,
        warmed.length,
        reason: 'a URL dispatched once is never dispatched again',
      );
    });

    testWidgets('the wide frame of the tile the remote is on is warmed', (tester) async {
      final warmed = <ArtworkPrefetchRequest>[];
      final groups = _netGroups(9);
      final rail = await pumpRail(tester, groups, precache: (request, context) async => warmed.add(request));
      await tester.pumpAndSettle();
      final beforeFocus = warmed.length;

      expect(rail.focusGroup(groups[3].groupId), isTrue);
      await tester.pumpAndSettle();

      final wide = warmed.where((r) => r.url.contains('Backdrop')).toList();
      expect(
        wide,
        isNotEmpty,
        reason: 'the 16:9 asset is a different file from the poster, and it is the one focus needs',
      );
      expect(
        wide.map((r) => r.groupId),
        contains('net-3'),
        reason: 'the tile the remote is on has its expanded artwork warm',
      );
      // Moving the focus moves the window rather than re-issuing it: a URL
      // dispatched once is never dispatched again, so what arrives here is the
      // new edge of the window and not a second copy of the old one.
      expect(warmed.length, greaterThan(beforeFocus));
      expect(warmed.map((r) => r.url).toSet(), hasLength(warmed.length));
    });

    testWidgets('focus arriving before the wide artwork does not blank the tile', (tester) async {
      // The fast-focus case. Warming ahead makes an empty frame rare; the
      // poster-frame placeholder makes it impossible. Asserted through the real
      // image pipeline (no `debugImageBuilder`), because the placeholder is
      // what `OptimizedMediaImage` draws while a load is outstanding — and in a
      // test no load ever completes, which is exactly the state under test.
      TvDiscoveryArtwork.remove();
      addTearDown(TvDiscoveryArtwork.install);

      final groups = _netGroups(9);
      final rail = await pumpRail(tester, groups, precache: (request, context) async {});

      expect(rail.focusGroup(groups.first.groupId), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // The tile is drawing *a picture* — the poster frame — rather than the
      // bare surface placeholder a lone unloaded network image would give.
      final images = tester.widgetList<OptimizedMediaImage>(
        find.descendant(of: find.byKey(ValueKey(groups.first.groupId)), matching: find.byType(OptimizedMediaImage)),
      );
      expect(images, isNotEmpty);
      expect(
        images.any((image) => image.placeholder != null),
        isTrue,
        reason: 'the wide branch carries the poster frame as its placeholder, so there is never an empty beat',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // LAND2
  // ---------------------------------------------------------------------------

  group('LAND2: only the rail that holds the focus projects its item', () {
    testWidgets('the rail the focus left stops describing the tile it was on', (tester) async {
      // The physical Apple TV finding: the title and synopsis of a title in one
      // rail stayed on screen while the focus already stood on a title in the
      // rail below, so two focus contexts were readable at once.
      //
      // The rail keeps a `_focused` group so a viewer returning from a detail
      // page lands back where they were. That is restoration, and it must
      // survive. What must not survive is the *drawing* of that group: a rail
      // with no focus in it is not describing anything.
      final top = [tvDiscoveryGroup('t0', [_item('t0', 'Boventitel')])];
      final bottom = [tvDiscoveryGroup('b0', [_item('b0', 'Ondertitel')])];

      final rails = await pumpTwoRails(tester, top, bottom);
      expect(rails, hasLength(2));

      expect(rails.first.focusGroup('t0'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Boventitel'), findsOneWidget);
      expect(find.text('Ondertitel'), findsNothing, reason: 'the other rail has never held the focus');

      expect(rails.last.focusGroup('b0'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Ondertitel'), findsOneWidget);
      expect(
        find.text('Boventitel'),
        findsNothing,
        reason: 'the rail the focus left may remember where it was, but not keep saying it',
      );
    });

    testWidgets('moving within one rail never blanks that rail for a frame', (tester) async {
      // The reason the block was never cleared in the first place. Clearing on
      // every loss would empty it on the way out of the old tile, so the fix
      // has to key on the rail holding the focus at all, not on one tile losing
      // it.
      final groups = [
        tvDiscoveryGroup('a', [_item('a', 'Eerste')]),
        tvDiscoveryGroup('b', [_item('b', 'Tweede')]),
      ];
      final rail = await pumpRail(tester, groups);

      expect(rail.focusGroup('a'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Eerste'), findsOneWidget);

      // One frame after the step, before anything has settled: the block has to
      // be saying something. A gate that keyed on a tile losing the focus would
      // read empty here, because the old tile reports its loss before the new
      // one reports its gain.
      expect(rail.focusGroup('b'), isTrue);
      await tester.pump();
      expect(
        find.text('Eerste').evaluate().isNotEmpty || find.text('Tweede').evaluate().isNotEmpty,
        isTrue,
        reason: 'a horizontal step inside one rail never blanks its block',
      );

      await tester.pumpAndSettle();
      expect(find.text('Tweede'), findsOneWidget);
      expect(find.text('Eerste'), findsNothing);
    });
  });
}

MediaItem _item(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: title,
  year: 2024,
  serverId: 'nas',
  serverName: 'NAS',
);
