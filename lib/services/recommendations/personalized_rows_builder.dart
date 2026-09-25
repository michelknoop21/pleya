import 'dart:convert';

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_role.dart';
import 'taste_profile.dart';

/// Localized titles for the synthesized personalized rows, injected so the
/// builder stays pure and unit-testable.
class PersonalizedRowTitles {
  final String topPicks;
  final String Function(String genre) becauseYouLike;
  final String hiddenGems;
  final String Function(String name) moreWithActor;
  final String Function(String name) moreFromDirector;

  const PersonalizedRowTitles({
    required this.topPicks,
    required this.becauseYouLike,
    required this.hiddenGems,
    required this.moreWithActor,
    required this.moreFromDirector,
  });
}

/// Genre, actor and director rows share these slots, so a warm profile never
/// gets more personalized rows than before this row existed.
const int kMaxAffinityRows = 2;

/// Persons need more than genres. The vector normalizes each dimension to its
/// strongest feature, so the top actor reads 1.0 no matter how much evidence
/// sits under him, and this threshold alone only bites after a penalty veto.
/// The guard against a weak person is the raw evidence floor
/// ([AffinityVector.hasPersonEvidence]); the tie-break towards genre covers
/// the rest.
const double kPersonFeatureThreshold = 0.7;

/// Builds synthesized home rows from a taste vector and a candidate pool.
/// Pure and side-effect-free: the same inputs always produce the same rows
/// (modulo the scorer's deterministic daily jitter).
///
/// - **Top Picks for You** — highest scoring unseen items overall.
/// - **Because you like `<genre>`**, **More with `<actor>`**, **More from
///   `<director>`**: the strongest genres and persons share
///   [kMaxAffinityRows] slots.
/// - **Hidden Gems** — well-rated, unseen, older-than-90-day catalogue depth.
///
/// Cold start (taste not warm): only Top Picks, ranked by the scorer's quality
/// + novelty priors (genre/actor terms are simply zero).
List<MediaHub> buildPersonalizedRows(
  AffinityVector taste,
  List<MediaItem> candidates, {
  required PersonalizedRowTitles titles,
  required int nowMs,
  Set<String> excludeKeys = const {},
  int rowSize = 20,
  int minRowItems = 4,
}) {
  // Unseen, non-excluded pool, de-duplicated by global key.
  final seen = <String>{...excludeKeys};
  final pool = <MediaItem>[];
  for (final item in candidates) {
    if (item.isWatched) continue;
    if (!seen.add(item.globalKey)) continue;
    pool.add(item);
  }
  if (pool.length < minRowItems) return const [];

  double scoreOf(MediaItem i) => recommendationScore(i, taste, nowMs: nowMs);
  final byScore = [...pool]..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

  final rows = <MediaHub>[];

  MediaHub row(String id, String title, List<MediaItem> items) => MediaHub(
    id: id,
    identifier: id,
    title: title,
    type: 'mixed',
    items: items.take(rowSize).toList(),
    size: items.length,
    serverId: items.isNotEmpty ? items.first.serverId : null,
  );

  // Top Picks
  final topPicks = byScore.take(rowSize).toList();
  rows.add(row('home.toppicks', titles.topPicks, byScore));
  // What already headlines the feed should not fill the row underneath it too.
  final usedInTopPicks = {for (final i in topPicks) i.globalKey};

  // Affinity rows (genre, actor, director) — only when taste is warm enough
  // to be meaningful.
  if (taste.isWarm) {
    final candidates =
        <({String dim, String feature, double weight})>[
          for (final g in taste.topFeatures('genre', threshold: 0.5, limit: 2))
            (dim: 'genre', feature: g, weight: taste.of('genre', g)),
          for (final dim in const ['actor', 'director'])
            for (final p in _topPerson(taste, dim)) (dim: dim, feature: p, weight: taste.of(dim, p)),
        ]..sort((a, b) {
          final byWeight = b.weight.compareTo(a.weight);
          return byWeight != 0 ? byWeight : _dimRank(a.dim).compareTo(_dimRank(b.dim));
        });

    final usedInAffinityRows = <String>{};
    var emitted = 0;
    for (final c in candidates) {
      if (emitted >= kMaxAffinityRows) break;
      final matches = byScore
          .where((i) => _matches(i, c.dim, c.feature) && usedInAffinityRows.add(i.globalKey))
          .toList();
      if (matches.length < minRowItems) continue;
      rows.add(switch (c.dim) {
        'genre' => row('home.becauselike.${c.feature}', titles.becauseYouLike(_titleCase(c.feature)), matches),
        'actor' => row(
          'home.becauselike.actor.${_slug(c.feature)}',
          titles.moreWithActor(_displayName(matches, c.feature)),
          matches,
        ),
        _ => row(
          'home.becauselike.director.${_slug(c.feature)}',
          titles.moreFromDirector(_displayName(matches, c.feature)),
          matches,
        ),
      });
      emitted++;
    }
  }

  // Hidden Gems — quality catalogue depth the user hasn't touched.
  final gemCutoff = nowMs - const Duration(days: 90).inMilliseconds;
  final gems = byScore.where((i) {
    if (usedInTopPicks.contains(i.globalKey)) return false;
    final rating = i.rating ?? 0;
    final added = i.addedAt;
    if (added == null || added <= 0) return false;
    final addedMs = added > 1000000000000 ? added : added * 1000;
    return rating >= 7.5 && addedMs < gemCutoff;
  }).toList();
  if (gems.length >= minRowItems) {
    rows.add(row('home.hiddengems', titles.hiddenGems, gems));
  }

  return rows;
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The strongest person above the threshold that also clears the evidence
/// floor; a thinly evidenced top actor steps aside for the next one.
Iterable<String> _topPerson(AffinityVector taste, String dim) => taste
    .topFeatures(dim, threshold: kPersonFeatureThreshold, limit: taste.dims[dim]?.length ?? 0)
    .where((p) => taste.hasPersonEvidence(dim, p))
    .take(1);

int _dimRank(String dim) => switch (dim) {
  'genre' => 0,
  'actor' => 1,
  _ => 2,
};

String _n(String s) => s.trim().toLowerCase();

bool _matches(MediaItem item, String dim, String feature) => switch (dim) {
  'genre' => (item.genres ?? const []).any((g) => _n(g) == feature),
  'actor' => (item.roles?.take(5) ?? const <MediaRole>[]).any((r) => _n(r.tag) == feature),
  _ => (item.directors ?? const []).any((d) => _n(d) == feature),
};

/// ASCII slug for the row id, which is also the hide key. A name that loses
/// non-ASCII characters on the way (Japanese, Cyrillic, Björk) gets a stable
/// hash of the full name, so hiding one person never hides another.
String _slug(String feature) {
  final ascii = feature.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (!RegExp(r'[^\x00-\x7f]').hasMatch(feature)) return ascii;
  final hash = _fnv1a(feature).toRadixString(36);
  return ascii.isEmpty ? hash : '$ascii-$hash';
}

/// 32-bit FNV-1a over UTF-8. Not [String.hashCode], which is not stable across
/// runs.
int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The name as the server spells it, from the first item that carries it.
/// The vector only knows the lowercased key.
String _displayName(List<MediaItem> matches, String feature) {
  for (final item in matches) {
    for (final r in item.roles ?? const <MediaRole>[]) {
      if (_n(r.tag) == feature) return r.tag;
    }
    for (final d in item.directors ?? const []) {
      if (_n(d) == feature) return d;
    }
  }
  return feature;
}
