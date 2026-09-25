import 'dart:math' as math;

import '../../media/media_item.dart';
import '../../media/media_role.dart';

/// How much positive evidence one title may ever contribute, expressed in
/// "titles worth of evidence". The n-th play of the same title counts 1/n, and
/// H(11) ≈ 3.02, so a show saturates around episode twelve: a binge is worth
/// three titles, never twenty.
const double kSeriesEvidenceCap = 3.0;

/// Distinct titles with net positive evidence before taste rows are meaningful.
/// Counting rows instead let ten episodes of one show pass as a taste profile.
const int kWarmDistinctTitles = 8;

/// Accumulated negative magnitude that equals a full penalty. One dismissal
/// (weight 0.3) lands at 0.2; five repeated signals reach the cap.
const double kPenaltyEvidenceUnit = 1.5;

/// Ceiling on a single feature's penalty.
const double kPenaltyMax = 1.0;

/// Ceiling on the summed penalty an item can take in [recommendationScore]. The
/// genre term alone contributes up to 4.5 positive, so a strong match still
/// wins from a partially disliked one.
const double kMaxTotalPenalty = 2.0;

/// A feature this heavily penalized never fronts a "Because you like X" row,
/// even when it also has positive evidence.
const double kTopFeaturePenaltyVeto = 0.5;

/// Distinct positive titles a person needs before fronting a row. Likes are
/// normalized per dimension, so the top actor reads 1.0 even from two titles;
/// this floor is counted on the raw evidence instead.
const int kPersonMinTitles = 3;

/// Share of the titles that warmed the model a person must appear in, on top
/// of [kPersonMinTitles]: three titles out of two hundred is not a taste.
const double kPersonMinTitleShare = 0.15;

/// One taste-relevant interaction, decoupled from the Drift row so this file
/// stays pure and unit-testable.
class TasteEvent {
  final double weight; // signed: completed 1.0, abandoned -0.4, …
  final int occurredAtMs;

  /// What this event is evidence *about*: the series key for an episode, the
  /// item's own global key for a movie. Events sharing a key are one title, so
  /// they saturate together instead of stacking. Empty means "no grouping
  /// known" and the event stands alone, which is what legacy rows without a
  /// series key need.
  final String evidenceKey;

  final List<String> genres;
  final List<String> actors;
  final List<String> directors;
  final List<String> moods;
  final String? studio;
  final int? year;

  const TasteEvent({
    required this.weight,
    required this.occurredAtMs,
    this.evidenceKey = '',
    this.genres = const [],
    this.actors = const [],
    this.directors = const [],
    this.moods = const [],
    this.studio,
    this.year,
  });
}

/// Per-profile taste vector: dimension → feature → weight in [0, 1] for likes,
/// plus a separate dimension → feature → penalty in [0, 1] for dislikes.
///
/// The two channels are deliberately not one signed map. Normalizing a signed
/// map divides by the strongest magnitude, so a single dismissal in a dimension
/// with no positive signal came out as exactly -1: a full veto from one tap.
/// Likes keep their scale-to-the-strongest-like semantics; dislikes are raw
/// evidence counted against a fixed unit and capped.
class AffinityVector {
  /// Positive affinities only, per-dimension normalized to the strongest like.
  final Map<String, Map<String, double>> dims;

  /// Dislike strength per feature, in [0, kPenaltyMax]. Never normalized.
  final Map<String, Map<String, double>> penalties;

  /// Raw interaction row count. Not a taste measure; [AffinitySnapshots]
  /// compares it against the live row count to spot a stale snapshot.
  final int eventCount;

  /// Distinct [TasteEvent.evidenceKey]s with net positive evidence.
  final int titleCount;

  /// Actors and directors (dimension → normalized names) that clear
  /// [kPersonMinTitles] and [kPersonMinTitleShare]. Only these may front a row.
  final Map<String, Set<String>> evidencedPersons;

  const AffinityVector(
    this.dims, {
    required this.eventCount,
    this.penalties = const {},
    this.titleCount = 0,
    this.evidencedPersons = const {},
  });

  static const empty = AffinityVector({}, eventCount: 0);

  /// Bumped whenever the stored shape changes; a snapshot at a lower version is
  /// treated as stale and recomputed, so there is nothing to migrate.
  static const int schemaVersion = 3;

  /// Whether there is enough history for taste-based rows; below this we fall
  /// back to quality/novelty-only ranking (cold start).
  bool get isWarm => titleCount >= kWarmDistinctTitles;

  double of(String dim, String? feature) {
    if (feature == null || feature.isEmpty) return 0;
    return dims[dim]?[_norm(feature)] ?? 0;
  }

  bool hasPersonEvidence(String dim, String feature) => evidencedPersons[dim]?.contains(_norm(feature)) ?? false;

