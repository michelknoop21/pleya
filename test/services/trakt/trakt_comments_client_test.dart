import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/services/trakt/trakt_comments_client.dart';
import 'package:pleya/utils/external_ids.dart';

Map<String, Object?> _comment(
  int id,
  String text, {
  int likes = 0,
  bool spoiler = false,
  String user = 'marshal',
  String? created,
}) => {
  'id': id,
  'comment': text,
  'spoiler': spoiler,
  'review': false,
  'parent_id': 0,
  'likes': likes,
  'replies': 0,
  'created_at': created ?? '2026-10-16T12:00:00.000Z',
  'user': {'username': user, 'private': false, 'name': 'Real Name'},
};

http.Response _json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> requests;
  late Map<String, http.Response Function()> routes;

  TraktCommentsClient client({String clientId = 'app-key', DateTime Function()? now}) => TraktCommentsClient(
    clientId: clientId,
    now: now,
    httpClient: MockClient((request) async {
      requests.add(request);
      return routes[request.url.path]?.call() ?? _json(const [], 404);
    }),
  );

  setUp(() {
    requests = [];
    routes = {};
  });

  test('a film is read by its IMDb id, with the app key and no account', () async {
    routes['/movies/tt123/comments/likes'] = () => _json([_comment(1, 'Great', likes: 3)]);

    final comments = await client().movieComments(const ExternalIds(imdb: 'tt123', tmdb: 9));

    expect(comments!.single.text, 'Great');
    expect(comments.single.author, 'marshal');
    expect(comments.single.likes, 3);
    expect(comments.single.createdAt, DateTime.utc(2026, 10, 16, 12));
    final request = requests.single;
    expect(request.headers['trakt-api-key'], 'app-key');
    expect(request.headers['trakt-api-version'], '2');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.url.queryParameters, {'page': '1', 'limit': '30'});
  });

  test('without an IMDb id the TMDB id is looked up, as a film or as a series', () async {
    routes['/search/tmdb/42'] = () => _json([
      {
        'type': 'movie',
        'score': 1000,
        'movie': {
          'title': 'Not read',
          'ids': {'trakt': 77, 'slug': 'x'},
        },
      },
    ]);
    routes['/movies/77/comments/likes'] = () => _json([_comment(1, 'Found')]);

    final comments = await client().movieComments(const ExternalIds(tmdb: 42));

    expect(comments!.single.text, 'Found');
    expect(requests.first.url.path, '/search/tmdb/42');
    expect(requests.first.url.queryParameters['type'], 'movie');
  });

  test('a TMDB hit of another type is not this title', () async {
    routes['/search/tmdb/42'] = () => _json([
      {
        'type': 'show',
        'show': {
          'ids': {'trakt': 77},
        },
      },
    ]);

    expect(await client().movieComments(const ExternalIds(tmdb: 42)), isNull);
    expect(requests, hasLength(1));
  });

  test('a title without IMDb or TMDB id asks nothing: no match on a name', () async {
    expect(await client().movieComments(const ExternalIds(tvdb: 5)), isNull);
    expect(await client().showComments(const ExternalIds()), isNull);
    expect(requests, isEmpty);
  });

  test('without an app key nothing is asked', () async {
    final keyless = client(clientId: '');

    expect(keyless.isConfigured, isFalse);
    expect(await keyless.movieComments(const ExternalIds(imdb: 'tt1')), isNull);
    expect(requests, isEmpty);
  });

  test('spoilers stay out: the flag, and an inline tag in any case', () async {
    routes['/movies/tt1/comments/likes'] = () => _json([
      _comment(1, 'Clean', likes: 1),
      _comment(2, 'Flagged', spoiler: true, likes: 50),
      _comment(3, 'He dies [spoiler]at the end[/spoiler]', likes: 40),
      _comment(4, 'Shouted [SPOILER]twist[/SPOILER]', likes: 30),
      _comment(5, 'Half a tag [/spoiler]', likes: 20),
    ]);

    final comments = await client().movieComments(const ExternalIds(imdb: 'tt1'));

    expect(comments!.map((comment) => comment.id), [1]);
  });

  test('a series brings its seasons, newest five, most liked first over all of them', () async {
    routes['/shows/tt9/comments/likes'] = () => _json([_comment(1, 'Show', likes: 5)]);
    routes['/shows/tt9/seasons/7/comments/likes'] = () => _json([_comment(2, 'Seven', likes: 9)]);
    routes['/shows/tt9/seasons/3/comments/likes'] = () => _json([_comment(3, 'Three', likes: 1)]);

    final comments = await client().showComments(const ExternalIds(imdb: 'tt9'), seasons: [1, 2, 3, 4, 5, 6, 7]);

    expect(comments!.map((comment) => (comment.text, comment.season)), [('Seven', 7), ('Show', null), ('Three', 3)]);
    expect(requests.map((request) => request.url.path), isNot(contains('/shows/tt9/seasons/2/comments/likes')));
    expect(requests.map((request) => request.url.path), contains('/shows/tt9/seasons/3/comments/likes'));
  });

  test('neither a season that fails nor one Trakt does not know takes the series with it', () async {
    routes['/shows/tt9/comments/likes'] = () => _json([_comment(1, 'Show')]);
    routes['/shows/tt9/seasons/2/comments/likes'] = () => _json('down', 500);

    expect(await client().showComments(const ExternalIds(imdb: 'tt9'), seasons: [1]), isNotNull);
    expect(await client().showComments(const ExternalIds(imdb: 'tt9'), seasons: [2]), isNotNull);
  });

  test('the series itself failing is no answer, whatever its seasons say', () async {
    routes['/shows/tt9/comments/likes'] = () => _json('down', 500);
    routes['/shows/tt9/seasons/1/comments/likes'] = () => _json([_comment(1, 'Season')]);

    expect(await client().showComments(const ExternalIds(imdb: 'tt9'), seasons: [1]), isNull);
  });

  test('an error, a bad body and a thrown request are all no answer', () async {
    final reader = client();
    routes['/movies/tt1/comments/likes'] = () => _json('down', 503);
    expect(await reader.movieComments(const ExternalIds(imdb: 'tt1')), isNull);

    routes['/movies/tt1/comments/likes'] = () => http.Response('<html>', 200);
    expect(await reader.movieComments(const ExternalIds(imdb: 'tt1')), isNull);

    routes['/movies/tt1/comments/likes'] = () => throw http.ClientException('offline');
    expect(await reader.movieComments(const ExternalIds(imdb: 'tt1')), isNull);
  });

  test('a title is asked once, an empty answer too, until the cache runs out; a failure is not kept', () async {
    var now = DateTime(2026, 10, 30, 12);
    final reader = client(now: () => now);
    routes['/movies/tt1/comments/likes'] = () => _json(const []);

    expect(await reader.movieComments(const ExternalIds(imdb: 'tt1')), isEmpty);
    expect(await reader.movieComments(const ExternalIds(imdb: 'tt1')), isEmpty);
    expect(requests, hasLength(1));

    now = now.add(TraktCommentsClient.cacheLifetime);
    await reader.movieComments(const ExternalIds(imdb: 'tt1'));
    expect(requests, hasLength(2));

    routes['/movies/tt2/comments/likes'] = () => _json('down', 500);
    await reader.movieComments(const ExternalIds(imdb: 'tt2'));
    routes['/movies/tt2/comments/likes'] = () => _json([_comment(1, 'Back')]);
    expect((await reader.movieComments(const ExternalIds(imdb: 'tt2')))!.single.text, 'Back');
  });

  test('a film and a series with the same id do not share a cache entry', () async {
    final reader = client();
    routes['/movies/tt1/comments/likes'] = () => _json([_comment(1, 'Film')]);
    routes['/shows/tt1/comments/likes'] = () => _json([_comment(2, 'Show')]);

    expect((await reader.movieComments(const ExternalIds(imdb: 'tt1')))!.single.text, 'Film');
    expect((await reader.showComments(const ExternalIds(imdb: 'tt1')))!.single.text, 'Show');
  });

  test('at most twenty reactions come back', () async {
    routes['/movies/tt1/comments/likes'] = () => _json([for (var i = 0; i < 30; i++) _comment(i, 'n$i', likes: i)]);

    final comments = await client().movieComments(const ExternalIds(imdb: 'tt1'));

    expect(comments, hasLength(TraktCommentsClient.maxComments));
    expect(comments!.first.likes, 29);
  });

  test('markdown goes and what it marks stays', () {
    expect(
      TraktCommentsClient.plainComment('## Title\n\n**Bold** and *soft* and [a link](https://x.y) and 2*3*4'),
      'Title\n\nBold and soft and a link and 2*3*4',
    );
  });

  group('when part of the answer is missing', () {
    test('a season that fails leaves the series and the other seasons, and is asked again later', () async {
      routes['/shows/tt1/comments/likes'] = () => _json([_comment(1, 'The series')]);
      routes['/shows/tt1/seasons/1/comments/likes'] = () => _json(const [], 500);
      routes['/shows/tt1/seasons/2/comments/likes'] = () => _json([_comment(2, 'Season two')]);
      final trakt = client();

      final found = await trakt.showComments(const ExternalIds(imdb: 'tt1'), seasons: const [1, 2]);

      expect(found!.map((comment) => comment.text), containsAll(['The series', 'Season two']));
      routes['/shows/tt1/seasons/1/comments/likes'] = () => _json([_comment(3, 'Season one')]);
      final again = await trakt.showComments(const ExternalIds(imdb: 'tt1'), seasons: const [1, 2]);
      expect(again!.map((comment) => comment.text), contains('Season one'));
    });

    test('an IMDb id Trakt does not know falls back on the TMDB id', () async {
      routes['/search/tmdb/42'] = () => _json([
        {
          'type': 'movie',
          'movie': {
            'ids': {'trakt': 7},
          },
        },
      ]);
      routes['/movies/7/comments/likes'] = () => _json([_comment(1, 'Found it')]);

      final found = await client().movieComments(const ExternalIds(imdb: 'tt404', tmdb: 42));

      expect(found!.single.text, 'Found it');
    });

    test('an IMDb id that fails for another reason does not ask for the TMDB id', () async {
      routes['/movies/tt500/comments/likes'] = () => _json(const [], 500);

      expect(await client().movieComments(const ExternalIds(imdb: 'tt500', tmdb: 42)), isNull);
      expect(requests.map((request) => request.url.path), isNot(contains('/search/tmdb/42')));
    });

    test('an unknown IMDb id without a TMDB id stays no answer', () async {
      expect(await client().movieComments(const ExternalIds(imdb: 'tt404')), isNull);
    });
  });
}
