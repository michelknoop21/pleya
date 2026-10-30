import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/named_fixtures.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

Future<http.Response> _get(PleyaFakeServer server, String path, {String? token = 'Bearer at-0'}) {
  final request = http.Request('GET', Uri.parse('http://fixture/pleya/v1$path'));
  if (token != null) request.headers['Authorization'] = token;
  return server.handle(request);
}

void main() {
  group('/verify/detail', () {
    test('answers what the film page reads, and nothing for a title without it', () async {
      final server = PleyaFakeServer();
      expect(applyNamedFixture(server, 'catalog.detail-movie.v1'), isTrue);

      final sintel = server.seededIds['movie/sintel']!;
      final detail = jsonDecode((await _get(server, '/verify/detail/$sintel')).body) as Map<String, dynamic>;
      expect(detail['external_ratings'], hasLength(4));
      expect(detail['reviews'], hasLength(4));
      expect(detail['roles'], hasLength(8));
      expect(detail['extras'], hasLength(2));

      final other = server.seededIds['movie/spring']!;
      expect((await _get(server, '/verify/detail/$other')).statusCode, 404);
    });

    test('stays out of the item, so an item answer remains the contract', () async {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.detail-movie.v1');

      final sintel = server.seededIds['movie/sintel']!;
      final item = jsonDecode((await _get(server, '/items/$sintel')).body) as Map<String, dynamic>;
      for (final key in ['external_ratings', 'reviews', 'extras', 'rows', 'file_info']) {
        expect(item.containsKey(key), isFalse, reason: key);
      }
    });

    test('a catalog seed clears it', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.detail-movie.v1');
      expect(server.verifyDetail, isNotEmpty);

      applyNamedFixture(server, 'catalog.empty.v1');
      expect(server.verifyDetail, isEmpty);
      expect(server.verifyTrakt, isEmpty);
    });

    test('Trakt answers without a token, and refuses one', () async {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.detail-movie.v1');
      final path = '/verify/trakt/movies/tt1727587/comments/likes';

      final answer = await _get(server, path, token: null);
      expect(answer.statusCode, 200);
      final comments = jsonDecode(answer.body) as List;
      expect(comments.where((comment) => comment['spoiler'] == true), hasLength(1));
      expect(comments.where((comment) => '${comment['comment']}'.contains('[spoiler]')), hasLength(1));

      expect((await _get(server, path)).statusCode, 401);
      expect((await _get(server, '/verify/trakt/movies/unknown/comments/likes', token: null)).statusCode, 404);
    });
  });

  group('catalog.detail-series.v1', () {
    test('two seasons, the first watched, the second under way', () async {
      final server = PleyaFakeServer();
      expect(applyNamedFixture(server, 'catalog.detail-series.v1'), isTrue);

      final show = server.seededIds['show/charge']!;
      expect(server.hubs['recently_added']!.first, show);
      final seasons = jsonDecode((await _get(server, '/items/$show/children')).body)['items'] as List;
      expect([for (final season in seasons) season['watched_episode_count']], [4, 2]);

      final second = server.seededIds['season/charge-s02']!;
      final episodes = jsonDecode((await _get(server, '/items/$second/children')).body)['items'] as List;
      expect([for (final episode in episodes) episode['user_state']['watched']], [true, true, false, false]);
      expect(episodes[2]['user_state']['position_ms'], greaterThan(0));
    });
  });
}
