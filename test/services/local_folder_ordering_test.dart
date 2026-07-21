import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
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
}
