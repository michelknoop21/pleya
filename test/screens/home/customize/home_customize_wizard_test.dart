/// HOME-R1: creating, editing and deleting an own row from "Home aanpassen",
/// and the quick menu of a row header. Same three steps as the tvOS wizard,
/// with a preview that is a real query (here: the test's own answer).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/home/customize/home_customize_entry.dart';
import 'package:pleya/screens/home/customize/home_customize_row_tile.dart';
import 'package:pleya/screens/home/customize/home_customize_screen.dart';
import 'package:pleya/screens/home/customize/home_row_wizard_view.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/home_layout_entries.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/widgets/app_menu.dart';

import '../../../test_helpers/home_rows_harness.dart';
import 'home_customize_screen_test.dart' show settle;

const _own = HomeCustomRow(
  id: 'r1',
  kind: MediaKind.movie,
  name: 'Mijn rij',
  preferences: UnifiedCatalogPreferences.defaults,
);

final _hubs = [
  plainHub('movie.recent', 'Recent', [homeFilm('a1', 'Dune')]),
  plainHub('movie.toprated', 'Top Rated', [homeFilm('c1', 'Casablanca')]),
];

void main() {
  late HomeRowsHarness h;
  final previewCalls = <HomeCustomRow>[];

  HomeCustomRowContent found() => HomeCustomRowContent(groups: [homeGroup('x1'), homeGroup('x2')], isExact: true);

  Future<void> pumpScreen(
    WidgetTester tester, {
    HomeTestDevice device = HomeTestDevice.phone,
    List<HomeCustomRow> own = const [_own],
    HomeCustomRowContent? preview,
    HomeCustomRowContent? rowContent,
    Future<HomeCustomRowContent> Function()? previewRequest,
    Widget? home,
  }) async {
    previewCalls.clear();
    installHomeRowEditingStub(
      preview: (draft) async {
        previewCalls.add(draft);
        if (previewRequest != null) return previewRequest();
        return preview ?? HomeCustomRowContent.empty;
      },
    );
    h = (await tester.runAsync(
      () =>
          HomeRowsHarness.boot(hubs: _hubs, own: own, loader: FixedRowLoader(rowContent ?? HomeCustomRowContent.empty)),
    ))!;
    addTearDown(h.dispose);
    tester.view.physicalSize = device.size;
    tester.view.devicePixelRatio = device.pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(h.app(home ?? const HomeCustomizeScreen(), platform: device.platform));
    await settle(tester);
  }

  tearDown(uninstallHomeRowEditingStub);

  final home = t.unifiedCatalog.homeRows;
  Finder tileOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(HomeCustomizeRowTile)).first;

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await settle(tester);
  }

  group('new row (iPhone)', () {
    testWidgets('three steps like tvOS: name and kind, filters with five lines, preview', (tester) async {
      await pumpScreen(tester, preview: found());
      await tester.tap(find.text(home.newRow));
      await settle(tester);
      expect(find.text(home.wizardTitle), findsOneWidget);
      expect(find.text('${home.stepOf(step: 1)} · ${home.stepName}'), findsOneWidget);
      expect(find.text(t.unifiedCatalog.moviesTitle), findsWidgets);

      await tapText(tester, home.next);
      expect(find.text('${home.stepOf(step: 2)} · ${home.stepFilters}'), findsOneWidget);
      for (final line in [home.status, home.genre, home.year, home.sources, home.sorting]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }

      await tapText(tester, home.next);
      expect(find.text('${home.stepOf(step: 3)} · ${home.stepPreview}'), findsOneWidget);
      expect(previewCalls, hasLength(1), reason: 'the preview is a real query, asked once on entering step 3');
      expect(find.text(home.addRow), findsOneWidget);
      expect(find.text(home.landsBelowContinue), findsOneWidget);
    });

    testWidgets('a name and a found preview save the row in front, under #custom:<id>', (tester) async {
      await pumpScreen(tester, own: const [], preview: found());
      await tester.tap(find.text(home.newRow));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Sci-fi avond');
      await tapText(tester, home.next);
      await tapText(tester, home.next);
      await tapText(tester, home.addRow);

      final saved = h.layout.customRows.single;
      expect(saved.name, 'Sci-fi avond');
      expect(saved.kind, MediaKind.movie);
      expect(h.layout.hiddenRowIds, isNot(contains(saved.layoutRowId)));
      // Back on the list, the new row is there.
      expect(find.text('Sci-fi avond'), findsOneWidget);
    });

    testWidgets('an empty preview cannot be saved: the way forward is the filters', (tester) async {
      await pumpScreen(tester, own: const [], preview: HomeCustomRowContent.empty);
      await tester.tap(find.text(home.newRow));
      await settle(tester);
      await tapText(tester, home.next);
      await tapText(tester, home.next);

      expect(find.text(home.emptyPreviewTitle), findsOneWidget);
      expect(find.text(home.emptyPreviewBody), findsOneWidget);
      expect(find.text(home.addRow), findsNothing, reason: 'C4: an empty row is never saved');
      await tapText(tester, home.adjustFilters);
      expect(find.text('${home.stepOf(step: 2)} · ${home.stepFilters}'), findsOneWidget);
      expect(h.layout.customRows, isEmpty);
    });

    testWidgets('NEGATIVE CONTROL: Annuleren on step 1 writes nothing', (tester) async {
      await pumpScreen(tester, own: const [], preview: found());
      await tester.tap(find.text(home.newRow));
      await settle(tester);
      await tapText(tester, t.common.cancel);
      expect(h.layout.customRows, isEmpty);
      expect(find.byType(HomeRowWizardView), findsNothing);
    });

    testWidgets('Series as the kind is what is saved', (tester) async {
      await pumpScreen(tester, own: const [], preview: found());
      await tester.tap(find.text(home.newRow));
      await settle(tester);
      await tapText(tester, t.unifiedCatalog.seriesTitle);
      await tapText(tester, home.next);
      await tapText(tester, home.next);
      await tapText(tester, home.addRow);
      expect(h.layout.customRows.single.kind, MediaKind.show);
    });
  });

  testWidgets('failed shared preview stops loading and can retry without saving', (tester) async {
    var attempts = 0;
    await pumpScreen(
      tester,
      own: const [],
      previewRequest: () async {
        if (++attempts == 1) throw StateError('fixture preview failure');
        return found();
      },
    );
    await tester.tap(find.text(home.newRow));
    await settle(tester);
    await tapText(tester, home.next);
    await tapText(tester, home.next);
    expect(find.text(t.common.error), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(h.layout.customRows, isEmpty);
    await tapText(tester, home.adjustFilters);
    await tapText(tester, home.next);
    await tapText(tester, home.addRow);
    expect(h.layout.customRows, hasLength(1));
    expect(attempts, 2);
  });

  group('edit and delete', () {
    testWidgets('editing keeps the id and the place of the row', (tester) async {
      await pumpScreen(tester, preview: found());
      await tester.runAsync(() => h.layout.setOrder(['nas:movie.recent', '#custom:r1', 'nas:movie.toprated']));
      await settle(tester);
      await tester.tap(find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.more_horiz_rounded)));
      await settle(tester);
      await tapText(tester, home.edit);
      expect(find.byType(HomeRowWizardView), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Andere naam');
      await tapText(tester, home.next);
      await tapText(tester, home.next);
      await tapText(tester, home.saveRow);

      final row = h.layout.customRowById('r1')!;
      expect(row.name, 'Andere naam');
      expect(h.layout.customRows, hasLength(1));
      expect(h.layout.order, ['nas:movie.recent', '#custom:r1', 'nas:movie.toprated']);
    });

    testWidgets('deleting asks first; Annuleren keeps the row', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.more_horiz_rounded)));
      await settle(tester);
      await tapText(tester, home.remove);
      expect(find.text(home.removeTitle), findsOneWidget);
      expect(find.textContaining('Mijn rij'), findsWidgets);
      await tapText(tester, t.common.cancel);
      expect(h.layout.customRowById('r1'), isNotNull);
    });

    testWidgets('confirming removes the row and every preference that named it', (tester) async {
      await pumpScreen(tester);
      await tester.runAsync(() async {
        await h.layout.setOrder(['#custom:r1', 'nas:movie.recent', 'nas:movie.toprated']);
        await h.layout.setRowHidden('#custom:r1', true);
      });
      await settle(tester);
      await tester.tap(find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.more_horiz_rounded)));
      await settle(tester);
      await tapText(tester, home.remove);
      // The confirmation's own button, not the menu item behind it.
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(home.remove)));
      await settle(tester);

      expect(h.layout.customRowById('r1'), isNull);
      expect(h.layout.order, ['nas:movie.recent', 'nas:movie.toprated']);
      expect(h.layout.hiddenRowIds, isNot(contains('#custom:r1')));
      expect(find.text('Mijn rij'), findsNothing);
    });

    testWidgets('a backend row has no Bewerken or Verwijderen: it only has the eye', (tester) async {
      await pumpScreen(tester);
      expect(find.descendant(of: tileOf('Top Rated'), matching: find.byIcon(Symbols.more_horiz_rounded)), findsNothing);
      expect(
        find.descendant(of: tileOf('Top Rated'), matching: find.byIcon(Symbols.visibility_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('"Alle N in Films" carries the row\'s own count, N is what the filter yields now', (tester) async {
      await pumpScreen(tester, rowContent: found());
      expect(find.textContaining(home.titlesCount(count: 2)), findsOneWidget, reason: 'the row says how many it holds');
      await tester.tap(find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.more_horiz_rounded)));
      await settle(tester);
      expect(find.text(home.allInCatalogMenu(catalog: t.unifiedCatalog.moviesTitle)), findsOneWidget);
    });

    testWidgets('an empty own row offers no "Alle N" (there is nothing to open)', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.descendant(of: tileOf('Mijn rij'), matching: find.byIcon(Symbols.more_horiz_rounded)));
      await settle(tester);
      expect(find.textContaining(RegExp(r"^All in ")), findsNothing);
    });
  });

  group('iPad', () {
    testWidgets('the wizard runs beside the list and saves from there', (tester) async {
      await pumpScreen(tester, device: HomeTestDevice.tablet, own: const [], preview: found());
      await tester.tap(find.text(home.newRow));
      await settle(tester);
      // Three tabs instead of the progress bar.
      expect(find.text('1  ${home.stepName}'), findsOneWidget);
      expect(find.text('Top Rated'), findsOneWidget, reason: 'the list stays in view');
      await tapText(tester, home.next);
      await tapText(tester, home.next);
      await tapText(tester, home.addRow);
      expect(h.layout.customRows, hasLength(1));
      expect(find.byType(HomeRowWizardView), findsNothing, reason: 'the wizard column closes');
    });
  });

  group('Mac', () {
    testWidgets('the Edit button opens the wizard of that row', (tester) async {
      await pumpScreen(tester, device: HomeTestDevice.mac);
      await tester.tap(find.widgetWithText(FilledButton, home.edit));
      await settle(tester);
      expect(find.byType(HomeRowWizardView), findsOneWidget);
    });
  });

  group('quick menu of a row header', () {
    Future<void> openMenu(WidgetTester tester, List<String> ids, {Offset? anchor}) async {
      await tester.pumpWidget(
        h.app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showHomeRowQuickMenu(context, ids: ids, anchor: anchor),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          platform: TargetPlatform.iOS,
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('Omlaag moves the row one place down and writes every id', (tester) async {
      await pumpScreen(tester);
      await openMenu(tester, ['nas:movie.toprated']);
      expect(find.text(home.moveUp), findsOneWidget);
      expect(find.text(home.hideOnHome), findsOneWidget);
      expect(find.text(home.customize), findsOneWidget);
      await tester.tap(find.text(home.moveDown));
      await settle(tester);
      expect(h.layout.order, ['#custom:r1', 'nas:movie.recent', 'nas:movie.toprated']);
    });

    testWidgets('Omhoog on the first row is not offered', (tester) async {
      await pumpScreen(tester);
      await openMenu(tester, ['#custom:r1']);
      final up = tester.widget<AppMenuItemTile<HomeRowQuickAction>>(
        find.ancestor(of: find.text(home.moveUp), matching: find.byType(AppMenuItemTile<HomeRowQuickAction>)).first,
      );
      expect(up.item.enabled, isFalse, reason: 'nothing above the first row');
    });

    testWidgets('Verbergen op Home hides the row; its place in the list stays', (tester) async {
      await pumpScreen(tester);
      await openMenu(tester, ['nas:movie.toprated']);
      await tester.tap(find.text(home.hideOnHome));
      await settle(tester);
      expect(h.layout.isRowHidden('nas:movie.toprated'), isTrue);
    });

    testWidgets('a row that is hidden is skipped over: one press moves past the next visible row', (tester) async {
      await pumpScreen(tester);
      await tester.runAsync(() async {
        await h.layout.setOrder(['#custom:r1', 'nas:movie.recent', 'nas:movie.toprated']);
        await h.layout.setRowHidden('nas:movie.recent', true);
      });
      await settle(tester);
      await openMenu(tester, ['#custom:r1']);
      await tester.tap(find.text(home.moveDown));
      await settle(tester);
      // Past the hidden Recent and the visible Top Rated.
      expect(h.layout.order.last, '#custom:r1');
    });

    testWidgets('with a pointer position the menu is a popup at that spot (Mac)', (tester) async {
      await pumpScreen(tester, device: HomeTestDevice.mac);
      // The per-hub list this Home draws: own row first, then the hubs.
      final listed = [
        for (final e in homeLayoutEntries(layout: h.layout, customRows: h.customRows, backendHubs: h.discover.hubs))
          e.ids.first,
      ];
      expect(listed.first, '#custom:r1');
      await openMenu(tester, [listed[1]], anchor: const Offset(300, 200));
      expect(find.byType(PopupMenuItem<HomeRowQuickAction>), findsNWidgets(4));
      await tester.tap(find.text(home.moveDown));
      await settle(tester);
      expect(h.layout.order, [listed[0], listed[2], listed[1]]);
    });

    testWidgets('the entry line opens the same screen', (tester) async {
      await pumpScreen(tester, home: const Scaffold(body: HomeCustomizeEntryTile()));
      await tester.tap(find.text(home.customize));
      await settle(tester);
      expect(find.byType(HomeCustomizeScreen), findsOneWidget);
      // And Klaar closes it again without writing anything.
      await tapText(tester, home.done);
      expect(find.byType(HomeCustomizeScreen), findsNothing);
    });
  });
}
