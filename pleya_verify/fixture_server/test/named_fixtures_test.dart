import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/named_fixtures.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

Future<http.Response> _post(PleyaFakeServer server, String path, Object body) {
  final request = http.Request('POST', Uri.parse('http://fixture$path'))..body = jsonEncode(body);
  return server.handle(request);
}

void main() {
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
