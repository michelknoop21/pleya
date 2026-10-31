/// A-06c: Spring naar reads a title the way the merge sorts it, and keeps
/// loading until the letter is known.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/widgets/tv/tv_catalog_jump_index.dart';

import '../../test_helpers/tv_full_bleed_catalog_harness.dart';

MediaItem _titled(String title, {String? sort}) => MediaItem(
  id: title,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  titleSort: sort,
  serverId: 'nas',
  serverName: 'nas',
);

void main() {
  FullBleedHarness.setUpAllTv();

  group('letter of a title', () {
    test('reads the sort title, as the merge does', () {
      expect(tvCatalogJumpLetterOf(_titled('The Accountant', sort: 'Accountant')), 'A');
      expect(tvCatalogJumpLetterOf(_titled('Dune')), 'D');
      expect(tvCatalogJumpLetterOf(_titled('2 Guns')), '#');
      expect(tvCatalogJumpLetterOf(_titled('…')), '#');
    });
  });

  group('index for a letter', () {
    const ascending = ['#', 'A', 'A', 'C', 'K'];

    test('lands on the first title of the letter', () {
      expect(tvCatalogJumpIndex(ascending, 'A', descending: false, complete: true), 1);
      expect(tvCatalogJumpIndex(ascending, '#', descending: false, complete: true), 0);
    });

    test('a letter nothing starts with lands on the first title past it', () {
      expect(tvCatalogJumpIndex(ascending, 'B', descending: false, complete: true), 3);
    });

    test('runs the other way on a descending page', () {
      const descending = ['K', 'C', 'A', '#'];
      expect(tvCatalogJumpIndex(descending, 'D', descending: true, complete: true), 1);
    });

    test('past the loaded titles it asks for more, unless nothing more comes', () {
      expect(tvCatalogJumpIndex(ascending, 'Z', descending: false, complete: false), isNull);
      expect(tvCatalogJumpIndex(ascending, 'Z', descending: false, complete: true), 4);
      expect(tvCatalogJumpIndex(const [], 'Z', descending: false, complete: true), isNull);
    });
  });

  group('target in the catalog', () {
    Future<FullBleedHarness> titles(int count) => FullBleedHarness.create([
      for (var i = 0; i < count; i++) fakeMovie(i, title: '${String.fromCharCode(65 + i * 26 ~/ count)} title $i'),
    ]);

    test('loads on until the letter is there, and no further', () async {
      final h = await titles(500);
      final firstPage = h.catalog.snapshot.groups.length;
      expect(firstPage, lessThan(500), reason: 'one page is loaded before anything asks');

      final target = await tvCatalogJumpTarget(h.catalog, 'Y', descending: false);

      final item = h.catalog.snapshot.groups.firstWhere((g) => g.groupId == target).representativeSource.item;
      expect(item.title, startsWith('Y'));
      expect(h.catalog.snapshot.groups.length, greaterThan(firstPage));
      expect(h.client.queries.length, greaterThan(1));
    });

    test('stops at the limit and lands on the last card it has', () async {
      final h = await titles(500);
      final target = await tvCatalogJumpTarget(h.catalog, 'Y', descending: false, limit: 1);
      expect(target, h.catalog.snapshot.groups.last.groupId);
      expect(h.client.queries.length, 1, reason: 'the limit was already reached');
    });

    test('a catalog that stops growing ends the search', () async {
      final h = await titles(500);
      h.client.items = const [];
      final target = await tvCatalogJumpTarget(h.catalog, 'Y', descending: false);
      expect(target, h.catalog.snapshot.groups.last.groupId);
    });
  });
}
