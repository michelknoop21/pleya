import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalFolderClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    final connection = LocalFolderConnection(
      id: 'local-1',
      directoryUri: 'file:///tmp/media',
      displayName: 'Test',
      createdAt: DateTime(2026),
    );
    client = LocalFolderClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
  });

  tearDown(() => db.close());

  MediaItem episode(int number) => MediaItem(
    id: 'ep-$number',
    backend: MediaBackend.local,
    kind: MediaKind.episode,
    title: 'ep$number',
    serverId: 'local-1',
    parentId: 'season-1',
    grandparentId: 'show-1',
    parentIndex: 1,
    index: number,
  );

  test('fetchChildren returns episodes in numeric watch order (regression: E5,E4 scrambled)', () async {
    // Seed in scrambled directory order, including a two-digit episode.
    for (final n in [5, 4, 6, 10, 7]) {
      client.cacheItemForTest(episode(n));
    }
    final children = await client.fetchChildren('season-1');
    expect(children.map((e) => e.index), [4, 5, 6, 7, 10]);
  });

  test('fetchClientSideEpisodeQueue orders numerically, not lexicographically', () async {
    for (final n in [10, 2, 1]) {
      client.cacheItemForTest(episode(n));
    }
    final queue = await client.fetchClientSideEpisodeQueue('show-1');
    expect(queue!.map((e) => e.index), [1, 2, 10]);
  });

  test('a library page honours the kind the query asked for', () async {
    // B6 lets a library this build cannot classify take part in every catalog,
    // on the promise that the item-level filtering happens per query. This
    // client does no such filtering on the wire — there is no wire — so it has
    // to happen here, or Series lists that folder's films.
    client.cacheItemForTest(
      MediaItem(id: 'film-1', backend: MediaBackend.local, kind: MediaKind.movie, title: 'Dune', serverId: 'local-1'),
    );
    client.cacheItemForTest(
      MediaItem(
        id: 'show-1',
        backend: MediaBackend.local,
        kind: MediaKind.show,
        title: 'Severance',
        serverId: 'local-1',
      ),
    );

    final movies = await client.fetchLibraryPagedContent(
      'local-1',
      query: const LibraryQuery(kind: MediaKind.movie, limit: 50),
    );
    final shows = await client.fetchLibraryPagedContent(
      'local-1',
      query: const LibraryQuery(kind: MediaKind.show, limit: 50),
    );

    expect(movies.items.map((i) => i.id), ['film-1']);
    expect(shows.items.map((i) => i.id), ['show-1']);
  });
}
