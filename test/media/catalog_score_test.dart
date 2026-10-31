/// Every backend's score lands on one 0 to 100 scale before the merge compares
/// it, and carries its source for the badge.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/catalog_score.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';

void main() {
  test('Plex runs 0 to 10 and keeps its own source image', () {
    const item = PlexMediaItem(
      id: 'p',
      kind: MediaKind.movie,
      rating: 9.6,
      audienceRating: 8.2,
      userRating: 7,
      ratingImage: 'rottentomatoes://image.rating.ripe',
      audienceRatingImage: 'rottentomatoes://image.rating.upright',
    );
    expect(catalogCriticScore(item)!.percent, closeTo(96, 1e-9));
    expect(catalogCriticScore(item)!.imageUri, 'rottentomatoes://image.rating.ripe');
    expect(catalogAudienceScore(item)!.percent, closeTo(82, 1e-9));
    expect(catalogAudienceScore(item)!.imageUri, 'rottentomatoes://image.rating.upright');
    expect(catalogUserScore(item)!.percent, closeTo(70, 1e-9));
  });

  test('Jellyfin critics are already a percentage, the community score is not', () {
    const item = JellyfinMediaItem(
      id: 'j',
      kind: MediaKind.movie,
      rating: 7.2,
      externalRatings: [
        ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 91),
        ExternalRating(source: ExternalRatingSource.community, value: 7.2),
      ],
    );
    expect(catalogCriticScore(item)!.percent, 91);
    expect(catalogCriticScore(item)!.imageUri, 'rottentomatoes://image.rating.ripe');
    expect(catalogAudienceScore(item)!.percent, closeTo(72, 1e-9));
  });

  test('a low Jellyfin critic score carries the rotten tomato', () {
    const item = JellyfinMediaItem(
      id: 'j',
      kind: MediaKind.movie,
      externalRatings: [ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 40)],
    );
    expect(catalogCriticScore(item)!.imageUri, 'rottentomatoes://image.rating.rotten');
  });

  test('zero is a score, absence is not', () {
    expect(catalogCriticScore(const PlexMediaItem(id: 'p', kind: MediaKind.movie, rating: 0))!.percent, 0);
    expect(catalogCriticScore(const PlexMediaItem(id: 'p', kind: MediaKind.movie)), isNull);
    expect(catalogAudienceScore(const JellyfinMediaItem(id: 'j', kind: MediaKind.movie)), isNull);
  });

  test('Pleya Server has no scores to give', () {
    final item = MediaItem(id: 'x', backend: MediaBackend.pleyaServer, kind: MediaKind.movie);
    expect(catalogCriticScore(item), isNull);
    expect(catalogAudienceScore(item), isNull);
  });
}
