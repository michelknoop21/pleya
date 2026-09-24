import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The local folder keeps its scan for the whole session, so Home's reload
/// could never show a file added after the first scan. `invalidateScanCache`
/// is how that reload asks for a fresh scan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory root;
  late LocalFolderClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    root = Directory.systemTemp.createTempSync('pleya_local_scan_');
    File('${root.path}/Arrival (2016).mkv').writeAsStringSync('x');
    client = LocalFolderClient(
      connection: LocalFolderConnection(
        id: 'local-1',
        directoryUri: root.path,
        displayName: 'Films',
        libraryType: 'movies',
        createdAt: DateTime(2026),
      ),
      cache: ApiCache.forBackend(MediaBackend.local),
    );
  });

  tearDown(() async {
    root.deleteSync(recursive: true);
    await db.close();
  });

  Future<List<String?>> recentTitles() async => [for (final item in await client.fetchRecentlyAdded()) item.title];

  test('a file added after the first scan shows up once the scan is invalidated', () async {
    await client.scanAllItems();
    expect(await recentTitles(), ['Arrival']);

    File('${root.path}/Dune (2021).mkv').writeAsStringSync('x');
    expect(await recentTitles(), ['Arrival'], reason: 'the cache is served until someone invalidates it');

    client.invalidateScanCache();

    expect(await recentTitles(), containsAll(['Arrival', 'Dune']));
  });

  test('a file removed from the folder leaves the catalog on the rescan', () async {
    File('${root.path}/Dune (2021).mkv').writeAsStringSync('x');
    await client.scanAllItems();
    expect(await recentTitles(), containsAll(['Arrival', 'Dune']));

    File('${root.path}/Dune (2021).mkv').deleteSync();
    client.invalidateScanCache();

    expect(await recentTitles(), ['Arrival']);
  });

  test('a rescan of an unreadable folder keeps the last good catalog and retries', () async {
    await client.scanAllItems();
    final moved = root.renameSync('${root.path}_gone');

    client.invalidateScanCache();
    final during = await client.scanAllItems();
    moved.renameSync(root.path);

    expect([for (final item in during) item.title], ['Arrival'], reason: 'the browse view keeps its titles');

    File('${root.path}/Dune (2021).mkv').writeAsStringSync('x');
    expect(await recentTitles(), containsAll(['Arrival', 'Dune']), reason: 'the failed rescan is retried');
  });
}
