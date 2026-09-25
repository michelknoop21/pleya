import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_filter_options.dart';

/// Answers the one call `loadUnifiedFilterOptions` makes on a client whose
/// values arrive cached (the Jellyfin shape).
class _Client implements MediaServerClient {
  _Client(this.id, this.values);

  final String id;
  final Map<String, List<MediaFilterValue>> values;

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async =>
      LibraryFilterResult(filters: const [], cachedValues: values);

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  ServerId get serverId => ServerId(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogLibrary _library(String server) => (
  serverId: ServerId(server),
  serverName: server,
  libraryId: '1',
  libraryTitle: 'Films',
  backend: MediaBackend.jellyfin,
);

void main() {
  test('content ratings are unioned across servers, ages first in age order', () async {
    final clients = {
      'a': _Client('a', {
        'contentRating': [MediaFilterValue(key: '16', title: '16'), MediaFilterValue(key: 'PG-13', title: 'PG-13')],
      }),
      'b': _Client('b', {
        'contentRating': [MediaFilterValue(key: '6', title: '6'), MediaFilterValue(key: '16', title: '16')],
      }),
    };
    final options = await loadUnifiedFilterOptions(
      libraries: [_library('a'), _library('b')],
      clientFor: (serverId) => clients[serverId.value],
    );
    expect(options.contentRatings.map((v) => v.value), ['6', '16', 'PG-13']);
  });

  // Plex filter-value keys can be paths that carry the value as a query
  // parameter; the filter must send the value, not the path.
  test('a path-shaped key yields its contentRating parameter as the value', () async {
    final client = _Client('a', {
      'contentRating': [
        MediaFilterValue(key: '/library/sections/1/all?contentRating=gb%2F12', title: '12'),
        MediaFilterValue(key: '/library/sections/1/contentRating/PG-13', title: 'PG-13'),
      ],
    });
    final options = await loadUnifiedFilterOptions(libraries: [_library('a')], clientFor: (_) => client);
    expect(options.contentRatings.map((v) => (v.value, v.label)), [('gb/12', '12'), ('PG-13', 'PG-13')]);
  });

  test('a server without audio languages leaves the list empty, not padded', () async {
    final client = _Client('a', {
      'genre': [MediaFilterValue(key: 'Drama', title: 'Drama')],
    });
    final options = await loadUnifiedFilterOptions(libraries: [_library('a')], clientFor: (_) => client);
    expect(options.audioLanguages, isEmpty);
    expect(options.contentRatings, isEmpty);
    expect(options.genres, ['Drama']);
  });
}
