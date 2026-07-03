import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_role.dart';
import 'package:plezy/services/recommendations/taste_profile.dart';

const _day = Duration.millisecondsPerDay;
const _nowMs = 1700000000000;

TasteEvent _ev({
  required double weight,
  int ageDays = 0,
  List<String> genres = const [],
  List<String> actors = const [],
  List<String> directors = const [],
  String? studio,
  int? year,
}) =>
    TasteEvent(
      weight: weight,
      occurredAtMs: _nowMs - ageDays * _day,
      genres: genres,
      actors: actors,
      directors: directors,
      studio: studio,
      year: year,
    );

void main() {
  group('AffinityVector.build', () {
    test('normalizes strongest feature to 1.0', () {
      final a = AffinityVector.build([
        _ev(weight: 1.0, genres: ['Sci-Fi']),
        _ev(weight: 1.0, genres: ['Sci-Fi']),
        _ev(weight: 1.0, genres: ['Drama']),
      ], nowMs: _nowMs);
      expect(a.of('genre', 'sci-fi'), closeTo(1.0, 1e-9));
      expect(a.of('genre', 'drama'), closeTo(0.5, 1e-9));
    });

    test('90-day-old event decays to half weight', () {
      final a = AffinityVector.build([
        _ev(weight: 1.0, genres: ['Fresh']),
        _ev(weight: 1.0, ageDays: 90, genres: ['Old']),
      ], nowMs: _nowMs);
      // Fresh is the max (1.0); Old decayed to 0.5 of Fresh.
      expect(a.of('genre', 'fresh'), closeTo(1.0, 1e-6));
      expect(a.of('genre', 'old'), closeTo(0.5, 1e-6));
    });

    test('negative weights push affinity below zero', () {
      final a = AffinityVector.build([
        _ev(weight: 1.0, genres: ['Liked']),
        _ev(weight: -0.4, genres: ['Disliked']),
      ], nowMs: _nowMs);
      expect(a.of('genre', 'liked'), greaterThan(0));
      expect(a.of('genre', 'disliked'), lessThan(0));
    });

    test('isWarm gates on event count', () {
      expect(AffinityVector.build([for (var i = 0; i < 9; i++) _ev(weight: 1)], nowMs: _nowMs).isWarm, isFalse);
      expect(AffinityVector.build([for (var i = 0; i < 10; i++) _ev(weight: 1)], nowMs: _nowMs).isWarm, isTrue);
    });

    test('a strong dislike does not suppress a liked genre below threshold', () {
      // Skips Horror hard, mildly likes Comedy. Comedy must stay a top feature.
      final a = AffinityVector.build([
        for (var i = 0; i < 5; i++) TasteEvent(weight: -0.8, occurredAtMs: _nowMs, genres: const ['Horror']),
        for (var i = 0; i < 3; i++) TasteEvent(weight: 0.8, occurredAtMs: _nowMs, genres: const ['Comedy']),
      ], nowMs: _nowMs);
      expect(a.of('genre', 'comedy'), closeTo(1.0, 1e-9)); // normalized to strongest positive
      expect(a.of('genre', 'horror'), lessThan(0));
      expect(a.topFeatures('genre', threshold: 0.5), contains('comedy'));
    });

    test('decadeOf buckets years', () {
      expect(decadeOf(1997), '1990s');
      expect(decadeOf(2000), '2000s');
      expect(decadeOf(2019), '2010s');
    });

    test('round-trips through json', () {
      final a = AffinityVector.build([_ev(weight: 1.0, genres: ['Sci-Fi'], year: 1999)], nowMs: _nowMs);
      final b = AffinityVector.fromJson(a.toJson());
      expect(b.of('genre', 'sci-fi'), closeTo(a.of('genre', 'sci-fi'), 1e-9));
      expect(b.of('decade', '1990s'), closeTo(a.of('decade', '1990s'), 1e-9));
      expect(b.eventCount, a.eventCount);
    });
  });

  group('recommendationScore', () {
    final taste = AffinityVector.build([
      _ev(weight: 1.0, genres: ['Sci-Fi'], actors: ['Actor A'], directors: ['Dir X'], year: 2015),
      _ev(weight: 1.0, genres: ['Sci-Fi']),
    ], nowMs: _nowMs);

    MediaItem movie({
      String id = 'm',
      List<String> genres = const [],
      int? year,
      double? rating,
      int viewCount = 0,
      int? addedAt,
    }) =>
        MediaItem.plex(
          id: id,
          kind: MediaKind.movie,
          serverId: 's1',
          title: 'M',
          genres: genres,
          year: year,
          rating: rating,
          viewCount: viewCount,
          addedAt: addedAt,
        );

    test('on-taste genre scores higher than off-taste', () {
      final onTaste = recommendationScore(movie(id: 'a', genres: ['Sci-Fi']), taste, nowMs: _nowMs);
      final offTaste = recommendationScore(movie(id: 'b', genres: ['Romance']), taste, nowMs: _nowMs);
      expect(onTaste, greaterThan(offTaste));
    });

    test('matching two liked genres scores at least as high as one', () {
      // Breadth must never be penalized (top2Of regression guard).
      final twoGenre = AffinityVector.build([
        for (var i = 0; i < 6; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, genres: const ['Sci-Fi']),
        for (var i = 0; i < 5; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, genres: const ['Thriller']),
      ], nowMs: _nowMs);
      final one = recommendationScore(movie(id: 'a', genres: ['Sci-Fi']), twoGenre, nowMs: _nowMs);
      final both = recommendationScore(movie(id: 'b', genres: ['Sci-Fi', 'Thriller']), twoGenre, nowMs: _nowMs);
      expect(both, greaterThanOrEqualTo(one));
    });

    test('watched item is heavily downranked', () {
      final unseen = recommendationScore(movie(id: 'a', genres: ['Sci-Fi'], viewCount: 0), taste, nowMs: _nowMs);
      final seen = recommendationScore(movie(id: 'a', genres: ['Sci-Fi'], viewCount: 1), taste, nowMs: _nowMs);
      expect(unseen - seen, closeTo(3.0, 0.2));
    });

    test('higher rating scores higher, all else equal', () {
      final hi = recommendationScore(movie(id: 'a', genres: ['Sci-Fi'], rating: 9), taste, nowMs: _nowMs);
      final lo = recommendationScore(movie(id: 'a', genres: ['Sci-Fi'], rating: 3), taste, nowMs: _nowMs);
      expect(hi, greaterThan(lo));
    });

    test('actor tag matches taste', () {
      final withActor = MediaItem.plex(
        id: 'z',
        kind: MediaKind.movie,
        serverId: 's1',
        title: 'Z',
        genres: const ['Sci-Fi'],
        roles: const [MediaRole(tag: 'Actor A')],
      );
      final s = recommendationScore(withActor, taste, nowMs: _nowMs);
      final withoutActor = recommendationScore(movie(id: 'z', genres: ['Sci-Fi']), taste, nowMs: _nowMs);
      expect(s, greaterThan(withoutActor));
    });
  });
}
