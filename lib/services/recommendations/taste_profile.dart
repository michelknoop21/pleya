import 'dart:math' as math;

import '../../media/media_item.dart';
import '../../media/media_role.dart';

/// One taste-relevant interaction, decoupled from the Drift row so this file
/// stays pure and unit-testable.
class TasteEvent {
  final double weight; // signed: completed 1.0, abandoned -0.4, …
  final int occurredAtMs;
  final List<String> genres;
  final List<String> actors;
  final List<String> directors;
  final List<String> moods;
  final String? studio;
  final int? year;

  const TasteEvent({
    required this.weight,
    required this.occurredAtMs,
    this.genres = const [],
    this.actors = const [],
    this.directors = const [],
    this.moods = const [],
    this.studio,
    this.year,
  });
}

/// Per-profile taste vector: dimension → feature → weight in [-1, 1].
/// Built from decayed interaction history; a pure derivative that can be
/// recomputed from [TasteEvent]s at any time.
class AffinityVector {
  final Map<String, Map<String, double>> dims;
  final int eventCount;

  const AffinityVector(this.dims, {required this.eventCount});

  static const empty = AffinityVector({}, eventCount: 0);

  /// Whether there is enough history for taste-based rows; below this we fall
  /// back to quality/novelty-only ranking (cold start).
  bool get isWarm => eventCount >= 10;

  double operator [](String key) => 0; // not used; see [of]

  double of(String dim, String? feature) {
    if (feature == null || feature.isEmpty) return 0;
    return dims[dim]?[_norm(feature)] ?? 0;
  }

  double maxOf(String dim, Iterable<String>? features) {
    if (features == null) return 0;
    var best = 0.0;
    for (final f in features) {
      final v = of(dim, f);
      if (v > best) best = v;
    }
    return best;
  }

  /// Mean of the two strongest matches — rewards items hitting multiple
  /// preferred genres without letting one dominant genre do all the work.
  double meanTop2Of(String dim, Iterable<String>? features) {
    if (features == null) return 0;
    var first = 0.0, second = 0.0;
    for (final f in features) {
      final v = of(dim, f);
      if (v > first) {
        second = first;
        first = v;
      } else if (v > second) {
        second = v;
      }
    }
    if (first == 0) return 0;
    return second == 0 ? first : (first + second) / 2;
  }

  /// Top features of a dimension above [threshold], strongest first.
  List<String> topFeatures(String dim, {double threshold = 0.5, int limit = 3}) {
    final entries = (dims[dim] ?? const {}).entries.where((e) => e.value >= threshold).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) e.key];
  }

  /// Builds the vector with exponential decay (90-day half-life) and
  /// per-dimension normalization to the strongest feature.
  static AffinityVector build(List<TasteEvent> events, {required int nowMs}) {
    if (events.isEmpty) return empty;
    const halfLifeDays = 90.0;
    final dims = <String, Map<String, double>>{};

    void bump(String dim, String? feature, double amount) {
      if (feature == null || feature.isEmpty) return;
      final map = dims.putIfAbsent(dim, () => {});
      final key = _norm(feature);
      map[key] = (map[key] ?? 0) + amount;
    }

    for (final e in events) {
      final ageDays = math.max(0, nowMs - e.occurredAtMs) / Duration.millisecondsPerDay;
      final decayed = e.weight * math.pow(0.5, ageDays / halfLifeDays);
      for (final g in e.genres) {
        bump('genre', g, decayed);
      }
      for (final a in e.actors.take(5)) {
        bump('actor', a, decayed);
      }
      for (final d in e.directors) {
        bump('director', d, decayed);
      }
      for (final m in e.moods) {
        bump('mood', m, decayed);
      }
      bump('studio', e.studio, decayed);
      if (e.year != null) bump('decade', decadeOf(e.year!), decayed);
    }

    // Normalize each dimension to its strongest |weight| so scores stay
    // comparable regardless of history size; clamp to [-1, 1].
    for (final map in dims.values) {
      var maxAbs = 0.0;
      for (final v in map.values) {
        final a = v.abs();
        if (a > maxAbs) maxAbs = a;
      }
      if (maxAbs > 0) {
        for (final k in map.keys) {
          map[k] = (map[k]! / maxAbs).clamp(-1.0, 1.0);
        }
      }
    }
    return AffinityVector(dims, eventCount: events.length);
  }

  Map<String, dynamic> toJson() => {
    'eventCount': eventCount,
    'dims': {
      for (final e in dims.entries) e.key: e.value,
    },
  };

  static AffinityVector fromJson(Map<String, dynamic> json) {
    final rawDims = json['dims'];
    final dims = <String, Map<String, double>>{};
    if (rawDims is Map) {
      for (final entry in rawDims.entries) {
        final inner = entry.value;
        if (inner is Map) {
          dims['${entry.key}'] = {
            for (final f in inner.entries)
              if (f.value is num) '${f.key}': (f.value as num).toDouble(),
          };
        }
      }
    }
    final count = json['eventCount'];
    return AffinityVector(dims, eventCount: count is int ? count : 0);
  }
}

String decadeOf(int year) => '${year - year % 10}s';

String _norm(String s) => s.trim().toLowerCase();

/// Personalized relevance score for [item] under taste [a]. Mirrors the shape
/// of `mediaSearchRelevanceScore`: a pure weighted sum, tunable in one place.
///
/// [dayBucket] feeds the deterministic exploration jitter so ordering is
/// stable within a day but rotates over time.
double recommendationScore(MediaItem item, AffinityVector a, {required int nowMs}) {
  final roleNames = [for (final r in item.roles?.take(5) ?? const <MediaRole>[]) r.tag];

  var score =
      3.0 * a.meanTop2Of('genre', item.genres) +
      2.0 * a.maxOf('actor', roleNames) +
      1.5 * a.maxOf('director', item.directors) +
      1.0 * a.of('decade', item.year != null ? decadeOf(item.year!) : null) +
      0.6 * a.of('studio', item.studio) +
      0.5 * a.maxOf('mood', item.moods);

  // Quality prior: community/critic rating, defaulting to a neutral 6.5.
  final rating = item.rating ?? 6.5;
  score += 0.8 * (rating / 10);

  // Novelty: fresh additions get a fading 30-day boost.
  final addedAt = item.addedAt;
  if (addedAt != null && addedAt > 0) {
    final addedMs = addedAt > 1000000000000 ? addedAt : addedAt * 1000;
    final ageDays = (nowMs - addedMs) / Duration.millisecondsPerDay;
    if (ageDays >= 0 && ageDays < 30) score += 0.4 * (1 - ageDays / 30);
  }

  // Deterministic exploration jitter: stable within a day, rotates daily.
  final dayBucket = nowMs ~/ Duration.millisecondsPerDay;
  score += 0.05 * ((Object.hash(item.globalKey, dayBucket) % 1000) / 1000);

  // Already-seen downrank dominates: recommendations are for discovery.
  if (item.isWatched) score -= 3.0;

  return score;
}
