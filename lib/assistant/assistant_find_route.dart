/// find_title's route: model interpretation, then the local plot index and
/// Wikipedia, then Pleya's own identity pipeline, then library and Seerr,
/// and a single web search only when that still leaves doubt.
library;

import 'dart:async';

import '../media/ids.dart';
import '../media/media_identity.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_client.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../services/unified_catalog/source_resolver.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import 'assistant_find_episodes.dart';
import 'assistant_find_match.dart';
import 'assistant_plot_index.dart';
import 'assistant_tool_context.dart';

class FindResult {
  const FindResult(this.matches, {this.partial = false, this.webSearched = false});
  final List<FindMatch> matches;

  /// A source did not answer before the deadline, or failed.
  final bool partial;
  final bool webSearched;
}

/// Runs the route for [q] within [budget]. Never throws; what did not answer
/// in time is left out and flagged as partial. Calls still in flight when it
/// returns are ignored, and no new one starts.
Future<FindResult> findTitles(
  AssistantToolContext ctx,
  FindQuery q, {
  Duration budget = const Duration(seconds: 8),
  Duration headStart = const Duration(milliseconds: 800),
  AssistantPlotIndexCache? plots,
}) => FindRun(ctx, q, budget, plots ?? AssistantPlotIndexCache.shared).run(headStart);

class FindRun {
  FindRun(this.ctx, this.q, this.budget, this.plots);
  final AssistantToolContext ctx;
  final FindQuery q;
  final Duration budget;
  final AssistantPlotIndexCache plots;
  final _clock = Stopwatch()..start();
  final matches = <FindMatch>[];
  var partial = false;
  var _webSearched = false;
  var _done = false;

  SeerrClient? get seerr => ctx.requests?.client();
  Duration get _left => budget - _clock.elapsed;
  bool get sufficient => matches.any((m) => m.rank == 2);

  /// [call] bounded by what is left of the deadline; null on any failure.
  Future<T?> attempt<T>(Future<T> Function() call) async {
    if (_done || _left <= Duration.zero) {
      partial = true;
      return null;
    }
    try {
      return await call().timeout(_left);
    } catch (e) {
      partial = true;
      appLogger.w('Assistant: find_title source failed', error: e.runtimeType);
      return null;
    }
  }

  /// The libraries Home would show this profile: visible servers, hidden
  /// libraries out. Without the catalog wiring the library side stays off
  /// rather than guessing which libraries are hidden.
  late final List<AssistantPlotSource> libraries = switch (ctx.catalog?.rowLoader) {
    final CatalogHomeCustomRowLoader loader => [
      for (final kind in const [MediaKind.movie, MediaKind.show])
        for (final l in loader.librariesFor(kind))
          if (ctx.userClient(l.serverId) case final client?) (client: client, libraryId: l.libraryId, kind: kind),
    ],
    _ => const [],
  };

  late final Set<String> _libraryKeys = {for (final l in libraries) '${l.client.serverId.value}/${l.libraryId}'};

  Future<FindResult> run(Duration headStart) async {
    final series = q.series;
    final showKind = q.wantsEpisode ? MediaKind.show : q.kind;
    for (final c in q.candidates) {
      if (c.kind == MediaKind.episode && series != null) continue;
      addMatch(matches, FindMatch(c.title, year: c.year, kind: c.kind ?? showKind, sources: [FindSource.model]));
    }
    if (series != null) addMatch(matches, FindMatch(series, kind: MediaKind.show, sources: [FindSource.model]));

    // Wave 1: the own synopsis first, with a short head start; Wikipedia
    // only joins when that does not already settle it.
    final local = attempt(_local);
    await Future.any([local, Future<void>.delayed(headStart)]);
    Future<void>? wiki;
    if (!sufficient) wiki = attempt(_wikipedia);
    await local;
    if (!sufficient) wiki ??= attempt(_wikipedia);
    await wiki;

    // Wave 2: ids through the existing pipeline, then library and Seerr.
    await _resolve(matches.toList());
    if (!sufficient && !q.wantsEpisode) await _webFallback();
    if (q.wantsEpisode) await findEpisode(this);

    _done = true;
    matches.sort((a, b) {
      final byRank = b.rank.compareTo(a.rank);
      if (byRank != 0) return byRank;
      final byEpisode = (b.kind == MediaKind.episode ? 1 : 0).compareTo(a.kind == MediaKind.episode ? 1 : 0);
      if (byEpisode != 0) return byEpisode;
      return (b.library.isNotEmpty ? 1 : 0).compareTo(a.library.isNotEmpty ? 1 : 0);
    });
    return FindResult(matches.take(8).toList(), partial: partial, webSearched: _webSearched);
  }

