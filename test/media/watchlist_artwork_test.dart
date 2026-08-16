import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/services/plex_watchlist_client.dart';
import 'package:pleya/utils/media_image_helper.dart';

/// Anything that could carry authentication into an image request.
const _authMarkers = ['x-plex-token', 'api_key', 'accesstoken', 'authorization', '/photo/:/transcode'];

String fixture(String name) => File('test/fixtures/watchlist/$name').readAsStringSync();

Future<List<PlexWatchlistItem>> capturedItems() async {
  final client = PlexWatchlistClient.forTesting(
    httpClient: MockClient((request) async {
      final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
      return http.Response(
        fixture(start == 0 ? 'watchlist_page1.json' : 'watchlist_page2.json'),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  addTearDown(client.dispose);
  return client.fetch(token: 'a-token-that-must-not-leak');
}

void main() {
  group('watchlist artwork stays headerless', () {
    test('every poster in the captured list is an absolute public URL', () async {
      final items = await capturedItems();

      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.posterUrl, isNotNull, reason: '${item.item.title} has no poster');
        expect(
          item.posterUrl!,
          startsWith('https://'),
          reason: 'a relative path would need a server, and a server means a token',
        );
      }
    });

    test('no poster reference carries authentication of any kind', () async {
      for (final item in await capturedItems()) {
        final lower = item.posterUrl!.toLowerCase();
        for (final marker in _authMarkers) {
          expect(lower, isNot(contains(marker)), reason: '${item.item.title} leaks $marker');
        }
      }
    });

    test('the sized URL the grid uses carries no token either', () async {
      for (final item in await capturedItems()) {
        final sized = MediaImageHelper.catalogPosterUrl(item.posterUrl, width: 300, height: 450).toLowerCase();

        expect(Uri.parse(sized).host, 'images.plex.tv');
        for (final marker in _authMarkers) {
          expect(sized, isNot(contains(marker)));
        }
      }
    });

    test('the token used to fetch the list never reaches an image URL', () async {
      const token = 'a-token-that-must-not-leak';

      for (final item in await capturedItems()) {
        expect(item.posterUrl, isNot(contains(token)));
        expect(MediaImageHelper.catalogPosterUrl(item.posterUrl, width: 300, height: 450), isNot(contains(token)));
      }
    });

    test('a poster is never handed to the transcoder path that appends a server token', () {
      const poster = 'https://metadata-static.plex.tv/1/gracenote/abc.jpg';

      // The guard is the client-less call. With a Plex client this same helper
      // would proxy through /photo/:/transcode and stamp X-Plex-Token into a
      // key that outlives the session.
      final passthrough = MediaImageHelper.getOptimizedImageUrl(
        thumbPath: poster,
        maxWidth: 300,
        maxHeight: 450,
        devicePixelRatio: 2,
      );

      expect(passthrough, poster);
      expect(MediaImageHelper.catalogPosterUrl(poster, width: 300, height: 450), isNot(contains('transcode')));
    });
  });
}
