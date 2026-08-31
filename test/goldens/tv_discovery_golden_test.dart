import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_expandable_media_tile.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_view_all_action.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/tv_discovery_artwork.dart';
import '../test_helpers/tv_discovery_fixtures.dart';

/// Visual acceptance for the fase-6 discovery landing (hoofdstuk 10.2a of
/// docs/tvos-unified-experience.md, [DEC-064]).
///
/// These render the real rail, the real tile and the real view-all row at the
/// tvOS logical canvas DEC-028 produces, with the production `monoTheme` and the
/// app's own fonts — so the band height, the expansion ratio, the type hierarchy
/// and the focus ring in the picture are decided by the code an Apple TV runs.
///
/// What they are for is the one question fase 6 exists to answer and fase 5
/// deliberately does not: **does focus change the composition?** A picture where
/// the focused tile is a poster with a slightly fatter ring is a failed phase,
/// whatever the tests say. So every state here is a focus state, and the pair
/// "first item focused" / "middle item focused" is in the set precisely so the
/// two can be laid side by side and the geometry compared.
///
/// The other question is hoofdstuk 23's: `#141414` is the cinema, not the film.
/// `TvDiscoveryArtwork` fills the image seam with panels that span warm orange,
/// bright blue, green, family animation, high-key comedy, neon and dark drama,
/// so these pictures judge Pleya's chrome against content that has a mood rather
/// than against grey.
///
/// Not pixel truth for tvOS — hoofdstuk 29 is explicit that rasterization,
/// render scale and HDR differ on the device. They catch a composition
/// regression here; hardware verification stays outstanding until after fase 10A.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_discovery_golden_test.dart`

Widget _shell(Widget child) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: InputModeTracker(
        child: Scaffold(backgroundColor: theme.extension<MonoTokens>()!.bg, body: child),
      ),
    ),
  );
}

/// One rail's worth of input, in the shape the landing screen will hand the
/// rail once the projection layer is wired to it.
typedef _Rail = ({String title, List<UnifiedMediaGroup> groups, bool isPartial});

