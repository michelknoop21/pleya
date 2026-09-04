/// DEC-087's density, measured rather than eyeballed.
///
/// The rail's composition is one number — [TvDiscoveryLayout.cardHeight] — and
/// everything else follows from it, so the honest way to guard the decision is
/// to count tiles on the canonical canvas rather than to assert the constant.
/// Asserting `cardHeight == 220` would pass just as happily after someone
/// changed [TvDiscoveryLayout.itemGap] or [TvDiscoveryLayout.pageInset] and
/// quietly lost the seventh tile.
///
/// The canvas is DEC-028's: an Apple TV renders 1920×1080 at scale 1.85, so the
/// logical surface is 1038×584 and [TvLayoutConstants.scaleOf] clamps to its
/// 0.85 floor. Every number below is on that surface.
///
/// `tvos.discovery.density` proves the same composition on a real build. It can
/// state "six tiles fully inside the viewport and a seventh beside them" and it
/// cannot state "the seventh is only partly visible" — `insideViewport` has no
/// negation. That half is here, where the rects are exact.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/tv_discovery_artwork.dart';
import '../../test_helpers/tv_discovery_fixtures.dart';

/// DEC-028's logical canvas.
const Size _canvas = Size(1038, 584);

void main() {
  setUpAll(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    TvDiscoveryArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDiscoveryArtwork.remove();
  });

  setUp(() {
    // The rail is a horizontal `ListView.builder`, so only what the viewport
    // plus the cache extent can reach is built. Six full tiles plus a partial
    // seventh is well inside that; the eighth and ninth may or may not exist,
    // and nothing here asks about them.
  });

  Future<void> pumpRail(WidgetTester tester, List<UnifiedMediaGroup> groups) async {
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
                child: TvDiscoveryRail(title: 'Films', groups: groups, onActivate: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The tiles that are drawn **entirely** inside the surface, in order.
  List<int> fullyVisibleIndices(WidgetTester tester, List<UnifiedMediaGroup> groups) {
    final visible = <int>[];
    for (var i = 0; i < groups.length; i++) {
      final finder = find.byKey(ValueKey(groups[i].groupId));
      if (finder.evaluate().isEmpty) continue;
      final rect = tester.getRect(finder);
      if (rect.left >= -0.01 && rect.right <= _canvas.width + 0.01) visible.add(i);
    }
    return visible;
  }

  testWidgets('at rest a rail draws six full tiles and a visibly partial seventh', (tester) async {
    final groups = tvDiscoveryFilmsRow();
    expect(groups.length, greaterThanOrEqualTo(8), reason: 'the fixture has to be able to overflow the band');
    await pumpRail(tester, groups);

    expect(fullyVisibleIndices(tester, groups), [
      0,
      1,
      2,
      3,
      4,
      5,
    ], reason: 'DEC-087 fixes cardHeight at 220 for exactly six full tiles at rest');

    // The seventh: built, and hanging off the right edge by more than a
    // rounding error. "A peek", not "a sliver you cannot tell from a clipping
    // bug" — the whole reason 240 was rejected is that it left 16px showing.
    final seventh = tester.getRect(find.byKey(ValueKey(groups[6].groupId)));
    final peek = _canvas.width - seventh.left;
    expect(seventh.right, greaterThan(_canvas.width), reason: 'the seventh tile must not fit');
    expect(peek, greaterThan(60), reason: 'a peek under ~60px reads as a clipped tile, not as "there is more"');
    expect(peek, lessThan(seventh.width), reason: 'if it fits entirely, this is a seven-up layout');
  });

  testWidgets('a focused tile leaves four full neighbours beside it', (tester) async {
    final groups = tvDiscoveryFilmsRow();
    await pumpRail(tester, groups);

    final rail = tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    expect(rail.focusGroup(groups.first.groupId), isTrue);
    await tester.pumpAndSettle();

    final visible = fullyVisibleIndices(tester, groups);
    expect(visible.first, 0, reason: 'the focused tile stays fully on screen (P9)');
    expect(
      visible.length,
      5,
      reason: 'DEC-087: the focused 16:9 frame plus four complete 2:3 neighbours — not three, as 270 gave',
    );

    // The expansion is a change of emphasis, not a takeover: at 270 the focused
    // frame took 42.3% of the usable band, which is what "bijna de helft" in the
    // report meant.
    final focused = tester.getRect(find.byKey(ValueKey(groups.first.groupId)));
    final scale = TvLayoutConstants.scaleOf(tester.element(find.byType(TvDiscoveryRail)));
    final usable = TvDiscoveryLayout.railUsableWidth(_canvas.width, scale);
    final share = TvDiscoveryLayout.wideWidth(scale) / usable;
    expect(share, closeTo(0.345, 0.005), reason: 'DEC-087 fixes the focused share at ~34.5%');
    expect(focused.width, greaterThan(TvDiscoveryLayout.posterWidth(scale)));
  });

  testWidgets('the rail keeps a full band height while focus moves', (tester) async {
    final groups = tvDiscoveryFilmsRow();
    await pumpRail(tester, groups);

    final before = tester.getRect(find.byKey(ValueKey(groups.first.groupId)));
    final rail = tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    expect(rail.focusGroup(groups[2].groupId), isTrue);
    await tester.pumpAndSettle();
    final after = tester.getRect(find.byKey(ValueKey(groups.first.groupId)));

    expect(after.height, before.height, reason: 'height is constant by construction — only width moves');
  });

  test('the tokens agree with what the widget draws', () {
    const scale = 0.85;
    final usable = TvDiscoveryLayout.railUsableWidth(_canvas.width, scale);
    expect(usable, closeTo(964.9, 0.1));
    expect(TvDiscoveryLayout.fullTilesAtRest(usable, scale), 6);
    expect(TvDiscoveryLayout.posterWidth(scale), closeTo(124.67, 0.01));
    expect(TvDiscoveryLayout.wideWidth(scale), closeTo(332.44, 0.01));
  });

  test('the bottom edge clears the overscan band with room to spare (P12)', () {
    const scale = 0.85;
    final grid = TvCatalogGrid.forWidth(_canvas.width, scale: scale);
    // The bare margin, without the focus growth that is spent the moment a
    // bottom-row card is focused.
    final bare = _canvas.width * (TvCatalogLayout.bottomSafeInset / 1920);
    expect(
      bare / _canvas.height,
      greaterThan(0.07),
      reason: 'a ~5% margin sits *on* the overscan band, not clear of it',
    );
    expect(
      grid.bottomSafeMargin,
      closeTo(bare, 0.001),
      reason: 'the margin itself is the overscan band and nothing else',
    );
    final padding = grid.scrollPadding(
      cardHeight: TvCatalogLayout.cardHeight(grid.cardWidth, scale),
      focusScale: FocusTheme.fullCardFocusScale,
    );
    expect(padding.bottom, greaterThan(bare), reason: 'the focus growth is on top of the margin, not out of it');
    expect(
      TvCatalogLayout.bottomSafeInset,
      greaterThan(TvCatalogLayout.topSafeInset),
      reason: 'hoofdstuk 8.1 states a minimum; the bottom edge is the one that needs more than the minimum',
    );
  });
}
