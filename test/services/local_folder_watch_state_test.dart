import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/utils/global_key_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() => db.close());

  LocalFolderClient buildClient(String connId) {
    final connection = LocalFolderConnection(
      id: connId,
      directoryUri: 'file:///tmp/media',
      displayName: 'Test',
      createdAt: DateTime(2026),
    );
    return LocalFolderClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
  }

  MediaItem movie(String connId, String fileUri) => MediaItem(
    id: fileUri,
    backend: MediaBackend.local,
    kind: MediaKind.movie,
    title: 'Loose File',
    serverId: connId,
    durationMs: 3600000,
  );

  test('progress written during playback is read back by Continue Watching (resume bug)', () async {
    const connId = 'local-1';
    const fileUri = 'file:///tmp/media/randomclip.mkv';
    final client = buildClient(connId);
    client.cacheItemForTest(movie(connId, fileUri));

    // Simulate watching 10 minutes in.
    await client.reportPlaybackProgress(
      itemId: fileUri,
      position: const Duration(minutes: 10),
      duration: const Duration(minutes: 60),
    );

    // A fresh client (reloads persisted state) must resume from the same key.
    final reopened = buildClient(connId);
    reopened.cacheItemForTest(movie(connId, fileUri));
    final continueWatching = await reopened.fetchContinueWatching();

    expect(continueWatching, hasLength(1));
    expect(continueWatching.single.id, fileUri);
    expect(continueWatching.single.viewOffsetMs, const Duration(minutes: 10).inMilliseconds);
  });

  test('finishing a file marks it watched under the read-side key (drops from Continue Watching)', () async {
    const connId = 'local-2';
    const fileUri = 'file:///tmp/media/a.mp4';
    final item = movie(connId, fileUri);

    // globalKey is "{connId}:{fileUri}"; report* must persist under the same key.
    expect(item.globalKey, buildGlobalKey(ServerId(connId), fileUri));

    final client = buildClient(connId);
    client.cacheItemForTest(item);
    // Watched past the threshold → stored as watched.
    await client.reportPlaybackStopped(
      itemId: fileUri,
      position: const Duration(minutes: 59),
      duration: const Duration(minutes: 60),
    );

    // A fresh client reads _watchedState[item.globalKey]; a watched item is
    // excluded from Continue Watching even though progress exists.
    final reopened = buildClient(connId);
    reopened.cacheItemForTest(item);
    expect(await reopened.fetchContinueWatching(), isEmpty);
  });
}
