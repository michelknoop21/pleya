/// HOME-R1: the rows "Home aanpassen" lists, and the order a move or a drag
/// writes back. Real providers; only the network edge is faked.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_layout_entries.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';

import '../../test_helpers/home_rows_harness.dart';

const _own = HomeCustomRow(
  id: 'r1',
  kind: MediaKind.movie,
  name: 'Mijn rij',
  preferences: UnifiedCatalogPreferences.defaults,
);

void main() {
  late HomeRowsHarness h;

  // Two Plex libraries of one server (one identifier, two hubs), one ordinary
  // hub, and one own row.
  final hubs = [
    sectionHub('1', 'Recent in Films', [homeFilm('a1', 'Dune')]),
    sectionHub('2', 'Recent in Kids', [homeFilm('b1', 'Moana')]),
    plainHub('movie.toprated', 'Top Rated', [homeFilm('c1', 'Casablanca')]),
  ];

  setUp(() async {
    h = await HomeRowsHarness.boot(hubs: hubs, own: [_own]);
  });
  tearDown(() => h.dispose());

  List<HomeLayoutEntry> unified() =>
      homeLayoutEntries(layout: h.layout, customRows: h.customRows, projection: h.projection);

  List<HomeLayoutEntry> perHub() =>
      homeLayoutEntries(layout: h.layout, customRows: h.customRows, backendHubs: h.discover.hubs);

  group('unified list (iPhone)', () {
    test('lists every row Home draws, twin hubs separately, the own row in front', () {
      final entries = unified();
      expect([for (final e in entries) e.title], ['Mijn rij', 'Recent in Films', 'Recent in Kids', 'Top Rated']);
      expect(entries[1].ids, entries[2].ids, reason: 'one server, one identifier, two rows');
    });

    test('an own row answers to #custom:<id> and never to hub:pleya:custom:<id>', () {
      final own = unified().first;
      expect(own.kind, HomeLayoutEntryKind.ownRow);
      expect(own.customRowId, 'r1');
      expect(own.ids, ['#custom:r1']);
      expect(own.ids.any((id) => id.startsWith('hub:pleya:')), isFalse);
    });

    test('a saved row that has not been asked yet is still listed, in front', () async {
      await h.layout.saveCustomRow(
        const HomeCustomRow(
          id: 'p1',
          kind: MediaKind.show,
          name: 'Nieuw',
          preferences: UnifiedCatalogPreferences.defaults,
        ),
      );
      final entries = unified();
      expect(entries.first.customRowId, 'p1');
      expect(entries.first.ids, ['#custom:p1']);
    });

    test('a row of one server is a server row; a global title leaves the name off', () {
      final top = unified().last;
      expect(top.kind, HomeLayoutEntryKind.serverRow);
      expect(top.serverName, isNull, reason: 'hoofdstuk 17.5: global row titles carry no server name');
    });
  });

  group('per-hub list (iPad and Mac)', () {
    test('lists one row per identity, so twin hubs are one block', () {
      final entries = perHub();
      expect([for (final e in entries) e.title], ['Mijn rij', 'Recent in Films', 'Top Rated']);
      expect(entries.first.ids, ['#custom:r1']);
    });

    test('server rows carry their server name', () {
      expect(perHub().last.serverName, 'NAS');
    });

    test('a hidden row stays in the list', () async {
      await h.layout.setRowHidden('nas:movie.toprated', true);
      expect(perHub().map((e) => e.title), contains('Top Rated'));
    });
  });

  group('Nu op tv (opt-in)', () {
    test('is listed as an opt-in Pleya row, hidden until turned on', () async {
      final live = await HomeRowsHarness.boot(hubs: hubs, liveTv: true);
      addTearDown(live.dispose);
      final entries = homeLayoutEntries(layout: live.layout, extraRows: live.extraRows, projection: live.projection);
      final nu = entries.firstWhere((e) => e.title == 'Nu op tv');
      expect(nu.optIn, isTrue);
      expect(nu.kind, HomeLayoutEntryKind.pleyaRow);
      expect(nu.ids.every(live.layout.isRowHidden), isTrue);
    });
  });

  group('order after a move', () {
    test('one step down lands where the list shows it, and keeps ids that are not on screen', () async {
      await h.layout.setOrder(['nas:movie.toprated', '#custom:r1', 'nas:movie.recentlyadded', 'nas:offline-row']);
      final entries = unified();
      expect([for (final e in entries) e.title], ['Top Rated', 'Mijn rij', 'Recent in Films', 'Recent in Kids']);
      final next = homeLayoutEntriesAfterReorder(entries, 0, 1, previous: h.layout.order);
      expect(next, ['#custom:r1', 'nas:movie.toprated', 'nas:movie.recentlyadded', 'nas:offline-row']);
    });

    test('NEGATIVE CONTROL: writing only what is on screen drops the offline row', () async {
      await h.layout.setOrder(['nas:movie.toprated', '#custom:r1', 'nas:movie.recentlyadded', 'nas:offline-row']);
      final entries = unified();
      final naive = [
        for (final e in [entries[1], entries[0], entries[2], entries[3]]) ...e.ids,
      ];
      expect(naive, isNot(contains('nas:offline-row')));
      final real = homeLayoutEntriesAfterReorder(entries, 0, 1, previous: h.layout.order)!;
      expect(real, contains('nas:offline-row'));
    });
  });

  group('order after a drag', () {
    test('an own row dragged across twin hubs lands on the block edge, never between the twins', () {
      final entries = unified(); // Mijn rij, Films, Kids, Top Rated
      final dropped = homeLayoutEntriesAfterReorder(entries, 0, 1, previous: const [])!;
      // Dropped "between" the twins: it goes after both, as one block.
      expect(dropped, ['nas:movie.recentlyadded', '#custom:r1', 'nas:movie.toprated']);
    });

    test('a long drag down to the end', () {
      final entries = unified();
      expect(homeLayoutEntriesAfterReorder(entries, 0, 3, previous: const []), [
        'nas:movie.recentlyadded',
        'nas:movie.toprated',
        '#custom:r1',
      ]);
    });

    test('a drag up from the end', () {
      final entries = unified();
      expect(homeLayoutEntriesAfterReorder(entries, 3, 0, previous: const []), [
        'nas:movie.toprated',
        '#custom:r1',
        'nas:movie.recentlyadded',
      ]);
    });

    test('a drag keeps the offline row where it was saved', () async {
      await h.layout.setOrder(['#custom:r1', 'nas:offline-row', 'nas:movie.recentlyadded', 'nas:movie.toprated']);
      final entries = unified();
      final next = homeLayoutEntriesAfterReorder(entries, 0, 3, previous: h.layout.order)!;
      // The hidden-by-offline id follows the row it came after, wherever that goes.
      expect(next, ['nas:movie.recentlyadded', 'nas:movie.toprated', '#custom:r1', 'nas:offline-row']);
    });

    test('dropping where it came from changes nothing', () {
      expect(homeLayoutEntriesAfterReorder(unified(), 2, 2, previous: const []), isNull);
    });
  });
}
