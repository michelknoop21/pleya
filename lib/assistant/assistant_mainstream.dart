import 'dart:math' as math;

import '../models/seerr/seerr_media.dart';

// What Big P suggests first: known titles, then the ones that fit the user.
// One rerank over the suggestions a tool already found, not a new engine.

final _han = RegExp(r'[⺀-⿟々〇〡-〩〸-〻㇀-㇯㐀-䶿一-鿿豈-﫿\u{20000}-\u{2FA1F}]', unicode: true);

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

/// Votes from which a title is known worldwide whatever its language
/// (a Korean series everyone watched), and below which it is obscure.
const _globalVotes = 2000;
const _obscureVotes = 100;

/// Fewest suggestions an obscure title may still fill up to.
const _fillTo = 5;

/// Fame from TMDB votes and popularity, 0 to 1. A title without either is
/// neither famous nor obscure.
double _fame(SeerrMedia m) {
  double scale(num n, int top) => (math.log(1 + n) / math.ln10 / top).clamp(0.0, 1.0);
  final votes = m.voteCount == null ? 0.5 : scale(m.voteCount!, 4);
  final popularity = m.popularity == null ? votes : scale(m.popularity!, 3);
  return 0.6 * votes + 0.4 * popularity;
}

bool _isNl(SeerrMedia m) => m.originalLanguage == 'nl' || (m.originCountry?.contains('NL') ?? false);

/// 1 for a wide-release or worldwide hit, 0.6 for a Dutch one, 0.3 for the
/// rest that people voted on, 0 for what hardly anyone did.
double _tier(SeerrMedia m) {
  final votes = m.voteCount;
  if (votes != null && votes >= _globalVotes) return 1;
  if (m.mainstream) return _isNl(m) ? 0.6 : 1;
  return votes == null || votes >= _obscureVotes ? 0.3 : 0;
}

bool _obscure(SeerrMedia m) => _tier(m) == 0;

/// [found] best first: well-known before less known, the source's own order
/// (its fit to the question or the user) as the second half of the score, so
/// a strong match can still beat a weak famous one. A title that has no
/// usable name is dropped. Obscure titles only fill up to [_fillTo] when
/// there are fewer known ones. [niche]: the user asked for obscure, arthouse
/// or foreign cinema; the source's order stands.
List<SeerrMedia> rankSuggestions(Iterable<SeerrMedia> found, {bool niche = false}) {
  final usable = [
    for (final m in found)
      if (!hasHan(m.title)) m,
  ];
  if (niche) return usable;
  final score = <SeerrMedia, double>{
    for (final (i, m) in usable.indexed)
      m: _tier(m) + 0.5 * _fame(m) + 0.5 * (usable.length < 2 ? 1 : 1 - i / (usable.length - 1)),
  };
  final ranked = [...usable]..sort((a, b) => score[b]!.compareTo(score[a]!));
  final known = ranked.where((m) => !_obscure(m)).toList();
  final fill = ranked.where(_obscure).take(math.max(0, _fillTo - known.length));
  return [...known, ...fill];
}
