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
  const fileUri = 'file:///tmp/media/clip.mkv';

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
    client.cacheItemForTest(
      MediaItem(id: fileUri, backend: MediaBackend.local, kind: MediaKind.movie, title: 'Clip', serverId: 'local-1'),
    );
  });

  tearDown(() => db.close());

  test('applyServerWatchState raises local progress from the server (continue on Plex → local)', () async {
    await client.reportPlaybackProgress(
      itemId: fileUri,
      position: const Duration(minutes: 1),
      duration: const Duration(minutes: 60),
    );
    // Server has newer progress (watched further on Plex).
    await client.applyServerWatchState(fileUri, viewOffsetMs: const Duration(minutes: 20).inMilliseconds);

    final cw = await client.fetchContinueWatching();
    expect(cw.single.viewOffsetMs, const Duration(minutes: 20).inMilliseconds);
  });

  test('applyServerWatchState never lowers newer local progress', () async {
    await client.reportPlaybackProgress(
      itemId: fileUri,
      position: const Duration(minutes: 30),
      duration: const Duration(minutes: 60),
    );
    await client.applyServerWatchState(fileUri, viewOffsetMs: const Duration(minutes: 5).inMilliseconds);

    final cw = await client.fetchContinueWatching();
    expect(cw.single.viewOffsetMs, const Duration(minutes: 30).inMilliseconds);
  });

  test('server watched flag drops the item from Continue Watching', () async {
    await client.reportPlaybackProgress(
      itemId: fileUri,
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 60),
    );
    await client.applyServerWatchState(fileUri, watched: true);
    expect(await client.fetchContinueWatching(), isEmpty);
  });
}
