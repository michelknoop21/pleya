import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import 'taste_profile.dart';

/// Localized titles for the synthesized personalized rows, injected so the
/// builder stays pure and unit-testable.
class PersonalizedRowTitles {
  final String topPicks;
  final String Function(String genre) becauseYouLike;
  final String hiddenGems;

  const PersonalizedRowTitles({
    required this.topPicks,
    required this.becauseYouLike,
    required this.hiddenGems,
  });
}

/// Builds synthesized home rows from a taste vector and a candidate pool.
/// Pure and side-effect-free: the same inputs always produce the same rows
/// (modulo the scorer's deterministic daily jitter).
///
/// - **Top Picks for You** — highest scoring unseen items overall.
/// - **Because you like `<genre>`** — for the strongest 1-2 genres.
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
  rows.add(row('home.toppicks', titles.topPicks, byScore));

  // Because you like <genre> — only when taste is warm enough to be meaningful.
  if (taste.isWarm) {
    final usedInGenreRows = <String>{};
    for (final genre in taste.topFeatures('genre', threshold: 0.5, limit: 2)) {
      final matches = byScore
          .where((i) => (i.genres ?? const []).any((g) => g.trim().toLowerCase() == genre) && usedInGenreRows.add(i.globalKey))
          .toList();
      if (matches.length >= minRowItems) {
        rows.add(row('home.becauselike.$genre', titles.becauseYouLike(_titleCase(genre)), matches));
      }
    }
  }

  // Hidden Gems — quality catalogue depth the user hasn't touched.
  final gemCutoff = nowMs - const Duration(days: 90).inMilliseconds;
  final gems = byScore.where((i) {
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
