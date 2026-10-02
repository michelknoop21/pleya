import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import 'assistant_find_match.dart';
import 'assistant_find_route.dart';
import 'assistant_plot_index.dart';

typedef _Episode = ({String title, String summary, int? season, int? number, MediaItem? item});

/// An episode is found inside its series, never from a Wikipedia episode
/// list: the series first, then its seasons from the media server (episode
/// summaries included) or, when it is not in a library, from Seerr's season
/// detail. Adds the episode as a match and returns.
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

  for (final series in show.library.where((i) => i.kind == MediaKind.show)) {
    final client = run.ctx.userClient(ServerId(series.serverId!));
    if (client == null) continue;
    final seasons = await run.attempt(() => client.fetchChildren(series.id)) ?? const [];
    final episodes = <_Episode>[];
    await Future.wait([
      for (final s in _wanted(seasons.where((s) => s.kind == MediaKind.season), (s) => s.index, q.season))
        run.attempt(() async {
          for (final e in await client.fetchChildren(s.id)) {
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
    if (_add(run, show, episodes, words)) return;
  }

  final seerr = run.seerr;
  final tmdb = show.ids.tmdb;
  if (seerr == null || tmdb == null) return;
  final detail = await run.attempt(() => seerr.getTv(tmdb));
  if (detail == null) return;
  final episodes = <_Episode>[];
  await Future.wait([
    for (final n in _wanted(SeerrSeason.listFromDetail(detail).map((s) => s.seasonNumber), (n) => n, q.season))
      run.attempt(() async {
        final season = await seerr.getTvSeason(tmdb, n);
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
  _add(run, show, episodes, words);
}

/// The asked season, or the first ten regular ones (specials only on request).
Iterable<T> _wanted<T>(Iterable<T> seasons, int? Function(T) number, int? asked) =>
    seasons.where((s) => asked == null ? (number(s) ?? 0) > 0 : number(s) == asked).take(10);

bool _add(FindRun run, FindMatch show, List<_Episode> episodes, Set<String> words) {
  final q = run.q;
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
  if (best == null) return false;
  final match = FindMatch(best.title, year: show.year, kind: MediaKind.episode, sources: show.sources)
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
