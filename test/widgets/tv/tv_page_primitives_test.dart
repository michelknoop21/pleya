/// The two primitives every nested Mijn Pleya page is built from.
///
/// [TvMenuGrid] carries the tile language and [TvPageChipBar] the capsule
/// language, and between them they draw Servers, Over, Samen Kijken, Logs and
/// Instellingen. Both grew a feature in this round that a settings index
/// needs, and both are worth pinning here rather than five times over in the
/// pages that use them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_menu_grid.dart';
import 'package:pleya/widgets/tv/tv_page_chip_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  group('TvMenuGrid', () {
    testWidgets('a toggle says its state without claiming the focus fill', (tester) async {
      // The reason `toggled` is not `selected`: `selected` raises the tile to
      // the focused fill, which is right for the one library a chooser is
      // showing and wrong for six switches on a settings index — six tiles
      // would all look like they were holding the remote.
      final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
      addTearDown(nodes.dispose);

      await pump(
        tester,
        TvMenuGrid(
          nodes: nodes,
          columns: 2,
          automationInstance: 'test',
          sections: [
            TvMenuSection(
              items: [
                TvMenuItem(key: 'on', icon: Symbols.wifi_rounded, title: 'On', toggled: true, onSelect: () {}),
                TvMenuItem(key: 'off', icon: Symbols.wifi_rounded, title: 'Off', toggled: false, onSelect: () {}),
                TvMenuItem(key: 'chosen', icon: Symbols.wifi_rounded, title: 'Chosen', selected: true, onSelect: () {}),
              ],
            ),
          ],
        ),
      );

      Color fillOf(String key) {
        final tile = find.ancestor(of: find.text(key), matching: find.byType(AnimatedContainer));
        return (tester.widget<AnimatedContainer>(tile.first).decoration! as BoxDecoration).color!;
      }

      expect(fillOf('On'), fillOf('Off'), reason: 'a switch does not change the tile surface');
      expect(fillOf('Chosen'), isNot(fillOf('On')), reason: 'a chosen tile still does');

      // And the state is legible without reading the value line.
      expect(find.byIcon(Icons.toggle_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.toggle_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('held SELECT only arms where a tile has a second action behind it', (tester) async {
      final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
      addTearDown(nodes.dispose);

      await pump(
        tester,
        TvMenuGrid(
          nodes: nodes,
          columns: 2,
          automationInstance: 'test',
          sections: [
            TvMenuSection(
              items: [
                TvMenuItem(key: 'plain', icon: Symbols.wifi_rounded, title: 'Plain', onSelect: () {}),
                TvMenuItem(key: 'menu', icon: Symbols.wifi_rounded, title: 'Menu', onSelect: () {}, onLongPress: () {}),
              ],
            ),
          ],
        ),
      );

      // A tile that is only a way in must not swallow a held press waiting for
      // a menu that does not exist.
      final tiles = tester.widgetList<TvMenuTile>(find.byType(TvMenuTile)).toList();
      expect(tiles.firstWhere((t) => t.item.key == 'plain').item.onLongPress, isNull);
      expect(tiles.firstWhere((t) => t.item.key == 'menu').item.onLongPress, isNotNull);
    });

    testWidgets('a tile with no action is still reachable, and does not strand the tiles past it', (tester) async {
      // Codex challenge, finding 3. `TvPageChipBar._step` walks past a capsule
      // that cannot take the focus; `TvMenuGrid._flatNeighbour` does not, and
      // `FocusableWrapper` reports the press handled whether or not the
      // callback moved anything. So the question is whether a grid can ever
      // hold a tile that refuses focus: Instellingen turns tiles off (an
      // update check in flight, iCloud unavailable) by passing a null
      // `onSelect`.
      final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
      addTearDown(nodes.dispose);

      await pump(
        tester,
        TvMenuGrid(
          nodes: nodes,
          columns: 3,
          automationInstance: 'test',
          sections: [
            TvMenuSection(
              items: [
                TvMenuItem(key: 'a', icon: Symbols.wifi_rounded, title: 'A', onSelect: () {}),
                const TvMenuItem(key: 'b', icon: Symbols.wifi_rounded, title: 'B'),
                TvMenuItem(key: 'c', icon: Symbols.wifi_rounded, title: 'C', onSelect: () {}),
              ],
            ),
          ],
        ),
      );

      nodes.get('a').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // A tile without an action keeps its place in the walk rather than being
      // skipped: it still says what the setting is, and a viewer scanning the
      // page must be able to stop on it. What must not happen is the press
      // being swallowed with nothing moving.
      expect(nodes.get('b').hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(nodes.get('c').hasPrimaryFocus, isTrue, reason: 'the tiles past it stay reachable');
    });
  });

  group('TvPageChipBar', () {
    testWidgets('LEFT and RIGHT step over a disabled capsule instead of stopping on it', (tester) async {
      // Logs turns Copy, Upload and Clear off when the buffer is empty but
      // leaves them in place, so the row does not reflow the moment a line
      // arrives. A walk that stopped on one of those would be a walk that
      // could not reach the level filter.
      final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
      addTearDown(nodes.dispose);

      await pump(
        tester,
        TvPageChipBar(
          nodes: nodes,
          chips: [
            TvPageChip(key: 'a', label: 'A', onSelect: () {}),
            const TvPageChip(key: 'b', label: 'B'),
            TvPageChip(key: 'c', label: 'C', onSelect: () {}),
          ],
        ),
      );

      nodes.get('a').requestFocus();
      await tester.pump();
      expect(nodes.get('a').hasPrimaryFocus, isTrue);

      // RIGHT from A. B cannot take the focus, so C does.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(nodes.get('c').hasPrimaryFocus, isTrue);
      expect(nodes.get('b').hasPrimaryFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(nodes.get('a').hasPrimaryFocus, isTrue);
    });

    testWidgets('the ends hold rather than wrap', (tester) async {
      final nodes = FocusMemoryTracker(debugLabelPrefix: 'test');
      addTearDown(nodes.dispose);

      await pump(
        tester,
        TvPageChipBar(
          nodes: nodes,
          chips: [
            TvPageChip(key: 'a', label: 'A', onSelect: () {}),
            TvPageChip(key: 'b', label: 'B', onSelect: () {}),
          ],
        ),
      );

      nodes.get('a').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      // A row that wraps in a page that also scrolls vertically makes it
      // impossible to tell where you are.
      expect(nodes.get('a').hasPrimaryFocus, isTrue);
    });
  });
}
