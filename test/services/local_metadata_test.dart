import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/local_server_match_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pickConfidentMatch matches a show by title for artwork enrichment', () {
    final local = MediaItem(
      id: 'show-local',
      backend: MediaBackend.local,
      kind: MediaKind.show,
      title: 'The Miniature Wife',
    );
    final match = LocalServerSyncBridge.pickConfidentMatch(local, [
      MediaItem(id: 'srv-show', backend: MediaBackend.plex, kind: MediaKind.show, title: 'The Miniature Wife'),
      MediaItem(id: 'other', backend: MediaBackend.plex, kind: MediaKind.show, title: 'Something Else'),
    ]);
    expect(match?.id, 'srv-show');
  });

  test('applyServerMetadata overlays poster and summary onto a local item', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);

    final connection = LocalFolderConnection(
      id: 'local-1',
      directoryUri: 'file:///tmp/media',
      displayName: 'Test',
      createdAt: DateTime(2026),
    );
    final client = LocalFolderClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
    const id = 'file:///tmp/media/clip.mkv';
    client.cacheItemForTest(
      MediaItem(id: id, backend: MediaBackend.local, kind: MediaKind.movie, title: 'Clip', serverId: 'local-1'),
    );

    client.applyServerMetadata(
      id,
      thumbUrl: 'https://plex.example/photo/thumb?X-Plex-Token=t',
      summary: 'A real description from Plex',
      year: 2024,
    );

    final item = await client.fetchItem(id);
    expect(item!.thumbPath, 'https://plex.example/photo/thumb?X-Plex-Token=t');
    expect(item.summary, 'A real description from Plex');
    expect(item.year, 2024);
  });
}
