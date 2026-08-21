import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

const _nowMs = 1700000000000;

TasteEvent _ev({
  required double weight,
  String evidenceKey = '',
  List<String> genres = const [],
  List<String> actors = const [],
  List<String> directors = const [],
  String? studio,
  int? year,
  List<String> moods = const [],
}) => TasteEvent(
  weight: weight,
  occurredAtMs: _nowMs,
  evidenceKey: evidenceKey,
  genres: genres,
  actors: actors,
  directors: directors,
  studio: studio,
  year: year,
  moods: moods,
);

MediaItem _movie({String id = 'm', List<String> genres = const [], double? rating, int? year, String? studio}) =>
    MediaItem.plex(
      id: id,
      kind: MediaKind.movie,
      serverId: 's1',
      title: 'M',
      genres: genres,
      rating: rating,
      year: year,
      studio: studio,
    );

void main() {
  group('penalties are a separate, bounded channel', () {
    test('dims never carry a negative weight', () {
      final v = AffinityVector.build([
        _ev(weight: 1.0, evidenceKey: 'a', genres: const ['Liked']),
        _ev(weight: -0.4, evidenceKey: 'b', genres: const ['Disliked']),
      ], nowMs: _nowMs);
      expect(v.of('genre', 'liked'), greaterThan(0));
      expect(v.of('genre', 'disliked'), 0);
      expect(v.penaltyOf('genre', 'disliked'), greaterThan(0));
    });

    test('one mild dismissal is nowhere near a full veto', () {
      // A single "remove from continue watching" carries weight -0.3.
      final v = AffinityVector.build([
        _ev(weight: -0.3, evidenceKey: 'a', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(v.penaltyOf('genre', 'horror'), closeTo(0.3 / kPenaltyEvidenceUnit, 1e-9));
      expect(v.penaltyOf('genre', 'horror'), closeTo(0.2, 1e-9));
      expect(v.penaltyOf('genre', 'horror'), lessThan(kTopFeaturePenaltyVeto));
    });

    test('repeated signals saturate at kPenaltyMax', () {
      final five = AffinityVector.build([
        for (var i = 0; i < 5; i++) _ev(weight: -0.3, evidenceKey: 'a$i', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(five.penaltyOf('genre', 'horror'), closeTo(kPenaltyMax, 1e-9));

      final twenty = AffinityVector.build([
        for (var i = 0; i < 20; i++) _ev(weight: -0.8, evidenceKey: 'a$i', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(twenty.penaltyOf('genre', 'horror'), closeTo(kPenaltyMax, 1e-9));
    });

    test('a penalty is not normalized against the strongest penalty', () {
      // The old maxAbs divisor turned any lone negative into exactly -1.
      final v = AffinityVector.build([
        _ev(weight: -0.3, evidenceKey: 'a', genres: const ['Mild']),
        for (var i = 0; i < 10; i++) _ev(weight: -1.0, evidenceKey: 'b$i', genres: const ['Hated']),
      ], nowMs: _nowMs);
      expect(v.penaltyOf('genre', 'mild'), closeTo(0.2, 1e-9));
      expect(v.penaltyOf('genre', 'hated'), closeTo(kPenaltyMax, 1e-9));
    });

    test('an unknown feature has no penalty', () {
      final v = AffinityVector.build([
        _ev(weight: -1.0, evidenceKey: 'a', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(v.penaltyOf('genre', 'western'), 0);
      expect(v.penaltyOf('actor', 'horror'), 0);
      expect(v.maxPenaltyOf('genre', null), 0);
      expect(v.maxPenaltyOf('genre', const ['Western', 'Horror']), closeTo(1.0 / kPenaltyEvidenceUnit, 1e-9));
    });
  });

  group('penalties in recommendationScore', () {
    test('a partially disliked item scores lower than a neutral one', () {
      final taste = AffinityVector.build([
        _ev(weight: 1.0, evidenceKey: 'a', genres: const ['Sci-Fi']),
        for (var i = 0; i < 5; i++) _ev(weight: -0.8, evidenceKey: 'h$i', genres: const ['Horror']),
      ], nowMs: _nowMs);
      final neutral = recommendationScore(
        _movie(id: 'a', genres: const ['Western']),
        taste,
        nowMs: _nowMs,
      );
      final disliked = recommendationScore(
        _movie(id: 'a', genres: const ['Horror']),
        taste,
        nowMs: _nowMs,
      );
      expect(disliked, lessThan(neutral));
      expect(neutral - disliked, closeTo(1.2 * kPenaltyMax, 1e-9));
    });

    test('a strong positive match outweighs a partially negative one', () {
      final taste = AffinityVector.build([
        for (var i = 0; i < 5; i++) _ev(weight: 1.0, evidenceKey: 'p$i', genres: const ['Sci-Fi']),
        for (var i = 0; i < 5; i++) _ev(weight: -0.8, evidenceKey: 'h$i', genres: const ['Horror']),
      ], nowMs: _nowMs);
      final both = recommendationScore(
        _movie(id: 'a', genres: const ['Sci-Fi', 'Horror']),
        taste,
        nowMs: _nowMs,
      );
      final offTaste = recommendationScore(
        _movie(id: 'a', genres: const ['Western']),
        taste,
        nowMs: _nowMs,
      );
      expect(both, greaterThan(offTaste));
    });

    test('the total penalty is capped at kMaxTotalPenalty', () {
      final taste = AffinityVector.build([
        for (var i = 0; i < 10; i++)
          _ev(
            weight: -1.0,
            evidenceKey: 'h$i',
            genres: const ['Horror'],
            actors: const ['Bad Actor'],
            directors: const ['Bad Dir'],
            studio: 'Bad Studio',
            year: 1985,
            moods: const ['Grim'],
          ),
      ], nowMs: _nowMs);
      // Uncapped this sums to 1.2 + 0.8 + 0.6 + 0.4 + 0.3 + 0.2 = 3.5.
      final worst = MediaItem.plex(
        id: 'a',
        kind: MediaKind.movie,
        serverId: 's1',
        title: 'M',
        genres: const ['Horror'],
        directors: const ['Bad Dir'],
        moods: const ['Grim'],
        roles: const [MediaRole(tag: 'Bad Actor')],
        studio: 'Bad Studio',
        year: 1985,
      );
      final clean = _movie(id: 'a', genres: const ['Western'], year: 2020, studio: 'Good Studio');
      expect(
        recommendationScore(clean, taste, nowMs: _nowMs) - recommendationScore(worst, taste, nowMs: _nowMs),
        closeTo(kMaxTotalPenalty, 1e-9),
      );
    });

    test('a profile with no negatives scores exactly as before', () {
      final taste = AffinityVector.build([
        _ev(weight: 1.0, evidenceKey: 'a', genres: const ['Sci-Fi']),
      ], nowMs: _nowMs);
      final item = _movie(id: 'a', genres: const ['Sci-Fi'], rating: 8);
      // 3.0 * top2Of(1.0) + 0.8 * 0.8 quality prior, no novelty, jitter < 0.05.
      final s = recommendationScore(item, taste, nowMs: _nowMs);
      expect(s, greaterThanOrEqualTo(3.0 + 0.64));
      expect(s, lessThan(3.0 + 0.64 + 0.05));
    });
  });

  group('topFeatures veto', () {
    test('a genre that is both liked and heavily disliked is vetoed', () {
      final v = AffinityVector.build([
        for (var i = 0; i < 4; i++) _ev(weight: 1.0, evidenceKey: 'p$i', genres: const ['Horror', 'Thriller']),
        for (var i = 0; i < 5; i++) _ev(weight: -1.0, evidenceKey: 'n$i', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(v.penaltyOf('genre', 'horror'), greaterThanOrEqualTo(kTopFeaturePenaltyVeto));
      expect(v.topFeatures('genre', threshold: 0.5), isNot(contains('horror')));
      expect(v.topFeatures('genre', threshold: 0.5), contains('thriller'));
    });

    test('a mildly penalized genre survives the veto', () {
      final v = AffinityVector.build([
        for (var i = 0; i < 4; i++) _ev(weight: 1.0, evidenceKey: 'p$i', genres: const ['Horror']),
        _ev(weight: -0.3, evidenceKey: 'n', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(v.penaltyOf('genre', 'horror'), lessThan(kTopFeaturePenaltyVeto));
      expect(v.topFeatures('genre', threshold: 0.5), contains('horror'));
    });
  });
}
