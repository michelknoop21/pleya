import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_stream.dart';
import '../utils/language_codes.dart';
import 'assistant_tool_context.dart';

/// Temporary queries require positive metadata evidence for every requested
/// filter. Kept separate from saved-row capabilities, which may differ.
class AssistantStrictFilters {
  const AssistantStrictFilters({
    this.kind,
    this.genres = const {},
    this.excludeGenres = const {},
    this.minRuntimeMinutes,
    this.maxRuntimeMinutes,
    this.yearFrom,
    this.yearTo,
    this.audioLanguages = const {},
    this.subtitleLanguages = const {},
    this.officialRatings = const {},
    this.minRating,
  });
  final MediaKind? kind;
  final Set<String> genres;
  final Set<String> excludeGenres;
  final int? minRuntimeMinutes;
  final int? maxRuntimeMinutes;
  final int? yearFrom;
  final int? yearTo;
  final Set<String> audioLanguages;
  final Set<String> subtitleLanguages;
  final Set<String> officialRatings;
  final double? minRating;

  static const properties = <String, Object?>{
    'kind': {
      'type': 'string',
      'enum': ['movie', 'show'],
    },
    'genres': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'exclude_genres': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'min_runtime_minutes': {'type': 'integer'},
    'max_runtime_minutes': {'type': 'integer'},
    'year_from': {'type': 'integer'},
    'year_to': {'type': 'integer'},
    'audio_languages': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'subtitle_languages': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'official_ratings': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'min_rating': {'type': 'number'},
  };

  factory AssistantStrictFilters.parse(Map<String, Object?> args) {
    int? integer(String key, int min, int max) {
      final value = args[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite || value != value.roundToDouble() || value < min || value > max)
        throw AssistantToolError('invalid_$key');
      return value.toInt();
    }

    Set<String> strings(String key) {
      final value = args[key];
      if (value == null) return const {};
      if (value is! List || value.length > 8 || value.any((v) => v is! String || v.trim().isEmpty || v.length > 64))
        throw AssistantToolError('invalid_$key');
      return {for (final v in value.cast<String>()) v.trim().toLowerCase()};
    }

    final min = integer('min_runtime_minutes', 1, 1440);
    final max = integer('max_runtime_minutes', 1, 1440);
    final from = integer('year_from', 1880, 2200);
    final to = integer('year_to', 1880, 2200);
    if (min != null && max != null && min > max) throw const AssistantToolError('invalid_max_runtime_minutes');
    if (from != null && to != null && from > to) throw const AssistantToolError('invalid_year_to');
    final rating = args['min_rating'];
    if (rating != null && (rating is! num || !rating.isFinite || rating < 0 || rating > 10))
      throw const AssistantToolError('invalid_min_rating');
    return AssistantStrictFilters(
      kind: switch (args['kind']) {
        null => null,
        'movie' => MediaKind.movie,
        'show' => MediaKind.show,
        _ => throw const AssistantToolError('invalid_kind'),
      },
      genres: strings('genres'),
      excludeGenres: strings('exclude_genres'),
      minRuntimeMinutes: min,
      maxRuntimeMinutes: max,
      yearFrom: from,
      yearTo: to,
      audioLanguages: strings('audio_languages'),
      subtitleLanguages: strings('subtitle_languages'),
      officialRatings: strings('official_ratings'),
      minRating: (rating as num?)?.toDouble(),
    );
  }

  bool matches(MediaItem item) {
    if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return false;
    if (kind != null && item.kind != kind) return false;
    final knownGenres = item.genres;
    if (genres.isNotEmpty || excludeGenres.isNotEmpty) {
      if (knownGenres == null) return false;
      final actual = knownGenres.map((g) => g.trim().toLowerCase()).toSet();
      if (genres.isNotEmpty && !genres.every(actual.contains)) return false;
      if (excludeGenres.any(actual.contains)) return false;
    }
    if (minRuntimeMinutes != null || maxRuntimeMinutes != null) {
      final duration = item.durationMs;
      if (duration == null || duration <= 0) return false;
      if (minRuntimeMinutes != null && duration < minRuntimeMinutes! * 60000) return false;
      if (maxRuntimeMinutes != null && duration > maxRuntimeMinutes! * 60000) return false;
    }
    if (yearFrom != null || yearTo != null) {
      final year = item.year;
      if (year == null || (yearFrom != null && year < yearFrom!) || (yearTo != null && year > yearTo!)) return false;
    }
    if (minRating != null && (item.rating == null || !item.rating!.isFinite || item.rating! < minRating!)) return false;
    if (officialRatings.isNotEmpty && !officialRatings.contains(item.contentRating?.trim().toLowerCase())) return false;
    bool tracks(Set<String> requested, MediaStreamKind kind) {
      if (requested.isEmpty) return true;
      final available = {
        for (final version in item.mediaVersions ?? const [])
          for (final part in version.parts)
            for (final stream in part.streams)
              if (stream.kind == kind && (stream.languageCode ?? stream.language) != null)
                ...LanguageCodes.getVariations((stream.languageCode ?? stream.language)!),
      };
      return requested.every((code) => LanguageCodes.getVariations(code).any(available.contains));
    }

    return tracks(audioLanguages, MediaStreamKind.audio) && tracks(subtitleLanguages, MediaStreamKind.subtitle);
  }

  /// Deterministic facts only; no inferred tastes, genres or history overlap.
  Map<String, Object?> facts(MediaItem item) => {
    if (kind != null) 'kind': item.kind.name,
    if (genres.isNotEmpty) 'genres': genres.toList()..sort(),
    if (excludeGenres.isNotEmpty) 'excluded_genres_absent': excludeGenres.toList()..sort(),
    if (minRuntimeMinutes != null || maxRuntimeMinutes != null) 'runtime_minutes': item.durationMs! / 60000,
    if (yearFrom != null || yearTo != null) 'year': item.year,
    if (audioLanguages.isNotEmpty) 'audio_languages': audioLanguages.toList()..sort(),
    if (subtitleLanguages.isNotEmpty) 'subtitle_languages': subtitleLanguages.toList()..sort(),
    if (officialRatings.isNotEmpty) 'official_rating': item.contentRating,
    if (minRating != null) 'rating': item.rating,
  };
}
