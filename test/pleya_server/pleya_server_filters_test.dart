import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// Filters, facets and the failing write (S14.2, S14.3), against a fake that
/// speaks the contract of venster 3 pakket D1.
void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  Future<PleyaServerClient> connected() async {
    final c = server.client();
    await c.refreshCapabilities();
    return c;
  }

  Future<List<String>> titles(LibraryQuery query) async {
    final page = await client.fetchLibraryPagedContent('lib-films', query: query);
    return page.items.map((i) => i.title ?? '').toList()..sort();
  }

  setUp(() {
    server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies', itemCount: 4);
    server.addItem(
      id: 'm1',
      kind: 'movie',
      title: 'Alien',
      libraryId: 'lib-films',
      year: 1979,
      durationMs: 7000000,
      genres: ['Horror', 'Sci-Fi'],
      contentRating: '16',
    );
    server.addItem(
      id: 'm2',
      kind: 'movie',
      title: 'Heat',
      libraryId: 'lib-films',
      year: 1995,
      durationMs: 10200000,
      genres: ['Drama'],
      contentRating: '16',
    );
    server.addItem(
      id: 'm3',
      kind: 'movie',
      title: 'Up',
      libraryId: 'lib-films',
      year: 2009,
      durationMs: 5800000,
      genres: ['drama', 'Animatie'],
      contentRating: 'AL',
    );
    server.addItem(
      id: 'm4',
      kind: 'movie',
      title: 'Dune',
      libraryId: 'lib-films',
      year: 2021,
      durationMs: 9300000,
      genres: ['Sci-Fi'],
      contentRating: '12',
    );
  });

  tearDown(() => client.close());

  group('with capabilities.filters', () {
    setUp(() => server.filtersCapability = true);

    test('the capability is read from /info', () async {
      client = await connected();
      expect(client.wireCapabilities.filters, isTrue);
    });

    test('genres go out as repeated parameters and narrow the list', () async {
      client = await connected();
      expect(await titles(const LibraryQuery(genres: ['drama'])), ['Heat', 'Up']);
      expect(await titles(const LibraryQuery(genres: ['horror', 'animatie'])), ['Alien', 'Up']);
      expect(server.requests.any((r) => r.contains('genre=horror') && r.contains('genre=animatie')), isTrue);
    });

    test('the filter sheet\'s comma-joined value is split again', () async {
      client = await connected();
      expect(await titles(const LibraryQuery(genres: ['horror,animatie'])), ['Alien', 'Up']);
    });

    test('years, content ratings and the three watch states', () async {
      client = await connected();
      expect(await titles(const LibraryQuery(years: [1995, 2021])), ['Dune', 'Heat']);
      expect(await titles(const LibraryQuery(officialRatings: ['16'])), ['Alien', 'Heat']);

      await client.reportPlaybackStopped(
        itemId: 'm2',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 170),
      );
      expect(await titles(const LibraryQuery(inProgressOnly: true)), ['Heat']);
      expect(await titles(const LibraryQuery(includeWatched: false)), ['Alien', 'Dune', 'Heat', 'Up']);
      await client.markWatched(
        (await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery())).items.first,
      );
      expect(await titles(const LibraryQuery(watchedOnly: true)), hasLength(1));
    });

    test('a year outside 1800 to 2200 is never sent', () async {
      client = await connected();
      await titles(const LibraryQuery(years: [82, 1995]));
      expect(server.requests.any((r) => r.contains('year=1995')), isTrue);
      expect(server.requests.any((r) => r.contains('year=82')), isFalse);
    });

    test('a cursor for one filter set is not reused for another', () async {
      client = await connected();
      await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 1, genres: ['sci-fi']));
      final before = server.requests.length;
      // Offset 1 under another filter set must start from the top, not resume a foreign cursor.
      await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(offset: 1, limit: 1, genres: ['drama']),
      );
      final sent = server.requests.skip(before).where((r) => r.contains('/items')).toList();
      expect(sent.first.contains('cursor='), isFalse, reason: sent.first);
    });

    test('last played and duration are real sorts, not a fallback to title', () async {
      client = await connected();
      await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(sort: LibrarySort(field: 'lastViewedAt')),
      );
      await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(
          sort: LibrarySort(field: 'duration', direction: LibrarySortDirection.ascending),
        ),
      );
      expect(server.requests.any((r) => r.contains('sort=-last_played_at')), isTrue);
      expect(server.requests.any((r) => r.contains('sort=duration')), isTrue);
      final keys = (await client.fetchSortOptions('lib-films')).map((s) => s.key);
      expect(keys, containsAll(['lastViewedAt', 'duration']));
    });

    test('the filter sheet is filled from /facets, with the counts left to the server', () async {
      client = await connected();
      final result = await client.fetchLibraryFiltersWithValues('lib-films');
      expect(result.filters.map((f) => f.filter), containsAll(['unwatched', 'genre', 'year', 'contentRating']));
      expect(result.cachedValues['genre']!.map((v) => v.key), containsAll(['Sci-Fi', 'Horror']));
      expect(result.cachedValues['year']!.map((v) => v.key).first, '2021');
      expect(server.requests.any((r) => r.endsWith('/libraries/lib-films/facets')), isTrue);
    });
  });

  group('without capabilities.filters', () {
    test('a filter answers an empty page instead of the whole library', () async {
      client = await connected();
      final before = server.requests.length;
      final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(genres: ['drama']));
      expect(page.items, isEmpty);
      expect(server.requests.skip(before).any((r) => r.contains('/items')), isFalse, reason: 'no request goes out');
    });

    test('an unfiltered list and the old sorts are untouched', () async {
      client = await connected();
      expect(await titles(const LibraryQuery()), hasLength(4));
      final keys = (await client.fetchSortOptions('lib-films')).map((s) => s.key).toList();
      expect(keys, ['title', 'addedAt', 'year']);
      await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(sort: LibrarySort(field: 'duration')),
      );
      expect(server.requests.any((r) => r.contains('sort=duration')), isFalse);
    });

    test('the filter sheet is empty and /facets is never called', () async {
      client = await connected();
      final result = await client.fetchLibraryFiltersWithValues('lib-films');
      expect(result.filters, isEmpty);
      expect(server.requests.any((r) => r.contains('/facets')), isFalse);
    });
  });

  group('a write that fails', () {
    test('a fast 5xx on /watch-state reaches the caller (backlog 24.3)', () async {
      client = await connected();
      server.watchStateFailureStatus = 503;
      await expectLater(
        client.reportPlaybackStopped(
          itemId: 'm1',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 117),
        ),
        throwsA(isA<MediaServerHttpException>().having((e) => e.statusCode, 'statusCode', 503)),
      );
      await expectLater(
        client.reportPlaybackProgress(
          itemId: 'm1',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 117),
        ),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(server.watchEvents, isEmpty, reason: 'the server recorded nothing, and the client did not pretend it did');
    });

    test('a 404 is not swallowed either', () async {
      client = await connected();
      server.watchStateFailureStatus = 404;
      await expectLater(
        client.reportPlaybackStopped(itemId: 'm1', position: Duration.zero, duration: const Duration(minutes: 117)),
        throwsA(isA<MediaServerHttpException>()),
      );
    });

    test('the write works again once the server does', () async {
      client = await connected();
      server.watchStateFailureStatus = 500;
      await expectLater(
        client.reportPlaybackStopped(
          itemId: 'm1',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 117),
        ),
        throwsA(isA<MediaServerHttpException>()),
      );
      server.watchStateFailureStatus = null;
      await client.reportPlaybackStopped(
        itemId: 'm1',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 117),
      );
      expect(server.watchEvents, hasLength(1));
    });

    test('a failed stream-token mint is still "no URL", not an exception', () async {
      client = await connected();
      final item = await client.fetchItem('m1');
      server.rejectCurrentAccessTokens = true;
      expect(await client.resolveExternalPlaybackUrl(item!), isNull);
    });
  });
}
