import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/discover_snapshot.dart';
import 'package:pleya/services/plex_api_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MediaItem item(String id) =>
      MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie $id', serverId: 'srv-1');

  test('save/load round-trips on-deck, hubs, and latest movies', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);

    final hub = MediaHub(
      id: 'hub-1',
      identifier: 'home.recent',
      title: 'Recently Added',
      type: 'movie',
      items: [item('a'), item('b')],
      size: 2,
      serverId: 'srv-1',
      serverName: 'Server',
    );
    await DiscoverSnapshot(onDeck: [item('deck')], hubs: [hub], latestMovies: [item('new')]).save();

    final loaded = await DiscoverSnapshot.load();
    expect(loaded, isNotNull);
    expect(loaded!.onDeck.single.id, 'deck');
    expect(loaded.latestMovies.single.title, 'Movie new');
    final loadedHub = loaded.hubs.single;
    expect(loadedHub.title, 'Recently Added');
    expect(loadedHub.identifier, 'home.recent');
    expect([for (final i in loadedHub.items) i.id], ['a', 'b']);
    expect(loadedHub.items.first.serverId, 'srv-1');
  });

  test('load returns null when nothing is stored or cache is unavailable', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    expect(await DiscoverSnapshot.load(), isNull);
  });
}
