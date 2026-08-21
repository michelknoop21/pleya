import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

import '../test_helpers/prefs.dart';

SeerrSession _session({
  SeerrAuthMode mode = SeerrAuthMode.plex,
  String? cookie = 'connect.sid=abc',
  String? apiKey,
  String? email,
  String? password,
}) {
  return SeerrSession(
    baseUrl: 'https://seerr.example',
    authMode: mode,
    cookie: cookie,
    apiKey: apiKey,
    email: email,
    password: password,
  );
}

http.Response _json(Object body, int status, {Map<String, String> headers = const {}}) {
  return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  group('SeerrConstants.normalizeBaseUrl', () {
    test('adds https scheme when missing', () {
      expect(SeerrConstants.normalizeBaseUrl('seerr.local:5055'), 'https://seerr.local:5055');
    });

    test('keeps an explicit http scheme', () {
      expect(SeerrConstants.normalizeBaseUrl('http://seerr.local:5055'), 'http://seerr.local:5055');
    });

    test('strips trailing slashes and a pasted /api/v1 suffix', () {
      expect(SeerrConstants.normalizeBaseUrl('https://x.example/api/v1/'), 'https://x.example');
      expect(SeerrConstants.normalizeBaseUrl('https://x.example///'), 'https://x.example');
    });

    test('leaves a bare /api reverse-proxy path alone', () {
      expect(SeerrConstants.normalizeBaseUrl('https://x.example/api'), 'https://x.example/api');
    });
  });

  group('SeerrPermission', () {
    test('admin implies every flag', () {
      expect(SeerrPermission.has(SeerrPermission.admin, SeerrPermission.manageRequests), isTrue);
      expect(SeerrPermission.has(SeerrPermission.admin, SeerrPermission.anyRequest4k), isTrue);
    });

    test('non-admin only has explicit flags', () {
      expect(SeerrPermission.has(SeerrPermission.request, SeerrPermission.request), isTrue);
      expect(SeerrPermission.has(SeerrPermission.request, SeerrPermission.manageRequests), isFalse);
    });

    test('anyRequest4k matches each 4k variant', () {
      for (final flag in [SeerrPermission.request4k, SeerrPermission.request4kMovie, SeerrPermission.request4kTv]) {
        expect(SeerrPermission.has(flag, SeerrPermission.anyRequest4k), isTrue);
      }
    });
  });

  group('SeerrRequestStatus/SeerrMediaStatus', () {
    test('unknown media status codes fall back to unknown', () {
      expect(SeerrMediaStatus.fromValue(99), SeerrMediaStatus.unknown);
      expect(SeerrMediaStatus.fromValue(null), SeerrMediaStatus.unknown);
    });
  });

  group('SeerrSession encode/decode', () {
    test('round-trips with protected secrets', () async {
      final session = _session(mode: SeerrAuthMode.local, email: 'a@b.c', password: 'geheim');
      final raw = await session.encode();
      // Secrets never persist in plaintext.
      expect(raw.contains('geheim'), isFalse);
      final decoded = await SeerrSession.decode(raw);
      expect(decoded.baseUrl, session.baseUrl);
      expect(decoded.authMode, SeerrAuthMode.local);
      expect(decoded.cookie, session.cookie);
      expect(decoded.password, 'geheim');
    });

    test('throws on an unrecognized auth_mode', () async {
      final raw = jsonEncode({'base_url': 'https://x', 'auth_mode': 'bogus'});
      await expectLater(SeerrSession.decode(raw), throwsA(anything));
    });
  });

  group('SeerrClient auth & error mapping', () {
    test('401 in cookie mode silently re-auths and retries once', () async {
      var statusCalls = 0;
      var authCalls = 0;
      final client = SeerrClient(
        _session(),
        plexTokenProvider: () async => 'plex-token',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/plex')) {
            authCalls++;
            return _json({'id': 7, 'displayName': 'M'}, 200, headers: {'set-cookie': 'connect.sid=fresh; Path=/'});
          }
          statusCalls++;
          final authed = request.headers['Cookie'] == 'connect.sid=fresh';
          return authed ? _json({'version': '1'}, 200) : _json({'message': 'nope'}, 401);
        }),
      );
      final status = await client.getStatus(force: true);
      expect(status['version'], '1');
      expect(authCalls, 1);
      expect(statusCalls, 2);
      expect(client.session.cookie, 'connect.sid=fresh');
    });

    test('401 with failing re-auth surfaces SeerrException.auth', () async {
      final client = SeerrClient(
        _session(),
        plexTokenProvider: () async => null,
        httpClient: MockClient((request) async => _json({'message': 'unauthorized'}, 401)),
      );
      await expectLater(
        client.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    test('apiKey mode sends X-Api-Key and never re-auths on 401', () async {
      var calls = 0;
      final client = SeerrClient(
        _session(mode: SeerrAuthMode.apiKey, cookie: null, apiKey: 'k'),
        httpClient: MockClient((request) async {
          calls++;
          expect(request.headers['X-Api-Key'], 'k');
          return _json({'message': 'unauthorized'}, 401);
        }),
      );
      await expectLater(
        client.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
      expect(calls, 1);
    });

    test('403 maps to forbidden and server message is surfaced on other errors', () async {
      final forbidden = SeerrClient(
        _session(),
        plexTokenProvider: () async => null,
        httpClient: MockClient((request) async => _json({}, 403)),
      );
      await expectLater(
        forbidden.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isForbidden, 'isForbidden', isTrue)),
      );

      final serverError = SeerrClient(
        _session(),
        plexTokenProvider: () async => null,
        httpClient: MockClient((request) async => _json({'message': 'Quota exceeded'}, 409)),
      );
      await expectLater(
        serverError.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.message, 'message', 'Quota exceeded')),
      );
    });

    test('transport failure maps to a network SeerrException', () async {
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async => throw http.ClientException('boom')),
      );
      await expectLater(
        client.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });

    test('getRequests threads requestedBy into the query', () async {
      Uri? seen;
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          seen = request.url;
          return _json({
            'results': [],
            'pageInfo': {'pages': 1},
          }, 200);
        }),
      );
      await client.getRequests(requestedBy: 42);
      expect(seen!.queryParameters['requestedBy'], '42');

      await client.getRequests();
      expect(seen!.queryParameters.containsKey('requestedBy'), isFalse);
    });
  });

  group('service server detail', () {
    test('quality profiles and root folders come from the per-server call', () async {
      final seen = <Uri>[];
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          seen.add(request.url);
          if (request.url.path.endsWith('/service/radarr/1')) {
            return _json({
              'server': {'id': 1, 'name': 'Radarr'},
              'profiles': [
                {'id': 4, 'name': 'HD-1080p'},
                {'id': 7, 'name': 'Ultra-HD'},
              ],
              'rootFolders': [
                {'id': 1, 'path': '/films', 'freeSpace': 123},
                {'id': 2, 'path': '/films-4k'},
              ],
            }, 200);
          }
          return _json({'message': 'not found'}, 404);
        }),
      );

      final detail = await client.getRadarrServerDetail(1);

      expect(seen.single.path, endsWith('/service/radarr/1'));
      expect(detail.profiles.map((p) => p.name), ['HD-1080p', 'Ultra-HD']);
      expect(detail.profiles.first.id, 4);
      expect(detail.rootFolders.map((f) => f.path), ['/films', '/films-4k']);
      expect(detail.rootFolders.first.freeSpace, 123);
      // A server that does not report free space is still a usable folder.
      expect(detail.rootFolders.last.freeSpace, isNull);
    });

    test('the server list carries the defaults to seed the pickers with', () async {
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          return _json([
            {'id': 1, 'name': 'Radarr', 'isDefault': true, 'activeProfileId': 4, 'activeDirectory': '/films'},
            {'id': 2, 'name': 'Radarr 4K', 'is4k': true},
          ], 200);
        }),
      );

      final servers = await client.getRadarrServers();
      expect(servers.first.activeProfileId, 4);
      expect(servers.first.activeDirectory, '/films');
      expect(servers.first.isDefault, isTrue);
      expect(servers.last.is4k, isTrue);
      expect(servers.last.activeProfileId, isNull);
    });

    test('a shape without profiles decodes to empty rather than throwing', () async {
      final client = SeerrClient(
        _session(),
        httpClient: MockClient(
          (request) async => _json({
            'server': {'id': 1},
          }, 200),
        ),
      );

      final detail = await client.getSonarrServerDetail(1);
      expect(detail.profiles, isEmpty);
      expect(detail.rootFolders, isEmpty);
    });
  });

  group('hydrateRequests', () {
    // What Overseerr actually answers on /request: the media row, with the
    // availability status and the tmdb id, and nothing that names the title.
    Map<String, dynamic> bareRequest({
      required int id,
      required int tmdbId,
      required String type,
      int status = 1,
      int mediaStatus = 3,
    }) => {
      'id': id,
      'status': status,
      'type': type,
      'media': {'id': id * 10, 'mediaType': type, 'tmdbId': tmdbId, 'status': mediaStatus, 'status4k': 1},
      'requestedBy': {'id': 7, 'displayName': 'rapmadri'},
    };

    SeerrClient clientFor(
      List<Map<String, dynamic>> requests,
      Map<String, Object> details, {
      List<Uri>? seen,
      Set<String>? failFor,
    }) {
      return SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          seen?.add(request.url);
          final path = request.url.path;
          if (path.endsWith('/request')) {
            return _json({
              'results': requests,
              'pageInfo': {'pages': 1},
            }, 200);
          }
          for (final entry in details.entries) {
            if (path.endsWith(entry.key)) {
              if (failFor?.contains(entry.key) ?? false) return _json({'message': 'nope'}, 500);
              return _json(entry.value, 200);
            }
          }
          return _json({'message': 'not found'}, 404);
        }),
      );
    }

    test('a movie request gets its real title, year and poster', () async {
      final client = clientFor(
        [bareRequest(id: 1, tmdbId: 550, type: 'movie')],
        {
          '/movie/550': {
            'id': 550,
            'title': 'Fight Club',
            'releaseDate': '1999-10-15',
            'posterPath': '/fight.jpg',
            'backdropPath': '/fight-bd.jpg',
          },
        },
      );

      final raw = await client.getRequests();
      // Straight off the wire there is nothing to show but the media type.
      expect(raw.items.single.mediaTitle, isNull);
      expect(raw.items.single.posterPath, isNull);

      final hydrated = await client.hydrateRequests(raw.items);
      expect(hydrated.single.mediaTitle, 'Fight Club');
      expect(hydrated.single.mediaYear, '1999');
      expect(hydrated.single.posterPath, '/fight.jpg');
      expect(hydrated.single.backdropPath, '/fight-bd.jpg');
      // Availability came off the request itself and must survive.
      expect(hydrated.single.mediaStatus, SeerrMediaStatus.processing);
      expect(hydrated.single.requestedByName, 'rapmadri');
    });

    test('a show request resolves through /tv and its first-air date', () async {
      final client = clientFor(
        [bareRequest(id: 2, tmdbId: 1399, type: 'tv')],
        {
          '/tv/1399': {'id': 1399, 'name': 'Game of Thrones', 'firstAirDate': '2011-04-17', 'posterPath': '/got.jpg'},
        },
      );

      final hydrated = await client.hydrateRequests((await client.getRequests()).items);
      expect(hydrated.single.mediaTitle, 'Game of Thrones');
      expect(hydrated.single.mediaYear, '2011');
      expect(hydrated.single.posterPath, '/got.jpg');
    });

    test('the same title is fetched once, however often it is requested', () async {
      final seen = <Uri>[];
      final client = clientFor(
        [bareRequest(id: 1, tmdbId: 550, type: 'movie'), bareRequest(id: 2, tmdbId: 550, type: 'movie')],
        {
          '/movie/550': {'id': 550, 'title': 'Fight Club', 'posterPath': '/fight.jpg'},
        },
        seen: seen,
      );

      final first = await client.hydrateRequests((await client.getRequests()).items);
      expect(first.map((r) => r.mediaTitle), everyElement('Fight Club'));
      expect(seen.where((u) => u.path.endsWith('/movie/550')), hasLength(1));

      // A second page, or a filter switch, must not go back for it.
      await client.hydrateRequests((await client.getRequests()).items);
      expect(seen.where((u) => u.path.endsWith('/movie/550')), hasLength(1));
    });

    test('a title that cannot be resolved leaves its row listed', () async {
      final client = clientFor(
        [bareRequest(id: 1, tmdbId: 550, type: 'movie'), bareRequest(id: 2, tmdbId: 99, type: 'movie')],
        {
          '/movie/550': {'id': 550, 'title': 'Fight Club', 'posterPath': '/fight.jpg'},
          '/movie/99': <String, Object>{},
        },
        failFor: {'/movie/99'},
      );

      final hydrated = await client.hydrateRequests((await client.getRequests()).items);
      expect(hydrated, hasLength(2));
      expect(hydrated.first.mediaTitle, 'Fight Club');
      // Still there, still cancellable, just without a name.
      expect(hydrated.last.mediaTitle, isNull);
      expect(hydrated.last.id, 2);
    });

    test('a page of twenty distinct titles costs exactly twenty lookups, then none', () async {
      final detailCalls = <String>[];
      final requests = [for (var i = 1; i <= 20; i++) bareRequest(id: i, tmdbId: 1000 + i, type: 'movie')];
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/request')) {
            return _json({
              'results': requests,
              'pageInfo': {'pages': 3},
            }, 200);
          }
          detailCalls.add(path);
          final id = int.parse(path.split('/').last);
          return _json({'id': id, 'title': 'Film $id', 'posterPath': '/p$id.jpg'}, 200);
        }),
      );

      final page = await client.getRequests();
      await client.hydrateRequests(page.items);
      // One per distinct title. Not one per row, not one per field.
      expect(detailCalls, hasLength(20));

      // Scrolling back over the same titles, or switching filter and back, is
      // free: the whole point of the cache.
      await client.hydrateRequests(page.items);
      await client.hydrateRequests((await client.getRequests(filter: 'approved')).items);
      expect(detailCalls, hasLength(20));
    });

    test('a page that repeats a title costs one lookup for it, not one per row', () async {
      final detailCalls = <String>[];
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/request')) {
            return _json({
              'results': [
                bareRequest(id: 1, tmdbId: 550, type: 'movie'),
                bareRequest(id: 2, tmdbId: 550, type: 'movie'),
                bareRequest(id: 3, tmdbId: 550, type: 'movie'),
                bareRequest(id: 4, tmdbId: 99, type: 'movie'),
              ],
              'pageInfo': {'pages': 1},
            }, 200);
          }
          detailCalls.add(path);
          final id = int.parse(path.split('/').last);
          return _json({'id': id, 'title': 'Film $id'}, 200);
        }),
      );

      final hydrated = await client.hydrateRequests((await client.getRequests()).items);

      // Four rows, two distinct titles, two lookups.
      expect(detailCalls, hasLength(2));
      expect(hydrated.where((r) => r.mediaTitle == 'Film 550'), hasLength(3));
      expect(hydrated.last.mediaTitle, 'Film 99');
    });

    test('two hydration passes at once share one lookup per title', () async {
      final detailCalls = <String>[];
      final requests = [bareRequest(id: 1, tmdbId: 550, type: 'movie')];
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/request')) {
            return _json({
              'results': requests,
              'pageInfo': {'pages': 1},
            }, 200);
          }
          detailCalls.add(path);
          return _json({'id': 550, 'title': 'Fight Club'}, 200);
        }),
      );

      final items = (await client.getRequests()).items;
      // A fast filter switch fires a second pass before the first has landed.
      await Future.wait([client.hydrateRequests(items), client.hydrateRequests(items)]);

      expect(detailCalls, hasLength(1));
    });

    test('a failing lookup costs one attempt per pass, and the list still renders', () async {
      var attempts = 0;
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/request')) {
            return _json({
              'results': [
                bareRequest(id: 1, tmdbId: 550, type: 'movie'),
                bareRequest(id: 2, tmdbId: 99, type: 'movie'),
              ],
              'pageInfo': {'pages': 1},
            }, 200);
          }
          if (path.endsWith('/movie/99')) {
            attempts++;
            return _json({'message': 'boom'}, 500);
          }
          return _json({'id': 550, 'title': 'Fight Club'}, 200);
        }),
      );

      final items = (await client.getRequests()).items;
      final first = await client.hydrateRequests(items);
      // The good title resolved, the bad one did not, and both rows survive.
      expect(first, hasLength(2));
      expect(first.first.mediaTitle, 'Fight Club');
      expect(first.last.mediaTitle, isNull);
      expect(first.last.tmdbId, 99, reason: 'the request data itself must stay intact');
      expect(first.last.requestedByName, 'rapmadri');
      expect(attempts, 1);

      // Retried on the next pass rather than written off for the session, but
      // once per pass -- never once per row.
      await client.hydrateRequests(items);
      expect(attempts, 2);
    });

    test('a payload that already carries the title is left alone', () async {
      final seen = <Uri>[];
      final client = clientFor(
        [
          {
            'id': 3,
            'status': 2,
            'type': 'movie',
            'media': {
              'tmdbId': 550,
              'status': 5,
              'title': 'Al bekend',
              'posterPath': '/known.jpg',
              'releaseDate': '2001-01-01',
            },
          },
        ],
        {
          '/movie/550': {'id': 550, 'title': 'Fight Club', 'posterPath': '/fight.jpg'},
        },
        seen: seen,
      );

      final hydrated = await client.hydrateRequests((await client.getRequests()).items);
      expect(hydrated.single.mediaTitle, 'Al bekend');
      expect(seen.any((u) => u.path.endsWith('/movie/550')), isFalse);
    });
  });
}
