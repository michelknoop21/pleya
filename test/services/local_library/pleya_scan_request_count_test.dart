import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';

import '../../pleya_server/pleya_fake_server.dart';

Map<String, int> _itemReads(PleyaFakeServer fake) {
  final counts = <String, int>{};
  for (final path in fake.requests) {
    final match = RegExp(r'/items/([^/?]+)$').firstMatch(path.split('?').first);
    if (match != null) counts.update(match[1]!, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a first scan reads each Pleya title once', () async {
    final fake = PleyaFakeServer();
    fake.addLibrary(id: 'films', title: 'Films', kind: 'movies');
    fake.addItem(id: 'm1', kind: 'movie', title: 'One', libraryId: 'films', year: 2001, externalIds: {'tmdb': 1});
    fake.addItem(id: 'm2', kind: 'movie', title: 'Two', libraryId: 'films', year: 2002);
    final client = fake.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    fake.requests.clear();
    final directory = await Directory.systemTemp.createTemp('pleya-scan-count-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalLibraryStore(directory);
    await store.load();

    await LocalLibrarySync(store: store).syncLibrary(
      const MediaLibrary(
        id: 'films',
        backend: MediaBackend.pleyaServer,
        title: 'Films',
        kind: MediaKind.movie,
        serverId: 'srv-1',
      ),
      client,
    );

    expect(_itemReads(fake), {'m1': 1, 'm2': 1});
  });

  test('a first scan of a series reads each title once', () async {
    final fake = PleyaFakeServer();
    fake.addLibrary(id: 'series', title: 'Series', kind: 'shows');
    fake.addItem(id: 'show', kind: 'show', title: 'Show', libraryId: 'series', year: 2020, externalIds: {'tmdb': 7});
    fake.addItem(id: 'season1', kind: 'season', title: 'Season 1', parentId: 'show', index: 1);
    for (var e = 1; e <= 3; e++) {
      fake.addItem(id: 'ep$e', kind: 'episode', title: 'Episode $e', parentId: 'season1', index: e);
    }
    final client = fake.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    fake.requests.clear();
    final directory = await Directory.systemTemp.createTemp('pleya-scan-count-');
    addTearDown(() => directory.delete(recursive: true));
    final store = LocalLibraryStore(directory);
    await store.load();

    await LocalLibrarySync(store: store).syncLibrary(
      const MediaLibrary(
        id: 'series',
        backend: MediaBackend.pleyaServer,
        title: 'Series',
        kind: MediaKind.show,
        serverId: 'srv-1',
      ),
      client,
    );

    expect(_itemReads(fake).values.where((n) => n > 1), isEmpty);
  });

  test('two pages of one season at once read their ancestors once', () async {
    final fake = PleyaFakeServer();
    fake.addLibrary(id: 'series', title: 'Series', kind: 'shows');
    fake.addItem(id: 'show', kind: 'show', title: 'Show', libraryId: 'series', year: 2020);
    fake.addItem(id: 'season1', kind: 'season', title: 'Season 1', parentId: 'show', index: 1);
    for (var e = 1; e <= 4; e++) {
      fake.addItem(id: 'ep$e', kind: 'episode', title: 'Episode $e', parentId: 'season1', index: e);
    }
    final client = fake.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    fake.requests.clear();

    await Future.wait([
      client.fetchChildrenPage('season1', start: 0, size: 2),
      client.fetchChildrenPage('season1', start: 2, size: 2),
    ]);

    expect(_itemReads(fake), {'season1': 1, 'show': 1});
  });
}
