import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_first_character.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/screens/libraries/alpha_jump_helper.dart';
import 'package:pleya/screens/libraries/library_alpha_bar_strategy.dart';
import 'package:pleya/screens/libraries/title_index_alpha_bar_strategy.dart';
import 'package:pleya/screens/libraries/title_letter_index.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/plex_client.dart';

/// Answers `fetchLibraryPagedContent` from a fixed, already ordered listing,
/// the way local folders and Pleya Server hand the grid its pages.
class _ListingClient implements MediaServerClient {
  _ListingClient(this.titles, {int? reportedTotal}) : reportedTotal = reportedTotal ?? titles.length;

  final List<String> titles;
  final int reportedTotal;
  LibraryQuery? lastQuery;

  @override
  ServerId get serverId => ServerId('srv');

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    lastQuery = query;
    final items = [
      for (var i = 0; i < titles.length; i++)
        MediaItem(id: '$i', backend: MediaBackend.local, kind: MediaKind.movie, title: titles[i], serverId: 'srv'),
    ];
    return LibraryPage(items: items, totalCount: reportedTotal, offset: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [count] titles starting with each letter of [letters], in that order.
List<String> _titles(String letters, {int count = 20}) => [
  for (final letter in letters.split(''))
    for (var i = 0; i < count; i++) '$letter title $i',
];

JellyfinConnection _conn() => JellyfinConnection(
  id: 'srv/u1',
  baseUrl: 'https://jf.example.com',
  serverName: 'JF',
  serverMachineId: 'srv',
  userId: 'u1',
  userName: 'user',
  accessToken: 'tok',
  deviceId: 'dev',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

const _query = LibraryQuery(sort: LibrarySort(field: 'title'));

void main() {
  group('Jellyfin counts to offsets', () {
    // Counts as the demo server answered them for its 12 films:
    // b c c c [the] d e g s s s t w. "The Daily Dweebs" counts under D.
    final before = {
      for (final bound in titleIndexBounds)
        bound: switch (bound) {
          'a' || 'b' => 0,
          'c' => 1,
          'd' => 4,
          'e' => 5,
          'f' || 'g' => 6,
          'h' || 'i' || 'j' || 'k' || 'l' || 'm' || 'n' || 'o' || 'p' || 'q' || 'r' || 's' => 7,
          't' => 10,
          'u' || 'v' || 'w' => 11,
          _ => 12,
        },
    };

    test('every letter starts at the number of titles before it', () {
      final chars = letterIndexFromCountsBefore(total: 12, before: before)!;
      final helper = AlphaJumpHelper(chars);
      expect(helper.letters, ['B', 'C', 'D', 'E', 'G', 'S', 'T', 'W']);
      expect(helper.letterToIndex, {'B': 0, 'C': 1, 'D': 4, 'E': 5, 'G': 6, 'S': 7, 'T': 10, 'W': 11});
      expect(helper.totalItemCount, 12);
    });

    test('titles before a and after z land in # and Z, offsets stay put', () {
      final shifted = {for (final e in before.entries) e.key: e.value + 3};
      final helper = AlphaJumpHelper(letterIndexFromCountsBefore(total: 17, before: shifted)!);
      expect(helper.letters.first, '#');
      expect(helper.letterToIndex['#'], 0);
      expect(helper.letterToIndex['B'], 3);
      expect(helper.letterToIndex['Z'], 15);
      expect(helper.totalItemCount, 17);
    });

    test('a count that goes down means the listing moved: no index', () {
      expect(letterIndexFromCountsBefore(total: 12, before: {...before, 'm': 2}), isNull);
      expect(letterIndexFromCountsBefore(total: 5, before: before), isNull);
      expect(letterIndexFromCountsBefore(total: 12, before: {...before}..remove('q')), isNull);
    });

    test('JellyfinClient asks NameLessThan per bound on the grid query, without paging or sort', () async {
      final requests = <Uri>[];
      final client = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final bound = request.url.queryParameters['NameLessThan'];
          final total = bound == null ? 12 : before[bound]!;
          return http.Response(
            jsonEncode({'Items': <Object>[], 'TotalRecordCount': total}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      final query = LibraryQuery(
        sort: const LibrarySort(field: 'title', direction: LibrarySortDirection.descending),
        genres: const ['Animation'],
        offset: 40,
        limit: 72,
      );
      final strategy = TitleIndexAlphaBarStrategy.counted(
        clientProvider: () => client,
        libraryKey: 'lib1',
        libraryKind: MediaKind.movie,
      );
      final result = await strategy.loadCharacters(filters: const {}, typeId: null, descending: true, query: query);

      expect(requests, hasLength(27));
      for (final url in requests) {
        expect(url.path, '/Items');
        expect(url.queryParameters['ParentId'], 'lib1');
        expect(url.queryParameters['Genres'], 'Animation');
        expect(url.queryParameters['IncludeItemTypes'], 'Movie');
        expect(url.queryParameters['Limit'], '0');
        expect(url.queryParameters['StartIndex'], '0');
        expect(url.queryParameters.containsKey('SortBy'), isFalse);
        expect(url.queryParameters.containsKey('NameStartsWith'), isFalse);
      }
      expect(requests.map((u) => u.queryParameters['NameLessThan']).whereType<String>().toList(), titleIndexBounds);
      // Descending: the helper reverses the buckets, W first.
      expect(result.helper.letters.first, 'W');
      expect(result.helper.letterToIndex['W'], 0);
      expect(result.helper.letterToIndex['B'], 11);
    });

    test('a server without an exact total hides the rail', () async {
      final client = JellyfinClient.forTesting(
        connection: _conn(),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'Items': <Object>[]}),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
      final strategy = TitleIndexAlphaBarStrategy.counted(
        clientProvider: () => client,
        libraryKey: 'lib1',
        libraryKind: MediaKind.movie,
      );
      expect(
        strategy.loadCharacters(filters: const {}, typeId: null, descending: false, query: _query),
        throwsStateError,
      );
    });
  });

  group('ordered listing to offsets (local folders, Pleya Server)', () {
    test('runs of first letters become cumulative offsets', () async {
      final client = _ListingClient(['1917', ..._titles('ABCDEFG'), 'Zodiac']);
      final strategy = TitleIndexAlphaBarStrategy.fromListing(
        clientProvider: () => client,
        libraryKey: 'lib',
        libraryKind: MediaKind.movie,
        sortTitleOf: (item) => item.title ?? '',
      );
      final result = await strategy.loadCharacters(filters: const {}, typeId: null, descending: false, query: _query);
      expect(client.lastQuery!.offset, 0);
      expect(result.helper.letters, ['#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'Z']);
      expect(result.helper.letterToIndex['A'], 1);
      expect(result.helper.letterToIndex['C'], 41);
      expect(result.helper.letterToIndex['Z'], 141);
      expect(result.helper.totalItemCount, 142);
    });

    test('descending listing maps to the reversed buckets', () {
      final titles = _titles('ABC', count: 3).reversed.toList();
      final helper = AlphaJumpHelper(letterIndexFromOrderedTitles(titles, descending: true)!, descending: true);
      expect(helper.letters, ['C', 'B', 'A']);
      expect(helper.letterToIndex, {'C': 0, 'B': 3, 'A': 6});
    });

    test('date-added order is not a title order: no index', () {
      expect(letterIndexFromOrderedTitles(['Brave', 'Alien', 'Cars', 'Avatar'], descending: false), isNull);
    });

    test('a listing sorted against the letters (article rule, case) gives no index', () {
      // Sorted on a sort title that drops "The": the T run would split.
      expect(letterIndexFromOrderedTitles(['Alien', 'The Batman', 'Cars', 'Tenet'], descending: false), isNull);
      // Case-sensitive codepoint order puts lower case after Z.
      expect(letterIndexFromOrderedTitles(['Alien', 'Zoo', 'avatar'], descending: false), isNull);
    });

    test('a short or uncounted read hides the rail', () async {
      final client = _ListingClient(_titles('ABCDEF'), reportedTotal: 500);
      final strategy = TitleIndexAlphaBarStrategy.fromListing(
        clientProvider: () => client,
        libraryKey: 'lib',
        libraryKind: MediaKind.movie,
        sortTitleOf: (item) => item.title ?? '',
      );
      final result = await strategy.loadCharacters(filters: const {}, typeId: null, descending: false, query: _query);
      expect(result.chars, isEmpty);
    });

    test('a non-title sort sends no request at all', () async {
      final client = _ListingClient(_titles('ABCDEF'));
      final strategy = TitleIndexAlphaBarStrategy.fromListing(
        clientProvider: () => client,
        libraryKey: 'lib',
        libraryKind: MediaKind.movie,
        sortTitleOf: (item) => item.title ?? '',
      );
      final result = await strategy.loadCharacters(
        filters: const {},
        typeId: null,
        descending: false,
        query: const LibraryQuery(sort: LibrarySort(field: 'addedAt')),
      );
      expect(result.chars, isEmpty);
      expect(client.lastQuery, isNull);
    });
  });

  group('visibility', () {
    final chars = [for (final l in 'ABCDEF'.split('')) LibraryFirstCharacter(key: l, title: l, size: 20)];
    final strategy = TitleIndexAlphaBarStrategy((query, {required descending}) async => chars);

    bool show({
      int total = 120,
      int loaded = 6,
      String? sortKey = 'title',
      bool isPhone = true,
      int? indexItemCount,
      bool folders = false,
    }) => strategy.shouldShow(
      totalItemCount: total,
      loadedCharacterCount: loaded,
      sortKey: sortKey,
      isFolderGrouping: folders,
      jellyfinAlphaPrefix: null,
      isPhone: isPhone,
      indexItemCount: indexItemCount ?? total,
    );

    test('shows on a phone for a title-sorted listing that matches its index', () {
      expect(show(), isTrue);
      expect(show(sortKey: null), isTrue);
    });

    test('hides when the index is missing, too small, or off', () {
      expect(show(loaded: 0), isFalse);
      expect(show(loaded: 5), isFalse);
      expect(show(total: 79), isFalse);
      expect(show(indexItemCount: 119), isFalse);
      expect(show(sortKey: 'addedAt'), isFalse);
      expect(show(folders: true), isFalse);
      expect(show(isPhone: false), isFalse);
    });
  });

  group('backend routing', () {
    LibraryAlphaBarStrategy forBackend(MediaBackend backend, {required bool isPhone}) =>
        LibraryAlphaBarStrategy.forBackend(
          backend,
          plexClientProvider: () => throw StateError('unused'),
          clientProvider: () => throw StateError('unused'),
          libraryKey: 'lib',
          libraryKind: MediaKind.movie,
          isShared: false,
          isPhone: isPhone,
        );

    test('phone: every non-Plex backend gets the title index, Plex keeps its own', () {
      expect(forBackend(MediaBackend.plex, isPhone: true), isA<PlexAlphaBarStrategy>());
      expect(forBackend(MediaBackend.jellyfin, isPhone: true), isA<TitleIndexAlphaBarStrategy>());
      expect(forBackend(MediaBackend.local, isPhone: true), isA<TitleIndexAlphaBarStrategy>());
      expect(forBackend(MediaBackend.pleyaServer, isPhone: true), isA<TitleIndexAlphaBarStrategy>());
    });

    test('tablet, desktop and TV keep what they had', () {
      expect(forBackend(MediaBackend.plex, isPhone: false), isA<PlexAlphaBarStrategy>());
      expect(forBackend(MediaBackend.jellyfin, isPhone: false), isA<JellyfinAlphaBarStrategy>());
      expect(forBackend(MediaBackend.local, isPhone: false), isA<NoAlphaBarStrategy>());
      expect(forBackend(MediaBackend.pleyaServer, isPhone: false), isA<NoAlphaBarStrategy>());
    });

    test('Plex thresholds are unchanged', () {
      final plex = PlexAlphaBarStrategy(
        plexClientProvider: () => throw StateError('unused') as PlexClient,
        libraryKey: 'lib',
        isShared: false,
      );
      bool show(int total, int loaded) => plex.shouldShow(
        totalItemCount: total,
        loadedCharacterCount: loaded,
        sortKey: 'titleSort',
        isFolderGrouping: false,
        jellyfinAlphaPrefix: null,
        isPhone: true,
        indexItemCount: 0,
      );
      expect(show(80, 6), isTrue);
      expect(show(79, 6), isFalse);
      expect(show(80, 5), isFalse);
    });
  });
}
