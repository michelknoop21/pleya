/// One title's score on the catalog's common scale, 0 to 100.
///
/// Every backend reports on its own scale: Plex `rating`, `audienceRating` and
/// `userRating` run 0 to 10, Jellyfin `CommunityRating` 0 to 10 and
/// `CriticRating` 0 to 100. The unified merge compares heads from different
/// servers, so the scale has to be settled before an item reaches the
/// comparator. What this does not settle is whether two scores mean the same
/// thing: a Plex critic score can be IMDb while Jellyfin's is Rotten Tomatoes.
/// DEC-170 accepts that comparison on purpose.
library;

import 'external_rating.dart';
import 'media_item.dart';

/// What the score says something about, which picks the fallback icon.
enum CatalogScoreKind { critic, audience, user }

class CatalogScore {
  const CatalogScore({required this.kind, required this.percent, this.imageUri});

  final CatalogScoreKind kind;

  /// 0 to 100.
  final double percent;

  /// The source, in Plex's `ratingImage` spelling, so `MediaRatingBadge` draws
  /// the same icon for every backend. Null when the source is unknown.
  final String? imageUri;

  /// The scale `MediaRatingBadge` and `parseRatingImage` take.
  double get tenPointValue => percent / 10;
}

double _fromTenPoint(double value) => (value * 10).clamp(0.0, 100.0);

/// The critics' score, or null when there is none.
///
/// Jellyfin's `CriticRating` is the Rotten Tomatoes critic percentage
/// (`jellyfin_mappers.dart`), so it carries the fresh or rotten tomato by the
/// same 60 percent line [ExternalRating.assetPath] draws.
CatalogScore? catalogCriticScore(MediaItem item) => switch (item) {
  PlexMediaItem(:final rating?, :final ratingImage) => CatalogScore(
    kind: CatalogScoreKind.critic,
    percent: _fromTenPoint(rating),
    imageUri: ratingImage,
  ),
  JellyfinMediaItem(:final externalRatings) => _jellyfinCritic(externalRatings),
  _ => null,
};

CatalogScore? _jellyfinCritic(List<ExternalRating> ratings) {
  for (final rating in ratings) {
    if (rating.source != ExternalRatingSource.rottenTomatoesCritic) continue;
    final percent = rating.value.clamp(0.0, 100.0);
    return CatalogScore(
      kind: CatalogScoreKind.critic,
      percent: percent,
      imageUri: 'rottentomatoes://image.rating.${percent >= 60 ? 'ripe' : 'rotten'}',
    );
  }
  return null;
}

/// The audience's score, or null when there is none. Jellyfin's
/// `CommunityRating` comes from the TMDB provider by default, the assumption
/// [ExternalRating.assetPath] already makes.
CatalogScore? catalogAudienceScore(MediaItem item) => switch (item) {
  PlexMediaItem(:final audienceRating?, :final audienceRatingImage) => CatalogScore(
    kind: CatalogScoreKind.audience,
    percent: _fromTenPoint(audienceRating),
    imageUri: audienceRatingImage,
  ),
  JellyfinMediaItem(:final rating?) => CatalogScore(
    kind: CatalogScoreKind.audience,
    percent: _fromTenPoint(rating),
    imageUri: 'themoviedb://image.rating',
  ),
  _ => null,
};

/// The viewer's own score, or null when they gave none. Only Plex can sort on
/// it; Jellyfin's mapped `Likes` flag never reaches a catalog sorted this way.
CatalogScore? catalogUserScore(MediaItem item) {
  final rating = item.userRating;
  return rating == null ? null : CatalogScore(kind: CatalogScoreKind.user, percent: _fromTenPoint(rating));
}
