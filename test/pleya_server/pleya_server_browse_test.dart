import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// Browsing against a fake that speaks the real contract, cursors included.
///
/// The paging walk is the part worth testing here. The app counts in offsets
/// and the protocol pages with opaque cursors, and the translation between the
/// two is the only place in PS-3 where an off-by-one silently shows the wrong
/// titles instead of failing.
void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  setUp(() {
    server = PleyaFakeServer();
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies', itemCount: 3);
    server.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows', itemCount: 1);
  });

  tearDown(() => client.close());

  group('libraries', () {
    test('map to the neutral model with kinds', () async {
      client = await connected(server);
      final libraries = await client.fetchLibraries();
      expect(libraries, hasLength(2));
      expect(libraries.first.title, 'Films');
      expect(libraries.first.kind, MediaKind.movie);
      expect(libraries.last.kind, MediaKind.show);
      expect(libraries.every((l) => l.backend == MediaBackend.pleyaServer), isTrue);
    });

    test('a library of an unknown kind is hidden rather than shown unbrowsable', () async {
      server.addLibrary(id: 'lib-music', title: 'Muziek', kind: 'music');
      client = await connected(server);
      final libraries = await client.fetchLibraries();
      expect(libraries.map((l) => l.id), isNot(contains('lib-music')));
      expect(libraries, hasLength(2));
    });

    test('nothing is fetched before /info says browse is on', () async {
      client = server.client();
      final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());
      expect(page.items, isEmpty, reason: 'a client that has not heard from the server does not call its endpoints');
    });
  });

  group('movies', () {
    setUp(() {
      for (var i = 1; i <= 25; i++) {
        server.addItem(
          id: 'movie-${i.toString().padLeft(2, '0')}',
          kind: 'movie',
          title: 'Film ${i.toString().padLeft(2, '0')}',
          libraryId: 'lib-films',
          year: 2000 + i,
          durationMs: 6000000,
        );
      }
    });

    test('the first page comes back in sort order', () async {
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 10));
      expect(page.items, hasLength(10));
      expect(page.items.first.title, 'Film 01');
      expect(page.items.last.title, 'Film 10');
      expect(page.totalCount, 25);
      expect(page.items.every((item) => item.backend == MediaBackend.pleyaServer), isTrue);
    });

    test('a second page continues where the first stopped', () async {
      client = await connected(server);
      await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 10));
      final second = await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(limit: 10, offset: 10),
      );
      expect(second.items.first.title, 'Film 11');
      expect(second.items.last.title, 'Film 20');
    });

    test('a library that pages smaller than the window still fills it', () async {
      // The walk used to stop after ten pages whatever they held, so a server
      // that answers four at a time returned forty items for a fifty-item
      // window while its cursor still pointed at more. One layer up a short
      // page *is* the end-of-library signal (E8), so the rest of the library
      // silently never appeared and the catalogue reported itself complete.
      final small = PleyaFakeServer(pageSizeCap: 4);
      small.addLibrary(id: 'lib-big', title: 'Groot', kind: 'movies', itemCount: 120);
      for (var i = 1; i <= 120; i++) {
        small.addItem(
          id: 'big-${i.toString().padLeft(3, '0')}',
          kind: 'movie',
          title: 'Film ${i.toString().padLeft(3, '0')}',
          libraryId: 'lib-big',
        );
      }
      client = await connected(small);

      final page = await client.fetchLibraryPagedContent('lib-big', query: const LibraryQuery(limit: 50));

      expect(page.items, hasLength(50), reason: 'the window is filled, not truncated at the walk bound');
      expect(page.items.map((i) => i.id).toSet(), hasLength(50), reason: 'and without repeating a page');
    });

    test('a resumed page reuses the stored cursor instead of walking again', () async {
      client = await connected(server);
      await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 10));
      final before = server.requests.length;
      await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 10, offset: 10));
      expect(
        server.requests.length - before,
        1,
        reason: 'the boundary at offset 10 was recorded, so one request is enough',
      );
    });

    test('a jump past anything scrolled walks forward rather than guessing', () async {
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 5, offset: 12));
      expect(page.items.first.title, 'Film 13');
      expect(page.items, hasLength(5));
    });

    test('the last page is short and does not loop', () async {
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery(limit: 10, offset: 20));
      expect(page.items, hasLength(5));
      expect(page.items.last.title, 'Film 25');
    });

    test('a descending sort is spelled with a leading minus, not a direction parameter', () async {
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(
          limit: 3,
          sort: LibrarySort(field: 'addedAt', direction: LibrarySortDirection.descending),
        ),
      );
      expect(server.requests.any((r) => r.contains('sort=-added_at')), isTrue);
      expect(page.items, hasLength(3));
    });

    test('a sort field the contract does not carry falls back to title, not to a 400', () async {
      client = await connected(server);
      await client.fetchLibraryPagedContent(
        'lib-films',
        query: const LibraryQuery(limit: 3, sort: LibrarySort(field: 'communityRating')),
      );
      expect(
        server.requests.any((r) => r.contains('sort=title') || r.contains('sort=-title')),
        isTrue,
        reason: 'the direction survives, the unknown field does not',
      );
      expect(server.requests.any((r) => r.contains('communityRating')), isFalse);
    });

    test('the sort sheet offers exactly what the contract accepts', () async {
      client = await connected(server);
      final sorts = await client.fetchSortOptions('lib-films');
      expect(sorts.map((s) => s.key), ['title', 'addedAt', 'year']);
    });

    test('one movie carries its version and edition', () async {
      server.addItem(
        id: 'movie-blade',
        kind: 'movie',
        title: 'Blade Runner',
        libraryId: 'lib-films',
        durationMs: 7020000,
        edition: "Director's Cut",
      );
      client = await connected(server);
      final item = await client.fetchItem('movie-blade');
      expect(item, isNotNull);
      expect(item!.kind, MediaKind.movie);
      expect(item.mediaVersions, hasLength(1));
      expect(item.mediaVersions!.single.name, "Director's Cut");
    });

    test('an item that is gone is null, not an exception', () async {
      client = await connected(server);
      expect(await client.fetchItem('does-not-exist'), isNull);
    });
  });

  group('shows, seasons and episodes', () {
    setUp(() {
      server.addItem(
        id: 'show-1',
        kind: 'show',
        title: 'How I Met Your Mother',
        libraryId: 'lib-series',
        childCount: 2,
        episodeCount: 40,
        watchedEpisodeCount: 5,
      );
      for (var s = 1; s <= 2; s++) {
        server.addItem(id: 'season-$s', kind: 'season', title: 'Season $s', parentId: 'show-1', index: s);
        for (var e = 1; e <= 3; e++) {
          server.addItem(
            id: 'ep-$s-$e',
            kind: 'episode',
            title: 'Episode $e',
            parentId: 'season-$s',
            index: e,
            durationMs: 1320000,
          );
        }
      }
    });

    test('a shows library lists shows, not episodes', () async {
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent('lib-series', query: const LibraryQuery());
      expect(page.items.map((i) => i.kind).toSet(), {MediaKind.show});
    });

    test('a show carries its episode rollup', () async {
      client = await connected(server);
      final show = await client.fetchItem('show-1');
      expect(show!.childCount, 2);
      expect(show.leafCount, 40);
      expect(show.viewedLeafCount, 5);
    });

    test('children of a show are its seasons, in order', () async {
      client = await connected(server);
      final seasons = await client.fetchChildren('show-1');
      expect(seasons.map((s) => s.kind).toSet(), {MediaKind.season});
      expect(seasons.map((s) => s.index), [1, 2]);
    });

    test('an episode gets its season and its show columns filled', () async {
      client = await connected(server);
      final episodes = await client.fetchChildren('season-2');
      expect(episodes, hasLength(3));
      final first = episodes.first;
      expect(first.kind, MediaKind.episode);
      expect(first.parentId, 'season-2');
      expect(first.parentTitle, 'Season 2');
      expect(first.parentIndex, 2);
      expect(first.grandparentId, 'show-1');
      expect(first.grandparentTitle, 'How I Met Your Mother');
    });

    test('one ancestor read serves a whole page of episodes', () async {
      client = await connected(server);
      final before = server.requests.length;
      await client.fetchChildren('season-1');
      final itemReads = server.requests
          .skip(before)
          .where((r) => RegExp(r'/items/[^/]+$').hasMatch(r.split('?').first))
          .length;
      expect(itemReads, lessThanOrEqualTo(2), reason: 'three episodes share one season and one show');
    });

    test('playable descendants of a show are its episodes across seasons', () async {
      client = await connected(server);
      final leaves = await client.fetchPlayableDescendants('show-1');
      expect(leaves, hasLength(6));
      expect(leaves.every((item) => item.kind == MediaKind.episode), isTrue);
    });

    test('a movie has no children and that is a list, not an error', () async {
      server.addItem(id: 'movie-solo', kind: 'movie', title: 'Solo', libraryId: 'lib-films', durationMs: 1000);
      client = await connected(server);
      expect(await client.fetchChildren('movie-solo'), isEmpty);
    });
  });

  group('hubs', () {
    setUp(() {
      for (var i = 1; i <= 3; i++) {
        server.addItem(id: 'recent-$i', kind: 'movie', title: 'Recent $i', libraryId: 'lib-films', durationMs: 6000000);
        server.hubs['recently_added']!.add('recent-$i');
      }
    });

    test('recently added comes back as a home row', () async {
      client = await connected(server);
      final hubs = await client.fetchGlobalHubs();
      expect(hubs, hasLength(1));
      expect(hubs.single.identifier, 'home.recent');
      expect(hubs.single.items, hasLength(3));
    });

    test('a server without watch state is never asked for the playback hubs', () async {
      client = await connected(server);
      await client.fetchGlobalHubs();
      expect(server.requests.any((r) => r.contains('continue_watching')), isFalse);
      expect(server.requests.any((r) => r.contains('next_up')), isFalse);
    });

    test('empty playback rows do not reach the home screen as blank sections', () async {
      final withWatchState = PleyaFakeServer(watchState: true);
      withWatchState.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      withWatchState.addItem(
        id: 'recent-1',
        kind: 'movie',
        title: 'Recent 1',
        libraryId: 'lib-films',
        durationMs: 1000,
      );
      withWatchState.hubs['recently_added']!.add('recent-1');
      client = await connected(withWatchState);
      final hubs = await client.fetchGlobalHubs();
      expect(
        withWatchState.requests.any((r) => r.contains('continue_watching')),
        isTrue,
        reason: 'the server said it has watch state, so the row is worth asking for',
      );
      expect(hubs.map((h) => h.identifier), ['home.recent']);
      expect(hubs.every((h) => h.items.isNotEmpty), isTrue);
    });

    test('the identifiers are the ones the generic hub logic already knows', () async {
      final withWatchState = PleyaFakeServer(watchState: true);
      withWatchState.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      withWatchState.addItem(
        id: 'resume-1',
        kind: 'movie',
        title: 'Resume 1',
        libraryId: 'lib-films',
        durationMs: 1000,
        userState: const {'position_ms': 500, 'watched': false, 'play_count': 0, 'updated_at': '2026-08-18T20:12:44Z'},
      );
      withWatchState.hubs['continue_watching']!.add('resume-1');
      client = await connected(withWatchState);
      final hubs = await client.fetchGlobalHubs();
      final resume = hubs.firstWhere((h) => h.identifier == 'home.continue');
      expect(resume.isContinueWatchingHub, isTrue);
      expect(resume.usesContinueWatchingAction, isTrue);
      expect(resume.items.single.viewOffsetMs, 500);
    });

    test('a library hub is scoped to that library', () async {
      client = await connected(server);
      final hubs = await client.fetchLibraryHubs('lib-films', libraryName: 'Films');
      expect(hubs.single.libraryId, 'lib-films');
      expect(server.requests.any((r) => r.contains('library_id=lib-films')), isTrue);
    });

    test('more items for a hub resolve the hub id back to its endpoint', () async {
      client = await connected(server);
      final more = await client.fetchMoreHubItems('home.recent', limit: 2);
      expect(more, hasLength(2));
      expect(await client.fetchMoreHubItems('home.nonsense'), isEmpty);
    });

    test('recently added shows filters to shows without a second call', () async {
      server.addItem(id: 'show-x', kind: 'show', title: 'Serie X', libraryId: 'lib-series');
      server.hubs['recently_added']!.add('show-x');
      client = await connected(server);
      final shows = await client.fetchRecentlyAddedShows();
      expect(shows.map((s) => s.kind).toSet(), {MediaKind.show});
    });
  });

  group('a server that stops answering', () {
    test('gives an empty page instead of throwing into the grid', () async {
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent('lib-unknown', query: const LibraryQuery());
      expect(page.items, isEmpty);
    });

    test('offline mode does not reach the network at all', () async {
      client = await connected(server);
      final before = server.requests.length;
      client.setOfflineMode(true);
      expect(await client.fetchLibraries(), isEmpty);
      expect(server.requests.length, before);
    });
  });

  group('unknown-safe values', () {
    test('an item of a kind this build does not know never reaches the grid', () async {
      server.addItem(id: 'movie-1', kind: 'movie', title: 'Film', libraryId: 'lib-films', durationMs: 1000);
      server.items['concert-1'] = {
        'id': 'concert-1',
        'kind': 'concert',
        'title': 'Live at Wembley',
        'added_at': '2026-06-18T21:34:02Z',
        'artwork': const {'poster_id': null, 'backdrop_id': null},
        'versions': const [],
        'user_state': null,
      };
      server.libraryItems['lib-films']!.add('concert-1');
      client = await connected(server);
      final page = await client.fetchLibraryPagedContent('lib-films', query: const LibraryQuery());
      expect(page.items.map((i) => i.id), ['movie-1']);
    });
  });
}
