import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/identity_lookup_exceptions.dart';
import 'package:pleya/media/library_query.dart';
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

    test('a broken value is not a final "no numbers": it reads as not reported, so it is asked again', () {
      // The contract says `tmdb` is an integer of at least 1 and the object is
      // an object or null. Anything else is a broken answer, and a broken answer
      // stored as final would hide a later match for good.
      for (final bad in <Object?>[
        {'tmdb': 0},
        {'tmdb': '438631'},
        {'tmdb': 4.5},
        'tmdb:438631',
        [438631],
      ]) {
        final item = PleyaItem.fromJson({
          'id': 'a',
          'kind': 'movie',
          'title': 'Dune',
          'added_at': '2026-06-18T21:34:02Z',
          'external_ids': bad,
        });
        expect(item.externalIdsReported, isFalse, reason: '$bad');
      }
      final noNumber = PleyaItem.fromJson({
        'id': 'a',
        'kind': 'movie',
        'title': 'Dune',
        'added_at': '2026-06-18T21:34:02Z',
        'external_ids': {'tmdb': null},
      });
      expect(noNumber.externalIdsReported, isTrue, reason: 'a null number is the server saying it has none');
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

    test('a title without a proven match answers empty, and says the server was sure about it', () async {
      client = await connected(serverWith());
      final answer = await client.fetchExternalIdsDetailed('unmatched');
      expect(answer.ids, const ExternalIds());
      expect(answer.authoritative, isTrue);
    });

    test('a season and an episode answer empty, so identity comes from the show', () async {
      client = await connected(serverWith());
      expect(await client.fetchExternalIds('sev-s1'), const ExternalIds());
      expect(await client.fetchExternalIds('sev-s1e1'), const ExternalIds());
    });

    test('a server that predates the field answers empty but not authoritatively', () async {
      client = await connected(serverWith(reportsExternalIds: false));
      final answer = await client.fetchExternalIdsDetailed('dune-2021');
      expect(answer.ids, const ExternalIds());
      expect(answer.authoritative, isFalse, reason: 'an empty answer from such a server must never be stored as final');
    });

    test('an item the server no longer has answers empty', () async {
      client = await connected(serverWith());
      expect(await client.fetchExternalIds('gone'), const ExternalIds());
    });

    test('429, 500 and 503 are "could not check", never "no numbers", and a later retry recovers', () async {
      final server = serverWith();
      client = await connected(server);
      for (final (status, code) in [
        (429, 'auth.rate_limited'),
        (500, 'server.internal'),
        (503, 'storage.unavailable'),
      ]) {
        server.queueFailure(pathPrefix: '/items/', status: status, errorCode: code);
        await expectLater(
          client.fetchExternalIds('dune-2021'),
          throwsA(isA<IdentityLookupUnavailable>()),
          reason: '$status',
        );
        expect(
          await client.fetchExternalIds('dune-2021'),
          const ExternalIds(tmdb: 438631),
          reason: 'recovered after $status',
        );
        client.debugForgetExternalIds();
      }
    });

    test('an unreachable server and offline mode both throw, and recover when the server is back', () async {
      final server = serverWith();
      client = await connected(server);
      server.unreachable = true;
      await expectLater(client.fetchExternalIds('dune-2021'), throwsA(isA<IdentityLookupUnavailable>()));
      server.unreachable = false;
      client.setOfflineMode(true);
      await expectLater(client.fetchExternalIds('dune-2021'), throwsA(isA<IdentityLookupUnavailable>()));
      client.setOfflineMode(false);
      expect(await client.fetchExternalIds('dune-2021'), const ExternalIds(tmdb: 438631));
    });

    test('numbers read off a page or a detail answer need no second request', () async {
      final server = serverWith();
      client = await connected(server);

      await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());
      server.requests.clear();
      expect(await client.fetchExternalIds('dune-2021'), const ExternalIds(tmdb: 438631));
      expect(await client.fetchExternalIds('unmatched'), const ExternalIds());
      expect(server.requests, isEmpty, reason: 'the page already carried them');

      await client.fetchItem('severance');
      server.requests.clear();
      expect(await client.fetchExternalIds('severance'), const ExternalIds(tmdb: 95396));
      expect(server.requests, isEmpty);
    });

    test(
      'a page read again replaces remembered numbers, so a later match shows without waiting for a timeout',
      () async {
        final server = serverWith();
        client = await connected(server);
        await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());
        expect(await client.fetchExternalIds('unmatched'), const ExternalIds());

        server.items['unmatched']!['external_ids'] = {'tmdb': 9};
        await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());

        expect(await client.fetchExternalIds('unmatched'), const ExternalIds(tmdb: 9));
      },
    );

    test('a new client after an account switch remembers nothing of the old one', () async {
      final server = serverWith();
      client = await connected(server);
      await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());
      final other = await connected(server);
      addTearDown(other.close);
      server.requests.clear();

      await other.fetchExternalIds('dune-2021');

      expect(server.requests.where((r) => r.contains('/items/dune-2021')), hasLength(1));
    });

    test('a large library costs no detail request per title once its pages were read', () async {
      final server = PleyaFakeServer()..addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      for (var i = 0; i < 600; i++) {
        server.addItem(
          id: 'm$i',
          kind: 'movie',
          title: 'Film $i',
          libraryId: 'lib-films',
          year: 2000,
          externalIds: i.isEven ? {'tmdb': 1000 + i} : null,
        );
      }
      client = await connected(server);
      var offset = 0;
      while (offset < 600) {
        final page = await client.fetchLibraryPagedContent(
          'lib-films',
          query: LibraryQuery(offset: offset, limit: 200),
        );
        offset += page.items.length;
        if (page.items.isEmpty) break;
      }
      server.requests.clear();
      for (var i = 0; i < 600; i++) {
        await client.fetchExternalIds('m$i');
      }
      expect(server.requests.where((r) => r.contains('/items/')), isEmpty);
    });
  });

  group('findAllByIdentity', () {
    tearDown(() => client.close());

    MediaIdentity dune({
      int? tmdb = 438631,
      MediaKind kind = MediaKind.movie,
      String title = 'Dune',
      int year = 2021,
    }) => MediaIdentity(
      externalIds: ExternalIds(tmdb: tmdb),
      title: title,
      year: year,
      kind: kind,
    );

    test('finds the title by number, not the remake with the same name and not an unmatched one', () async {
      client = await connected(serverWith());
      expect((await client.findAllByIdentity(dune())).map((m) => m.id), ['dune-2021']);
    });

    test('the folder title and the year the server holds play no part', () async {
      final server = serverWith();
      server.addItem(
        id: 'other-name',
        kind: 'movie',
        title: 'Duin (extended)',
        libraryId: 'lib-films',
        year: 2020,
        durationMs: 1000,
        externalIds: {'tmdb': 777},
      );
      client = await connected(server);

      final hits = await client.findAllByIdentity(dune(tmdb: 777, title: 'Dune: Part One', year: 2021));

      expect(hits.map((m) => m.id), ['other-name']);
    });

    test('every hit carries its library, so hidden libraries can be filtered like for any backend', () async {
      client = await connected(serverWith());
      final hit = (await client.findAllByIdentity(dune())).single;
      expect(hit.libraryId, 'lib-films');
    });

    test('a number is per kind: the show with the same number does not answer a movie', () async {
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

    test('a server that knows the field and does not have the title answers a real, empty "not here"', () async {
      client = await connected(serverWith());
      expect(await client.findAllByIdentity(dune(tmdb: 1)), isEmpty);
    });

    test('an identity without a tmdb number or kind is unsupported here, not absent', () async {
      client = await connected(serverWith());
      await expectLater(
        client.findAllByIdentity(
          const MediaIdentity(externalIds: ExternalIds(tvdb: 9), title: 'Dune', year: 2021, kind: MediaKind.movie),
        ),
        throwsA(isA<IdentityLookupUnsupported>()),
      );
      await expectLater(
        client.findAllByIdentity(dune(kind: MediaKind.unknown)),
        throwsA(isA<IdentityLookupUnsupported>()),
      );
    });

    test('a server without the lookup capability is unsupported, which is not a complete "not here"', () async {
      client = await connected(serverWith(reportsExternalIds: false));
      await expectLater(client.findAllByIdentity(dune()), throwsA(isA<IdentityLookupUnsupported>()));
    });

    test('a client that never heard from /info cannot tell', () async {
      final fresh = serverWith().client();
      client = fresh;
      await expectLater(fresh.findAllByIdentity(dune()), throwsA(isA<IdentityLookupUnsupported>()));
    });

    test('transport failures are "unavailable" and recover; they are never an empty answer', () async {
      final server = serverWith();
      client = await connected(server);
      server.unreachable = true;
      await expectLater(client.findAllByIdentity(dune()), throwsA(isA<IdentityLookupUnavailable>()));
      server.unreachable = false;
      server.queueFailure(pathPrefix: '/libraries', status: 503);
      await expectLater(client.findAllByIdentity(dune()), throwsA(isA<IdentityLookupUnavailable>()));
      server.queueFailure(pathPrefix: '/libraries/', status: 429, errorCode: 'auth.rate_limited');
      // /libraries answers, the first library listing is the one refused.
      await expectLater(client.findAllByIdentity(dune()), throwsA(isA<IdentityLookupUnavailable>()));
      expect((await client.findAllByIdentity(dune())).map((m) => m.id), ['dune-2021']);
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
