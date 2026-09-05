import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/books/books_source.dart';
import 'package:pleya/providers/books_home_provider.dart';
import 'package:pleya/screens/books/books_search_screen.dart';
import 'package:provider/provider.dart';

/// Boeken zoeken draws three sections — books, authors, series — and used to
/// give every row in all three the same base id, `books.search.result`,
/// distinguished only by an instance suffix taken from that row's own key.
/// Those keys come from three different namespaces, so nothing stopped two of
/// them colliding, and in the demo source they do: `Book(id: 'dune')` and
/// `BookSeries(id: 'dune')` both exist (`lib/books/books_source.dart`).
///
/// Observed live in the evidence bundle for `books.search.layout`:
///
///     duplicates: ['books.search.result[dune]']
///     books.search.result[dune]    y=241   (the book)
///     books.search.result[dune]#2  y=679   (the series)
///
/// `AutomationRegistry` hands the second one a `#2` rather than dropping it,
/// so the run still passed — on whichever of the two registered first. That is
/// the same defect the three Discover landings had (see
/// `discover_scope_ids_test.dart`), one level down: an assertion resolves an
/// ambiguous id, and the `#2` suffix it falls back to is positional, so the
/// scenario silently changes meaning when the section order or the result
/// count does.
const Size _viewport = Size(393, 852);

Future<void> _pump(WidgetTester tester, {String query = 'dune'}) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final provider = BooksHomeProvider(source: const DemoBooksSource());
  await provider.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<BooksHomeProvider>.value(
      value: provider,
      child: MaterialApp(theme: ThemeData.dark(), home: const BooksSearchScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

/// Every id the mounted tree would register, in registration order.
///
/// Read off the widgets rather than off `AutomationRegistry`: `kPleyaVerify`
/// is a compile-time `false` in a plain `flutter test` run, so `AutomationNode`
/// registers nothing here. The widgets are in the tree either way, and the id
/// they *would* register is `id[instance]` — the same string
/// `_AutomationNodeState._resolvedId` builds.
List<String> _declaredIds(WidgetTester tester) => [
  for (final node in tester.widgetList<AutomationNode>(find.byType(AutomationNode)))
    if (node.id case final id?) node.instance != null ? '$id[${node.instance}]' : id,
];

void main() {
  testWidgets('a book and a series that share a key are two different ids', (tester) async {
    await _pump(tester);

    final ids = _declaredIds(tester);
    final duplicates = <String>[
      for (final id in ids.toSet())
        if (ids.where((other) => other == id).length > 1) id,
    ];

    expect(
      duplicates,
      isEmpty,
      reason:
          'ui_tree reports these under `duplicates` and suffixes the loser `#2`, so an assertion on the '
          'plain id resolves whichever row happens to be registered first',
    );
  });

  testWidgets('each section addresses its own id, and the book row keeps the scenario name', (tester) async {
    await _pump(tester);

    final ids = _declaredIds(tester);

    // `books.search.layout.yaml` asserts on the book row by this exact name.
    // Splitting the sections must not rename the one the scenario already
    // addresses — the same constraint `discover_scope_ids_test` puts on Home.
    expect(ids, contains('${AutomationIds.booksSearchResult}[dune]'));
    expect(ids, contains('${AutomationIds.booksSearchResultAuthor}[Frank Herbert]'));
    expect(ids, contains('${AutomationIds.booksSearchResultSeries}[dune]'));
  });

  test('all three are addressable through GET /v1/automation_ids', () {
    final catalogued = {for (final entry in AutomationIds.catalog()) entry['id'] as String};

    for (final id in [
      AutomationIds.booksSearchResult,
      AutomationIds.booksSearchResultAuthor,
      AutomationIds.booksSearchResultSeries,
    ]) {
      expect(
        catalogued,
        contains(id),
        reason: '$id is declared by a widget but not in the catalogue: `verify validate` rejects a scenario using it',
      );
      expect(
        AutomationIds.instanceableIds,
        contains(id),
        reason: '$id is registered with an instance suffix, so a scenario must be allowed to write `$id[x]`',
      );
    }
  });
}
