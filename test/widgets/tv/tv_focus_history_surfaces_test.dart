/// A row move on TV goes around Flutter's directional traversal, and that
/// traversal keeps a history it answers the opposite direction from. A history
/// from another row must not survive the move, on any surface that mixes the two.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_home_customize_panel.dart';
import 'package:pleya/widgets/tv/tv_rail_stack.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/tv_discovery_artwork.dart';
import '../../test_helpers/tv_discovery_fixtures.dart';

MediaItem _item(String id) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: id,
  year: 2024,
  serverId: 'nas',
  serverName: 'NAS',
);
List<UnifiedMediaGroup> row(String p, int n) => [
  for (var i = 0; i < n; i++) tvDiscoveryGroup('$p$i', [_item('$p$i')]),
];

void main() {
  setUpAll(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    TvDiscoveryArtwork.install();
  });
  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDiscoveryArtwork.remove();
  });

  Future<List<TvDiscoveryRailState>> pumpStack(WidgetTester tester, List<List<UnifiedMediaGroup>> rows) async {
    tester.view.physicalSize = const Size(1038, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final stack = TvRailStack();
    stack.layOut([for (var i = 0; i < rows.length; i++) 'row$i']);
    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: InputModeTracker(
          child: Scaffold(
            backgroundColor: theme.extension<MonoTokens>()!.bg,
            body: Builder(
              builder: (context) {
                final height = TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context));
                return ListView(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      SizedBox(
                        height: height,
                        child: TvDiscoveryRail(
                          key: stack.keyFor('row$i'),
                          title: 'R$i',
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

  String? tile() {
    final l = FocusManager.instance.primaryFocus?.debugLabel;
    const p = 'tvDiscoveryTile_';
    return l != null && l.startsWith(p) ? l.substring(p.length) : l;
  }

  Future<void> press(WidgetTester t, LogicalKeyboardKey k, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.sendKeyEvent(k);
      await t.pumpAndSettle();
    }
  }

  testWidgets('a rail keeps LEFT in place after a step down and back up', (tester) async {
    final rails = await pumpStack(tester, [row('t', 8), row('b', 2)]);
    rails.first.focusGroup('t0');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    expect(tile(), 't3');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(tile(), 'b1');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(tile(), 't1');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(tile(), 't0');
  });

  Future<ValueNotifier<List<UnifiedMediaGroup>>> pumpRail(
    WidgetTester tester, {
    TvDiscoveryViewAllTile? viewAll,
  }) async {
    tester.view.physicalSize = const Size(1038, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final stack = TvRailStack();
    stack.layOut(['row0']);
    final groups = ValueNotifier(row('t', 8));
    addTearDown(groups.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                height: TvDiscoveryLayout.railSectionHeight(TvLayoutConstants.scaleOf(context)),
                child: ValueListenableBuilder(
                  valueListenable: groups,
                  builder: (context, value, _) => TvDiscoveryRail(
                    key: stack.keyFor('row0'),
                    title: 'R',
                    groups: value,
                    viewAll: viewAll,
                    onActivate: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.state<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).focusGroup('t0');
    await tester.pumpAndSettle();
    return groups;
  }

  testWidgets('a rail drops the history when its order changes', (tester) async {
    final groups = await pumpRail(tester);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(tile(), 't2');
    final now = groups.value;
    groups.value = [now[0], now[3], now[2], now[1], ...now.skip(4)];
    await tester.pumpAndSettle();
    expect(tile(), 't2');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(tile(), 't3');
  });

  testWidgets('a rail drops the history when a title is inserted before the ring', (tester) async {
    final groups = await pumpRail(tester);
    await press(tester, LogicalKeyboardKey.arrowRight, times: 3);
    expect(tile(), 't3');
    final now = groups.value;
    groups.value = [
      ...now.take(3),
      tvDiscoveryGroup('new', [_item('new')]),
      ...now.skip(3),
    ];
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(tile(), 'new');
  });

  testWidgets('a rail drops the history when the view-all tile holds the ring', (tester) async {
    final groups = await pumpRail(
      tester,
      viewAll: TvDiscoveryViewAllTile(count: 8, destinationLabel: 'Alle films', onSelect: () {}),
    );
    await press(tester, LogicalKeyboardKey.arrowRight, times: 8);
    expect(tile(), 'tvDiscoveryViewAllTile');
    final now = groups.value;
    groups.value = [...now.take(5), now[7], now[6], now[5]];
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(tile(), 't5');
  });

  testWidgets('the Home panel keeps LEFT in the row after UP', (tester) async {
    tester.view.physicalSize = const Size(1920, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final entries = [
      for (var i = 0; i < 5; i++)
        TvHomeRowEntry(
          row: UnifiedMediaHub(
            hubId: 'hub$i',
            title: 'Rij $i',
            kind: UnifiedHubKind.movie,
            groups: const [],
            contributingRowIds: ['r$i'],
          ),
          layoutIds: ['r$i'],
          isHidden: false,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Material(
            child: TvHomeCustomizePanel(
              fixedRows: const [],
              entries: entries,
              onMove: (_, _) {},
              onToggleHidden: (_) {},
              onEdit: (_) {},
              onRemove: (_) {},
              onNewRow: () async => null,
              onClose: () {},
              onAdded: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String? lab() => FocusManager.instance.primaryFocus?.debugLabel;
    FocusNode n(String want) => FocusManager.instance.rootScope.descendants.firstWhere((d) => d.debugLabel == want);
    n('TvHomeCustomize.r3#up').requestFocus();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
    expect(lab(), 'TvHomeCustomize.r3#primary');
    await press(tester, LogicalKeyboardKey.arrowUp, times: 2);
    expect(lab(), 'TvHomeCustomize.r1#primary');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(lab(), 'TvHomeCustomize.r1#down');
  });

  group('grid', () {
    const canvas = Size(1038, 584);
    Widget gridOf(List<String> ids, Map<String, FocusNode> nodes, GlobalKey<TvCatalogCardGridState> key) => SizedBox(
      width: canvas.width,
      height: canvas.height,
      child: TvCatalogCardGrid(
        key: key,
        rowAligned: true,
        itemIds: ids,
        cardHeight: (w) => TvCatalogLayout.cardHeight(w, 0.85),
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
        itemBuilder: (context, cell) {
          nodes[ids[cell.index]] = cell.focusNode;
          return TvCatalogCard(
            key: ValueKey(ids[cell.index]),
            width: cell.width,
            artwork: const SizedBox(),
            title: ids[cell.index],
            meta: '',
            focusNode: cell.focusNode,
            onFocusChange: cell.onFocusChange,
            onNavigateUp: cell.onNavigateUp,
            onNavigateDown: cell.onNavigateDown,
            onNavigateLeft: cell.onNavigateLeft,
            onNavigateRight: cell.onNavigateRight,
            onSelect: () {},
          );
        },
      ),
    );

    Widget app(List<String> ids, Map<String, FocusNode> nodes, GlobalKey<TvCatalogCardGridState> key) => MaterialApp(
      theme: monoTheme(dark: true),
      home: InputModeTracker(child: Material(child: gridOf(ids, nodes, key))),
    );

    String focused(Map<String, FocusNode> nodes) => nodes.entries.firstWhere((e) => e.value.hasPrimaryFocus).key;

    // The list changes below one MaterialApp, as it does on a screen: a new app
    // would build a new traversal policy and lose the history by accident.
    Future<ValueNotifier<List<String>>> pumpStable(
      WidgetTester tester,
      Map<String, FocusNode> nodes,
      GlobalKey<TvCatalogCardGridState> key,
    ) async {
      tester.view.physicalSize = canvas;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ids = ValueNotifier([for (var i = 0; i < 40; i++) 'm$i']);
      addTearDown(ids.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Material(
              child: ValueListenableBuilder(
                valueListenable: ids,
                builder: (context, value, _) => gridOf(value, nodes, key),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ids;
    }

    testWidgets('LEFT follows the new order after a reorder under the ring', (tester) async {
      final nodes = <String, FocusNode>{};
      final ids = await pumpStable(tester, nodes, GlobalKey<TvCatalogCardGridState>());
      nodes['m1']!.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(nodes), 'm2');
      // A merge round moves m1 far away; m2 slides onto its place. No id leaves.
      ids.value = [...ids.value]
        ..remove('m1')
        ..add('m1');
      await tester.pumpAndSettle();
      expect(focused(nodes), 'm2');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(nodes), 'm0');
    });

    testWidgets('LEFT takes the neighbour after cards are inserted before the ring', (tester) async {
      final nodes = <String, FocusNode>{};
      final ids = await pumpStable(tester, nodes, GlobalKey<TvCatalogCardGridState>());
      nodes['m7']!.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight, times: 2);
      expect(focused(nodes), 'm9');
      // A wider filter puts titles between the cards the history remembers.
      final at = ids.value.indexOf('m9');
      ids.value = [...ids.value]..insertAll(at, [for (var i = 0; i < 20; i++) 'n$i']);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(nodes), 'n19');
    });

    testWidgets('a key press still moves after the focused card is removed', (tester) async {
      final nodes = <String, FocusNode>{};
      final ids = await pumpStable(tester, nodes, GlobalKey<TvCatalogCardGridState>());
      nodes['m9']!.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(nodes), 'm8');
      ids.value = [...ids.value]..remove('m8');
      await tester.pumpAndSettle();
      expect(focused(nodes), 'm9');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(nodes), 'm10');
    });

    testWidgets('RIGHT on the last card of a short last row stays put', (tester) async {
      tester.view.physicalSize = canvas;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nodes = <String, FocusNode>{};
      final key = GlobalKey<TvCatalogCardGridState>();
      await tester.pumpWidget(app([for (var i = 0; i < 40; i++) 'm$i'], nodes, key));
      await tester.pumpAndSettle();
      final top = tester.getTopLeft(find.text('m0')).dy;
      var c = 0;
      while (tester.getTopLeft(find.text('m$c')).dy == top) {
        c++;
      }
      final ids = [for (var i = 0; i < 2 * c + 2; i++) 'm$i'];
      await tester.pumpWidget(app(ids, nodes, key));
      await tester.pumpAndSettle();
      nodes['m${2 * c + 1}']!.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(nodes), 'm${2 * c + 1}');
    });
  });
}
