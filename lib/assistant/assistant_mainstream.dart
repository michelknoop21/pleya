import 'dart:math' as math;

import '../models/seerr/seerr_media.dart';

// What Big P suggests first: known titles, then the ones that fit the user.
// One rerank over the suggestions a tool already found, not a new engine.

final _han = RegExp(r'[⺀-⿟々〇〡-〩〸-〻㇀-㇯㐀-䶿一-鿿豈-﫿\u{20000}-\u{2FA1F}\u{30000}-\u{3134F}]', unicode: true);

/// Chinese characters, in Chinese, Japanese or Korean titles alike.
bool hasHan(String? text) => text != null && _han.hasMatch(text);

/// The title to show: Dutch, else English, else the original, the first one
/// without Han characters. Null when none is: the candidate is skipped.
String? displayTitle({String? nl, String? en, String? original}) {
  for (final title in [nl, en, original]) {
    final t = title?.trim();
    if (t != null && t.isNotEmpty && !hasHan(t)) return t;
  }
  return null;
}

/// Votes from which a title in another language still counts as known, and
/// below which a title is obscure. A regional title can pass the first
/// without being mainstream, so it stands with the Dutch ones, not with the
/// big American releases (its fame score does the rest).
const _knownVotes = 2000;
const _obscureVotes = 100;

/// Known suggestions a tool wants before an obscure one may fill up; fewer
/// and it first looks at the next page of its source.
const suggestionFloor = 8;

/// Fame from TMDB votes and popularity, 0 to 1. A title without either is
/// neither famous nor obscure.
double _fame(SeerrMedia m) {
  double scale(num n, int top) => (math.log(1 + n) / math.ln10 / top).clamp(0.0, 1.0);
  final votes = m.voteCount == null ? 0.5 : scale(m.voteCount!, 4);
  final popularity = m.popularity == null ? votes : scale(m.popularity!, 3);
  return 0.6 * votes + 0.4 * popularity;
}

bool _isNl(SeerrMedia m) => m.originalLanguage == 'nl' || (m.originCountry?.contains('NL') ?? false);

/// 1 for a wide-release American or English title, 0.6 for a Dutch one or a
/// well-voted title in another language, 0.3 for the rest that people voted
/// on, 0 for what hardly anyone did.
double _tier(SeerrMedia m) {
  final votes = m.voteCount;
  if (m.mainstream && !_isNl(m)) return 1;
  if (m.mainstream || (votes != null && votes >= _knownVotes)) return 0.6;
  return votes == null || votes >= _obscureVotes ? 0.3 : 0;
}

bool _obscure(SeerrMedia m) => _tier(m) == 0;

/// [found] best first: well-known before less known, the source's own order
/// (its fit to the question or the user) as the second half of the score, so
/// a strong match can still beat a weak famous one. The order is per kind, so
/// series after movies in one list are not ranked below them for that alone.
/// A title that has no usable name is dropped, a title twice is kept once.
/// Obscure titles only fill up to [fillTo] when there are fewer known ones.
/// [niche]: the user asked for obscure, arthouse or foreign cinema; the
/// source's order stands.
List<SeerrMedia> rankSuggestions(Iterable<SeerrMedia> found, {bool niche = false, int fillTo = suggestionFloor}) {
  final seen = <String>{};
  final usable = [
    for (final m in found)
      if (!hasHan(m.title) && seen.add('${m.mediaType}:${m.tmdbId}')) m,
  ];
  if (niche) return usable;
  final perKind = <String, int>{};
  for (final m in usable) {
    perKind[m.mediaType] = (perKind[m.mediaType] ?? 0) + 1;
  }
  final next = <String, int>{};
  double relevance(SeerrMedia m) {
    final i = next[m.mediaType] = (next[m.mediaType] ?? -1) + 1;
    final n = perKind[m.mediaType]!;
    return n < 2 ? 1 : 1 - i / (n - 1);
  }

  final score = <SeerrMedia, double>{for (final m in usable) m: _tier(m) + 0.5 * _fame(m) + 0.5 * relevance(m)};
  final ranked = [...usable]..sort((a, b) => score[b]!.compareTo(score[a]!));
  final known = ranked.where((m) => !_obscure(m)).toList();
  final fill = ranked.where(_obscure).take(math.max(0, fillTo - known.length));
  return [...known, ...fill];
}

/// How many of [found] are known ones (not obscure, not Han, once each): what
/// a tool checks before it looks at the next page.
int knownCount(Iterable<SeerrMedia> found) {
  final seen = <String>{};
  return found.where((m) => !hasHan(m.title) && seen.add('${m.mediaType}:${m.tmdbId}') && !_obscure(m)).length;
}