  double penaltyOf(String dim, String? feature) {
    if (feature == null || feature.isEmpty) return 0;
    return penalties[dim]?[_norm(feature)] ?? 0;
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

  double maxPenaltyOf(String dim, Iterable<String>? features) {
    if (features == null) return 0;
    var worst = 0.0;
    for (final f in features) {
      final v = penaltyOf(dim, f);
      if (v > worst) worst = v;
    }
    return worst;
  }

  /// Strongest match plus a bonus for a second match — rewards items hitting
  /// multiple preferred genres without letting one dominant genre do all the
  /// work, and never scores a broader match below a single-genre one.
  double top2Of(String dim, Iterable<String>? features) {
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
    if (first <= 0) return 0;
    return first + 0.5 * second;
  }

  /// Top features of a dimension above [threshold], strongest first. A feature
  /// carrying a penalty of [kTopFeaturePenaltyVeto] or more is left out: it is
  /// liked and disliked at once, which is the worst thing to headline a row
  /// with.
  List<String> topFeatures(String dim, {double threshold = 0.5, int limit = 3}) {
    final entries =
        (dims[dim] ?? const {}).entries
            .where((e) => e.value >= threshold && (penalties[dim]?[e.key] ?? 0) < kTopFeaturePenaltyVeto)
            .toList()
          // Name after weight, so a tie picks the same feature on every load.
          ..sort((a, b) {
            final byWeight = b.value.compareTo(a.value);
            return byWeight != 0 ? byWeight : a.key.compareTo(b.key);
          });
    return [for (final e in entries.take(limit)) e.key];
  }

  /// Builds the vector with exponential decay (90-day half-life), per-title
  /// evidence saturation, per-dimension normalization of the likes, and a
  /// separate bounded penalty channel for the dislikes.
  static AffinityVector build(List<TasteEvent> events, {required int nowMs}) {
    if (events.isEmpty) return empty;
    const halfLifeDays = 90.0;

    final dims = <String, Map<String, double>>{};
    final penalties = <String, Map<String, double>>{};

    void bump(Map<String, Map<String, double>> into, String dim, String? feature, double amount) {
      if (feature == null || feature.isEmpty || amount == 0) return;
      final map = into.putIfAbsent(dim, () => {});
      final key = _norm(feature);
      map[key] = (map[key] ?? 0) + amount;
    }

    void spread(Map<String, Map<String, double>> into, TasteEvent e, double amount) {
      for (final g in e.genres) {
        bump(into, 'genre', g, amount);
      }
      for (final a in e.actors.take(5)) {
        bump(into, 'actor', a, amount);
      }
      for (final d in e.directors) {
        bump(into, 'director', d, amount);
      }
      for (final m in e.moods) {
        bump(into, 'mood', m, amount);
      }
      bump(into, 'studio', e.studio, amount);
      if (e.year != null) bump(into, 'decade', decadeOf(e.year!), amount);
    }

    // Decay once, then split. An event with an empty evidence key gets a key of
    // its own so it never merges with an unrelated legacy row.
    final decayed = <({TasteEvent event, double weight, String key})>[];
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      final ageDays = math.max(0, nowMs - e.occurredAtMs) / Duration.millisecondsPerDay;
      final w = e.weight * math.pow(0.5, ageDays / halfLifeDays);
      decayed.add((event: e, weight: w, key: e.evidenceKey.isEmpty ? '\u0000$i' : e.evidenceKey));
    }

    // Net evidence per title decides warmth: a title watched once and then
    // dismissed twice is not something to build a taste profile on.
    final netByKey = <String, double>{};
    for (final d in decayed) {
      netByKey[d.key] = (netByKey[d.key] ?? 0) + d.weight;
    }

    final positivesByKey = <String, List<({TasteEvent event, double weight, String key})>>{};
    for (final d in decayed) {
      if (d.weight > 0) {
        positivesByKey.putIfAbsent(d.key, () => []).add(d);
      } else if (d.weight < 0) {
        spread(penalties, d.event, -d.weight);
      }
    }

    // Per title: strongest (so freshest) first, n-th play counts 1/n, and the
    // running total is clipped at kSeriesEvidenceCap.
    for (final group in positivesByKey.values) {
      group.sort((a, b) => b.weight.compareTo(a.weight));
      var used = 0.0;
      for (var i = 0; i < group.length; i++) {
        var contribution = group[i].weight / (i + 1);
        if (used + contribution > kSeriesEvidenceCap) {
          contribution = kSeriesEvidenceCap - used;
        }
        if (contribution <= 0) break;
        used += contribution;
        spread(dims, group[i].event, contribution);
      }
    }

    // Person evidence floor, on raw title counts before normalization.
    final titleCount = netByKey.values.where((v) => v > 0).length;
    final personTitles = <String, Map<String, int>>{};
    for (final entry in positivesByKey.entries) {
      if ((netByKey[entry.key] ?? 0) <= 0) continue;
      final persons = <String, Set<String>>{
        'actor': {for (final d in entry.value) ...d.event.actors.take(5).map(_norm)},
        'director': {for (final d in entry.value) ...d.event.directors.map(_norm)},
      };
      for (final p in persons.entries) {
        final counts = personTitles.putIfAbsent(p.key, () => {});
        for (final name in p.value) {
          if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + 1;
        }
      }
    }
    final evidencedPersons = {
      for (final dim in personTitles.entries)
        dim.key: {
          for (final c in dim.value.entries)
            if (c.value >= kPersonMinTitles && c.value >= kPersonMinTitleShare * titleCount) c.key,
        },
    };

    // Likes: scale each dimension to its strongest like, so thresholds and row
    // cutoffs mean the same thing for every profile.
    for (final map in dims.values) {
      var maxPos = 0.0;
      for (final v in map.values) {
        if (v > maxPos) maxPos = v;
      }
      if (maxPos > 0) {
        for (final k in map.keys) {
          map[k] = (map[k]! / maxPos).clamp(0.0, 1.0);
        }
      }
    }

    // Dislikes: raw accumulated magnitude against a fixed unit, capped. No
    // normalization, because dividing by the strongest dislike is exactly what
    // turned one mild signal into a full veto.
    for (final map in penalties.values) {
      for (final k in map.keys) {
        map[k] = math.min(kPenaltyMax, map[k]! / kPenaltyEvidenceUnit);
      }
    }

    return AffinityVector(
      dims,
      eventCount: events.length,
      penalties: penalties,
      titleCount: titleCount,
      evidencedPersons: evidencedPersons,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'eventCount': eventCount,
    'titleCount': titleCount,
    'dims': {for (final e in dims.entries) e.key: e.value},
    'penalties': {for (final e in penalties.entries) e.key: e.value},
    'persons': {for (final e in evidencedPersons.entries) e.key: e.value.toList()},
  };

  static AffinityVector fromJson(Map<String, dynamic> json) {
    final count = json['eventCount'];
    final titles = json['titleCount'];
    return AffinityVector(
      _decodeDims(json['dims']),
      eventCount: count is int ? count : 0,
      penalties: _decodeDims(json['penalties']),
      titleCount: titles is int ? titles : 0,
      evidencedPersons: _decodePersons(json['persons']),
    );
  }

  static Map<String, Set<String>> _decodePersons(Object? raw) => {
    if (raw is Map)
      for (final entry in raw.entries)
        if (entry.value is List) '${entry.key}': {for (final n in entry.value as List) '$n'},
  };

  static Map<String, Map<String, double>> _decodeDims(Object? raw) {
    final out = <String, Map<String, double>>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final inner = entry.value;
        if (inner is Map) {
          out['${entry.key}'] = {
            for (final f in inner.entries)
              if (f.value is num) '${f.key}': (f.value as num).toDouble(),
          };
        }
      }
    }
    return out;
  }
}

