/// [TvDetailPage] on its own: what stays put, what scrolls, who holds the focus
/// and when the next section is asked for.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_layout.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_page.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';

const Size _canvas = Size(1038, 584);
const _backgroundKey = ValueKey('background');
const _heroButton = ValueKey('hero-button');

TvDetailSection _section(String id, {int count = 8, double width = 130, Map<String, FocusNode>? nodes}) {
  return TvDetailSection(
    id: id,
    title: 'Row $id',
    itemIds: [for (var i = 0; i < count; i++) '$id$i'],
    cardWidth: width,
    cardHeight: TvDetailLayout.cardHeight(width, 0.85, aspectRatio: 16 / 9),
    footerHeight: TvDetailLayout.cardFooterHeight(width, 0.85),
    itemBuilder: (context, cell) {
      final key = '$id${cell.index}';
      nodes?[key] = cell.focusNode;
      return TvCatalogCard(
        width: cell.width,
        aspectRatio: 16 / 9,
        artwork: const SizedBox(),
        title: key,
        meta: '',
        titleLines: 1,
        autoScroll: false,
        focusNode: cell.focusNode,
        onFocusChange: cell.onFocusChange,
        onNavigateUp: cell.onNavigateUp,
        onNavigateDown: cell.onNavigateDown,
        onNavigateLeft: cell.onNavigateLeft,
        onNavigateRight: cell.onNavigateRight,
        onSelect: () {},
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<TvDetailSection> sections, {
  GlobalKey<TvDetailPageState>? key,
  FocusNode? heroNode,
  VoidCallback? onFocusHero,
  bool hasPendingSections = false,
  VoidCallback? onApproachEnd,
}) async {
  tester.view.physicalSize = _canvas;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: InputModeTracker(
        child: TvDisplayMetrics(
          size: _canvas,
          child: Material(
            child: TvDetailPage(
              key: key,
              background: const ColoredBox(key: _backgroundKey, color: Colors.teal),
              hero: SizedBox(
                height: 420,
                child: Center(
                  child: Focus(
                    focusNode: heroNode,
                    child: const SizedBox(key: _heroButton, width: 60, height: 60),
                  ),
                ),
              ),
              sections: sections,
              onFocusHero: onFocusHero ?? () => heroNode?.requestFocus(),
              hasPendingSections: hasPendingSections,
              onApproachEnd: onApproachEnd,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the backdrop stays put while the page scrolls under it', (tester) async {
    final nodes = <String, FocusNode>{};
    final key = GlobalKey<TvDetailPageState>();
    await _pump(tester, [_section('a', nodes: nodes), _section('b', nodes: nodes)], key: key);

    expect(find.ancestor(of: find.byKey(_backgroundKey), matching: find.byType(Scrollable)), findsNothing);
    final before = tester.getRect(find.byKey(_backgroundKey));

    nodes['b0']!.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0));
    expect(tester.getRect(find.byKey(_backgroundKey)), before);
  });

  testWidgets('a section without items is not drawn at all', (tester) async {
    await _pump(tester, [_section('a'), _section('empty', count: 0), _section('b')]);
    expect(find.text('Row a'), findsOneWidget);
    expect(find.text('Row b'), findsOneWidget);
    expect(find.text('Row empty'), findsNothing);
  });

  testWidgets('a focused row lands with its artwork on the band of the northstar', (tester) async {
    final nodes = <String, FocusNode>{};
    await _pump(tester, [_section('a', nodes: nodes), _section('b', nodes: nodes), _section('c', nodes: nodes)]);

    nodes['b0']!.requestFocus();
    await tester.pumpAndSettle();

    final rail = tester.getRect(find.byType(ListView).at(1));
    final footer = TvDetailLayout.cardFooterHeight(130, 0.85);
    expect(rail.center.dy - footer / 2, closeTo(_canvas.height * TvDetailLayout.focusBandCentre, 1));
  });

  testWidgets('UP and DOWN walk the sections and stop at both ends', (tester) async {
    final nodes = <String, FocusNode>{};
    final heroNode = FocusNode(debugLabel: 'hero');
    addTearDown(heroNode.dispose);
    final key = GlobalKey<TvDetailPageState>();
    await _pump(
      tester,
      [_section('a', nodes: nodes), _section('b', nodes: nodes)],
      key: key,
      heroNode: heroNode,
    );

    String focused() => nodes.entries.firstWhere((e) => e.value.hasPrimaryFocus).key;

    expect(key.currentState!.focusFirstSection(), isTrue);
    await tester.pumpAndSettle();
    final column = focused().substring(1);
    expect(focused(), 'a$column');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(), 'b$column');

    // The end of the page keeps the press; the traversal would wrap it upwards.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(), 'b$column');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(), 'a$column');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(heroNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('a vertical step lands under the card it left, on rows of another pitch', (tester) async {
    final nodes = <String, FocusNode>{};
    await _pump(tester, [_section('a', nodes: nodes), _section('b', width: 277, nodes: nodes)]);

    nodes['a4']!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(nodes['b0']!.hasPrimaryFocus || nodes['b1']!.hasPrimaryFocus || nodes['b2']!.hasPrimaryFocus, isTrue);
    expect(nodes['b4']!.hasPrimaryFocus, isFalse, reason: 'same index is a different place on this row');
  });

  testWidgets('a section step wipes the directional history of the row it left', (tester) async {
    final nodes = <String, FocusNode>{};
    await _pump(tester, [_section('a', nodes: nodes), _section('b', nodes: nodes)]);

    nodes['a0']!.requestFocus();
    await tester.pumpAndSettle();
    // A traversal step, the one thing that writes history.
    FocusManager.instance.primaryFocus!.focusInDirection(TraversalDirection.right);
    await tester.pumpAndSettle();
    expect(nodes['a1']!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final landed = FocusManager.instance.primaryFocus!;

    // Kept, the history answers LEFT with the row above.
    landed.focusInDirection(TraversalDirection.left);
    await tester.pumpAndSettle();
    expect(nodes['a0']!.hasFocus, isFalse);
    expect(nodes['a1']!.hasFocus, isFalse);
  });

  testWidgets('the next section is asked for near the end, until the content runs on', (tester) async {
    var sections = [_section('a')];
    var asks = 0;
    late StateSetter setOuter;
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: TvDisplayMetrics(
            size: _canvas,
            child: Material(
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return TvDetailPage(
                    background: const SizedBox(),
                    hero: const SizedBox(height: 420),
                    sections: sections,
                    onFocusHero: () {},
                    hasPendingSections: true,
                    onApproachEnd: () => asks++,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(asks, greaterThan(0), reason: 'less than a page of content is left below the viewport');

    // Empty result: nothing moved, so the page asks again.
    asks = 0;
    setOuter(() => sections = [...sections, _section('empty', count: 0)]);
    await tester.pump();
    await tester.pump();
    expect(asks, greaterThan(0));

    // Content past the next viewport: nothing is near any more.
    asks = 0;
    setOuter(() => sections = [for (final id in 'bcdefg'.split('')) _section(id), ...sections]);
    await tester.pump();
    await tester.pump();
    expect(asks, 0);
  });

  testWidgets('restoreFocus finds the card a route was opened from, and says when it cannot', (tester) async {
    final nodes = <String, FocusNode>{};
    final key = GlobalKey<TvDetailPageState>();
    await _pump(tester, [_section('a', nodes: nodes), _section('b', nodes: nodes)], key: key);

    expect(key.currentState!.restoreFocus(sectionId: 'b', itemId: 'b2'), isTrue);
    await tester.pumpAndSettle();
    expect(nodes['b2']!.hasPrimaryFocus, isTrue);

    expect(key.currentState!.restoreFocus(sectionId: 'gone', itemId: 'x'), isFalse);
    expect(key.currentState!.restoreFocus(sectionId: null, itemId: 'b2'), isFalse);
  });

  testWidgets('a section that empties under the remote hands the focus to the hero', (tester) async {
    final nodes = <String, FocusNode>{};
    final heroNode = FocusNode(debugLabel: 'hero');
    addTearDown(heroNode.dispose);
    final key = GlobalKey<TvDetailPageState>();
    await _pump(
      tester,
      [_section('a', nodes: nodes)],
      key: key,
      heroNode: heroNode,
    );
    nodes['a0']!.requestFocus();
    await tester.pumpAndSettle();

    await _pump(tester, [_section('a', count: 0)], key: key, heroNode: heroNode);

    expect(heroNode.hasPrimaryFocus, isTrue);
  });

  test('body ink holds 4.5:1 over the worst artwork, in both themes', () {
    const worst = [Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFF808080)];
    for (final artwork in worst) {
      final dark = TvDetailLayout.worstCaseContrast(
        ink: const Color(0xFFFFFFFF),
        scrim: const Color(0xFF101010),
        artwork: artwork,
      );
      final light = TvDetailLayout.worstCaseContrast(
        ink: const Color(0xFF101010),
        scrim: const Color(0xFFFFFFFF),
        artwork: artwork,
      );
      expect(dark, greaterThanOrEqualTo(4.5), reason: 'dark on $artwork');
      expect(light, greaterThanOrEqualTo(4.5), reason: 'light on $artwork');
    }
  });
}
