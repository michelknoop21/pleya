/// find_title's route: model interpretation, then the local plot index and
/// Wikipedia, then Pleya's own identity pipeline, then library and Seerr,
/// and a single web search only when that still leaves doubt. Web answers
/// are cached per profile session; web calls still running when evidence
/// suffices or the deadline hits are aborted on the wire.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import '../services/data_aggregation_service.dart' show filterHiddenLibraryItems;
import '../services/seerr/seerr_client.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../services/unified_catalog/source_resolver.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import '../utils/global_key_utils.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_find_episodes.dart';
import 'assistant_find_match.dart';
import 'assistant_plot_index.dart';
import 'assistant_tool_context.dart';
import 'assistant_web_lookup.dart';
import 'assistant_web_search.dart';

/// How long find_title waits for its fast sources (library, plot index,
/// Seerr, Wikipedia/Wikidata, web search). A bound for showing results
/// quickly, not for the model: its calls run under
/// `AssistantProviderConfig.providerTimeout`.
const fastSearchDeadline = Duration(seconds: 8);

class FindResult {
  const FindResult(this.matches, {this.partial = false, this.webSearched = false});
  final List<FindMatch> matches;

  /// A source did not answer before the deadline, or failed.
  final bool partial;
  final bool webSearched;
}

/// Runs the route for [q] within [budget] ([fastSearchDeadline]). Never throws; what did not answer
/// in time is left out and flagged as partial. Web calls still in flight when
/// it returns, or when the run is cancelled, are aborted; media-server and
/// Seerr calls, whose clients take no abort, are left to finish unread and
/// their late answers are dropped. No new call starts.
Future<FindResult> findTitles(
  AssistantToolContext ctx,
  FindQuery q, {
  Duration budget = fastSearchDeadline,
  Duration headStart = const Duration(milliseconds: 800),
  AssistantPlotIndexCache? plots,
  AssistantWebCache? webCache,
}) => FindRun(
  ctx,
  q,
  budget,
  plots ?? AssistantPlotIndexCache.shared,
  webCache ?? AssistantWebCache.shared,
).run(headStart);

class FindRun {
  FindRun(this.ctx, this.q, this.budget, this.plots, this.webCache);
  final AssistantToolContext ctx;
  final FindQuery q;
  final Duration budget;
  final AssistantPlotIndexCache plots;
  final AssistantWebCache webCache;
  final _clock = Stopwatch()..start();

  /// Fires when the run ends, its deadline passes or it is cancelled: every
  /// web call of the run listens to it.
  final _abort = AbortController();

  /// External ids already fetched, per library copy, for the identity resolver.
  final _knownIds = <String, ExternalIds>{};
  final matches = <FindMatch>[];
  var partial = false;
  var _webSearched = false;

  SeerrClient? get seerr => ctx.requests?.client();
  Duration get _left => budget - _clock.elapsed;
  bool get sufficient => matches.any((m) => m.rank == 2);

  /// The route is over (returned, out of time or cancelled): no new call
  /// starts and a late answer writes nothing into [matches].
  bool get settled => _abort.isAborted || _left <= Duration.zero || ctx.cancelled;

