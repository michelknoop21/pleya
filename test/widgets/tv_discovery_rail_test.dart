import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_section_header.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/tv_discovery_fixtures.dart';

/// Behaviour contracts of the fase-6 discovery rail — the ones the goldens
/// cannot see (hoofdstuk 19, 20, 21, 26, 35, 37, 44 of the fase-6 brief and
/// hoofdstuk 10.2a/25 of docs/tvos-unified-experience.md).
///
/// Deliberately separate from `test/goldens/tv_discovery_golden_test.dart`: a
/// picture proves the composition, and none of what is below is visible in one.
/// What is announced, what is remembered, what is *not* activated, and whether a
/// number moves when it must not — those are assertions.

Widget _shell(Widget child, {bool disableAnimations = false}) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: kTvGoldenSurfaceSize, disableAnimations: disableAnimations),
        child: InputModeTracker(
          child: Scaffold(backgroundColor: theme.extension<MonoTokens>()!.bg, body: child),
        ),
      ),
    ),
  );
}

Widget _rail({
  required List<UnifiedMediaGroup> groups,
  ValueChanged<UnifiedMediaGroup>? onActivate,
  String? initialFocusedGroupId,
  ValueChanged<String>? onFocusedGroupChanged,
  bool isPartial = false,
  Key? key,
}) => Builder(
  builder: (context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return SizedBox(
      height: TvDiscoveryLayout.railSectionHeight(scale),
      child: TvDiscoveryRail(
        key: key,
        title: t.discover.recentlyAdded,
        groups: groups,
        isPartial: isPartial,
        initialFocusedGroupId: initialFocusedGroupId,
        onFocusedGroupChanged: onFocusedGroupChanged,
        onActivate: onActivate ?? (_) {},
      ),
    );
  },
);

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  TvDiscoveryRailState railOf(WidgetTester tester) => tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));

  group('metadata is focus-driven', () {
    // Hoofdstuk 26: an unfocused tile is artwork. The context that belongs to
    // the focused item is drawn once, under the rail — never as a caption on
    // every tile, which is the database-listing impression the phase is against.
    testWidgets('the context block describes the focused tile, and only it', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      await tester.pumpWidget(_shell(_rail(groups: films)));
      await tester.pumpAndSettle();

      final first = discoveryContextFor(films.first);
      final third = discoveryContextFor(films[2]);
      expect(first.title, isNot(third.title));

      // A rail nobody is standing in describes nothing (LAND2, `2371c62`). This
      // file asserted the opposite until then — "before any press the rail
      // describes its first tile" — because every rail drew its own block and a
      // stacked feed showed one caption per rail at once. `alwaysDescribesCurrent`
      // is the opt-out, and TV Search is the surface that takes it.
      expect(find.text(first.title), findsNothing);

      railOf(tester).focusCurrent();
      await tester.pumpAndSettle();
      expect(find.text(first.title), findsOneWidget);
      expect(find.text(third.title), findsNothing);

      railOf(tester).focusGroup(films[2].groupId);
      await tester.pumpAndSettle();

      expect(find.text(third.title), findsOneWidget);
      expect(find.text(first.title), findsNothing);
    });

    // A move off the rail empties the block but not the memory. LAND2 took the
    // caption away from a rail the remote has left; what it did not touch is
    // *where* that rail resumes, which is the tile the viewer walked off, never
    // the first one. The two used to be asserted through the same widget, so
    // this test read as "the block survives" and could not tell them apart.
    testWidgets('losing focus empties the block but not the tile it remembers', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      final outside = FocusNode(debugLabel: 'outside');
      addTearDown(outside.dispose);
      await tester.pumpWidget(
        _shell(
          Column(
            children: [
              Focus(focusNode: outside, child: const SizedBox(height: 20)),
              _rail(groups: films),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      railOf(tester).focusGroup(films[1].groupId);
      await tester.pumpAndSettle();
      expect(find.text(discoveryContextFor(films[1]).title), findsOneWidget);

      outside.requestFocus();
      await tester.pumpAndSettle();
      expect(find.text(discoveryContextFor(films[1]).title), findsNothing);

      // And back. `focusCurrent` is what a vertical step into this rail calls,
      // so this is the return trip, not a second way of naming a tile.
      expect(railOf(tester).focusCurrent(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(discoveryContextFor(films[1]).title), findsOneWidget);
      expect(find.text(discoveryContextFor(films.first).title), findsNothing);
    });

    // Hoofdstuk 15: episode context only when the data is really there.
    test('an episode announces where it is and how much is left; a film does not', () {
      final cw = tvDiscoveryContinueWatchingRow();
      final episode = cw.firstWhere((g) => g.groupId == 'disc-cw-harbourlight');
      final context = discoveryContextFor(episode);
      expect(context.title, 'Harbourlight', reason: 'a resumed episode is announced under its show');
      expect(context.context, contains('S2 E4'));
      expect(context.context, contains(t.discover.minutesLeft(minutes: 18)));

      final film = discoveryContextFor(tvDiscoveryFilmsRow().first);
      expect(film.context, isNot(contains('S')), reason: 'a film has no season to be in');
    });

    // A row on a server that reported no runtime gets no remaining-time line
    // rather than a made-up one.
    test('no runtime means no remaining-time claim', () {
      final group = tvDiscoveryGroup('t-noruntime', [
        tvDiscoveryItem(id: 'x', title: 'No Runtime', durationMs: null, viewOffsetMs: 90000, artwork: 0),
      ], inProgress: true);
      expect(discoveryContextFor(group).context, isNot(contains('min')));
    });
  });

  group('focus identity and restoration', () {
    // Hoofdstuk 37: focus identity is the group id, never a list index. A late
    // server lengthening the row must not move the focus to another title.
    testWidgets('restores the named tile, not the one at its old index', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      await tester.pumpWidget(_shell(_rail(groups: films, initialFocusedGroupId: films[2].groupId)));
      await tester.pumpAndSettle();

      // The block is the probe for "which tile is current", and since LAND2 it
      // is drawn only while the rail holds the focus — so the rail is given the
      // focus before it is read, exactly as a vertical step into it would.
      expect(railOf(tester).focusCurrent(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(discoveryContextFor(films[2]).title), findsOneWidget);

      // Now a late source lands and pushes two groups in front of it.
      final lengthened = [tvDiscoveryThreeSourceGroup(), tvDiscoveryLongTitleGroup(), ...films];
      await tester.pumpWidget(_shell(_rail(groups: lengthened, initialFocusedGroupId: films[2].groupId)));
      await tester.pumpAndSettle();

      expect(
        find.text(discoveryContextFor(films[2]).title),
        findsOneWidget,
        reason: 'the rail followed the index instead of the group id',
      );
    });

    testWidgets('falls back to the first tile when the remembered one is gone', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      await tester.pumpWidget(_shell(_rail(groups: films, initialFocusedGroupId: 'a-title-that-was-removed')));
      await tester.pumpAndSettle();
      expect(railOf(tester).focusCurrent(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(discoveryContextFor(films.first).title), findsOneWidget);
    });

    testWidgets('reports each focused group so a landing can remember it', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      final seen = <String>[];
      await tester.pumpWidget(_shell(_rail(groups: films, onFocusedGroupChanged: seen.add)));
      await tester.pumpAndSettle();

      railOf(tester).focusGroup(films[1].groupId);
      await tester.pumpAndSettle();
      railOf(tester).focusGroup(films[3].groupId);
      await tester.pumpAndSettle();

      expect(seen, [films[1].groupId, films[3].groupId]);
    });

    // Virtualization is honest about its limits: a tile far outside the viewport
    // has no focus node yet, and the rail says so instead of focusing whatever
    // happens to be nearest — which would restore the user to a title they
    // never chose.
    testWidgets('refuses to focus a group it has not built', (tester) async {
      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(_shell(_rail(groups: tvDiscoveryFilmsRow())));
      await tester.pumpAndSettle();
      expect(railOf(tester).focusGroup('not-in-this-rail'), isFalse);
    });
  });

  group('activation', () {
    // Hoofdstuk 27: a tile reports a press and nothing else. Walking the rail
    // must never activate, and one press must produce exactly one activation of
    // the group — not of a concrete source.
    testWidgets('walking activates nothing; one press activates one group', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      final activated = <UnifiedMediaGroup>[];
      await tester.pumpWidget(_shell(_rail(groups: films, onActivate: activated.add)));
      await tester.pumpAndSettle();

      final rail = railOf(tester);
      for (final group in films.take(5)) {
        rail.focusGroup(group.groupId);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(activated, isEmpty);

      // The real remote path: Select on the focused tile.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(activated.map((g) => g.groupId), [films[4].groupId]);
    });
  });

  group('accessibility', () {
    // Hoofdstuk 25/44: VoiceOver has to be able to say what this is and where
    // in the row it sits. Position is part of it because a rail has no visible
    // scrollbar to infer it from.
    testWidgets('every tile announces its title and its position in the rail', (tester) async {
      setGoldenSurfaceSize(tester);
      final handle = tester.ensureSemantics();
      final films = tvDiscoveryFilmsRow();
      await tester.pumpWidget(_shell(_rail(groups: films)));
      await tester.pumpAndSettle();

      final first = films.first.representativeSource.item;
      expect(
        find.bySemanticsLabel(
          RegExp(
            '${RegExp.escape(first.displayTitle)}.*'
            '${RegExp.escape(t.unifiedCatalog.discovery.semantics.position(position: 1, count: films.length))}',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    // Hoofdstuk 41: a rail that lost a source still shows what it has, and says
    // so once in its heading rather than over the page.
    testWidgets('a partial rail says so in its heading and keeps its content', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_shell(_rail(groups: films, isPartial: true)));
      await tester.pumpAndSettle();

      // Visually the partial state is only the glyph — a written sentence in
      // every affected heading competed with the row title (hoofdstuk 41 asks
      // for subtle). The full wording still has to reach assistive tech.
      expect(find.text(t.unifiedCatalog.discovery.partial), findsNothing);

      // Read off the heading's own node rather than through
      // `find.bySemanticsLabel`. The glyph's `Semantics` has no container of
      // its own, so its wording merges into the heading and the node reads
      // "Recently Added\nSome sources did not answer" — which is precisely
      // hoofdstuk 41's "says so once in its heading", and precisely what an
      // exact-string finder cannot see. The finder was the wrong instrument,
      // not the widget: it matched nothing whatever the widget did, so this
      // assertion never had a failing state to be a test of.
      final heading = tester.getSemantics(find.byType(TvSectionHeader));
      expect(heading.label, contains(t.discover.recentlyAdded));
      expect(heading.label, contains(t.unifiedCatalog.discovery.partial));

      expect(find.byKey(ValueKey(films.first.groupId)), findsOneWidget);
      handle.dispose();
    });
  });

  group('geometry', () {
    // Hoofdstuk 20, as arithmetic: the section is exactly as tall as the layout
    // says, whatever focus is doing. The fase-5 grid already proved what a
    // focus-dependent row height costs.
    testWidgets('the section height never depends on where focus is', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      await tester.pumpWidget(_shell(_rail(groups: films)));
      await tester.pumpAndSettle();

      final scale = TvLayoutConstants.scaleForSize(kTvGoldenSurfaceSize);
      final expected = TvDiscoveryLayout.railSectionHeight(scale);
      expect(tester.getSize(find.byType(TvDiscoveryRail)).height, closeTo(expected, 0.5));

      for (final group in films.take(4)) {
        railOf(tester).focusGroup(group.groupId);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(TvDiscoveryRail)).height, closeTo(expected, 0.5));
      }
    });

    // Hoofdstuk 19: the focused tile is wide, its neighbours stay their poster
    // width and stay on screen. Both halves matter — a focused tile that
    // covered its neighbours would fail the phase as surely as one that did not
    // grow at all.
    testWidgets('focus widens one tile and leaves its neighbours their own width', (tester) async {
      setGoldenSurfaceSize(tester);
      final films = tvDiscoveryFilmsRow();
      await tester.pumpWidget(_shell(_rail(groups: films)));
      await tester.pumpAndSettle();

      final scale = TvLayoutConstants.scaleForSize(kTvGoldenSurfaceSize);
      final ringPadding = TvDiscoveryLayout.cardFocusRingGap * scale * 2;
      double widthOf(UnifiedMediaGroup g) => tester.getSize(find.byKey(ValueKey(g.groupId))).width;

      railOf(tester).focusGroup(films[1].groupId);
      await tester.pumpAndSettle();

      expect(widthOf(films[1]), closeTo(TvDiscoveryLayout.wideWidth(scale) + ringPadding, 1.5));
      expect(widthOf(films[0]), closeTo(TvDiscoveryLayout.posterWidth(scale) + ringPadding, 1.5));
      expect(widthOf(films[2]), closeTo(TvDiscoveryLayout.posterWidth(scale) + ringPadding, 1.5));

      // And the neighbour on each side is still inside the viewport.
      expect(tester.getTopLeft(find.byKey(ValueKey(films[0].groupId))).dx, greaterThan(-1));
      expect(tester.getTopLeft(find.byKey(ValueKey(films[2].groupId))).dx, lessThan(kTvGoldenSurfaceSize.width));
    });

    // Hoofdstuk 44: Reduce Motion snaps the expansion instead of tweening it.
    // The width it snaps to is the same width — the accessibility setting turns
    // off the animation, not the design.
    //
    // Asserted against its own control, because "the width is right after two
    // frames" would also pass on a tween that happened to be fast. The same two
    // frames with animations *on* must land somewhere short of the target; with
    // them off, exactly on it.
    testWidgets('Reduce Motion snaps the expansion instead of tweening it', (tester) async {
      final scale = TvLayoutConstants.scaleForSize(kTvGoldenSurfaceSize);
      final target = TvDiscoveryLayout.wideWidth(scale) + TvDiscoveryLayout.cardFocusRingGap * scale * 2;
      final films = tvDiscoveryFilmsRow();

      Future<double> widthAfterTwoFrames({required bool disableAnimations}) async {
        // A distinct key, so the second run builds a fresh rail rather than
        // inheriting the first one's already-expanded tile.
        await tester.pumpWidget(
          _shell(
            _rail(groups: films, key: ValueKey(disableAnimations)),
            disableAnimations: disableAnimations,
          ),
        );
        await tester.pumpAndSettle();
        railOf(tester).focusGroup(films[1].groupId);
        await tester.pump();
        await tester.pump();
        final width = tester.getSize(find.byKey(ValueKey(films[1].groupId))).width;
        await tester.pumpAndSettle();
        return width;
      }

      setGoldenSurfaceSize(tester);
      expect(await widthAfterTwoFrames(disableAnimations: true), closeTo(target, 1.5));
      expect(await widthAfterTwoFrames(disableAnimations: false), lessThan(target - 1.5));
    });
  });
}
