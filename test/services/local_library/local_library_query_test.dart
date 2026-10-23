import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/local_library/local_library_query.dart';
import 'local_library_store_test.dart' show film;

void main() {
  final rows = [
    film(
      'arrival',
    ).copyWith(title: 'Arrival', titleSort: 'Arrival', year: 2016, genres: ['Science Fiction'], viewCount: 1),
    film('dune').copyWith(title: 'Dune', titleSort: 'Dune', year: 2021, genres: ['Science Fiction'], viewCount: 0),
    film('comedy').copyWith(title: 'Comedy', titleSort: 'Comedy', year: 2021, genres: ['Comedy']),
  ];
  test('offline filters and Plex titleSort ordering use the saved metadata', () {
    final result = queryLocalLibrary(
      rows,
      const LibraryQuery(
        kind: MediaKind.movie,
        genres: ['Science Fiction'],
        years: [2021],
        sort: LibrarySort(field: 'titleSort'),
      ),
    );
    expect(result?.map((i) => i.id), ['dune']);
    expect(queryLocalLibrary(rows, const LibraryQuery(includeWatched: false))?.map((i) => i.id), ['comedy', 'dune']);
  });
  test('unsupported predicates never return an unfiltered library as a match', () {
    expect(queryLocalLibrary(rows, const LibraryQuery(favoritesOnly: true)), isNull);
    expect(queryLocalLibrary(rows, const LibraryQuery(audioLanguages: ['nl'])), isNull);
    expect(
      queryLocalLibrary(
        rows,
        const LibraryQuery(
          filters: [
            LibraryFilter(field: 'unknown', values: ['x']),
          ],
        ),
      ),
      isNull,
    );
  });
}
