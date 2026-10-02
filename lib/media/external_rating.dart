import 'package:json_annotation/json_annotation.dart';

import '../utils/rating_utils.dart';

part 'external_rating.g.dart';

enum ExternalRatingSource { imdb, rottenTomatoesCritic, rottenTomatoesAudience, tmdb, community }

/// A score from an outside source. [value] uses the source's own scale:
/// IMDb and community 0 to 10, Rotten Tomatoes and TMDB 0 to 100.
@JsonSerializable(includeIfNull: false)
class ExternalRating {
  final ExternalRatingSource source;
  final double value;
  final String? imageUri;

  const ExternalRating({required this.source, required this.value, this.imageUri});

  factory ExternalRating.fromJson(Map<String, dynamic> json) => _$ExternalRatingFromJson(json);

  Map<String, dynamic> toJson() => _$ExternalRatingToJson(this);

  String get assetPath => switch (source) {
    ExternalRatingSource.imdb => 'assets/rating_icons/imdb.svg',
    // Jellyfin's community score comes from the TMDB provider by default.
    ExternalRatingSource.tmdb || ExternalRatingSource.community => 'assets/rating_icons/tmdb.svg',
    ExternalRatingSource.rottenTomatoesCritic =>
      _rtAsset() ?? (value >= 60 ? 'assets/rating_icons/rt_fresh.svg' : 'assets/rating_icons/rt_rotten.svg'),
    ExternalRatingSource.rottenTomatoesAudience =>
      _rtAsset() ?? (value >= 60 ? 'assets/rating_icons/rt_upright.svg' : 'assets/rating_icons/rt_spilled.svg'),
  };

  String get label => switch (source) {
    ExternalRatingSource.imdb || ExternalRatingSource.community => value.toStringAsFixed(1),
    _ => '${value.round()}%',
  };

  String? _rtAsset() => isRottenTomatoes(imageUri) ? parseRatingImage(imageUri, value)?.assetPath : null;
}
