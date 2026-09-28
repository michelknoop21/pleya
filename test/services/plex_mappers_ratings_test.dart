import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/services/plex_mappers.dart';

void main() {
  test('Rating[] and Review[] from a live capture map to external ratings and reviews', () {
    final json = jsonDecode(File('test/fixtures/plex_detail/movie_metadata_reviews.json').readAsStringSync());
    final metadata = (json['MediaContainer']['Metadata'] as List).first as Map<String, dynamic>;
    final item = PlexMappers.mediaItemFromJson(metadata);

    expect(item.externalRatings.map((r) => r.source), [
      ExternalRatingSource.imdb,
      ExternalRatingSource.rottenTomatoesCritic,
      ExternalRatingSource.rottenTomatoesAudience,
      ExternalRatingSource.tmdb,
    ]);
    expect(item.externalRatings.map((r) => r.value), [6.0, 37, 50, 65]);
    expect(item.externalRatings[1].assetPath, 'assets/rating_icons/rt_rotten.svg');
    expect(item.reviews, isNotEmpty);
    expect(item.reviews.first.author, 'Nell Minow');
    expect(item.reviews.first.text, isNotEmpty);
    expect(item.reviews.first.source, 'Common Sense Media');

    final restored = MediaItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>);
    expect(restored.externalRatings.map((r) => r.label), item.externalRatings.map((r) => r.label));
    expect(restored.reviews.length, item.reviews.length);
  });

  test('flat ratingImage attributes fill in when Rating[] is absent', () {
    final item = PlexMappers.mediaItemFromJson({
      'ratingKey': '1',
      'type': 'movie',
      'title': 'Sintel',
      'rating': 9.2,
      'ratingImage': 'rottentomatoes://image.rating.ripe',
      'audienceRating': 8.8,
      'audienceRatingImage': 'rottentomatoes://image.rating.upright',
    });
    expect(item.externalRatings.map((r) => (r.source, r.value)), [
      (ExternalRatingSource.rottenTomatoesCritic, 92),
      (ExternalRatingSource.rottenTomatoesAudience, 88),
    ]);
    expect(item.reviews, isEmpty);
  });
}
