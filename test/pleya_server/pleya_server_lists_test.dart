import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/collection_ownership.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart' show FakeList;

import 'pleya_fake_server.dart';

/// S19.4 on the client side, through the public interface. The rights around a
/// role live in `pleya_server_manager_authority_test.dart`; here the guard is
/// open and the question is what goes over the wire.
void main() {
  late PleyaServerClient client;
  tearDown(() => client.close());

  MediaItem movie(String id) => MediaItem(id: id, backend: MediaBackend.pleyaServer, kind: MediaKind.movie);

  Future<PleyaFakeServer> connected({int pageSizeCap = 100, bool lists = true}) async {
    final server = PleyaFakeServer(pageSizeCap: pageSizeCap)
      ..listsCapability = lists
      ..usersCapability = true;
    for (final id in ['m1', 'm2', 'm3', 'm4']) {
      server.addItem(id: id, kind: 'movie', title: id, posterId: 'art-$id');
    }
    client = server.client();
    client.canManageCollections = () => true;
    await client.refreshCapabilities();
    return server;
  }

  group('a server without the flags', () {
    test('answers empty and false without a request', () async {
      final server = await connected(lists: false);
      final MediaServerClient public = client;
      expect(await public.fetchPlaylists(), isEmpty);
      expect(await public.fetchCollections('lib'), isEmpty);
      expect(await public.fetchPlaylistMetadata('p'), isNull);
      expect((await public.fetchPlaylistPage('p')).items, isEmpty);
      expect((await public.fetchCollectionPage('c')).items, isEmpty);
      expect(await public.createPlaylist(title: 'x', items: [movie('m1')]), isNull);
      expect(await public.createCollection(libraryId: 'lib', title: 'x', items: [movie('m1')]), isNull);
      expect(await public.addToPlaylist(playlistId: 'p', items: [movie('m1')]), isFalse);
      expect(await public.addToCollection(collectionId: 'c', items: [movie('m1')]), isFalse);
      expect(server.lists.writes, isEmpty);
    });

    test('a server with the flags reports them through the capabilities', () async {
      await connected();
      expect(client.capabilities.serverSidePlaylists, isTrue);
      expect(client.capabilities.serverSideCollections, isTrue);
    });
  });

  group('playlists', () {
    test('are made, filled, listed and read back in order', () async {
      final server = await connected();
      final MediaServerClient public = client;
      final created = await public.createPlaylist(title: 'Zondag', items: [movie('m2'), movie('m1')]);
      expect(created?.title, 'Zondag');
      expect(created?.leafCount, 2);
      expect(created?.thumbPath, 'pleya-artwork:art-m2');
      expect(created?.backend, MediaBackend.pleyaServer);

      expect((await public.fetchPlaylists()).map((p) => p.id), [created!.id]);
      expect((await public.fetchPlaylistPage(created.id)).items.map((i) => i.id), ['m2', 'm1']);
      expect((await public.fetchPlaylistItems(created.id, offset: 1, limit: 1)).map((i) => i.id), ['m1']);
      expect(server.lists.playlists[created.id]!.visibility, 'private');
    });

    test('have no smart or audio variant', () async {
      final server = await connected();
      server.lists.playlists['p'] = FakeList(id: 'p', title: 'p');
      expect(await client.fetchPlaylists(smart: true), isEmpty);
      expect(await client.fetchPlaylists(playlistType: 'audio'), isEmpty);
      expect(await client.fetchPlaylists(smart: false), hasLength(1));
    });

    test('take the episodes of a show, once each and in order', () async {
      final server = await connected();
      server.addItem(id: 'show', kind: 'show', title: 'Show');
      server.addItem(id: 's1', kind: 'season', title: 'S1', parentId: 'show');
      server.addItem(id: 'e1', kind: 'episode', title: 'E1', parentId: 's1');
      server.addItem(id: 'e2', kind: 'episode', title: 'E2', parentId: 's1');
      final list = (await client.createPlaylist(title: 'Binge', items: const []))!;
      final show = MediaItem(id: 'show', backend: MediaBackend.pleyaServer, kind: MediaKind.show);
      final episode = MediaItem(id: 'e1', backend: MediaBackend.pleyaServer, kind: MediaKind.episode);

      expect(await client.addToPlaylist(playlistId: list.id, items: [episode, show]), isTrue);
      expect(server.lists.playlists[list.id]!.itemIds, ['e1', 'e2']);
    });

    test('a move lands behind its neighbour, or first without one', () async {
      final server = await connected();
      final list = (await client.createPlaylist(
        title: 'Volgorde',
        items: [movie('m1'), movie('m2'), movie('m3'), movie('m4')],
      ))!;
      final ids = server.lists.playlists[list.id]!.itemIds;

      expect(
        await client.movePlaylistItem(playlistId: list.id, item: movie('m1'), newIndex: 2, afterItem: movie('m3')),
        isTrue,
      );
      expect(ids, ['m2', 'm3', 'm1', 'm4']);

      await client.movePlaylistItem(playlistId: list.id, item: movie('m4'), newIndex: 0, afterItem: null);
      expect(ids, ['m4', 'm2', 'm3', 'm1']);

      // The neighbour left in the meantime: the index is what remains of the intent.
      await client.movePlaylistItem(playlistId: list.id, item: movie('m2'), newIndex: 2, afterItem: movie('gone'));
      expect(ids, ['m4', 'm3', 'm2', 'm1']);
    });

    test('a move reads the whole list across pages and writes all of it', () async {
      final server = await connected(pageSizeCap: 1);
      final list = (await client.createPlaylist(title: 'Paginas', items: [movie('m1'), movie('m2'), movie('m3')]))!;
      await client.movePlaylistItem(playlistId: list.id, item: movie('m3'), newIndex: 0, afterItem: null);
      expect(server.lists.playlists[list.id]!.itemIds, ['m3', 'm1', 'm2']);
    });

    test('a row of a kind this build does not know survives a move', () async {
      final server = await connected();
      server.addItem(id: 'clip', kind: 'clip', title: 'Clip');
      final list = (await client.createPlaylist(title: 'Gemengd', items: [movie('m1')]))!;
      server.lists.playlists[list.id]!.itemIds.insert(0, 'clip');
      server.lists.playlists[list.id]!.itemIds.add('m2');
      await client.movePlaylistItem(playlistId: list.id, item: movie('m2'), newIndex: 0, afterItem: null);
      expect(server.lists.playlists[list.id]!.itemIds, ['m2', 'clip', 'm1']);
    });

    test('a move sends the revision it read, and a list that moved on refuses it', () async {
      final server = await connected();
      final list = (await client.createPlaylist(title: 'Twee', items: [movie('m1'), movie('m2'), movie('m3')]))!;
      final fake = server.lists.playlists[list.id]!;
      expect(
        await client.movePlaylistItem(playlistId: list.id, item: movie('m3'), newIndex: 0, afterItem: null),
        isTrue,
      );
      expect(fake.itemIds, ['m3', 'm1', 'm2']);

      // Between this client's read and its write somebody else wrote.
      server.lists.beforeNextListWrite = () => fake.revision++;
      await expectLater(
        client.movePlaylistItem(playlistId: list.id, item: movie('m1'), newIndex: 0, afterItem: null),
        throwsA(isA<MediaListChangedException>()),
      );
      expect(fake.itemIds, ['m3', 'm1', 'm2'], reason: 'a refused replace changes nothing');
    });

    test('a move of a row that is gone writes nothing', () async {
      final server = await connected();
      final list = (await client.createPlaylist(title: 'Weg', items: [movie('m1')]))!;
      server.lists.writes.clear();
      expect(
        await client.movePlaylistItem(playlistId: list.id, item: movie('m9'), newIndex: 0, afterItem: null),
        isFalse,
      );
      expect(server.lists.writes, isEmpty);
    });

    test('a failed fill leaves no empty playlist behind and says so', () async {
      final server = await connected();
      await expectLater(client.createPlaylist(title: 'Mislukt', items: [movie('missing')]), throwsA(anything));
      expect(server.lists.playlists, isEmpty);
    });

    test('remove and delete reach the server', () async {
      final server = await connected();
      final list = (await client.createPlaylist(title: 'Weg', items: [movie('m1'), movie('m2')]))!;
      expect(await client.removeFromPlaylist(playlistId: list.id, item: movie('m1')), isTrue);
      expect(server.lists.playlists[list.id]!.itemIds, ['m2']);
      expect(await client.deletePlaylist(list), isTrue);
      expect(server.lists.playlists, isEmpty);
    });

    test('a list of another account stays closed to a read', () async {
      await connected();
      expect(await client.fetchPlaylistMetadata('not-mine'), isNull);
    });
  });

  group('collections', () {
    test('are created for the whole server and filled in one go', () async {
      final server = await connected();
      final MediaServerClient public = client;
      final id = await public.createCollection(libraryId: 'lib', title: 'Klassiek', items: [movie('m1'), movie('m2')]);
      expect(server.lists.lastCollectionBody, {'title': 'Klassiek', 'visibility': 'everyone'});
      expect(server.lists.collections[id]!.itemIds, ['m1', 'm2']);

      final listed = await public.fetchCollections('lib');
      expect(listed.single.id, id);
      expect(listed.single.kind, MediaKind.collection);
      expect(listed.single.libraryId, 'lib');
      expect(listed.single.childCount, 2);
      expect(listed.single.thumbPath, 'pleya-artwork:art-m1');
      expect(listed.single.isOwnCollection, isTrue);
      expect((await public.fetchCollectionPage(id!)).items.map((i) => i.id), ['m1', 'm2']);
    });

    test('of someone else are marked, and the server refuses the write', () async {
      final server = await connected();
      server.lists.collections['c'] = FakeList(id: 'c', title: 'Van Sanne', isOwner: false, visibility: 'everyone');
      final listed = await client.fetchCollections('lib');
      expect(listed.single.isOwnCollection, isFalse);
      await expectLater(
        client.addToCollection(collectionId: 'c', items: [movie('m1')]),
        throwsA(isA<MediaServerAuthException>().having((e) => e.statusCode, 'status', 403)),
      );
      expect(server.lists.collections['c']!.itemIds, isEmpty);
    });

    test('page across the cursor and count what they have', () async {
      final server = await connected();
      for (final title in ['a', 'b', 'c']) {
        server.lists.collections[title] = FakeList(id: title, title: title);
      }
      final first = await client.fetchCollectionsPage('lib', start: 0, size: 2);
      expect(first.items.map((c) => c.id), ['a', 'b']);
      expect(first.totalCount, 3);
      final second = await client.fetchCollectionsPage('lib', start: 2, size: 2);
      expect(second.items.map((c) => c.id), ['c']);
    });

    test('a read that fails is a failure and not an empty shelf', () async {
      final server = await connected();
      server.lists.collections['c'] = FakeList(id: 'c', title: 'c');
      server.rejectCurrentAccessTokens = true;
      await expectLater(client.fetchCollections('lib'), throwsA(anything));
    });

    test('remove and delete reach the server', () async {
      final server = await connected();
      final id = (await client.createCollection(libraryId: 'lib', title: 'Weg', items: [movie('m1'), movie('m2')]))!;
      expect(await client.removeFromCollection(collectionId: id, item: movie('m1')), isTrue);
      expect(server.lists.collections[id]!.itemIds, ['m2']);
      final item = MediaItem(id: id, backend: MediaBackend.pleyaServer, kind: MediaKind.collection);
      expect(await client.deleteCollection(item), isTrue);
      expect(server.lists.collections, isEmpty);
    });
  });

  test('a playlist is a MediaPlaylist, so the shared screens take it as is', () async {
    await connected();
    final created = await client.createPlaylist(title: 'Scherm', items: const []);
    expect(created, isA<MediaPlaylist>());
    expect(created!.isEditable, isTrue);
    expect(created.smart, isFalse);
  });
}