  /// [call] bounded by what is left of the deadline; null on any failure.
  Future<T?> attempt<T>(Future<T> Function() call) async {
    if (settled) {
      partial = true;
      return null;
    }
    try {
      // A cancel or the end of the run releases the wait at once.
      final result = await Future.any<T?>([call(), _abort.trigger.then<T?>((_) => null)]).timeout(_left);
      return settled ? null : result;
    } on http.RequestAbortedException {
      // Cancelled on purpose: enough evidence already, or the run is over.
      return null;
    } catch (e) {
      if (e is TimeoutException) _abort.abort();
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

  /// Movie and series libraries of [server] that Home hides from this
  /// profile. A deny-list, like normal search: a copy whose `libraryId` names
  /// no known library (Jellyfin falls back to `ParentId`) stays in.
  Future<Set<String>> _hiddenKeys(ServerId server) async {
    final visible = {for (final l in libraries) buildGlobalKey(l.client.serverId, l.libraryId)};
    return {
      for (final l in await ctx.libraries(server))
        if ((l.kind == MediaKind.movie || l.kind == MediaKind.show) && !visible.contains(l.globalKey)) l.globalKey,
    };
  }

  Future<FindResult> run(Duration headStart) async {
    // The ask's cancel ends the route at once, web calls included.
    unawaited(ctx.cancel?.trigger.then((_) => _abort.abort()));
    try {
      return await _run(headStart);
    } finally {
      _abort.abort();
    }
  }

  Future<FindResult> _run(Duration headStart) async {
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
    final wikiAbort = _child();
    Future<void>? wiki;
    if (!sufficient) wiki = attempt(() => _wikipedia(wikiAbort));
    await local;
    if (sufficient) {
      wikiAbort.abort();
    } else {
      wiki ??= attempt(() => _wikipedia(wikiAbort));
    }
    await wiki;

    // Wave 2: ids through the existing pipeline, then library and Seerr.
    await _resolve(matches.toList());
    if (!sufficient && !q.wantsEpisode) await _webFallback();
    if (q.wantsEpisode) await findEpisode(this);

    _abort.abort();
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
    final index = await plots.indexFor(libraries, stop: () => ctx.cancelled);
    if (settled) return;
    final kind = q.wantsEpisode ? MediaKind.show : q.kind;
    final hits = index
        .search([...q.variants, for (final c in q.candidates) c.title], limit: 15, kind: kind)
        .where((h) => _aboutIt(h.doc))
        .take(5)
        .toList();
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

  /// A title word alone says nothing about what a film is about: "space"
  /// must not bring up Space Jam or Safe Space. A hit counts when its plot,
  /// genres or cast share a search word, or a candidate names it.
  bool _aboutIt(AssistantPlotDoc doc) {
    final item = doc.item;
    final named = {for (final c in q.candidates) titleKey(c.title)}..remove('');
    if (named.contains(titleKey(item.title)) || named.contains(titleKey(item.originalTitle))) return true;
    final words = {for (final v in q.variants) ...plotTokens(v)};
    final about = [item.summary, ...?item.genres, for (final r in (item.roles ?? const []).take(5)) r.tag];
    return plotTokens(about.join(' ')).any(words.contains);
  }

  /// An abort that also fires with the run's own.
  AbortController _child() {
    final child = AbortController();
    _abort.trigger.then((_) => child.abort());
    return child;
  }

  String get _profile => ctx.catalog?.activeProfileId() ?? '';

  /// Wikipedia search on [lang], from the session cache when asked before.
  Future<List<WikiHit>> wikipedia(String query, String lang, [AbortController? abort]) => webCache.get(
    _profile,
    'wikipedia:$lang',
    query,
    () => ctx.web!.wikipedia(query, lang: lang, abort: abort ?? _abort),
  );

  /// The one real web search of the question; null once it was spent, when
  /// there is none, or when it failed.
  Future<List<WebSearchHit>?> searchWebOnce(String query) async {
    final search = ctx.web?.search;
    if (search == null || _webSearched || query.isEmpty || settled) return null;
    _webSearched = true;
    return attempt(
      () => webCache.get(_profile, 'web', query, () => search.search(query, maxResults: 5, abort: _abort)),
    );
  }

  Future<void> _wikipedia(AbortController abort) async {
    final web = ctx.web;
    if (web == null || q.variants.isEmpty) return;
    final searches = [
      for (final (i, lang) in web.languages.indexed)
        if (i < q.variants.length) wikipedia(q.variants[i], lang, abort),
    ];
    final found = await Future.wait(searches);
    if (settled) return;
    for (final hits in found) {
      for (final hit in hits.take(3)) {
        if (hit.kind == MediaKind.episode) continue;
        if (q.kind != null && !q.wantsEpisode && hit.kind != null && hit.kind != q.kind) continue;
        final m = FindMatch(hit.title, year: hit.year, kind: hit.kind, sources: [FindSource.wikipedia])
          ..qid = hit.qid
          ..snippet = hit.description;
        // An untyped page only counts when it names a title already in play.
        if (hit.kind == null && !matches.any((e) => e.namesSameTitle(m))) continue;
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
            if (client == null) return;
            final ids = await client.fetchExternalIds(item.id);
            if (!settled) m.ids = _knownIds[item.globalKey] = ids;
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
      final qids = [for (final m in bridge) m.qid!]..sort();
      final ids = await attempt(
        () => webCache.get(_profile, 'wikidata', qids.join(' '), () => web.wikidataIds(qids, abort: _abort)),
      );
      for (final m in bridge) {
        m.ids = ids?[m.qid] ?? m.ids;
      }
    }
    attachLooseMatches(matches);
    final live = [
      for (final m in todo)
        if (matches.contains(m)) m,
    ];
    await Future.wait([for (final m in live) _link(m)]);
    await groupLibraryMatches(matches, (serverId, targetId) async {
      if (_knownIds[buildGlobalKey(ServerId(serverId), targetId)] case final known?) return known;
      final client = ctx.userClient(ServerId(serverId));
      if (client == null || settled) throw StateError('no lookup');
      return client.fetchExternalIds(targetId).timeout(_left);
    });
    attachLooseMatches(matches);
  }

  void _pickSeerr(FindMatch m, List<SeerrMedia> found) {
    if (settled) return;
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
    final identity = m.identity;
    final servers = {for (final l in libraries) l.client.serverId: l.client};
    final client = seerr;
    final tmdb = m.ids.tmdb;
    await Future.wait([
      if (servers.isNotEmpty && kind != MediaKind.episode)
        attempt(() async {
          final hidden = {for (final id in servers.keys) id.value: await _hiddenKeys(id)};
          return fanOutFindAllByIdentity(
            servers: [
              for (final MapEntry(:key, :value) in servers.entries)
                if (isIdentityEligibleBackend(value.backend)) (serverId: key, client: value, online: true),
            ],
            identity: identity,
            maxConcurrent: 3,
            onBatch: (batch) {
              if (settled) return true;
              for (final r in batch) {
                m.addLibrary([
                  for (final item in filterHiddenLibraryItems([
                    for (final item in r.matches) _stamp(item, r.serverId.value),
                  ], hidden[r.serverId.value]))
                    item,
                ]);
              }
              return false;
            },
          );
        }),
      if (client != null && m.seerr == null && tmdb != null && kind != null)
        attempt(() async {
          final movie = kind == MediaKind.movie;
          final detail = movie ? await client.getMovie(tmdb) : await client.getTv(tmdb);
          if (detail.isNotEmpty && !settled) m.seerr = SeerrMedia.fromDetail(detail, mediaType: movie ? 'movie' : 'tv');
        }),
    ]);
  }

  /// One real web search for the whole question, only when the cheap
  /// sources left it open.
  Future<void> _webFallback() async {
    final hits = await searchWebOnce(q.variants.firstOrNull ?? '');
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
      if (!matches.any((e) => e.namesSameTitle(m))) fresh.add(addMatch(matches, m));
    }
    if (fresh.isNotEmpty) await _resolve(fresh);
  }

  MediaItem _stamp(MediaItem item, String serverId) =>
      item.serverId == serverId ? item : item.copyWith(serverId: serverId);
}
