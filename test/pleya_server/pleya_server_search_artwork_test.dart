import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/image_cache_service.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/pleya_server_mappers.dart';

import 'pleya_fake_server.dart';

void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  setUp(() {
    ArtworkAuthorizationRegistry.clear();
    server = PleyaFakeServer();
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    server.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
    server.addItem(
      id: 'movie-sea',
      kind: 'movie',
      title: 'The Sea Beast',
      libraryId: 'lib-films',
      durationMs: 6000000,
      posterId: 'art-sea',
    );
    server.addItem(id: 'show-seaside', kind: 'show', title: 'Seaside Hotel', libraryId: 'lib-series');
    server.addItem(id: 'season-1', kind: 'season', title: 'Season 1', parentId: 'show-seaside', index: 1);
    server.addItem(
      id: 'ep-searchers',
      kind: 'episode',
      title: 'The Searchers',
      parentId: 'season-1',
      index: 1,
      durationMs: 1320000,
    );
  });

  tearDown(() {
    client.close();
    ArtworkAuthorizationRegistry.clear();
  });

  group('search', () {
    test('finds movies, shows and episodes in one page', () async {
      client = await connected(server);
      final results = await client.searchItems('sea');
      expect(results.map((r) => r.kind).toSet(), {MediaKind.movie, MediaKind.show, MediaKind.episode});
      expect(results.map((r) => r.title), containsAll(['The Sea Beast', 'Seaside Hotel', 'The Searchers']));
    });

    test('sends no kind, which is what leaves seasons out (DEC-045)', () async {
      client = await connected(server);
      final results = await client.searchItems('season');
      expect(server.requests.any((r) => r.contains('/search')), isTrue);
      expect(server.requests.any((r) => r.contains('kind=')), isFalse);
      expect(results.map((r) => r.kind), isNot(contains(MediaKind.season)));
    });

    test('no hits is an empty list and not an error', () async {
      client = await connected(server);
      expect(await client.searchItems('zzzz'), isEmpty);
    });

    test('an empty query never reaches the wire', () async {
      client = await connected(server);
      final before = server.requests.length;
      expect(await client.searchItems('   '), isEmpty);
      expect(server.requests.length, before, reason: 'q has minLength 1, so an empty query is a 400 worth avoiding');
    });

    test('the limit is clamped to what the contract accepts', () async {
      client = await connected(server);
      await client.searchItems('sea', limit: 5000);
      expect(server.requests.any((r) => r.contains('limit=500')), isTrue);
    });

    test('a server that says it cannot search is not asked', () async {
      client = server.client();
      final before = server.requests.length;
      expect(await client.searchItems('sea'), isEmpty);
      expect(server.requests.length, before);
    });

    test('results carry the backend so a merged list stays attributable', () async {
      client = await connected(server);
      final results = await client.searchItems('sea');
      expect(results.every((r) => r.serverId == 'srv-1'), isTrue);
      expect(results.every((r) => r.serverName == 'Zolder'), isTrue);
    });
  });

  group('artwork', () {
    test('a mapper path becomes an absolute protocol URL', () async {
      client = await connected(server);
      final url = client.thumbnailUrl(PleyaServerMappers.artworkPath('art-sea'));
      expect(url, 'http://nas.lan:8832/pleya/v1/artwork/art-sea');
    });

    test('a width is passed through and a height is not, because the contract has no height', () async {
      client = await connected(server);
      final url = client.thumbnailUrl(PleyaServerMappers.artworkPath('art-sea'), width: 320, height: 480);
      expect(url, 'http://nas.lan:8832/pleya/v1/artwork/art-sea?width=320');
    });

    test('an oversized width is clamped rather than rejected by the server', () async {
      client = await connected(server);
      final url = client.thumbnailUrl(PleyaServerMappers.artworkPath('art-sea'), width: 99999);
      expect(url, contains('width=4096'));
    });

    test('a path from another backend yields nothing instead of a wrong URL', () async {
      client = await connected(server);
      expect(client.thumbnailUrl('/library/metadata/12345/thumb'), '');
      expect(client.thumbnailUrl(null), '');
      expect(client.thumbnailUrl(''), '');
    });

    test('a server that says it has no artwork produces no URL at all', () async {
      client = server.client();
      expect(client.thumbnailUrl(PleyaServerMappers.artworkPath('art-sea')), '');
    });

    test('an external URL passes through, because there is no image proxy', () async {
      client = await connected(server);
      expect(client.externalImageUrl('https://image.tmdb.org/x.jpg'), 'https://image.tmdb.org/x.jpg');
    });

    test('the token travels as a header and never as a query parameter', () async {
      client = await connected(server);
      final url = client.thumbnailUrl(PleyaServerMappers.artworkPath('art-sea'));
      expect(url, isNot(contains('token')));
      expect(url, isNot(contains('api_key')));

      final headers = await ArtworkAuthorizationRegistry.headersFor(Uri.parse(url));
      expect(headers['Authorization'], startsWith('Bearer '));
    });

    test('closing the client stops it answering for its origin', () async {
      client = await connected(server);
      final url = client.thumbnailUrl(PleyaServerMappers.artworkPath('art-sea'));
      client.close();
      expect(await ArtworkAuthorizationRegistry.headersFor(Uri.parse(url)), isEmpty);
      // The tearDown closes again; that has to stay harmless.
      client = await connected(server);
    });

    test('an origin nobody registered gets no headers', () async {
      client = await connected(server);
      expect(await ArtworkAuthorizationRegistry.headersFor(Uri.parse('https://image.tmdb.org/x.jpg')), isEmpty);
    });

    test('a supplier that fails yields no headers rather than failing the download', () async {
      client = await connected(server);
      ArtworkAuthorizationRegistry.register('http://broken.lan:1', () async => throw Exception('token gone'));
      expect(await ArtworkAuthorizationRegistry.headersFor(Uri.parse('http://broken.lan:1/x.png')), isEmpty);
    });
  });

  group('items carry artwork paths the client can resolve', () {
    test('a poster survives the round-trip from wire to URL', () async {
      client = await connected(server);
      final item = await client.fetchItem('movie-sea');
      expect(item!.thumbPath, isNotNull);
      expect(client.thumbnailUrl(item.thumbPath, width: 240), contains('/artwork/art-sea?width=240'));
    });
  });
}