  Future<void> _local() async {
    if (libraries.isEmpty) return;
    final index = await plots.indexFor(libraries);
    final kind = q.wantsEpisode ? MediaKind.show : q.kind;
    final hits = index.search([...q.variants, for (final c in q.candidates) c.title], limit: 5, kind: kind);
    if (hits.isEmpty) return;
    final lead = hits.length == 1 || hits[0].score >= 2 * hits[1].score;
    for (final (i, hit) in hits.indexed) {
      if (hit.score < hits.first.score / 2) break;
      final item = hit.doc.item;
      final m = FindMatch(item.title ?? '', year: item.year, kind: item.kind, sources: [FindSource.libraryPlot])
        ..titles.addAll([?item.originalTitle])
        ..snippet = item.summary ?? ''
        ..plotScore = hit.score
        ..plotLead = i == 0 && lead;
      addMatch(matches, m..addLibrary([_stamp(item, hit.doc.serverId)]));
    }
  }

  Future<void> _wikipedia() async {
    final web = ctx.web;
    if (web == null || q.variants.isEmpty) return;
    final searches = [
      for (final (i, lang) in web.languages.indexed)
        if (i < q.variants.length) web.wikipedia(q.variants[i], lang: lang),
    ];
    for (final hits in await Future.wait(searches)) {
      for (final hit in hits.take(3)) {
        if (hit.kind == MediaKind.episode) continue;
        if (q.kind != null && !q.wantsEpisode && hit.kind != null && hit.kind != q.kind) continue;
        final m = FindMatch(hit.title, year: hit.year, kind: hit.kind, sources: [FindSource.wikipedia])
          ..qid = hit.qid
          ..snippet = hit.description;
        // An untyped page only counts when it names a title already in play.
        if (hit.kind == null && !matches.any((e) => e.sameAs(m))) continue;
        addMatch(matches, m);
      }
    }
  }

  /// Library ids first, Seerr's search next, Wikidata only for what still
  /// has none; then every library copy and Seerr's status.
  Future<void> _resolve(List<FindMatch> todo) async {
    await Future.wait([
      for (final m in todo)
        if (m.library.isNotEmpty && !m.ids.hasAny)
          attempt(() async {
            final item = m.library.first;
            final client = ctx.userClient(ServerId(item.serverId!));
            if (client != null) m.ids = await client.fetchExternalIds(item.id);
          }),
    ]);
    final client = seerr;
    if (client != null) {
      await Future.wait([
        for (final m in todo)
          if (m.ids.tmdb == null) attempt(() async => _pickSeerr(m, (await client.search(m.title)).items)),
      ]);
    }
    final bridge = [
      for (final m in todo)
        if (!m.ids.hasAny && m.qid != null) m,
    ];
    final web = ctx.web;
    if (bridge.isNotEmpty && web != null) {
      final ids = await attempt(() => web.wikidataIds(bridge.map((m) => m.qid!)));
      for (final m in bridge) {
        m.ids = ids?[m.qid] ?? m.ids;
      }
    }
    collapseMatches(matches);
    final live = [
      for (final m in todo)
        if (matches.contains(m)) m,
    ];
    await Future.wait([for (final m in live) _link(m)]);
    collapseMatches(matches);
  }

