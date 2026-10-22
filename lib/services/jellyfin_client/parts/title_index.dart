part of '../../jellyfin_client.dart';

/// Title counts for the phone alphabet scrubber.
///
/// Every count reuses the browse translator, so filters, item types and the
/// parent library match the grid exactly. Only the window changes: `Limit=0`
/// returns just `TotalRecordCount`, and `NameLessThan` narrows it to the titles
/// whose `SortName` sorts before the bound.
mixin _JellyfinTitleIndexMethods on MediaServerCacheMixin {
  JellyfinConnection get connection;
  FailoverHttpClient get _http;

  Future<({int total, Map<String, int> before})> fetchTitleCountsBefore(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    required List<String> bounds,
    AbortController? abort,
  }) async {
    final effective = (query.kind == null && libraryKind != null && libraryKind != MediaKind.unknown)
        ? query.copyWith(kind: libraryKind)
        : query;
    final translator = JellyfinLibraryQueryTranslator(
      userId: connection.userId,
      parentId: libraryId,
      fields: 'SortName',
    );
    final base = translator.toQueryParameters(effective.copyWith(offset: 0, limit: 0, sort: null, nameStartsWith: null))
      ..remove('SortBy')
      ..remove('SortOrder');

    Future<int> count(String? bound) async {
      final response = await _http.get('/Items', queryParameters: {...base, 'NameLessThan': ?bound}, abort: abort);
      throwIfHttpError(response);
      final data = response.data;
      final total = data is Map<String, dynamic> ? data['TotalRecordCount'] : null;
      if (total is! int || total < 0) throw StateError('Jellyfin did not report a title count');
      return total;
    }

    final results = await Future.wait([count(null), for (final bound in bounds) count(bound)]);
    return (total: results.first, before: {for (var i = 0; i < bounds.length; i++) bounds[i]: results[i + 1]});
  }
}