String decadeOf(int year) => '${year - year % 10}s';

String _norm(String s) => s.trim().toLowerCase();

/// Personalized relevance score for [item] under taste [a]. Mirrors the shape
/// of `mediaSearchRelevanceScore`: a pure weighted sum, tunable in one place.
double recommendationScore(MediaItem item, AffinityVector a, {required int nowMs}) {
  final roleNames = [for (final r in item.roles?.take(5) ?? const <MediaRole>[]) r.tag];
  final decade = item.year != null ? decadeOf(item.year!) : null;

  var score =
      3.0 * a.top2Of('genre', item.genres) +
      2.0 * a.maxOf('actor', roleNames) +
      1.5 * a.maxOf('director', item.directors) +
      1.0 * a.of('decade', decade) +
      0.6 * a.of('studio', item.studio) +
      0.5 * a.maxOf('mood', item.moods);

  // Dislikes subtract on their own damped scale, and the total is capped so a
  // partially disliked item can still surface on a strong positive match.
  final penalty =
      1.2 * a.maxPenaltyOf('genre', item.genres) +
      0.8 * a.maxPenaltyOf('actor', roleNames) +
      0.6 * a.maxPenaltyOf('director', item.directors) +
      0.4 * a.penaltyOf('studio', item.studio) +
      0.3 * a.penaltyOf('decade', decade) +
      0.2 * a.maxPenaltyOf('mood', item.moods);
  score -= math.min(kMaxTotalPenalty, penalty);

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

  // Deterministic exploration jitter in [0, 0.05): stable within a day,
  // rotates daily. abs() because Dart's % keeps the (possibly negative) sign
  // of Object.hash.
  final dayBucket = nowMs ~/ Duration.millisecondsPerDay;
  score += 0.05 * ((Object.hash(item.globalKey, dayBucket).abs() % 1000) / 1000);

  // Already-seen downrank dominates: recommendations are for discovery.
  if (item.isWatched) score -= 3.0;

  return score;
}
