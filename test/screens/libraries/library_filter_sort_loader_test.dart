/// One menu on every app: a library's own sorts and filters reach the sheets of
/// the non-TV platforms in the order and the words of the menu definition, and
/// whatever a backend has beyond that definition stays, at the bottom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/screens/libraries/library_filter_sort_loader.dart';
import 'package:pleya/screens/libraries/sort_bottom_sheet.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

class _Offline implements Exception {
  const _Offline(this.call);
  final String call;
}

class _Failing extends _Client {
  _Failing({this.failSorts = false, this.failFilters = false});

  final bool failSorts;
  final bool failFilters;

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async {
    if (failSorts) throw const _Offline('sorts');
    return super.fetchSortOptions(libraryId, libraryType: libraryType);
  }

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async {
    if (failFilters) throw const _Offline('filters');
    return super.fetchLibraryFiltersWithValues(libraryId);
  }
}

class _Client implements MediaServerClient {
  _Client({this.sorts = const [], this.filters = const [], this.values = const {}});

  final List<MediaSort> sorts;
  final List<MediaFilter> filters;
  final Map<String, List<MediaFilterValue>> values;

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async => sorts;

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async =>
      LibraryFilterResult(filters: filters, cachedValues: values);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

MediaLibrary _library(MediaBackend backend) =>
    MediaLibrary(id: '1', backend: backend, title: 'Films', kind: MediaKind.movie);

MediaSort _sort(String key, String title) => MediaSort(key: key, title: title);

MediaFilter _filter(String key, String title, {String type = 'string'}) =>
    MediaFilter(filter: key, filterType: type, key: 'k:$key', title: title, type: 'filter');

Future<LoadedFiltersAndSorts> _load(MediaBackend backend, _Client client) =>
    LibraryFilterSortLoader(clientFor: (_) => client).load(_library(backend));

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LocaleSettings.setLocale(AppLocale.nl);
  });
  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  group('a failure keeps its own face, so friendlyError can word it', () {
    Matcher offline(String call) => throwsA(isA<_Offline>().having((e) => e.call, 'call', call));

    test('sorts failing', () {
      expect(_load(MediaBackend.plex, _Failing(failSorts: true)), offline('sorts'));
    });

    test('filters failing', () {
      expect(_load(MediaBackend.plex, _Failing(failFilters: true)), offline('filters'));
    });

    test('both failing: the first is the one reported', () {
      expect(_load(MediaBackend.plex, _Failing(failSorts: true, failFilters: true)), offline('filters'));
    });
  });

  group('sorts', () {
    final plex = [
      _sort('random', 'Random'),
      _sort('addedAt', 'Date Added'),
      _sort('rating', 'Rating'),
      _sort('titleSort', 'Title'),
      _sort('mediaBitrate', 'Bitrate'),
      _sort('audienceRating', 'Audience Rating'),
      _sort('year', 'Year'),
    ];

    test('Plex reads in the menu order and words, its own options stay at the bottom', () async {
      final loaded = await _load(MediaBackend.plex, _Client(sorts: plex));
      expect(loaded.sorts.map((s) => s.key), [
        'titleSort',
        'year',
        'rating',
        'audienceRating',
        'addedAt',
        'random',
        'mediaBitrate',
      ]);
      expect(loaded.sorts.map((s) => s.title), [
        'Titel',
        'Jaar',
        'Critici',
        'Publiek',
        'Toegevoegd',
        'Random',
        'Bitrate',
      ]);
    });

    test('rating is the critics on Plex and the audience on Jellyfin', () async {
      final loaded = await _load(
        MediaBackend.jellyfin,
        _Client(
          sorts: [
            _sort('title', 'Title'),
            _sort('rating', 'Community Rating'),
            _sort('criticRating', 'Critic Rating'),
            _sort('runtime', 'Runtime'),
            _sort('officialRating', 'Official Rating'),
            _sort('studio', 'Studio'),
            _sort('random', 'Random'),
          ],
        ),
      );
      expect(loaded.sorts.map((s) => s.title), ['Titel', 'Critici', 'Publiek', 'Leeftijd', 'Duur', 'Studio', 'Random']);
    });

    test('the key a saved sort is restored by does not change', () async {
      final loaded = await _load(MediaBackend.plex, _Client(sorts: plex));
      expect(loaded.sorts.map((s) => s.key).toSet(), plex.map((s) => s.key).toSet());
    });

    test('loadSorts is the same answer, for the Jellyfin path that loads it alone', () async {
      final client = _Client(sorts: [_sort('random', 'Random'), _sort('title', 'Title')]);
      final sorts = await LibraryFilterSortLoader(clientFor: (_) => client).loadSorts(_library(MediaBackend.jellyfin));
      expect(sorts.map((s) => s.title), ['Titel', 'Random']);
    });

    testWidgets('SortBottomSheet draws that list top to bottom', (tester) async {
      final loaded = await _load(MediaBackend.plex, _Client(sorts: plex));
      await tester.pumpWidget(
        MaterialApp(
          home: OverlaySheetHost(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => OverlaySheetController.of(context).show(
                  builder: (_) => SortBottomSheet(
                    sortOptions: loaded.sorts,
                    selectedSort: null,
                    isSortDescending: false,
                    onSortChanged: (_, _) {},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final tops = [
        for (final label in ['Titel', 'Jaar', 'Critici', 'Toegevoegd']) tester.getTopLeft(find.text(label)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
    });
  });

  group('filters', () {
    test('Plex: quick rows first, then the categories, unknown ones at the end of each', () async {
      final loaded = await _load(
        MediaBackend.plex,
        _Client(
          filters: [
            _filter('studio', 'Studio'),
            _filter('contentRating', 'Content Rating'),
            _filter('genre', 'Genre'),
            _filter('hasSubtitles', 'Subtitles', type: 'boolean'),
            _filter('duplicate', 'Duplicates', type: 'boolean'),
            _filter('unwatched', 'Unwatched', type: 'boolean'),
            _filter('hdr', 'HDR', type: 'boolean'),
            _filter('year', 'Year'),
          ],
        ),
      );
      expect(loaded.filters.map((f) => f.filter), [
        'hdr',
        'unwatched',
        'duplicate',
        'hasSubtitles',
        'genre',
        'year',
        'contentRating',
        'studio',
      ]);
      expect(loaded.filters.map((f) => f.title), [
        'HDR',
        'Ongekeken',
        'Dubbel',
        'Subtitles',
        'Genre',
        'Jaar',
        'Leeftijd',
        'Studio',
      ]);
    });

    test('Jellyfin keeps the toggle, the tag and its pre-fetched values', () async {
      final values = {
        'tag': [MediaFilterValue(key: 'cult', title: 'cult')],
      };
      final loaded = await _load(
        MediaBackend.jellyfin,
        _Client(
          filters: [
            _filter('unwatched', 'Unwatched', type: 'boolean'),
            _filter('tag', 'Tag'),
            _filter('audioLanguage', 'Audio language'),
            _filter('genre', 'Genre'),
          ],
          values: values,
        ),
      );
      expect(loaded.filters.map((f) => f.filter), ['unwatched', 'genre', 'audioLanguage', 'tag']);
      expect(loaded.cachedValues['tag']!.single.key, 'cult');
    });

    test('Pleya Server keeps resolution', () async {
      final loaded = await _load(
        MediaBackend.pleyaServer,
        _Client(
          filters: [
            _filter('unwatched', 'Unwatched', type: 'boolean'),
            _filter('resolution', 'Resolution'),
            _filter('year', 'Year'),
          ],
        ),
      );
      expect(loaded.filters.map((f) => f.filter), ['unwatched', 'year', 'resolution']);
    });

    test('nothing a server lists goes missing, however it is spelled', () async {
      final filters = [
        _filter('dolbyVision', 'Dolby Vision', type: 'boolean'),
        _filter('dovi', 'DoVi', type: 'boolean'),
        _filter('', 'No key'),
        _filter('watched', 'Watched', type: 'boolean'),
      ];
      final loaded = await _load(MediaBackend.plex, _Client(filters: filters));
      expect(loaded.filters.map((f) => f.key).toSet(), filters.map((f) => f.key).toSet());
    });
  });
}
