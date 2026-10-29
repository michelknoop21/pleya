import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/pleya_server/pleya_wire_library.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/utils/external_ids.dart';

import 'pleya_fake_server.dart';

/// What unified needs from a Pleya Server: the provider number it has proven
/// for a title, read from the item itself, and an honest "I cannot tell" from a
/// server that predates the field.
void main() {
  late PleyaServerClient client;

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  PleyaFakeServer serverWith({bool reportsExternalIds = true}) {
    final server = PleyaFakeServer()..reportsExternalIds = reportsExternalIds;
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    server.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
    server.addItem(
      id: 'dune-2021',
      kind: 'movie',
      title: 'Dune',
      libraryId: 'lib-films',
      year: 2021,
      durationMs: 9300000,
      externalIds: {'tmdb': 438631},
    );
    server.addItem(
      id: 'dune-1984',
      kind: 'movie',
      title: 'Dune',
      libraryId: 'lib-films',
      year: 1984,
      durationMs: 8220000,
      externalIds: {'tmdb': 841},
    );
    server.addItem(id: 'unmatched', kind: 'movie', title: 'Dune', libraryId: 'lib-films', year: 2021, durationMs: 6000);
    server.addItem(
      id: 'severance',
      kind: 'show',
      title: 'Severance',
      libraryId: 'lib-series',
      year: 2022,
      externalIds: {'tmdb': 95396},
    );
    server.addItem(id: 'sev-s1', kind: 'season', title: 'Season 1', parentId: 'severance', index: 1);
    server.addItem(
      id: 'sev-s1e1',
      kind: 'episode',
      title: 'Good News About Hell',
      parentId: 'sev-s1',
      index: 1,
      durationMs: 3000000,
    );
    return server;
  }

  group('PleyaExternalIds wire parsing', () {
    test('reads the tmdb number and notes that the key was sent', () {
      final item = PleyaItem.fromJson({
        'id': 'a',
        'kind': 'movie',
        'title': 'Dune',
        'added_at': '2026-06-18T21:34:02Z',
        'external_ids': {'tmdb': 438631},
      });
      expect(item.externalIds.tmdb, 438631);
      expect(item.externalIdsReported, isTrue);
    });

    test('a null object is a server that knows the field and has no proof', () {
      final item = PleyaItem.fromJson({
        'id': 'a',
        'kind': 'movie',
        'title': 'Dune',
        'added_at': '2026-06-18T21:34:02Z',
        'external_ids': null,
      });
      expect(item.externalIds.isEmpty, isTrue);
      expect(item.externalIdsReported, isTrue);
    });

    test('a missing key is a server that predates the field, not a "no"', () {
      final item = PleyaItem.fromJson({
        'id': 'a',
        'kind': 'movie',
        'title': 'Dune',
        'added_at': '2026-06-18T21:34:02Z',
      });
      expect(item.externalIds.isEmpty, isTrue);
      expect(item.externalIdsReported, isFalse);
    });

    test('a number that is not a positive integer is dropped instead of becoming evidence', () {
      for (final bad in <Object?>[0, -4, '438631', 4.5, null]) {
        final item = PleyaItem.fromJson({
          'id': 'a',
          'kind': 'movie',
          'title': 'Dune',
          'added_at': '2026-06-18T21:34:02Z',
          'external_ids': {'tmdb': bad},
        });
        expect(item.externalIds.tmdb, isNull, reason: '$bad');
      }
    });

    test('an unknown provider key is ignored', () {
      final item = PleyaItem.fromJson({
        'id': 'a',
        'kind': 'movie',
        'title': 'Dune',
        'added_at': '2026-06-18T21:34:02Z',
        'external_ids': {'tmdb': 7, 'anidb': 99},
      });
      expect(item.externalIds.tmdb, 7);
    });
  });

  group('fetchExternalIds', () {
    tearDown(() => client.close());

    test('a matched movie and a matched show answer their tmdb number', () async {
      client = await connected(serverWith());
      expect(await client.fetchExternalIds('dune-2021'), const ExternalIds(tmdb: 438631));
      expect(await client.fetchExternalIds('severance'), const ExternalIds(tmdb: 95396));
    });

    test('a title without a proven match answers empty, which is no evidence', () async {
      client = await connected(serverWith());
      expect(await client.fetchExternalIds('unmatched'), const ExternalIds());
    });

    test('a season and an episode answer empty, so identity comes from the show', () async {
      client = await connected(serverWith());
      expect(await client.fetchExternalIds('sev-s1'), const ExternalIds());
      expect(await client.fetchExternalIds('sev-s1e1'), const ExternalIds());
    });

    test('a server that predates the field answers empty', () async {
      client = await connected(serverWith(reportsExternalIds: false));
      expect(await client.fetchExternalIds('dune-2021'), const ExternalIds());
    });

    test('an item the server no longer has answers empty', () async {
      client = await connected(serverWith());
      expect(await client.fetchExternalIds('gone'), const ExternalIds());
    });

    test('an unreachable server throws, so an empty answer is never cached as proof of nothing', () async {
      final server = serverWith();
      client = await connected(server);
      server.unreachable = true;
      await expectLater(client.fetchExternalIds('dune-2021'), throwsA(isA<StateError>()));
    });
  });

  group('findAllByIdentity', () {
    tearDown(() => client.close());

    MediaIdentity dune({int? tmdb = 438631, MediaKind kind = MediaKind.movie}) => MediaIdentity(
      externalIds: ExternalIds(tmdb: tmdb),
      title: 'Dune',
      year: 2021,
      kind: kind,
    );

    test('returns only the title that carries the same number, not the remake with the same name', () async {
      client = await connected(serverWith());
      final matches = await client.findAllByIdentity(dune());
      expect(matches.map((m) => m.id), ['dune-2021']);
    });

    test('a same-named title without a proven number is not taken for the same title', () async {
      client = await connected(serverWith());
      final matches = await client.findAllByIdentity(dune());
      expect(matches.map((m) => m.id), isNot(contains('unmatched')));
    });

    test('a number is per kind: the show with another kind of the same number does not answer a movie', () async {
      final server = serverWith();
      server.addItem(
        id: 'dune-show',
        kind: 'show',
        title: 'Dune',
        libraryId: 'lib-series',
        year: 2021,
        externalIds: {'tmdb': 438631},
      );
      client = await connected(server);
      expect((await client.findAllByIdentity(dune())).map((m) => m.id), ['dune-2021']);
      expect((await client.findAllByIdentity(dune(kind: MediaKind.show))).map((m) => m.id), ['dune-show']);
    });

    test('two copies on one server are both returned, as for every backend', () async {
      final server = serverWith();
      server.addItem(
        id: 'dune-2021-b',
        kind: 'movie',
        title: 'Dune',
        libraryId: 'lib-films',
        year: 2021,
        durationMs: 9300000,
        externalIds: {'tmdb': 438631},
      );
      client = await connected(server);
      expect((await client.findAllByIdentity(dune())).map((m) => m.id).toSet(), {'dune-2021', 'dune-2021-b'});
    });

    test('no match is an honest empty list from a server that does speak external ids', () async {
      client = await connected(serverWith());
      expect(await client.findAllByIdentity(dune(tmdb: 1)), isEmpty);
    });

    test('an identity without a tmdb number cannot be proven here and says so by throwing', () async {
      client = await connected(serverWith());
      await expectLater(
        client.findAllByIdentity(
          const MediaIdentity(externalIds: ExternalIds(tvdb: 9), title: 'Dune', year: 2021, kind: MediaKind.movie),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an identity of unknown kind cannot be proven either', () async {
      client = await connected(serverWith());
      await expectLater(client.findAllByIdentity(dune(kind: MediaKind.unknown)), throwsA(isA<StateError>()));
    });

    test('a server that predates external_ids throws instead of answering "not here"', () async {
      client = await connected(serverWith(reportsExternalIds: false));
      await expectLater(client.findAllByIdentity(dune()), throwsA(isA<StateError>()));
    });

    test('findByIdentity declines when two titles carry the number', () async {
      final server = serverWith();
      server.addItem(
        id: 'dune-2021-b',
        kind: 'movie',
        title: 'Dune',
        libraryId: 'lib-films',
        year: 2021,
        durationMs: 9300000,
        externalIds: {'tmdb': 438631},
      );
      client = await connected(server);
      expect(await client.findByIdentity(dune()), isNull);
    });
  });
}
