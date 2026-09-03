/// CAT3 (docs/tvos-fysieke-correctieronde.md): the header's action cluster —
/// Bronnen, Filters, Sortering — has to end flush against the page's own
/// canonical right content edge, the same edge [TvCatalogGrid] lines the
/// grid's own artwork up against, whatever the title's length or how many
/// actions are on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

/// The real header, inside [TvShellSurface] the way `TvUnifiedCatalogScreen`
/// always mounts it — not a bare `Row` in isolation.
Widget _shell(List<FocusNode> nodes, {String title = 'Films', bool includeSources = true, int filterBadge = 0}) =>
    TranslationProvider(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: TvShellSurface(
            child: Scaffold(
              body: TvCatalogHeaderBar(
                title: title,
                actions: [
                  if (includeSources)
                    TvCatalogHeaderAction(
                      icon: Symbols.dns_rounded,
                      action: LibraryHeaderAction(label: 'Alle bronnen', focusNode: nodes[0], onPressed: () {}),
                    ),
                  TvCatalogHeaderAction(
                    icon: Symbols.filter_list_rounded,
                    badgeCount: filterBadge,
                    action: LibraryHeaderAction(label: 'Filters', focusNode: nodes[1], onPressed: () {}),
                  ),
                  TvCatalogHeaderAction(
                    icon: Symbols.swap_vert_rounded,
                    action: LibraryHeaderAction(label: 'Titel A-Z', focusNode: nodes[2], onPressed: () {}),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('CAT3', () {
    Future<double> pumpAndMeasureRightDelta(
      WidgetTester tester, {
      required Size surface,
      String title = 'Films',
      bool includeSources = true,
      int filterBadge = 0,
    }) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final nodes = [for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'action$i')];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });

      await tester.pumpWidget(_shell(nodes, title: title, includeSources: includeSources, filterBadge: filterBadge));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(TvCatalogHeaderBar));
      final scale = TvLayoutConstants.scaleOf(context);
      final width = MediaQuery.sizeOf(context).width;
      final grid = TvCatalogGrid.forWidth(width, scale: scale);
      final canonicalRight = width - (grid.inset + TvCatalogLayout.cardContentInset(scale));

      // The rightmost action's own capsule box — what the focus ring is
      // drawn on — rather than its label text, for the same reason CAT1
      // measures the ring and not the resting `SizedBox`.
      final capsules = find.descendant(
        of: find.byType(TvCatalogHeaderBar),
        matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'FocusableWrapper'),
      );
      final lastCapsule = tester.getRect(capsules.last);
      return canonicalRight - lastCapsule.right;
    }

    testWidgets('the action cluster reaches the canonical right edge on the canonical canvas', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1038, 584));
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    // This is the case that actually reproduced CAT3: on the canonical
    // canvas the old 50/50 flex split happened to land close to the actions'
    // own intrinsic width, so the bug was invisible there. At the reference
    // 1920x1080 resolution `TvLayoutConstants.scaleForHeight` stops being
    // clamped, and the two widths diverge — the old code left the cluster
    // roughly 240 logical pixels short of the edge.
    testWidgets('the action cluster reaches the canonical right edge at 1920x1080', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1920, 1080));
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    // Hoofdstuk 10.6: Bronnen is conditionally omitted. Filters and
    // Sortering must not drift left when it is missing — the old flex split
    // left ~140 logical pixels of gap here on the canonical canvas alone.
    testWidgets('the action cluster still reaches the edge with Bronnen conditionally absent', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1038, 584), includeSources: false);
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    testWidgets('a short title does not pull the actions away from the edge', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1038, 584), title: 'TV');
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    testWidgets('a long localized title ellipsizes instead of pushing the actions off the line', (tester) async {
      final delta = await pumpAndMeasureRightDelta(
        tester,
        surface: const Size(1038, 584),
        title: 'Alle films en series in de bibliotheek',
      );
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    testWidgets('an active filter badge does not move the cluster off the edge', (tester) async {
      final delta = await pumpAndMeasureRightDelta(tester, surface: const Size(1038, 584), filterBadge: 3);
      expect(delta.abs(), lessThan(0.5), reason: 'delta was $delta logical pixels');
    });

    // The safety net for the pathological case a plain (unflexed) Row child
    // needs: a title squeezed to nothing plus a long enough action set that
    // it cannot fit at all must degrade to the actions' own internal
    // reverse-scroll, never to a `RenderFlex` overflow.
    testWidgets('an action row that cannot fully fit clips instead of overflowing', (tester) async {
      tester.view.physicalSize = const Size(640, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final nodes = [for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'action$i')];
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });

      await tester.pumpWidget(_shell(nodes, title: 'Alle films en series in de bibliotheek'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'a title long enough to squeeze to zero must not overflow');

      final context = tester.element(find.byType(TvCatalogHeaderBar));
      final scale = TvLayoutConstants.scaleOf(context);
      final width = MediaQuery.sizeOf(context).width;
      final grid = TvCatalogGrid.forWidth(width, scale: scale);
      final canonicalRight = width - (grid.inset + TvCatalogLayout.cardContentInset(scale));
      final sortLabel = tester.getRect(find.text('Titel A-Z'));
      expect(
        sortLabel.right,
        lessThanOrEqualTo(canonicalRight + 0.5),
        reason: 'Sort — the rightmost, most recently used action — must stay on screen even when the row is tight',
      );
    });
  });
}
