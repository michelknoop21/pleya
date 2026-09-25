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
import '../../utils/language_codes.dart';
import '../plex_client.dart';
import 'source_cursor.dart';
import 'unified_catalog_filters.dart';

/// The choices one filter panel offers, already unioned and ordered.
class UnifiedFilterValue {
  const UnifiedFilterValue({required this.value, required this.label});

  final String value;
  final String label;
}

class UnifiedFilterOptions {
  const UnifiedFilterOptions({
    this.genres = const [],
    this.audioLanguages = const [],
    this.contentRatings = const [],
    this.years = const [],
  });

  /// Genre names, alphabetically. The value a backend filters on *is* the name
  /// for both Plex and Jellyfin (`genre=Drama`, `Genres=Drama`), so there is no
  /// id to carry alongside it.
  final List<String> genres;
  final List<UnifiedFilterValue> audioLanguages;

  /// Content ratings, numeric ages first in age order, then the rest
  /// alphabetically. Jellyfin's `/Items/Filters`
  /// lists them as `OfficialRatings`; Plex as its `contentRating` category.
  final List<UnifiedFilterValue> contentRatings;

  /// Years, newest first — which is the order someone scanning for "last year"
  /// reads, and the opposite of the order a server returns them in.
  final List<int> years;

  static const empty = UnifiedFilterOptions();

  bool get isEmpty => genres.isEmpty && audioLanguages.isEmpty && contentRatings.isEmpty && years.isEmpty;
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
  final audioLanguages = <String, String>{};
  final contentRatings = <String, Set<String>>{};
  final years = <int>{};

  await Future.wait([
    for (final library in libraries)
      _collectFor(
        library: library,
        clientFor: clientFor,
        genres: genres,
        audioLanguages: audioLanguages,
        contentRatings: contentRatings,
        years: years,
      ),
  ]);

  final sortedGenres = genres.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
  final sortedAudioLanguages = [
    for (final entry in audioLanguages.entries) UnifiedFilterValue(value: entry.key, label: entry.value),
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  final sortedContentRatings = [
    for (final entry in contentRatings.entries)
      UnifiedFilterValue(value: (entry.value.toList()..sort()).join(contentRatingValueSeparator), label: entry.key),
  ]..sort((a, b) => compareContentRatingLabels(a.label, b.label));
  return UnifiedFilterOptions(
    genres: sortedGenres,
    audioLanguages: sortedAudioLanguages,
    contentRatings: sortedContentRatings,
    years: sortedYears,
  );
}

Future<void> _collectFor({
  required CatalogLibrary library,
  required MediaServerClient? Function(ServerId serverId) clientFor,
  required Set<String> genres,
  required Map<String, String> audioLanguages,
  required Map<String, Set<String>> contentRatings,
  required Set<int> years,
}) async {
  final client = clientFor(library.serverId);
  if (client == null) return;
  try {
    final result = await client.fetchLibraryFiltersWithValues(library.libraryId);
    final cachedGenres = result.cachedValues[_genreKey];
    final cachedYears = result.cachedValues[_yearKey];
    final cachedAudioLanguages = result.cachedValues[_audioLanguageKey];
    final cachedContentRatings = result.cachedValues[_contentRatingKey];

    if (cachedGenres != null || cachedYears != null || cachedAudioLanguages != null || cachedContentRatings != null) {
      _addGenres(cachedGenres, genres);
      _addYears(cachedYears, years);
      _addAudioLanguages(cachedAudioLanguages, audioLanguages);
      _addContentRatings(cachedContentRatings, contentRatings);
      return;
    }

    // Plex: categories without values. Its own `getFilterValues` takes the
    // category's `key`, which is a full path the client resolves against the
    // server, so it has to come from this library's own filter list rather than
    // being constructed here.
    if (client is! PlexClient) return;
    await Future.wait([
      for (final filter in result.filters)
        if (_plexCategories.contains(filter.filter))
          client.getFilterValues(filter.key).then((values) {
            if (filter.filter == _genreKey) return _addGenres(values, genres);
            if (filter.filter == _yearKey) return _addYears(values, years);
            if (filter.filter == _contentRatingKey) return _addContentRatings(values, contentRatings);
            _addAudioLanguages(values, audioLanguages);
          }, onError: (Object e) => appLogger.d('Unified filter values failed for ${filter.filter}: $e')),
    ]);
  } catch (e) {
    appLogger.d('Unified filter options failed for ${library.libraryTitle}: $e');
  }
}

const String _genreKey = 'genre';
const String _yearKey = 'year';
const String _audioLanguageKey = 'audioLanguage';
const String _contentRatingKey = 'contentRating';
const Set<String> _plexCategories = {_genreKey, _yearKey, _audioLanguageKey, _contentRatingKey};

/// Raw ratings grouped by their label. The raw value is what a backend filters
/// on: a plain value on Jellyfin, and on Plex either the value or a path that
/// carries it as `?contentRating=` or as its last segment (the shapes
/// `FiltersBottomSheet` already unpacks). Grouping by label is what keeps
/// Plex `gb/12` and Jellyfin `12` one "12" instead of two rows that each find
/// nothing on the other server.
void _addContentRatings(List<MediaFilterValue>? values, Map<String, Set<String>> into) {
  for (final value in values ?? const <MediaFilterValue>[]) {
    final key = value.key.trim();
    final rating = key.contains('?')
        ? (Uri.splitQueryString(key.substring(key.indexOf('?') + 1))[_contentRatingKey] ?? '')
        : key.startsWith('/')
        ? Uri.decodeComponent(key.split('/').last)
        : key;
    final raw = rating.isNotEmpty ? rating : value.title.trim();
    if (raw.isEmpty || raw.contains(contentRatingValueSeparator)) continue;
    into.putIfAbsent(contentRatingLabel(raw), () => <String>{}).add(raw);
  }
}

void _addAudioLanguages(List<MediaFilterValue>? values, Map<String, String> into) {
  for (final value in values ?? const <MediaFilterValue>[]) {
    final code = value.key.trim();
    if (code.isEmpty) continue;
    final title = value.title.trim();
    into.putIfAbsent(code, () => languageDisplayName(code) ?? (title.isEmpty ? code : title));
  }
}

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
