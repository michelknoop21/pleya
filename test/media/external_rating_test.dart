import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';

void main() {
  test('RT critic picks the fresh icon from a ripe image uri', () {
    const r = ExternalRating(
      source: ExternalRatingSource.rottenTomatoesCritic,
      value: 92,
      imageUri: 'rottentomatoes://image.rating.ripe',
    );
    expect(r.assetPath, 'assets/rating_icons/rt_fresh.svg');
    expect(r.label, '92%');
  });
  test('RT critic without image uri falls back on the 60 threshold', () {
    expect(
      const ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 59).assetPath,
      'assets/rating_icons/rt_rotten.svg',
    );
    expect(
      const ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 60).assetPath,
      'assets/rating_icons/rt_fresh.svg',
    );
  });
  test('RT audience maps to upright/spilled', () {
    expect(
      const ExternalRating(source: ExternalRatingSource.rottenTomatoesAudience, value: 88).assetPath,
      'assets/rating_icons/rt_upright.svg',
    );
    expect(
      const ExternalRating(source: ExternalRatingSource.rottenTomatoesAudience, value: 40).assetPath,
      'assets/rating_icons/rt_spilled.svg',
    );
  });
  test('IMDb shows one decimal, TMDB a percentage', () {
    expect(const ExternalRating(source: ExternalRatingSource.imdb, value: 7.4).label, '7.4');
    expect(const ExternalRating(source: ExternalRatingSource.tmdb, value: 73).label, '73%');
  });
}
