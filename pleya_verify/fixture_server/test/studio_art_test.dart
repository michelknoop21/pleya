import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/named_fixtures.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:pleya_verify_fixture_server/src/fixtures/studio_art.dart';
import 'package:test/test.dart';

/// The sha256 of every studio-art file, as committed. A changed file is a
/// changed fixture: update the README and this table together, on purpose.
const _pinned = {
  'sintel-poster.jpg': '013a3208ddceee79523cf6fbeb29cb144a4a9c4c57a900be91e98c5752ede943',
  'sintel-backdrop.jpg': 'b049b5f08088daf99ece78f3c13e791553b539e9e06653fb8e8fb0f9c6ac4add',
  'bbb-poster.jpg': '91d3877534d90e392f33adf1c66ebc20549ffc45d7749cee42f57691d8bc1f2e',
  'bbb-backdrop.jpg': '53234d00ad260cd7b9c18e7fd08dec22ee282d23f2ed8effecdb479bc804b670',
  'tears-poster.jpg': '9536d5f611ace930406f04a1da90fa6531a28826de4f2f083bc8c52f3eb3ddf2',
  'tears-backdrop.jpg': 'a666c612a0dc28c27f85491ef8b85e91a04b192900a848864bcaa6f26839187c',
  'spring-poster.jpg': '4646ad5a91f73b51fc3d66b284708bc723a38c4951956a5f297285d64fea4daa',
  'spring-backdrop.jpg': '2c78a7e73ef162de5b743d30468c653dc4bee3e9f603efd3861f2e39b5e234f3',
  'charge-poster.jpg': '7405ced3cd77dd0d209eacce36750a7649ba48cbe844edb5b208d548debb1301',
  'charge-backdrop.jpg': '642aa2647027affb17ad485c7a0a4f896321591707438dec3c54aed83f0f3686',
  'coffeerun-poster.jpg': '6a8ec242cbae46cf4ede11b6cbd15d060df72bcf1796a12c84aa1f3f47ebaaed',
  'coffeerun-backdrop.jpg': '572ad3f84d41dbe4dde6195444015ed6820564b1f44493f9d2ec82706c5663bd',
};

/// Read by `catalog.detail-series.v1`, not by the film list.
const _logoSha256 = '95220e08a462a484bf1d069ce2bf0bc5105c932b97dfc322e0b3c981b2fc59c9';

/// An authorized GET, as the app sends it (`at-0` is the fake's first token).
Future<http.Response> _get(PleyaFakeServer server, String path) {
  final request = http.Request('GET', Uri.parse('http://fixture/pleya/v1$path'));
  request.headers['Authorization'] = 'Bearer at-0';
  return server.handle(request);
}

void main() {
  group('catalog.studio-art.v1', () {
    test('every file the fixture names is pinned, and serves its pinned bytes', () async {
      final server = PleyaFakeServer();
      expect(applyNamedFixture(server, 'catalog.studio-art.v1'), isTrue);

      final named = {
        for (final film in studioArtFilms) ...[film.poster, film.backdrop],
      };
      expect(named, unorderedEquals(_pinned.keys), reason: 'a film file without a pin, or a pin for no file');

      for (final film in studioArtFilms) {
        final id = server.seededIds['movie/${film.slug}']!;
        final poster = await _get(server, '/artwork/$id');
        final backdrop = await _get(server, '/artwork/$id-backdrop');
        expect(sha256.convert(poster.bodyBytes).toString(), _pinned[film.poster], reason: film.poster);
        expect(sha256.convert(backdrop.bodyBytes).toString(), _pinned[film.backdrop], reason: film.backdrop);
        expect(poster.headers['content-type'], 'image/jpeg');
      }
    });

    test('the logo of the series fixture is pinned too', () {
      expect(sha256.convert(studioArtBytes('charge-logo.png')).toString(), _logoSha256);
    });

    test('two seeds serve byte-identical artwork', () async {
      final a = PleyaFakeServer();
      final b = PleyaFakeServer();
      applyNamedFixture(a, 'catalog.studio-art.v1');
      applyNamedFixture(b, 'catalog.studio-art.v1');
      for (final film in studioArtFilms) {
        final id = a.seededIds['movie/${film.slug}']!;
        expect(b.seededIds['movie/${film.slug}'], id, reason: 'ids are minted from the slug, not from order or time');
        expect((await _get(a, '/artwork/$id')).bodyBytes, (await _get(b, '/artwork/$id')).bodyBytes);
      }
    });

    test('items carry a poster and a separate backdrop, and fill the two Home hubs', () async {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.studio-art.v1');
      final sintel = server.seededIds['movie/sintel']!;
      final item = jsonDecode((await _get(server, '/items/$sintel')).body) as Map<String, dynamic>;
      expect(item['title'], 'Sintel');
      expect(item['artwork'], {'poster_id': sintel, 'backdrop_id': '$sintel-backdrop'});
      expect(server.hubs['recently_added'], hasLength(studioArtFilms.length));
      expect(server.hubs['continue_watching'], [sintel, server.seededIds['movie/big-buck-bunny']]);
    });

    test('the catalog alone leaves the kijklijst empty', () async {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.studio-art.v1');
      final body = jsonDecode((await _get(server, '/verify/watchlist')).body) as Map<String, dynamic>;
      expect(body['item_ids'], isEmpty);
    });
  });

  group('watchlist.studio.v1', () {
    test('lists four films of the studio catalog, newest first', () async {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.studio-art.v1');
      expect(applyNamedFixture(server, 'watchlist.studio.v1'), isTrue);
      final body = jsonDecode((await _get(server, '/verify/watchlist')).body) as Map<String, dynamic>;
      expect(body['item_ids'], [
        for (final slug in ['spring', 'charge', 'tears-of-steel', 'coffee-run']) server.seededIds['movie/$slug'],
      ]);
    });

    test('refuses to seed without the studio catalog', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.mixed.v1');
      expect(applyNamedFixture(server, 'watchlist.studio.v1'), isFalse);
      expect(server.verifyWatchlistIds, isEmpty);
    });

    test('a later catalog seed clears it, so catalog.empty.v1 has no kijklijst', () async {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.studio-art.v1');
      applyNamedFixture(server, 'watchlist.studio.v1');
      applyNamedFixture(server, 'catalog.empty.v1');
      final body = jsonDecode((await _get(server, '/verify/watchlist')).body) as Map<String, dynamic>;
      expect(body['item_ids'], isEmpty);
    });
  });
}
