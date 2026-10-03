import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_client.dart';
import 'assistant_find_match.dart';
import 'assistant_find_route.dart';
import 'assistant_plot_index.dart';

typedef _Episode = ({String title, String summary, int? season, int? number, MediaItem? item});

/// An episode is found inside its series: the series first, then its seasons
/// from the media server (episode summaries included) or, when it is not in
/// a library, from Seerr's season detail. When neither summary fits, an
/// episode page on Wikipedia, or the question's one web search, names the
/// episode, and that name (or the season and episode number it gives) is
/// looked up in the same episode lists. Adds the episode as a match.
Future<void> findEpisode(FindRun run) async {
  final shows = [
    for (final m in run.matches)
      if (m.kind == MediaKind.show) m,
  ]..sort((a, b) => b.rank.compareTo(a.rank));
  final show = shows.firstOrNull;
  if (show == null) return;
  final q = run.q;
  final words = {
    for (final v in [
      ...q.variants,
      for (final c in q.candidates)
        if (c.kind == MediaKind.episode) c.title,
    ])
      ...plotTokens(v),
  };

  final listed = <_Episode>[];
  for (final series in show.library.where((i) => i.kind == MediaKind.show)) {
    final client = run.ctx.userClient(ServerId(series.serverId!));
    if (client == null) continue;
    final seasons = await run.attempt(() => client.fetchChildren(series.id)) ?? const [];
    final episodes = <_Episode>[];
    await Future.wait([
      for (final s in _wanted(seasons.where((s) => s.kind == MediaKind.season), (s) => s.index, q.season))
        run.attempt(() async {
          final children = await client.fetchChildren(s.id);
          if (run.settled) return;
          for (final e in children) {
            final item = e.serverId == series.serverId ? e : e.copyWith(serverId: series.serverId);
            episodes.add((
              title: e.title ?? '',
              summary: e.summary ?? '',
              season: e.parentIndex ?? s.index,
              number: e.index,
              item: item,
            ));
          }
        }),
    ]);
    listed.addAll(episodes);
    if (_add(run, show, _byWords(run.q, episodes, words))) return;
  }

  final seerr = run.seerr;
  final tmdb = show.ids.tmdb;
  final detail = seerr == null || tmdb == null ? null : await run.attempt(() => seerr.getTv(tmdb));
  if (detail != null) await _seerrEpisodes(run, seerr!, tmdb!, detail, listed);
  if (_add(run, show, _byWords(run.q, listed.where((e) => e.item == null).toList(), words))) return;
  await _byEvidence(run, show, listed);
}

Future<void> _seerrEpisodes(
  FindRun run,
  SeerrClient seerr,
  int tmdb,
  Map<String, dynamic> detail,
  List<_Episode> episodes,
) async {
  final q = run.q;
  await Future.wait([
    for (final n in _wanted(SeerrSeason.listFromDetail(detail).map((s) => s.seasonNumber), (n) => n, q.season))
      run.attempt(() async {
        final season = await seerr.getTvSeason(tmdb, n);
        if (run.settled) return;
        for (final e in season['episodes'] is List ? season['episodes'] as List : const []) {
          if (e is! Map) continue;
          final number = e['episodeNumber'];
          episodes.add((
            title: '${e['name'] ?? ''}',
            summary: '${e['overview'] ?? ''}',
            season: n,
            number: number is num ? number.toInt() : null,
            item: null,
          ));
        }
      }),
  ]);
}

/// The asked season, or the first ten regular ones (specials only on request).
Iterable<T> _wanted<T>(Iterable<T> seasons, int? Function(T) number, int? asked) =>
    seasons.where((s) => asked == null ? (number(s) ?? 0) > 0 : number(s) == asked).take(10);

_Episode? _byWords(FindQuery q, List<_Episode> episodes, Set<String> words) {
  _Episode? best;
  if (q.season != null && q.episode != null) {
    best = episodes.where((e) => e.season == q.season && e.number == q.episode).firstOrNull;
  } else {
    var top = 0;
    for (final e in episodes) {
      if (q.episode != null && e.number != q.episode) continue;
      final score = {...plotTokens('${e.title} ${e.summary}')}.where(words.contains).length;
      if (score > top) (top, best) = (score, e);
    }
    // One shared word is chance unless the question had hardly more.
    if (top < (words.length <= 2 ? 1 : 2) && q.episode == null) best = null;
  }
  return best;
}

/// Episode names and numbers an outside source gives for the question:
/// episode pages on English Wikipedia first, then the one web search.
/// Resolved against [listed] (library copies first) back to numbers and the
/// library episode. Evidence that names no episode in [listed] (the library's
/// or Seerr's own episode list) adds nothing: a snippet's SxxEyy alone is
/// not an episode.
Future<void> _byEvidence(FindRun run, FindMatch show, List<_Episode> listed) async {
  final phrase = run.q.variants.firstOrNull;
  if (run.ctx.web == null || phrase == null) return;
  final query = '${show.title} episode $phrase';
  final wiki = await run.attempt(() => run.wikipedia(query, 'en')) ?? const [];
  final named = [
    for (final hit in wiki.take(5))
      if (hit.kind == MediaKind.episode) (title: hit.title, text: hit.description),
  ];
  if (_resolve(run, show, listed, named, FindSource.wikipedia)) return;
  final hits = await run.searchWebOnce(query) ?? const [];
  _resolve(run, show, listed, [
    for (final h in hits) (title: _episodeTitle(h.title), text: '${h.title} ${h.snippet}'),
  ], FindSource.web);
}

final _numbered = RegExp(r'\bs(\d{1,2})\s?e(\d{1,3})\b|season (\d{1,2}),? episode (\d{1,3})', caseSensitive: false);

bool _resolve(
  FindRun run,
  FindMatch show,
  List<_Episode> listed,
  List<({String title, String text})> named,
  FindSource source,
) {
  for (final n in named) {
    final key = titleKey(n.title);
    final numbers = _numbered.firstMatch(n.text);
    final season = int.tryParse(numbers?.group(1) ?? numbers?.group(3) ?? '');
    final number = int.tryParse(numbers?.group(2) ?? numbers?.group(4) ?? '');
    final found =
        listed.where((e) => key.length > 2 && titleKey(e.title) == key).firstOrNull ??
        listed.where((e) => season != null && e.season == season && e.number == number).firstOrNull;
    if (_add(run, show, found, source)) return true;
  }
  return false;
}

/// '"Blink" (Doctor Who) - Wikipedia' → 'Blink'.
String _episodeTitle(String raw) =>
    webTitle(raw).title.replaceAll(RegExp(r'\s*\([^)]*\)$'), '').replaceAll(RegExp(r'["“”]'), '').trim();

bool _add(FindRun run, FindMatch show, _Episode? best, [FindSource? source]) {
  // Every caller has awaited deadline-bound work; past the deadline nothing lands.
  if (best == null || run.settled) return false;
  final match = FindMatch(best.title, year: show.year, kind: MediaKind.episode, sources: {...show.sources, ?source})
    ..ids = show.ids
    ..seerr = show.seerr
    ..snippet = best.summary
    ..series = show.title
    ..season = best.season
    ..episode = best.number;
  if (best.item case final item?) match.addLibrary([item]);
  run.matches.insert(0, match);
  return true;
}
