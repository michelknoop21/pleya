import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/jellyfin_fake_server.dart';
import 'package:pleya_verify_fixture_server/named_fixtures.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:pleya_verify_fixture_server/seerr_fake_server.dart';
import 'package:pleya_verify_fixture_server/tautulli_fake_server.dart';
import 'package:test/test.dart';

Future<http.Response> _post(PleyaFakeServer server, String path, Object body) {
  final request = http.Request('POST', Uri.parse('http://fixture$path'))..body = jsonEncode(body);
  return server.handle(request);
}

void main() {
  group('catalog.hero-recent.v1', () {
    test('Latest answers with a bare array of films inside the DEC-097 window', () async {
      final jellyfin = JellyfinFakeServer();
      expect(applyNamedFixture(PleyaFakeServer(), 'catalog.hero-recent.v1', jellyfin: jellyfin), isTrue);
      final url = Uri.parse('http://fixture/jellyfin/Users/${JellyfinFakeServer.userId}/Items/Latest?Limit=100');
      final response = await jellyfin.handle(http.Request('GET', url));
      final films = jsonDecode(response.body) as List;
      expect(films, hasLength(3));
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 90));
      for (final film in films.cast<Map<String, dynamic>>()) {
        expect(DateTime.parse(film['PremiereDate'] as String).isAfter(cutoff), isTrue, reason: '${film['Name']}');
        expect(film['BackdropImageTags'], isNotEmpty, reason: '${film['Name']}');
      }
    });

    test('needs the fake Jellyfin, because the Pleya fixture carries no date', () {
      expect(applyNamedFixture(PleyaFakeServer(), 'catalog.hero-recent.v1'), isFalse);
    });
  });

  group('catalog.scores.v1', () {
    Future<Map<String, dynamic>> items(JellyfinFakeServer jellyfin, String sortOrder) async {
      final url = Uri.parse(
        'http://fixture/jellyfin/Items?ParentId=${JellyfinFakeServer.libraryId}&SortBy=CriticRating,SortName&SortOrder=$sortOrder&StartIndex=0&Limit=50',
      );
      final response = await jellyfin.handle(http.Request('GET', url));
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    test('seeds a Jellyfin library with scores, two titles without', () async {
      final jellyfin = JellyfinFakeServer();
      expect(applyNamedFixture(PleyaFakeServer(), 'catalog.scores.v1', jellyfin: jellyfin), isTrue);
      expect(jellyfin.movies, hasLength(12));
      expect(jellyfin.movies.where((movie) => movie.criticRating == null), hasLength(2));
    });

    test('sends titles without a value last descending and first ascending', () async {
      final jellyfin = JellyfinFakeServer();
      applyNamedFixture(PleyaFakeServer(), 'catalog.scores.v1', jellyfin: jellyfin);
      final down = (await items(jellyfin, 'Descending'))['Items'] as List;
      final up = (await items(jellyfin, 'Ascending'))['Items'] as List;
      expect((down.first as Map)['CriticRating'], 100);
      expect((down.last as Map).containsKey('CriticRating'), isFalse);
      expect((up.first as Map).containsKey('CriticRating'), isFalse);
    });

    test('one SortOrder runs every key that way, a list runs per key', () async {
      final jellyfin = JellyfinFakeServer();
      applyNamedFixture(PleyaFakeServer(), 'catalog.scores.v1', jellyfin: jellyfin);
      List<Object?> tied(List<dynamic> rows) => [
        for (final row in rows.cast<Map>())
          if (!row.containsKey('CriticRating')) row['Name'],
      ];
      final one = tied((await items(jellyfin, 'Descending'))['Items'] as List);
      final perKey = tied((await items(jellyfin, 'Descending,Ascending'))['Items'] as List);
      expect(one, hasLength(2));
      expect(one, perKey.reversed.toList());
    });
  });

  group('seeding preserves the session', () {
    // `seed` used to call the full reset(), which also wiped credentials,
    // refreshCount and the clock. Nothing in the scenario grammar forbids
    // `sign_in` before `seed`, so that made step order silently
    // load-bearing: the seed invalidated the session the sign_in had just
    // created, and every later authenticated step failed with an error
    // about a dead session that pointed nowhere near the real cause.
    Future<PleyaFakeServer> signedInServer() async {
      // `setupRequired: true` is what a scenario's `sign_in` step meets: a
      // fresh server offering setup once, which registers the owner.
      final server = PleyaFakeServer(setupRequired: true);
      final setup = await _post(server, '/pleya/v1/auth/setup', {
        'setup_code': server.setupCode,
        'username': 'verify-owner',
        'password': 'verify-password',
      });
      expect(setup.statusCode, 200, reason: 'precondition: the fixture owner must exist');
      return server;
    }

    test('a catalog seed after sign_in leaves the credentials usable', () async {
      final server = await signedInServer();

      applyNamedFixture(server, 'catalog.shows.v1');

      final login = await _post(server, '/pleya/v1/auth/login', {
        'username': 'verify-owner',
        'password': 'verify-password',
      });
      expect(login.statusCode, 200, reason: 'the seed must not invalidate the session sign_in created');
      expect(server.setupRequired, isFalse);
    });

    test('every named fixture preserves the session, not just one', () async {
      for (final name in ['catalog.shows.v1', 'catalog.mixed.v1', 'catalog.empty.v1']) {
        final server = await signedInServer();
        applyNamedFixture(server, name);

        final login = await _post(server, '/pleya/v1/auth/login', {
          'username': 'verify-owner',
          'password': 'verify-password',
        });
        expect(login.statusCode, 200, reason: '$name wiped the credentials');
      }
    });

    test('a seed still replaces the catalog rather than appending to it', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.shows.v1');
      final afterShows = server.libraries.length;

      applyNamedFixture(server, 'catalog.mixed.v1');

      expect(server.libraries.length, lessThanOrEqualTo(afterShows + 1));
      expect(
        server.libraries.where((l) => l['title'] == 'Shows').length,
        lessThanOrEqualTo(1),
        reason: 'seeding twice must not stack duplicate libraries',
      );
    });

    test('a seed does not reset counters the scenario may be asserting on', () {
      final server = PleyaFakeServer()..refreshCount = 3;
      applyNamedFixture(server, 'catalog.shows.v1');
      expect(server.refreshCount, 3);
    });
  });

  test('applyNamedFixture returns false and mutates nothing for an unknown name', () {
    final server = PleyaFakeServer();
    final applied = applyNamedFixture(server, 'catalog.does-not-exist');
    expect(applied, isFalse);
    expect(server.libraries, isEmpty);
  });

  group('fixtureItemId', () {
    test('the same (fixture, kind, slug) always yields the same id', () {
      expect(fixtureItemId('f', 'k', 's'), fixtureItemId('f', 'k', 's'));
    });

    test('a different slug yields a different id', () {
      expect(fixtureItemId('f', 'k', 'a'), isNot(fixtureItemId('f', 'k', 'b')));
    });
  });

  group('catalog.shows.v1', () {
    test('one library, one show, one season, ten episodes, deterministically', () {
      final server = PleyaFakeServer();
      final applied = applyNamedFixture(server, 'catalog.shows.v1');

      expect(applied, isTrue);
      expect(server.libraries, hasLength(1));
      final show = server.items.values.singleWhere((i) => i['kind'] == 'show');
      expect(show['title'], 'Testserie');
      // VER8: Home's first rail is the TV way in to the show.
      expect(server.hubs['recently_added'], [show['id']]);
      final season = server.items.values.singleWhere((i) => i['kind'] == 'season');
      expect(server.children[season['id']], hasLength(10));
      expect(season['child_count'], 10);
      expect(season['episode_count'], 10);

      final episodes = server.items.values.where((i) => i['kind'] == 'episode').toList()
        ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      expect(episodes.map((e) => e['title']), [for (var i = 1; i <= 10; i++) 'S01E${i.toString().padLeft(2, '0')}']);
      // Every episode has a version, and every version is playable.
      for (final episode in episodes) {
        expect(server.versionBytes.containsKey('${episode['id']}-v1'), isTrue);
      }
    });

    test('applying it twice to fresh servers produces byte-identical item maps', () {
      final serverA = PleyaFakeServer();
      final serverB = PleyaFakeServer();
      applyNamedFixture(serverA, 'catalog.shows.v1');
      applyNamedFixture(serverB, 'catalog.shows.v1');

      expect(serverA.items, serverB.items);
      expect(serverA.libraries, serverB.libraries);
    });

    test('every registered artwork id is a real, distinguishable PNG per item', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.shows.v1');

      final colors = server.artworkById.values.map((bytes) => bytes.join(',')).toSet();
      expect(server.artworkById, isNotEmpty);
      expect(colors.length, server.artworkById.length, reason: 'artwork must differ per item, not repeat one blob');
      for (final bytes in server.artworkById.values) {
        expect(bytes.take(8).toList(), const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      }
    });
  });

  group('catalog.mixed.v1', () {
    test('both library kinds are present, plus non-empty hubs', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.mixed.v1');

      final kinds = server.libraries.map((l) => l['kind']).toSet();
      expect(kinds, {'movies', 'shows'});
      expect(server.items.values.where((i) => i['kind'] == 'movie'), hasLength(3));
      expect(server.hubs['recently_added'], isNotEmpty);
      expect(server.hubs['continue_watching'], isNotEmpty);
    });
  });

  group('seerr.requests.v1', () {
    test('returns false without a seerr server, seeds one when given', () {
      final server = PleyaFakeServer();
      expect(applyNamedFixture(server, 'seerr.requests.v1'), isFalse);

      final seerr = SeerrFakeServer();
      expect(applyNamedFixture(server, 'seerr.requests.v1', seerr: seerr), isTrue);
      expect(seerr.requests, hasLength(5));
      expect(seerr.discover.values.every((bucket) => bucket.length == 6), isTrue);
    });

    test('does not touch the pleya server catalog', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.mixed.v1');
      final seerr = SeerrFakeServer();

      applyNamedFixture(server, 'seerr.requests.v1', seerr: seerr);

      expect(server.libraries, isNotEmpty, reason: 'seeding seerr must not reset the catalog');
    });
  });

  group('seerr.detail.*', () {
    test('the same available title, with and without a 4K instance', () {
      final server = PleyaFakeServer();
      final seerr = SeerrFakeServer();
      expect(applyNamedFixture(server, 'seerr.detail.4k.v1'), isFalse);

      expect(applyNamedFixture(server, 'seerr.detail.4k.v1', seerr: seerr), isTrue);
      expect(seerr.fourKServers, isTrue);
      expect(seerr.discover['trending']!.single['title'], 'Glacier Run');

      expect(applyNamedFixture(server, 'seerr.detail.hd-only.v1', seerr: seerr), isTrue);
      expect(seerr.fourKServers, isFalse);
      expect(seerr.discover['trending']!.single['title'], 'Glacier Run');
    });
  });

  group('seerr.requester.*', () {
    test('a requester with the 4K right, in the three states of the instance list', () {
      final server = PleyaFakeServer();
      final seerr = SeerrFakeServer();
      expect(applyNamedFixture(server, 'seerr.requester.4k-default.v1'), isFalse);

      expect(applyNamedFixture(server, 'seerr.requester.4k-default.v1', seerr: seerr), isTrue);
      expect(seerr.userPermissions, 32 | 1024);
      expect(seerr.fourKServers, isTrue);
      expect(seerr.serviceListForbidden, isFalse);
      expect(seerr.discover['trending']!.single['title'], 'Frost Line');

      expect(applyNamedFixture(server, 'seerr.requester.no-4k-default.v1', seerr: seerr), isTrue);
      expect(seerr.fourKServers, isFalse);
      expect(seerr.serviceListForbidden, isFalse);

      expect(applyNamedFixture(server, 'seerr.requester.list-unknown.v1', seerr: seerr), isTrue);
      expect(seerr.serviceListForbidden, isTrue);

      seerr.reset();
      expect(seerr.userPermissions, 2, reason: 'reset returns the fixture user to admin');
      expect(seerr.serviceListForbidden, isFalse);
    });
  });

  group('seerr.search.v1', () {
    test('seeds titles the library fixture does not hold', () {
      final server = PleyaFakeServer();
      applyNamedFixture(server, 'catalog.mixed.v1');
      final seerr = SeerrFakeServer();

      expect(applyNamedFixture(server, 'seerr.search.v1', seerr: seerr), isTrue);
      final found = {for (final row in seerr.searchItems) row['title'] ?? row['name']};
      expect(found, {'Ashfall', 'Glass Harbor'});
      final library = {for (final item in server.items.values) item['title']};
      expect(library.intersection(found), isEmpty);
    });
  });

  group('server.owner.v1', () {
    test('turns on the users capability and a reset turns it off again', () {
      final server = PleyaFakeServer();
      expect(server.usersCapability, isFalse);
      expect(applyNamedFixture(server, 'server.owner.v1'), isTrue);
      expect(server.usersCapability, isTrue);
      server.reset();
      expect(server.usersCapability, isFalse);
    });
  });

  group('server.admin-jobs.v1', () {
    test('lists one failed job, retries it through running to succeeded, and logs a scan', () async {
      final server = PleyaFakeServer();
      expect(applyNamedFixture(server, 'server.admin-jobs.v1'), isTrue);
      expect(server.usersCapability, isTrue);
      expect(server.adminJobs.single['state'], 'failed');

      Future<Map<String, dynamic>> jobs() async {
        final response = await server.handle(
          http.Request('GET', Uri.parse('http://f/pleya/v1/jobs'))..headers['Authorization'] = 'Bearer at-0',
        );
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      expect((await jobs())['items'].single['state'], 'failed');
      final retry = await server.handle(
        http.Request('POST', Uri.parse('http://f/pleya/v1/jobs/job-failed-1/retry'))
          ..headers['Authorization'] = 'Bearer at-0',
      );
      expect(retry.statusCode, 200);
      expect(server.retryRequests, ['job-failed-1']);
      for (var i = 0; i < 4; i++) {
        expect((await jobs())['items'].single['state'], 'running', reason: 'read ${i + 1}');
      }
      expect((await jobs())['items'].single['state'], 'succeeded');

      final scan = await server.handle(
        http.Request('POST', Uri.parse('http://f/pleya/v1/libraries/lib-movies/scan'))
          ..headers['Authorization'] = 'Bearer at-0',
      );
      expect(scan.statusCode, 202);
      expect(server.scanRequests, ['lib-movies']);
    });

    test('negative control: without the fixture the routes do not exist, and a reset clears them', () async {
      final server = PleyaFakeServer();
      final response = await server.handle(
        http.Request('GET', Uri.parse('http://f/pleya/v1/jobs'))..headers['Authorization'] = 'Bearer at-0',
      );
      expect(response.statusCode, isNot(200));
      applyNamedFixture(server, 'server.admin-jobs.v1');
      server.reset();
      expect(server.adminJobs, isEmpty);
      expect(server.usersCapability, isFalse);
    });
  });

  group('activity.active-session.v1', () {
    test('returns false without a tautulli server, seeds one when given', () {
      final server = PleyaFakeServer();
      expect(applyNamedFixture(server, 'activity.active-session.v1'), isFalse);

      final tautulli = TautulliFakeServer();
      expect(applyNamedFixture(server, 'activity.active-session.v1', tautulli: tautulli), isTrue);
      expect(tautulli.sessions, hasLength(1));
    });
  });

  group('catalog.long-rails.v1', () {
    test('recently_added carries twelve movies', () {
      final server = PleyaFakeServer();
      final applied = applyNamedFixture(server, 'catalog.long-rails.v1');

      expect(applied, isTrue);
      expect(server.hubs['recently_added'], hasLength(12));
      expect(server.items.values.where((i) => i['kind'] == 'movie'), hasLength(12));
    });
  });

  group('catalog.long-grid.v1', () {
    test('one library with eighteen movies, under one catalogue page', () {
      final server = PleyaFakeServer();
      final applied = applyNamedFixture(server, 'catalog.long-grid.v1');

      expect(applied, isTrue);
      expect(server.libraries, hasLength(1));
      expect(server.items.values.where((i) => i['kind'] == 'movie'), hasLength(18));
    });
  });

  group('catalog.long-grid.v2', () {
    test('one library with nineteen movies: four TV rows, still one catalogue page', () {
      final server = PleyaFakeServer();
      final applied = applyNamedFixture(server, 'catalog.long-grid.v2');

      expect(applied, isTrue);
      expect(server.libraries, hasLength(1));
      expect(server.items.values.where((i) => i['kind'] == 'movie'), hasLength(19));
    });
  });

  group('catalog.alphabet-500.v1', () {
    test('five hundred movies, twenty per letter from A to Y and none under Z', () {
      final server = PleyaFakeServer();
      final applied = applyNamedFixture(server, 'catalog.alphabet-500.v1');

      expect(applied, isTrue);
      expect(server.libraries, hasLength(1));
      final titles = server.items.values.where((i) => i['kind'] == 'movie').map((i) => i['title'] as String);
      expect(titles, hasLength(500));
      expect(titles.where((title) => title.startsWith('M ')), hasLength(20));
      expect(titles.where((title) => title.startsWith('Z ')), isEmpty);
    });
  });

  group('catalog.seasons.v1', () {
    test('one show with four seasons of two to five episodes, on the first rail', () {
      final server = PleyaFakeServer();
      final applied = applyNamedFixture(server, 'catalog.seasons.v1');

      expect(applied, isTrue);
      final shows = server.items.entries.where((e) => e.value['kind'] == 'show').toList();
      expect(shows, hasLength(1));
      expect(server.hubs['recently_added'], [shows.single.key]);

      final seasons = server.items.entries.where((e) => e.value['kind'] == 'season').toList()
        ..sort((a, b) => (a.value['index'] as int).compareTo(b.value['index'] as int));
      expect([for (final s in seasons) s.value['index']], [1, 2, 3, 4]);
      expect([for (final s in seasons) server.items.values.where((i) => i['parent_id'] == s.key).length], [2, 3, 4, 5]);
    });
  });

  group('catalog.empty.v1', () {
    test('leaves the server with no libraries and no items', () {
      final server = PleyaFakeServer();
      server.addLibrary(id: 'stale', title: 'Stale', kind: 'movies');
      final applied = applyNamedFixture(server, 'catalog.empty.v1');

      expect(applied, isTrue);
      expect(server.libraries, isEmpty);
      expect(server.items, isEmpty);
    });
  });
}