  void _pickSeerr(FindMatch m, List<SeerrMedia> found) {
    bool fits(SeerrMedia s) =>
        (m.kind == null || (m.kind == MediaKind.movie) == s.isMovie) &&
        (m.year == null || s.year == null || (int.parse(s.year!) - m.year!).abs() <= 1);
    final keys = {for (final t in m.titles) titleKey(t)};
    final pick =
        found.where((s) => fits(s) && keys.contains(titleKey(s.title))).firstOrNull ??
        (m.year == null ? null : found.where((s) => fits(s) && s.year == '${m.year}').firstOrNull);
    if (pick == null) return;
    m
      ..seerr = pick
      ..ids = ExternalIds(tmdb: pick.tmdbId, imdb: m.ids.imdb, tvdb: m.ids.tvdb)
      ..kind ??= pick.isMovie ? MediaKind.movie : MediaKind.show
      ..year ??= int.tryParse(pick.year ?? '')
      ..sources.add(FindSource.seerr);
    if (m.snippet.isEmpty) m.snippet = pick.overview ?? '';
  }

  /// Every visible copy through findAllByIdentity, and Seerr's own status
  /// for the title, side by side.
  Future<void> _link(FindMatch m) async {
    final kind = m.kind;
    final identity = MediaIdentity(externalIds: m.ids, title: m.title, year: m.year, kind: kind ?? MediaKind.unknown);
    final servers = {for (final l in libraries) l.client.serverId: l.client};
    final client = seerr;
    final tmdb = m.ids.tmdb;
    await Future.wait([
      if (servers.isNotEmpty && kind != MediaKind.episode)
        attempt(
          () => fanOutFindAllByIdentity(
            servers: [
              for (final MapEntry(:key, :value) in servers.entries)
                if (isIdentityEligibleBackend(value.backend)) (serverId: key, client: value, online: true),
            ],
            identity: identity,
            maxConcurrent: 3,
            onBatch: (batch) {
              for (final r in batch) {
                m.addLibrary([
                  for (final item in r.matches)
                    if (item.libraryId == null || _libraryKeys.contains('${r.serverId.value}/${item.libraryId}'))
                      _stamp(item, r.serverId.value),
                ]);
              }
              return false;
            },
          ),
        ),
      if (client != null && m.seerr == null && tmdb != null && kind != null)
        attempt(() async {
          final movie = kind == MediaKind.movie;
          final detail = movie ? await client.getMovie(tmdb) : await client.getTv(tmdb);
          if (detail.isNotEmpty) m.seerr = SeerrMedia.fromDetail(detail, mediaType: movie ? 'movie' : 'tv');
        }),
    ]);
  }

  /// One real web search for the whole question, only when the cheap
  /// sources left it open.
  Future<void> _webFallback() async {
    final search = ctx.web?.search;
    if (search == null || _webSearched || q.variants.isEmpty || _done || _left <= Duration.zero) return;
    _webSearched = true;
    final hits = await attempt(() => search.search(q.variants.first, maxResults: 5));
    if (hits == null) return;
    final fresh = <FindMatch>[];
    for (final hit in hits) {
      final text = foldText('${hit.title} ${hit.snippet}');
      for (final m in matches) {
        if (m.titles.any((t) => titleKey(t).length > 2 && text.contains(foldText(t)))) m.sources.add(FindSource.web);
      }
      final parsed = webTitle(hit.title);
      if (parsed.title.isEmpty || parsed.title.length > 80 || fresh.length >= 3) continue;
      final m = FindMatch(parsed.title, year: parsed.year, kind: q.kind, sources: [FindSource.web])
        ..snippet = hit.snippet;
      if (!matches.any((e) => e.sameAs(m))) fresh.add(addMatch(matches, m));
    }
    if (fresh.isNotEmpty) await _resolve(fresh);
  }

  MediaItem _stamp(MediaItem item, String serverId) =>
      item.serverId == serverId ? item : item.copyWith(serverId: serverId);
}
