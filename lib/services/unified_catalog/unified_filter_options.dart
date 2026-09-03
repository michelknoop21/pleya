/// The genre and year values a unified catalog can actually be filtered by
/// (hoofdstuk 10.4 of docs/tvos-unified-experience.md).
///
/// A filter panel needs a list of choices, and no single server holds it: the
/// catalog spans every eligible library, so the options are the *union* of what
/// each library reports. Union, not intersection — a genre that exists on one
/// server is a real genre, and offering only the ones every server agrees on
/// would hide most of them the moment a second server appears.
///
/// ## Why this touches both backends by name
///
/// `MediaServerClient.fetchLibraryFiltersWithValues` is the neutral call, and
/// it answers differently on purpose: Jellyfin's `/Items/Filters` returns the
/// categories *and* their values in one response, while Plex returns categories
/// only and expects a second call per category. That asymmetry is not this
/// file's to fix — it is how the two APIs are shaped — so the neutral call is
/// tried first and the Plex follow-up happens only where the neutral answer
/// came back without values.
///
/// A backend that answers neither way simply contributes nothing. It cannot
/// execute these filters anyway (see `unifiedFilterCapabilitiesFor`), so a
/// catalog containing one has no genre section for it to be missing from.
library;

import 'dart:async';

import '../../media/ids.dart';
import '../../media/media_filter.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../plex_client.dart';
import 'source_cursor.dart';

/// The choices one filter panel offers, already unioned and ordered.
class UnifiedFilterOptions {
  const UnifiedFilterOptions({this.genres = const [], this.years = const []});

  /// Genre names, alphabetically. The value a backend filters on *is* the name
  /// for both Plex and Jellyfin (`genre=Drama`, `Genres=Drama`), so there is no
  /// id to carry alongside it.
  final List<String> genres;

  /// Years, newest first — which is the order someone scanning for "last year"
  /// reads, and the opposite of the order a server returns them in.
  final List<int> years;

  static const empty = UnifiedFilterOptions();

  bool get isEmpty => genres.isEmpty && years.isEmpty;
}

/// Loads the options for [libraries].
///
/// Failures are swallowed per library rather than propagated: one server being
/// unreachable must not empty a panel the other three can fill, which is the
/// same partial-result rule the catalog itself follows (hoofdstuk 12.6). A
/// library that fails contributes nothing and is not retried here — the panel
/// closing and reopening is the retry.
Future<UnifiedFilterOptions> loadUnifiedFilterOptions({
  required List<CatalogLibrary> libraries,
  required MediaServerClient? Function(ServerId serverId) clientFor,
}) async {
  final genres = <String>{};
  final years = <int>{};

  await Future.wait([
    for (final library in libraries) _collectFor(library: library, clientFor: clientFor, genres: genres, years: years),
  ]);

  final sortedGenres = genres.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
  return UnifiedFilterOptions(genres: sortedGenres, years: sortedYears);
}

Future<void> _collectFor({
  required CatalogLibrary library,
  required MediaServerClient? Function(ServerId serverId) clientFor,
  required Set<String> genres,
  required Set<int> years,
}) async {
  final client = clientFor(library.serverId);
  if (client == null) return;
  try {
    final result = await client.fetchLibraryFiltersWithValues(library.libraryId);
    final cachedGenres = result.cachedValues[_genreKey];
    final cachedYears = result.cachedValues[_yearKey];

    if (cachedGenres != null || cachedYears != null) {
      _addGenres(cachedGenres, genres);
      _addYears(cachedYears, years);
      return;
    }

    // Plex: categories without values. Its own `getFilterValues` takes the
    // category's `key`, which is a full path the client resolves against the
    // server, so it has to come from this library's own filter list rather than
    // being constructed here.
    if (client is! PlexClient) return;
    await Future.wait([
      for (final filter in result.filters)
        if (filter.filter == _genreKey || filter.filter == _yearKey)
          client
              .getFilterValues(filter.key)
              .then(
                (values) => filter.filter == _genreKey ? _addGenres(values, genres) : _addYears(values, years),
                onError: (Object e) => appLogger.d('Unified filter values failed for ${filter.filter}: $e'),
              ),
    ]);
  } catch (e) {
    appLogger.d('Unified filter options failed for ${library.libraryTitle}: $e');
  }
}

const String _genreKey = 'genre';
const String _yearKey = 'year';

void _addGenres(List<MediaFilterValue>? values, Set<String> into) {
  for (final value in values ?? const <MediaFilterValue>[]) {
    final title = value.title.trim();
    if (title.isNotEmpty) into.add(title);
  }
}

/// Years arrive as strings on both backends and occasionally as a range or a
/// decade label. Anything that is not a plain four-digit year is dropped rather
/// than guessed at: a filter row the query cannot execute is worse than a
/// missing one.
void _addYears(List<MediaFilterValue>? values, Set<int> into) {
  for (final value in values ?? const <MediaFilterValue>[]) {
    final parsed = int.tryParse(value.title.trim());
    if (parsed != null && parsed > 1800 && parsed < 2200) into.add(parsed);
  }
}