/// A whole landing: page heading, rails, and the view-all row that closes it —
/// composed here the same way `TvUnifiedCatalogScreen`'s goldens compose header
/// plus grid, and for the same reason. What these pictures are about is the
/// composition, and the composition lives entirely in these widgets.
Widget _landing({
  required String title,
  required List<_Rail> rails,
  required String allTitle,
  required List<FocusNode> railNodes,
  FocusNode? viewAllNode,
  ScrollController? controller,
}) {
  return Builder(
    builder: (context) {
      final scale = TvLayoutConstants.scaleOf(context);
      return ListView(
        controller: controller,
        padding: EdgeInsets.only(
          top: TvCatalogLayout.topSafeInset * scale,
          bottom: TvCatalogLayout.topSafeInset * scale,
        ),
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: TvDiscoveryLayout.pageInset * scale,
              right: (TvDiscoveryLayout.pageInset - TvDiscoveryLayout.viewAllFocusRingGap) * scale,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).extension<MonoTokens>()!.text,
                      fontSize: TvDiscoveryLayout.pageTitleFontSize * scale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                SizedBox(width: TvDiscoveryLayout.pageTitleActionGap * scale),
                Flexible(
                  child: TvViewAllAction(
                    label: allTitle,
                    focusNode: viewAllNode,
                    onSelect: () {},
                    semanticLabel: t.unifiedCatalog.discovery.semantics.viewAllMovies,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: TvDiscoveryLayout.titleRailGap * scale),
          for (var i = 0; i < rails.length; i++) ...[
            if (i > 0) SizedBox(height: TvDiscoveryLayout.sectionGap * scale),
            SizedBox(
              height: TvDiscoveryLayout.railSectionHeight(scale),
              child: TvDiscoveryRail(
                key: ValueKey(rails[i].title),
                title: rails[i].title,
                groups: rails[i].groups,
                isPartial: rails[i].isPartial,
                onActivate: (_) {},
              ),
            ),
          ],
        ],
      );
    },
  );
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
    TvDiscoveryArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDiscoveryArtwork.remove();
  });

  List<FocusNode> nodes(WidgetTester tester, int count) {
    final list = [for (var i = 0; i < count; i++) FocusNode(debugLabel: 'rail$i')];
    addTearDown(() {
      for (final node in list) {
        node.dispose();
      }
    });
    return list;
  }

  List<_Rail> moviesRails() {
    final films = tvDiscoveryFilmsRow();
    return [
      (title: t.discover.continueWatching, groups: tvDiscoveryContinueWatchingRow(), isPartial: false),
      (title: t.discover.recentlyAdded, groups: films, isPartial: false),
    ];
  }

  /// Focuses one tile the way the landing's own restoration does — through the
  /// rail, by group id — rather than by reaching for a `Focus` ancestor the
  /// tile does not have.
  Future<void> focusTile(WidgetTester tester, String groupId) async {
    expect(
      find.byKey(ValueKey(groupId)),
      findsOneWidget,
      reason: 'fixture $groupId must be built before it can be focused',
    );
    final rails = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    expect(rails.any((rail) => rail.focusGroup(groupId)), isTrue, reason: 'no rail could focus $groupId');
    await tester.pumpAndSettle();
  }

  testWidgets('movies landing, first item focused', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        _landing(
          title: t.unifiedCatalog.moviesTitle,
          rails: moviesRails(),
          allTitle: t.unifiedCatalog.discovery.allMovies,
          railNodes: nodes(tester, 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await focusTile(tester, tvDiscoveryContinueWatchingRow().first.groupId);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_movies_first_focused');
  });

  testWidgets('movies landing, a middle item focused', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        _landing(
          title: t.unifiedCatalog.moviesTitle,
          rails: moviesRails(),
          allTitle: t.unifiedCatalog.discovery.allMovies,
          railNodes: nodes(tester, 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await focusTile(tester, tvDiscoveryFilmsRow()[2].groupId);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_movies_middle_focused');
  });

  testWidgets('series landing, an episode-context item focused', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        _landing(
          title: t.unifiedCatalog.seriesTitle,
          rails: [
            (title: t.discover.continueWatching, groups: tvDiscoveryContinueWatchingRow(), isPartial: false),
            (title: t.discover.latestShows, groups: tvDiscoverySeriesRow(), isPartial: true),
          ],
          allTitle: t.unifiedCatalog.discovery.allSeries,
          railNodes: nodes(tester, 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await focusTile(tester, 'disc-cw-harbourlight');
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_series_episode_focused');
  });

  // The composition with the *second* rail active: the page has scrolled, the
  // active rail owns the screen, and the rail above has become the peek. This
  // is the state a viewer is in for most of a browsing session, so the visual
  // gate judges it alongside the landing state, not instead of it.
  testWidgets('series landing, second rail focused', (tester) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      _shell(
        _landing(
          title: t.unifiedCatalog.seriesTitle,
          rails: [
            (title: t.discover.continueWatching, groups: tvDiscoveryContinueWatchingRow(), isPartial: false),
            (title: t.discover.latestShows, groups: tvDiscoverySeriesRow(), isPartial: true),
          ],
          allTitle: t.unifiedCatalog.discovery.allSeries,
          railNodes: nodes(tester, 2),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await focusTile(tester, tvDiscoverySeriesRow()[1].groupId);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_series_second_rail_focused');
  });

  testWidgets('view all focused', (tester) async {
    setGoldenSurfaceSize(tester);
    final viewAll = FocusNode(debugLabel: 'viewAll');
    addTearDown(viewAll.dispose);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _shell(
        _landing(
          title: t.unifiedCatalog.moviesTitle,
          rails: moviesRails(),
          allTitle: t.unifiedCatalog.discovery.allMovies,
          railNodes: nodes(tester, 2),
          viewAllNode: viewAll,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    viewAll.requestFocus();
    await tester.pumpAndSettle();
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_view_all_focused');
  });

  // Hoofdstuk 20's contract, as a measurement rather than a picture: moving
  // focus along a rail may not move anything below it. The fase-5 grid already
  // proved what a focus-dependent row height costs.
  testWidgets('vertical geometry does not move when focus moves along a rail', (tester) async {
    setGoldenSurfaceSize(tester);
    final viewAll = FocusNode(debugLabel: 'viewAll');
    addTearDown(viewAll.dispose);
    await tester.pumpWidget(
      _shell(
        _landing(
          title: t.unifiedCatalog.moviesTitle,
          rails: moviesRails(),
          allTitle: t.unifiedCatalog.discovery.allMovies,
          railNodes: nodes(tester, 2),
          viewAllNode: viewAll,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final films = tvDiscoveryFilmsRow();
    double railTop() => tester.getTopLeft(find.byType(TvDiscoveryRail).last).dy;

    await focusTile(tester, films.first.groupId);
    final before = railTop();
    for (final group in films.take(4)) {
      await focusTile(tester, group.groupId);
      expect(railTop(), before, reason: 'the second rail moved while focus walked the first');
    }
  });

  // Rapid input: four presses faster than the 200ms tween. Nothing may be
  // activated, and the focus must land where the last press put it — hoofdstuk
  // 21, "animation is presentation, focus state is authority".
  testWidgets('rapid focus moves leave no stale geometry and activate nothing', (tester) async {
    setGoldenSurfaceSize(tester);
    final activated = <String>[];
    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) {
            final scale = TvLayoutConstants.scaleOf(context);
            return SizedBox(
              height: TvDiscoveryLayout.railSectionHeight(scale),
              child: TvDiscoveryRail(
                title: t.discover.recentlyAdded,
                groups: tvDiscoveryFilmsRow(),
                onActivate: (group) => activated.add(group.groupId),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final films = tvDiscoveryFilmsRow();
    final rail = tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    for (final group in films.take(4)) {
      expect(rail.focusGroup(group.groupId), isTrue);
      // Deliberately shorter than the 200ms expansion tween: each press lands
      // while the previous one is still animating.
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();

    expect(activated, isEmpty, reason: 'walking a rail must never activate a title');
    final last = films[3];
    expect(
      rail.focusGroup(last.groupId),
      isTrue,
      reason: 'the last press decides where focus is, not the last animation to finish',
    );
    // And the tile the focus landed on is the expanded one, at wide width.
    final scale = TvLayoutConstants.scaleForSize(kTvGoldenSurfaceSize);
    final expanded = tester.getSize(find.byKey(ValueKey(last.groupId)));
    expect(
      expanded.width,
      closeTo(TvDiscoveryLayout.wideWidth(scale) + TvDiscoveryLayout.cardFocusRingGap * scale * 2, 1.5),
    );
  });

  // The tile picks the right image path for what it is showing: an episode
  // expands into its own 16:9 still, a film into its backdrop, and a compact
  // neighbour is always a 2:3 poster.
  test('artwork paths follow the item kind', () {
    final episode = tvDiscoveryContinueWatchingRow()
        .firstWhere((g) => g.groupId == 'disc-cw-harbourlight')
        .representativeSource
        .item;
    expect(discoveryWideArtPath(episode), episode.thumbPath);
    expect(discoveryPosterPath(episode), episode.grandparentThumbPath);
    expect(discoveryPosterPath(episode), isNot(episode.thumbPath));

    final film = tvDiscoveryFilmsRow().first.representativeSource.item;
    expect(discoveryWideArtPath(film), film.artPath);
    expect(discoveryPosterPath(film), film.thumbPath);
  });
}
