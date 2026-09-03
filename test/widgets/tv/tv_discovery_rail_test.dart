/// The discovery rail's own contracts, added this round: P9 (the focused tile
/// is scrolled fully into view at its *expanded* width), P10 (what the context
/// line says), and P8 (who owns the artwork warm-up, and that focus never lands
/// on an empty frame).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:pleya/widgets/tv/tv_rail_stack.dart';
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

  /// The same stack, wired the way every production surface wires it: one
  /// [TvRailStack] owning UP and DOWN between the rails.
  ///
  /// The wiring is the thing under test, so the harness has to carry it. A
  /// stack of bare rails is what the *old* implementation was — rails with no
  /// vertical handler at all, leaving the step to Flutter's geometry — which is
  /// what `pumpTwoRails` still builds, and what the negative control below
  /// contrasts against.
  Future<List<TvDiscoveryRailState>> pumpRailStack(WidgetTester tester, List<List<UnifiedMediaGroup>> rows) async {
    tester.view.physicalSize = const Size(1038, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final stack = TvRailStack();
    stack.layOut([for (var i = 0; i < rows.length; i++) 'row$i']);

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
                // A `ListView` and not a `Column`, for the same reason the
                // production surfaces use one: three rails are taller than a
                // TV screen, and the page has to scroll rather than overflow.
                return ListView(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      SizedBox(
                        height: height,
                        child: TvDiscoveryRail(
                          key: stack.keyFor('row$i'),
                          title: 'Rij $i',
                          groups: rows[i],
                          onActivate: (_) {},
                          onNavigateUp: stack.up(i),
                          onNavigateDown: stack.down(i),
                        ),
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

  /// What the remote is standing on, by the debug label
  /// `TvDiscoveryRailState._nodeFor` gives every tile.
  String? focusedTile() {
    final label = FocusManager.instance.primaryFocus?.debugLabel;
    const prefix = 'tvDiscoveryTile_';
    return label != null && label.startsWith(prefix) ? label.substring(prefix.length) : null;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
  }

  List<UnifiedMediaGroup> row(String prefix, int count) => [
    for (var i = 0; i < count; i++) tvDiscoveryGroup('$prefix$i', [_item('$prefix$i', '$prefix$i')]),
  ];

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
      final top = [
        tvDiscoveryGroup('t0', [_item('t0', 'Boventitel')]),
      ];
      final bottom = [
        tvDiscoveryGroup('b0', [_item('b0', 'Ondertitel')]),
      ];

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

  // ---------------------------------------------------------------------------
  // LAND4
  // ---------------------------------------------------------------------------

  group('LAND4: a vertical step arrives at the column it left from', () {
    testWidgets('DOWN out of a scrolled rail lands under the tile it left', (tester) async {
      // The finding: the stack has to read as one plane. Standing on the sixth
      // tile of a rail and pressing DOWN puts you on the sixth tile of the rail
      // below, not on whatever the geometry underneath happened to be.
      final rails = await pumpRailStack(tester, [row('t', 12), row('b', 12)]);
      expect(rails, hasLength(2));

      rails.first.focusGroup('t0');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 5);
      expect(focusedTile(), 't5');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedTile(), 'b5');
    });

    testWidgets('and UP comes back to the same column', (tester) async {
      // The round trip is the half that made the old behaviour feel haunted:
      // walking down and straight back up arrived one tile further along than
      // it started, because each step was decided by two independently
      // scrolled bands.
      final rails = await pumpRailStack(tester, [row('t', 12), row('b', 12)]);

      rails.first.focusGroup('t0');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 5);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedTile(), 't5');
    });

    testWidgets('the target rail may remember where it was left, but it does not decide', (tester) async {
      // The scherpe punt of the contract, and the negative control for it.
      // A rail's scroll offset *is* its focus memory, so leaving the step to
      // geometry lets memory decide traversal: this rail was walked to its
      // tenth tile and is still parked there.
      final rails = await pumpRailStack(tester, [row('t', 12), row('b', 12)]);

      rails.last.focusGroup('b0');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 9);
      expect(focusedTile(), 'b9', reason: 'sanity: the lower rail is parked far to the right');

      rails.first.focusGroup('t2');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedTile(), 'b2', reason: 'the column the step left from, not the tile the rail remembers');
    });

    testWidgets('a shorter rail clamps on its last tile rather than declining the step', (tester) async {
      final rails = await pumpRailStack(tester, [row('t', 8), row('b', 4)]);

      rails.first.focusGroup('t0');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 6);
      expect(focusedTile(), 't6');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedTile(), 'b3', reason: 'seven items with the focus on the seventh, into a rail of four');
    });

    testWidgets('an empty rail is stepped over, a filled one never is', (tester) async {
      final rails = await pumpRailStack(tester, [row('t', 6), const <UnifiedMediaGroup>[], row('b', 6)]);

      rails.first.focusGroup('t3');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedTile(), 'b3', reason: 'the empty rail has nothing to stand on, so the step carries past it');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedTile(), 't3', reason: 'and back over it the same way');
    });

    testWidgets('the tile the step arrives on is fully in view at its expanded width', (tester) async {
      // A correct focus node is not enough (the LAND3 half of this item): the
      // rail it landed in has to have moved its own band, or the viewer is
      // looking at a focus ring off the edge of the screen.
      final rails = await pumpRailStack(tester, [row('t', 14), row('b', 14)]);
      final inset = TvDiscoveryLayout.railLeadInset(
        TvLayoutConstants.scaleOf(tester.element(find.byType(TvDiscoveryRail).first)),
      );

      rails.first.focusGroup('t0');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 9);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedTile(), 'b9');

      final rect = tester.getRect(find.byKey(const ValueKey('b9')));
      expect(rect.left, greaterThanOrEqualTo(inset - 0.5));
      expect(rect.right, lessThanOrEqualTo(1038 - inset + 0.5));
      expect(
        rect.width,
        closeTo(
          TvDiscoveryLayout.tileWidth(
            TvLayoutConstants.scaleOf(tester.element(find.byType(TvDiscoveryRail).first)),
            focused: true,
          ),
          0.5,
        ),
        reason: 'at the width it expands to, not the portrait width it landed at',
      );
    });

    testWidgets('a column outside the built window is reached, not approximated', (tester) async {
      // Virtualisation is why geometry cannot be repaired in place: the tiles
      // near the target column are not in the tree at all while the band is
      // parked elsewhere, so nothing on screen can be picked to stand for them.
      final rails = await pumpRailStack(tester, [row('t', 30), row('b', 30)]);

      rails.last.focusGroup('b0');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 25);
      expect(focusedTile(), 'b25');
      expect(find.byKey(const ValueKey('b1')), findsNothing, reason: 'sanity: the target column is not built');

      rails.first.focusGroup('t1');
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedTile(), 'b1');
    });

    testWidgets('leaving the stack is still Flutter\'s job', (tester) async {
      // The edges are deliberately not owned here: above the first rail is a
      // page header, a hero or a search field, and below the last rail of TV
      // Search is a vertical result list. A rail at the edge gets no handler,
      // so the key falls through to the traversal that reaches those.
      final stack = TvRailStack();
      stack.layOut(['row0', 'row1']);
      expect(stack.up(0), isNull);
      expect(stack.down(1), isNull);
      expect(stack.up(1), isNotNull);
      expect(stack.down(0), isNotNull);
      // Unless the caller names a target for that edge, which is how the
      // landing gets back to its header and Home gets back to its hero.
      expect(stack.up(0, whenExhausted: () {}), isNotNull);
    });

    testWidgets('every rail on a page lays its tiles on one grid', (tester) async {
      // The invariant that makes "column" and "index" the same word here.
      // `TvDiscoveryLayout.railPitch` is a function of the page scale alone, so
      // tile n of one rail sits exactly above tile n of the next. Should a rail
      // ever get its own tile width, `focusColumn` is the one place that has to
      // start comparing centres instead of indices.
      await pumpRailStack(tester, [row('t', 6), row('b', 6)]);

      var compared = 0;
      for (var i = 0; i < 6; i++) {
        final top = find.byKey(ValueKey('t$i'));
        final bottom = find.byKey(ValueKey('b$i'));
        // Only the tiles both bands actually built: past the right edge the
        // rails are virtualised, and a tile that does not exist has no column.
        if (top.evaluate().isEmpty || bottom.evaluate().isEmpty) continue;
        compared++;
        expect(
          tester.getRect(top).left,
          closeTo(tester.getRect(bottom).left, 0.01),
          reason: 'tile $i of the two rails must share a column',
        );
      }
      expect(compared, greaterThanOrEqualTo(4), reason: 'sanity: the assertion above actually ran');
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
