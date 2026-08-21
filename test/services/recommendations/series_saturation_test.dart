import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

const _day = Duration.millisecondsPerDay;
const _nowMs = 1700000000000;

TasteEvent _ev({
  required double weight,
  required String evidenceKey,
  int ageDays = 0,
  List<String> genres = const [],
}) => TasteEvent(weight: weight, occurredAtMs: _nowMs - ageDays * _day, evidenceKey: evidenceKey, genres: genres);

/// One undamped reference title, so a normalized vector still reveals how much
/// raw evidence a group produced: `evidence = 1 / of('genre', 'control')`.
TasteEvent _control() => _ev(weight: 1.0, evidenceKey: 's1:control', genres: const ['Control']);

double _evidenceRatio(AffinityVector v) => 1 / v.of('genre', 'control');

void main() {
  group('series saturation', () {
    test('twenty episodes of one show weigh at most kSeriesEvidenceCap titles', () {
      final binge = AffinityVector.build([
        for (var i = 0; i < 20; i++) _ev(weight: 1.0, evidenceKey: 's1:show', genres: const ['Sci-Fi']),
        _control(),
      ], nowMs: _nowMs);
      expect(_evidenceRatio(binge), lessThanOrEqualTo(kSeriesEvidenceCap + 1e-9));
      expect(_evidenceRatio(binge), greaterThan(2.5));
    });

    test('saturation is real: ten more episodes change nothing', () {
      double ratio(int episodes) => _evidenceRatio(
        AffinityVector.build([
          for (var i = 0; i < episodes; i++) _ev(weight: 1.0, evidenceKey: 's1:show', genres: const ['Sci-Fi']),
          _control(),
        ], nowMs: _nowMs),
      );
      expect(ratio(30), closeTo(ratio(20), 1e-9));
      expect(ratio(30), closeTo(kSeriesEvidenceCap, 1e-9));
    });

    test('three separate shows count independently', () {
      final one = AffinityVector.build([
        for (var i = 0; i < 20; i++) _ev(weight: 1.0, evidenceKey: 's1:a', genres: const ['Drama']),
        _control(),
      ], nowMs: _nowMs);
      final three = AffinityVector.build([
        for (var i = 0; i < 20; i++) _ev(weight: 1.0, evidenceKey: 's1:a', genres: const ['Drama']),
        for (var i = 0; i < 20; i++) _ev(weight: 1.0, evidenceKey: 's1:b', genres: const ['Drama']),
        for (var i = 0; i < 20; i++) _ev(weight: 1.0, evidenceKey: 's1:c', genres: const ['Drama']),
        _control(),
      ], nowMs: _nowMs);
      expect(_evidenceRatio(three), closeTo(_evidenceRatio(one) * 3, 1e-9));
    });

    test('a single movie is undamped', () {
      final v = AffinityVector.build([
        _ev(weight: 1.0, evidenceKey: 's1:movie', genres: const ['Noir']),
        _control(),
      ], nowMs: _nowMs);
      // Two equally strong single titles: neither dominates.
      expect(v.of('genre', 'noir'), closeTo(1.0, 1e-9));
      expect(v.of('genre', 'control'), closeTo(1.0, 1e-9));
    });

    test('rewatching the same movie yields a diminishing, bounded bonus', () {
      double ratio(int plays) => _evidenceRatio(
        AffinityVector.build([
          for (var i = 0; i < plays; i++) _ev(weight: 1.0, evidenceKey: 's1:movie', genres: const ['Noir']),
          _control(),
        ], nowMs: _nowMs),
      );
      expect(ratio(1), closeTo(1.0, 1e-9));
      expect(ratio(2), closeTo(1.5, 1e-9)); // 1 + 1/2
      expect(ratio(3), closeTo(1.0 + 0.5 + 1 / 3, 1e-9));
      expect(ratio(50), closeTo(kSeriesEvidenceCap, 1e-9));
    });

    test('the newest episodes take the undamped slots', () {
      // Ten year-old episodes plus one fresh one, same show. The fresh episode
      // has the highest decayed weight, so it must get the n=1 slot and the old
      // ones must not push the total far past a single title.
      final v = AffinityVector.build([
        for (var i = 0; i < 10; i++) _ev(weight: 1.0, ageDays: 360, evidenceKey: 's1:show', genres: const ['Sci-Fi']),
        _ev(weight: 1.0, evidenceKey: 's1:show', genres: const ['Sci-Fi']),
        _control(),
      ], nowMs: _nowMs);
      expect(_evidenceRatio(v), greaterThan(1.0));
      expect(_evidenceRatio(v), lessThan(1.2));
    });

    test('events without an evidence key stay independent', () {
      // Legacy rows carry no series key and must behave exactly as before.
      final v = AffinityVector.build([
        for (var i = 0; i < 3; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, genres: const ['Sci-Fi']),
        TasteEvent(weight: 1.0, occurredAtMs: _nowMs, genres: const ['Control']),
      ], nowMs: _nowMs);
      expect(_evidenceRatio(v), closeTo(3.0, 1e-9));
    });
  });

  group('warmth on distinct titles', () {
    TasteEvent title(int i) => _ev(weight: 1.0, evidenceKey: 's1:$i', genres: const ['Drama']);

    test('one binged series is not a warm profile', () {
      final v = AffinityVector.build([
        for (var i = 0; i < 40; i++) _ev(weight: 1.0, evidenceKey: 's1:show', genres: const ['Drama']),
      ], nowMs: _nowMs);
      expect(v.eventCount, 40);
      expect(v.titleCount, 1);
      expect(v.isWarm, isFalse);
    });

    test('warmth needs kWarmDistinctTitles distinct titles', () {
      expect(
        AffinityVector.build([for (var i = 0; i < kWarmDistinctTitles - 1; i++) title(i)], nowMs: _nowMs).isWarm,
        isFalse,
      );
      final warm = AffinityVector.build([for (var i = 0; i < kWarmDistinctTitles; i++) title(i)], nowMs: _nowMs);
      expect(warm.isWarm, isTrue);
      expect(warm.titleCount, kWarmDistinctTitles);
    });

    test('a title with net negative evidence does not count toward warmth', () {
      final v = AffinityVector.build([
        for (var i = 0; i < kWarmDistinctTitles - 1; i++) title(i),
        _ev(weight: 1.0, evidenceKey: 's1:disliked', genres: const ['Horror']),
        _ev(weight: -1.5, evidenceKey: 's1:disliked', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(v.titleCount, kWarmDistinctTitles - 1);
      expect(v.isWarm, isFalse);
    });

    test('eventCount stays the raw row count', () {
      final v = AffinityVector.build([
        for (var i = 0; i < 12; i++) _ev(weight: 1.0, evidenceKey: 's1:show', genres: const ['Drama']),
        _ev(weight: -0.3, evidenceKey: 's1:other', genres: const ['Horror']),
      ], nowMs: _nowMs);
      expect(v.eventCount, 13);
    });
  });

  group('snapshot version', () {
    test('toJson carries the current schema version', () {
      final v = AffinityVector.build([
        _ev(weight: 1.0, evidenceKey: 's1:a', genres: const ['Drama']),
      ], nowMs: _nowMs);
      expect(v.toJson()['v'], AffinityVector.schemaVersion);
      expect(AffinityVector.schemaVersion, 2);
    });

    test('round-trips titleCount and penalties', () {
      final v = AffinityVector.build([
        _ev(weight: 1.0, evidenceKey: 's1:a', genres: const ['Drama']),
        _ev(weight: -0.6, evidenceKey: 's1:b', genres: const ['Horror']),
      ], nowMs: _nowMs);
      final back = AffinityVector.fromJson(v.toJson());
      expect(back.titleCount, v.titleCount);
      expect(back.penaltyOf('genre', 'horror'), closeTo(v.penaltyOf('genre', 'horror'), 1e-9));
      expect(back.penaltyOf('genre', 'horror'), greaterThan(0));
    });
  });
}
