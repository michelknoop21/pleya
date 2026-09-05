/// CAT3 (docs/tvos-fysieke-correctieronde.md): whatever balances the page
/// heading has to end flush against the page's own canonical right content
/// edge, the same edge [TvCatalogGrid] lines the grid's artwork up against,
/// whatever the title's length or how much is standing there.
///
/// The finding was made against the three action capsules
/// (Bronnen/Filters/Sortering) that used to live there. CAT5 and
/// [DEC-093](../../../docs/DECISIONS.md#dec-093) replaced them with the
/// selection tags, and the geometry survives the swap unchanged: it is a
/// statement about the `Row` (one flex child, one plain one), not about what
/// the plain child happens to be. So the measurements below are the same
/// measurements, taken on the tags.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const _sortTagLabel = 'Titel A-Z';

List<TvCatalogSelectionTag> _tags({int filters = 2}) => [
  for (var i = 0; i < filters; i++) TvCatalogSelectionTag(['Niet bekeken', 'Sciencefiction', '2023'][i % 3]),
  const TvCatalogSelectionTag(_sortTagLabel, muted: true),
];

/// The real header, inside [TvShellSurface] the way `TvUnifiedCatalogScreen`
/// always mounts it — not a bare `Row` in isolation.
Widget _shell({String title = 'Films', List<TvCatalogSelectionTag>? tags}) => TranslationProvider(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: monoTheme(dark: true),
    home: InputModeTracker(
      child: TvShellSurface(
        child: Scaffold(
          body: TvCatalogHeaderBar(title: title, tags: tags ?? _tags()),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('CAT3', () {
    /// Pumps the header at [surface] and returns how far the tag row's right
    /// edge sits from the page's canonical right content edge. Zero is flush.
    Future<double> pumpAndMeasureRightDelta(
      WidgetTester tester, {
      required Size surface,
      String title = 'Films',
      List<TvCatalogSelectionTag>? tags,
    }) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_shell(title: title, tags: tags));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TvCatalogHeaderBar));
      final scale = TvLayoutConstants.scaleOf(context);
      final width = MediaQuery.sizeOf(context).width;
      final grid = TvCatalogGrid.forWidth(width, scale: scale);
      final canonicalRight = width - (grid.inset + TvCatalogLayout.cardContentInset(scale));
      return canonicalRight - tester.getRect(find.byType(TvCatalogSelectionTagStrip)).right;
    }

    testWidgets('the tag row reaches the canonical right edge on the canonical canvas', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1038, 584));
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    // This is the case that actually reproduced CAT3: on the canonical
    // canvas the old 50/50 flex split happened to land close to the cluster's
    // own intrinsic width, so the bug was invisible there. At the reference
    // 1920x1080 resolution `TvLayoutConstants.scaleForHeight` stops being
    // clamped, and the two widths diverge — the old code left the cluster
    // roughly 240 logical pixels short of the edge.
    testWidgets('the tag row reaches the canonical right edge at 1920x1080', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1920, 1080));
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    // The count of tags is not fixed (nothing filtered leaves only the sort),
    // and a narrower row must not drift left, which is the same failure the
    // conditionally absent Bronnen action used to produce.
    testWidgets('the tag row still reaches the edge with nothing filtered', (tester) async {
      final delta = await pumpAndMeasureRightDelta(
        tester,
        surface: const Size(1038, 584),
        tags: const [TvCatalogSelectionTag(_sortTagLabel, muted: true)],
      );
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    testWidgets('a short title does not pull the tags away from the edge', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1038, 584), title: 'TV');
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    testWidgets('a long localized title ellipsizes instead of pushing the tags off the line', (tester) async {
      final delta = await pumpAndMeasureRightDelta(
        tester,
        surface: const Size(1038, 584),
        title: 'Alle films en series in de bibliotheek',
      );
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    testWidgets('the overflow tag does not move the row off the edge', (tester) async {
      final delta = await pumpAndMeasureRightDelta(
        tester,
        surface: const Size(1038, 584),
        tags: const [
          TvCatalogSelectionTag('Niet bekeken'),
          TvCatalogSelectionTag('Sciencefiction'),
          TvCatalogSelectionTag('2023'),
          TvCatalogSelectionTag('+2'),
          TvCatalogSelectionTag(_sortTagLabel, muted: true),
        ],
      );
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    // The safety net for the pathological case a plain (unflexed) Row child
    // needs: a title squeezed to nothing plus a tag row long enough that it
    // cannot fit at all must degrade to the row's own reverse anchoring, never
    // to a `RenderFlex` overflow.
    testWidgets('a tag row that cannot fully fit clips instead of overflowing', (tester) async {
      tester.view.physicalSize = const Size(640, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _shell(
          title: 'Alle films en series in de bibliotheek',
          tags: const [
            TvCatalogSelectionTag('Niet bekeken'),
            TvCatalogSelectionTag('Sciencefiction'),
            TvCatalogSelectionTag('Documentaire'),
            TvCatalogSelectionTag(_sortTagLabel, muted: true),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'a title long enough to squeeze to zero must not overflow');

      final context = tester.element(find.byType(TvCatalogHeaderBar));
      final scale = TvLayoutConstants.scaleOf(context);
      final width = MediaQuery.sizeOf(context).width;
      final grid = TvCatalogGrid.forWidth(width, scale: scale);
      final canonicalRight = width - (grid.inset + TvCatalogLayout.cardContentInset(scale));
      expect(
        tester.getRect(find.text(_sortTagLabel)).right,
        lessThanOrEqualTo(canonicalRight + 0.5),
        reason: 'the sort tag is last and always true, so it is the one that must stay on screen',
      );
    });
  });
}
