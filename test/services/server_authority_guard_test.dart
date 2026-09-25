/// The service half of the owner rule: a canonical write from a client that
/// is not allowed to manage the server fails before any HTTP request leaves,
/// so no menu entry, test seed or remote path can bypass the hidden UI.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

final _item = MediaItem(
  id: 'item-1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  serverId: 'server-1',
  libraryId: '1',
);

final Matcher _refused = throwsA(isA<MediaServerAuthException>().having((e) => e.statusCode, 'statusCode', 403));

JellyfinConnection _jellyfinConnection({bool admin = false}) => JellyfinConnection(
  id: 'jf-machine/user-a',
  baseUrl: 'https://jf.example.com',
  serverName: 'JF',
  serverMachineId: 'jf-machine',
  userId: 'user-a',
  userName: 'user-a',
  accessToken: 'token',
  deviceId: 'device',
  isAdministrator: admin,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  late List<http.Request> requests;
  late MockClient httpClient;

  setUp(() {
    requests = [];
    httpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 200, headers: {'content-type': 'application/json'});
    });
  });

  group('PlexClient', () {
    late PlexClient client;

    setUp(() {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);
      client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Pleya',
          version: 'test',
        ),
        serverId: ServerId('server-1'),
        serverName: 'Plex',
        httpClient: httpClient,
      );
      addTearDown(client.close);
    });

    final canonicalWrites = <String, Future<Object?> Function(PlexClient c)>{
      'deleteMediaItem': (c) => c.deleteMediaItem(_item),
      'updateMetadata': (c) => c.updateMetadata(sectionId: 1, ratingKey: '1', typeNumber: 1, title: 'x'),
      'applyMatch': (c) => c.applyMatch('1', guid: 'g'),
      'unmatchItem': (c) => c.unmatchItem('1'),
      'setArtworkFromUrl': (c) => c.setArtworkFromUrl('1', 'posters', 'https://x'),
      'uploadArtwork': (c) => c.uploadArtwork('1', 'posters', const [1, 2]),
      'updateMetadataPrefs': (c) => c.updateMetadataPrefs('1', const {'audioLanguage': 'nl'}),
      'deleteCollection': (c) => c.deleteCollection(_item),
      'createCollection': (c) => c.createCollection(libraryId: '1', title: 't', items: [_item]),
      'createCollectionFromUri': (c) => c.createCollectionFromUri(sectionId: '1', title: 't', uri: 'u'),
      'addToCollection': (c) => c.addToCollection(collectionId: 'c', items: [_item]),
      'addItemsToCollectionByUri': (c) => c.addItemsToCollectionByUri(collectionId: 'c', uri: 'u'),
      'removeFromCollection': (c) => c.removeFromCollection(collectionId: 'c', item: _item),
      'scanLibrary': (c) => c.scanLibrary('1'),
      'refreshLibraryMetadata': (c) => c.refreshLibraryMetadata('1'),
      'emptyLibraryTrash': (c) => c.emptyLibraryTrash('1'),
      'analyzeLibrary': (c) => c.analyzeLibrary('1'),
    };

    for (final MapEntry(key: name, value: call) in canonicalWrites.entries) {
      test('$name is refused without owner rights and sends nothing', () async {
        await expectLater(call(client), _refused);
        expect(requests, isEmpty);
      });
    }

    test('an unwired client refuses too (fail closed)', () async {
      client.canManageServerMetadata = null;
      await expectLater(client.deleteMediaItem(_item), _refused);
      expect(requests, isEmpty);
    });

    test('the owner reaches the server', () async {
      client.canManageServerMetadata = () => true;
      await client.deleteMediaItem(_item);
      expect(requests.single.method, 'DELETE');
    });

    test('user data is not guarded', () async {
      client.canManageServerMetadata = () => false;
      await client.rate(_item, 8);
      expect(requests.single.url.path, '/:/rate');
    });
  });

  group('JellyfinClient', () {
    late JellyfinClient client;

    setUp(() {
      client = JellyfinClient.forTesting(connection: _jellyfinConnection(), httpClient: httpClient);
      addTearDown(client.close);
    });

    final canonicalWrites = <String, Future<Object?> Function(JellyfinClient c)>{
      'deleteMediaItem': (c) => c.deleteMediaItem(_item),
      'deleteCollection': (c) => c.deleteCollection(_item),
      'createCollection': (c) => c.createCollection(libraryId: '1', title: 't', items: [_item]),
      'addToCollection': (c) => c.addToCollection(collectionId: 'c', items: [_item]),
      'removeFromCollection': (c) => c.removeFromCollection(collectionId: 'c', item: _item),
      'refreshLibraryMetadata': (c) => c.refreshLibraryMetadata('1'),
      'updateMetadataItem': (c) => c.updateMetadataItem('1', const {'Name': 'x'}),
      'downloadRemoteImage': (c) => c.downloadRemoteImage('1', imageType: 'Primary', imageUrl: 'https://x'),
      'uploadItemImage': (c) =>
          c.uploadItemImage('1', imageType: 'Primary', bytes: const [1], contentType: 'image/png'),
    };

    for (final MapEntry(key: name, value: call) in canonicalWrites.entries) {
      test('$name is refused without owner rights and sends nothing', () async {
        await expectLater(call(client), _refused);
        expect(requests, isEmpty);
      });
    }

    test('the administrator reaches the server', () async {
      client.canManageServerMetadata = () => true;
      await client.deleteMediaItem(_item);
      expect(requests.single.method, 'DELETE');
    });
  });

  group('MultiServerManager wiring', () {
    test('a registered client asks the manager for the owner rule', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final admin = JellyfinClient.forTesting(connection: _jellyfinConnection(admin: true), httpClient: httpClient);
      manager.debugRegisterJellyfinClientForTesting(admin);

      await admin.deleteMediaItem(_item);
      expect(requests, hasLength(1));

      // Borrowed: the same admin client loses the right with the binding.
      manager.setServerAuthorityRestrictions(serverIds: {'jf-machine'});
      await expectLater(admin.deleteMediaItem(_item), _refused);
      expect(requests, hasLength(1));
    });

    test('a client that is no longer the active one for its server is refused', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final old = JellyfinClient.forTesting(connection: _jellyfinConnection(admin: true), httpClient: httpClient);
      manager.debugRegisterJellyfinClientForTesting(old);
      manager.debugRegisterJellyfinClientForTesting(
        JellyfinClient.forTesting(
          connection: _jellyfinConnection(admin: true).copyWith(id: 'jf-machine/user-b', userId: 'user-b'),
          httpClient: httpClient,
        ),
      );

      await expectLater(old.deleteMediaItem(_item), _refused);
      expect(requests, isEmpty);
    });
  });
}
