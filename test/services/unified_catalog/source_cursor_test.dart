import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';

MediaLibrary _library(String id, {required String serverId, MediaKind kind = MediaKind.movie, bool hidden = false}) =>
    MediaLibrary(
      id: id,
      backend: MediaBackend.plex,
      title: 'Library $id',
      kind: kind,
      hidden: hidden,
      serverId: serverId,
      serverName: serverId,
    );

void main() {
  group('eligibleCatalogLibraries', () {
    test('restricts to the requested kind', () {
      final result = eligibleCatalogLibraries(
        libraries: [
          _library('movies', serverId: 's1', kind: MediaKind.movie),
          _library('shows', serverId: 's1', kind: MediaKind.show),
        ],
        kind: MediaKind.movie,
        isServerVisible: (_) => true,
        hiddenLibraryKeys: const {},
      );

      expect(result.map((l) => l.libraryId), ['movies']);
    });

    test('excludes a library on a server the active profile has hidden', () {
      final result = eligibleCatalogLibraries(
        libraries: [
          _library('lib-visible', serverId: 'visible'),
          _library('lib-hidden-server', serverId: 'hidden'),
        ],
        kind: MediaKind.movie,
        isServerVisible: (id) => id.value == 'visible',
        hiddenLibraryKeys: const {},
      );

      expect(result.map((l) => l.libraryId), ['lib-visible']);
    });

    test('excludes a library the user hid, even though its server is visible', () {
      final result = eligibleCatalogLibraries(
        libraries: [
          _library('lib-1', serverId: 's1'),
          _library('lib-2', serverId: 's1'),
        ],
        kind: MediaKind.movie,
        isServerVisible: (_) => true,
        hiddenLibraryKeys: {'s1:lib-2'},
      );

      expect(result.map((l) => l.libraryId), ['lib-1']);
    });

    test('a library missing its serverId is never eligible', () {
      final noServer = MediaLibrary(id: 'orphan', backend: MediaBackend.plex, title: 'Orphan', kind: MediaKind.movie);

      final result = eligibleCatalogLibraries(
        libraries: [noServer],
        kind: MediaKind.movie,
        isServerVisible: (_) => true,
        hiddenLibraryKeys: const {},
      );

      expect(result, isEmpty);
    });

    test('carries the library fields a CatalogLibrary needs', () {
      final result = eligibleCatalogLibraries(
        libraries: [_library('movies', serverId: 's1')],
        kind: MediaKind.movie,
        isServerVisible: (_) => true,
        hiddenLibraryKeys: const {},
      );

      expect(result.single.serverId, ServerId('s1'));
      expect(result.single.libraryId, 'movies');
      expect(result.single.libraryTitle, 'Library movies');
      expect(result.single.backend, MediaBackend.plex);
    });
  });

  group('UnifiedSourceCursor', () {
    UnifiedSourceCursor cursorFor(String serverId, String libraryId) => UnifiedSourceCursor((
      serverId: ServerId(serverId),
      serverName: serverId,
      libraryId: libraryId,
      libraryTitle: libraryId,
      backend: MediaBackend.plex,
    ));

    test('libraryGlobalKey combines server and library id', () {
      expect(cursorFor('s1', 'lib-1').libraryGlobalKey, 's1:lib-1');
    });

    test('isFetchable is false once exhausted or while a fetch is in flight', () {
      final cursor = cursorFor('s1', 'lib-1');
      expect(cursor.isFetchable, isTrue);

      cursor.fetchInFlight = true;
      expect(cursor.isFetchable, isFalse);
      cursor.fetchInFlight = false;

      cursor.exhausted = true;
      expect(cursor.isFetchable, isFalse);
    });

    test("popHead removes and returns the buffer's first item, FIFO", () {
      final cursor = cursorFor('s1', 'lib-1');
      final a = MediaItem(id: 'a', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'A', serverId: 's1');
      final b = MediaItem(id: 'b', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'B', serverId: 's1');
      cursor.buffer.addAll([a, b]);

      expect(cursor.head, a);
      expect(cursor.popHead(), a);
      expect(cursor.head, b);
      expect(cursor.hasBufferedItem, isTrue);
      cursor.popHead();
      expect(cursor.hasBufferedItem, isFalse);
    });
  });
}
