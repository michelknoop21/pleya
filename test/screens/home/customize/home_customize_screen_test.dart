/// HOME-R1: "Home aanpassen" on iPhone, iPad and Mac, driven through the real
/// screen over real providers (only the network edge is faked).
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/screens/home/customize/home_customize_row_tile.dart';
import 'package:pleya/screens/home/customize/home_customize_screen.dart';
import 'package:pleya/screens/settings/home_layout_screen.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/widgets/tv/tv_home_row_assembly.dart';

import '../../../test_helpers/home_rows_harness.dart';

const _own = HomeCustomRow(
  id: 'r1',
  kind: MediaKind.movie,
  name: 'Mijn rij',
  preferences: UnifiedCatalogPreferences.defaults,
);

/// Two Plex libraries of one server give two hubs with one identifier, plus an
/// ordinary hub.
final _twinHubs = [
  sectionHub('1', 'Recent toegevoegd', [homeFilm('a1', 'Dune')]),
  sectionHub('2', 'Recent toegevoegd', [homeFilm('b1', 'Moana')]),
  plainHub('movie.toprated', 'Top Rated', [homeFilm('c1', 'Casablanca')]),
];

void main() {
  late HomeRowsHarness h;

  setUp(installHomeRowEditingStub);
  tearDown(uninstallHomeRowEditingStub);

  Future<void> pumpScreen(
    WidgetTester tester, {
    HomeTestDevice device = HomeTestDevice.phone,
    List<HomeCustomRow> own = const [_own],
    HomeCustomRowContent? content,
    bool liveTv = false,
    Widget? home,
  }) async {
    h = (await tester.runAsync(
      () => HomeRowsHarness.boot(
        hubs: _twinHubs,
        own: own,
        liveTv: liveTv,
        loader: FixedRowLoader(content ?? HomeCustomRowContent.empty),
      ),
    ))!;
    addTearDown(h.dispose);
    tester.view.physicalSize = device.size;
    tester.view.devicePixelRatio = device.pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.app(home ?? const HomeCustomizeScreen(), platform: device.platform));
    await settle(tester);
  }

  List<String> homeTitles() => [
    for (final row in tvHomeOrderableRows(
      projection: h.projection,
      layout: h.layout,
      customRows: h.customRows,
      extraRows: h.extraRows,
    ))
      row.title,
  ];

  Finder tileOf(String title, {int occurrence = 0}) =>
      find.ancestor(of: find.text(title).at(occurrence), matching: find.byType(HomeCustomizeRowTile)).first;

  group('iPhone', () {
    testWidgets('lists the fixed rows locked and the rows Home draws, twin hubs separately', (tester) async {
      await pumpScreen(tester);
      expect(find.text(t.unifiedCatalog.homeRows.customize), findsOneWidget);
      expect(find.text(t.unifiedCatalog.homeRows.featured), findsOneWidget);
      expect(find.text(t.unifiedCatalog.homeRows.alwaysFirst), findsOneWidget);
      // The fixed rows have no drag handle: only the movable rows do.
      expect(find.byIcon(Symbols.drag_indicator_rounded), findsNWidgets(4));
      expect(find.byIcon(Symbols.lock_rounded), findsWidgets);
      // Twin hubs share one title and one layout id; both are listed, with no
      // duplicate-key failure.
      expect(find.text('Recent toegevoegd'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      expect(find.text(t.unifiedCatalog.homeRows.onHomeCount(shown: 4, total: 4)), findsOneWidget);
    });

    testWidgets('dragging the own row past twin hubs lands after both, and Home draws what the list shows', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(homeTitles().first, isNot('Top Rated'));
      final handle = find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.drag_indicator_rounded));
      // Down past the first twin, onto the second.
      await dragBy(tester, handle, const Offset(0, 160));
      expect(h.layout.order, ['nas:movie.recentlyadded', '#custom:r1', 'nas:movie.toprated']);
      expect(homeTitles(), ['Recent toegevoegd', 'Recent toegevoegd', 'Top Rated']);
    });

    testWidgets('a hidden row stays listed, dimmed, and the eye brings it back', (tester) async {
      await pumpScreen(tester);
      final eye = find.descendant(of: tileOf('Top Rated'), matching: find.byIcon(Symbols.visibility_rounded));
      await tester.tap(eye);
      await settle(tester);
      expect(h.layout.isRowHidden('nas:movie.toprated'), isTrue);
      expect(find.text('Top Rated'), findsOneWidget);
      expect(find.text(t.unifiedCatalog.homeRows.onHomeCount(shown: 3, total: 4)), findsOneWidget);
      await tester.tap(find.descendant(of: tileOf('Top Rated'), matching: find.byIcon(Symbols.visibility_off_rounded)));
      await settle(tester);
      expect(h.layout.isRowHidden('nas:movie.toprated'), isFalse);
    });

    testWidgets('hiding a twin hides both hubs of its identifier, because they are one id', (tester) async {
      await pumpScreen(tester);
      await tester.tap(
        find.descendant(of: tileOf('Recent toegevoegd'), matching: find.byIcon(Symbols.visibility_rounded)),
      );
      await settle(tester);
      expect(h.layout.isRowHidden('nas:movie.recentlyadded'), isTrue);
    });

    testWidgets('an empty own row stays in the list and says so', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining(t.unifiedCatalog.homeRows.emptyNote), findsOneWidget);
      expect(homeTitles(), isNot(contains('Mijn rij')), reason: 'Home does not draw an empty row');
    });

    testWidgets('an own row can be hidden without being deleted, and is hidden under #custom:<id>', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.more_horiz_rounded)));
      await settle(tester);
      await tester.tap(find.text(t.unifiedCatalog.homeRows.hideOnHome));
      await settle(tester);
      expect(h.layout.isRowHidden('#custom:r1'), isTrue);
      expect(h.layout.isRowHidden('hub:pleya:custom:r1'), isFalse, reason: 'identity pitfall');
      expect(h.layout.customRowById('r1'), isNotNull);
      expect(find.textContaining(t.unifiedCatalog.homeRows.hiddenNote), findsOneWidget);
    });

    testWidgets('Nu op tv is listed as an opt-in row, off until the eye turns it on', (tester) async {
      await pumpScreen(tester, liveTv: true);
      expect(find.text('Nu op tv'), findsOneWidget);
      expect(find.textContaining(t.unifiedCatalog.homeRows.optInNote), findsOneWidget);
      expect(h.layout.isRowHidden('#pleya:livetv'), isTrue);
      await tester.tap(find.descendant(of: tileOf('Nu op tv'), matching: find.byIcon(Symbols.visibility_off_rounded)));
      await settle(tester);
      expect(h.layout.isRowHidden('#pleya:livetv'), isFalse);
    });

    testWidgets('Verborgen items is a tile under the rows once something is hidden', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining(t.discover.hiddenItems), findsNothing);
      await tester.runAsync(
        () => h.hidden.hide(
          MediaItem(id: 'f1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Sintel', serverId: 'nas'),
        ),
      );
      await settle(tester);
      await tester.scrollUntilVisible(find.textContaining(t.discover.hiddenItems), 300);
      expect(find.textContaining(t.discover.hiddenItems), findsOneWidget);
    });

    testWidgets('each row announces its title and position, and offers move up and down to VoiceOver', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester);
      final node = tester.getSemantics(tileOf('Top Rated'));
      expect(node.label, contains('Top Rated'));
      expect(node.label, contains(t.unifiedCatalog.homeRows.rowPosition(position: 4, total: 4)));
      final data = node.getSemanticsData();
      final actions = [
        for (final id in data.customSemanticsActionIds ?? const <int>[]) CustomSemanticsAction.getAction(id)?.label,
      ];
      expect(actions, contains(t.unifiedCatalog.homeRows.moveUp));
      expect(actions, isNot(contains(t.unifiedCatalog.homeRows.moveDown)), reason: 'it is the last row');
      handle.dispose();
    });
  });

  group('a row of an offline server', () {
    // The offline row is in the stored order but not on screen: its server did
    // not answer, so Home has no row to draw.
    const stored = ['#custom:r1', 'nas:offline-row', 'nas:movie.recentlyadded', 'nas:movie.toprated'];

    testWidgets('keeps its saved place when a visible row is dragged, also after a restart', (tester) async {
      await pumpScreen(tester);
      await tester.runAsync(() => h.layout.setOrder(stored));
      await settle(tester);

      // Drag Top Rated to the top.
      final handle = find.descendant(of: tileOf('Top Rated'), matching: find.byIcon(Symbols.drag_indicator_rounded));
      await dragBy(tester, handle, const Offset(0, -330));
      expect(h.layout.order, contains('nas:offline-row'));
      expect(h.layout.order.first, 'nas:movie.toprated');
      // The offline row still sits behind the row it followed.
      expect(h.layout.order.indexOf('nas:offline-row'), h.layout.order.indexOf('#custom:r1') + 1);

      // A restart: a fresh provider reads the same order back from storage.
      final reloaded = await tester.runAsync(() async {
        final provider = HomeLayoutProvider();
        await provider.ensureInitialized();
        final order = provider.order;
        provider.dispose();
        return order;
      });
      expect(reloaded, h.layout.order);
    });

    testWidgets('keeps its saved place when a visible row is hidden', (tester) async {
      await pumpScreen(tester);
      await tester.runAsync(() => h.layout.setOrder(stored));
      await settle(tester);
      await tester.tap(find.descendant(of: tileOf('Top Rated'), matching: find.byIcon(Symbols.visibility_rounded)));
      await settle(tester);
      expect(h.layout.order, stored);
      expect(h.layout.isRowHidden('nas:movie.toprated'), isTrue);
    });
  });

  group('settings tile', () {
    testWidgets('Instellingen > Indeling van Home opens the same screen', (tester) async {
      await pumpScreen(tester, home: const HomeLayoutScreen());
      expect(find.byType(HomeCustomizeScreen), findsOneWidget);
    });
  });

  group('iPad', () {
    testWidgets('lists one row per server hub (what the iPad Home draws), twins as one block', (tester) async {
      await pumpScreen(tester, device: HomeTestDevice.tablet);
      expect(find.text('Recent toegevoegd'), findsOneWidget, reason: 'same identity, one block');
      expect(find.text(t.unifiedCatalog.homeRows.dragIntroTablet), findsOneWidget);
      expect(find.text('Top Rated'), findsOneWidget);
    });

    testWidgets('tapping an own row opens its wizard beside the list', (tester) async {
      await pumpScreen(tester, device: HomeTestDevice.tablet);
      await tester.tap(tileOf('Mijn rij'));
      await settle(tester);
      expect(find.text(t.unifiedCatalog.homeRows.wizardEditTitle), findsOneWidget);
      // The list stays on screen next to it.
      expect(find.text('Top Rated'), findsOneWidget);
    });
  });

  group('Mac', () {
    testWidgets('own rows get an Edit button, and a row can be dragged with the mouse', (tester) async {
      await pumpScreen(tester, device: HomeTestDevice.mac);
      expect(find.text(t.unifiedCatalog.homeRows.dragIntroDesktop), findsOneWidget);
      expect(find.widgetWithText(FilledButton, t.unifiedCatalog.homeRows.edit), findsOneWidget);
      final handle = find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.drag_indicator_rounded));
      await dragBy(tester, handle, const Offset(0, 100), mouse: true);
      expect(h.layout.order.first, isNot('#custom:r1'));
    });
  });
}

/// Pumps until storage writes (which never complete under the widget test's
/// fake clock) have landed.
Future<void> settle(WidgetTester tester) async {
  // Long enough for a sheet or a dialog to finish its own transition, then for
  // what the choice kicked off (a write) to land, then for the redraw.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  for (var i = 0; i < 2; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> dragBy(WidgetTester tester, Finder handle, Offset by, {bool mouse = false}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
  );
  await tester.pump(const Duration(milliseconds: 50));
  const steps = 8;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(by / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 30));
  }
  await gesture.up();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}
