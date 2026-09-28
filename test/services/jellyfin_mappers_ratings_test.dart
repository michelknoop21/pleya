import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/jellyfin_mappers.dart';

void main() {
  test('CriticRating becomes an RT critic score, CommunityRating a community score', () {
    final item = JellyfinMappers.mediaItem(
      {'Id': 'x', 'Type': 'Movie', 'Name': 'Sintel', 'CriticRating': 92, 'CommunityRating': 7.4},
      serverId: ServerId('s'),
      absolutizer: null,
    )!;
    expect(item.externalRatings.map((r) => r.source), [
      ExternalRatingSource.rottenTomatoesCritic,
      ExternalRatingSource.community,
    ]);
    expect(item.externalRatings.first.value, 92);
    expect(item.reviews, isEmpty);
  });
}
