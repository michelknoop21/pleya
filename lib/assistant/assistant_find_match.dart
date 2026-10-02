import '../media/media_backend.dart';
import '../media/media_identity.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/unified/canonical_media_identity.dart';
import '../media/unified/identity_evidence.dart';
import '../media/unified/unified_media_source.dart';
import '../models/seerr/seerr_media.dart';
import '../services/unified_catalog/grouping_service.dart';
import '../services/unified_catalog/identity_resolver.dart';
import '../utils/external_ids.dart';

/// A title the model proposed: never an id, only words.
typedef FindCandidate = ({String title, int? year, MediaKind? kind});

/// The question, interpreted once by the model.
class FindQuery {
  const FindQuery({
    this.candidates = const [],
    this.kind,
    this.variants = const [],
    this.series,
    this.season,
    this.episode,
  });
  final List<FindCandidate> candidates;

  /// movie, show or episode; null when the user did not say.
  final MediaKind? kind;

  /// Search phrases in Dutch and English, for the plot index and Wikipedia.
  final List<String> variants;
  final String? series;
  final int? season;
  final int? episode;

  bool get wantsEpisode => kind == MediaKind.episode || season != null || episode != null;
}

/// Where the evidence for a match came from. [library] and [seerr] only say
/// the title exists; the others say it fits the description.
enum FindSource { model, libraryPlot, wikipedia, web, library, seerr }

/// One title the route found, merged across every source that named it.
class FindMatch {
  FindMatch(String title, {this.year, this.kind, Iterable<FindSource> sources = const []})
    : titles = {title},
      title = title,
      sources = {...sources};

  String title;
  final Set<String> titles;
  int? year;
  MediaKind? kind;
  final Set<FindSource> sources;
  ExternalIds ids = const ExternalIds();
  String? qid;
  String snippet = '';

  /// Concrete library copies, each stamped with the server that answered.
  final List<MediaItem> library = [];
  SeerrMedia? seerr;

  /// BM25 score and whether it led the runner-up clearly.
  double plotScore = 0;
  bool plotLead = false;

  // An episode inside [series].
  String? series;
  int? season;
  int? episode;

  int get _evidence => sources
      .where(
        (s) => s == FindSource.model || s == FindSource.libraryPlot || s == FindSource.wikipedia || s == FindSource.web,
      )
      .length;

  bool get exists => library.isNotEmpty || seerr != null;

  /// Two independent sources agreeing (or a plot hit far ahead of the rest)
  /// is high; one source, or a proposal that turned out to exist, is medium.
  String get confidence {
    if (_evidence >= 2 || (plotLead && sources.contains(FindSource.libraryPlot))) return 'high';
    if (sources.contains(FindSource.libraryPlot) ||
        sources.contains(FindSource.wikipedia) ||
        sources.contains(FindSource.web) ||
        exists) {
      return 'medium';
    }
    return 'low';
  }

  int get rank => switch (confidence) {
    'high' => 2,
    'medium' => 1,
    _ => 0,
  };

  /// The match in the type `findAllByIdentity` takes.
  MediaIdentity get identity =>
      MediaIdentity(externalIds: ids, title: title, year: year, kind: kind ?? MediaKind.unknown);

  /// What [MediaIdentity.pickAllMatches] compares against: the concrete
  /// library copies, or every name a source gave the title.
  List<({MediaItem item, ExternalIds ids})> get _probes => library.isNotEmpty
      ? [for (final item in library) MediaIdentity.candidate(item, ids)]
      : [
          for (final t in titles)
            MediaIdentity.candidate(
              MediaItem(id: '', backend: MediaBackend.plex, kind: kind ?? MediaKind.unknown, title: t, year: year),
              ids,
            ),
        ];

  /// Whether [other] names the same title, by [MediaIdentity]'s own rules
  /// (an external id is proof, a title with a year that does not disagree
  /// the fallback), and no external id of one contradicts the other.
  bool namesSameTitle(FindMatch other) {
    if (kind != null && other.kind != null && kind != other.kind) return false;
    final mine = externalIdTokens(scope: 'title', ids: ids);
    final theirs = externalIdTokens(scope: 'title', ids: other.ids);
    if (mine.any((a) => theirs.any((b) => a.namespace == b.namespace && a.value != b.value))) return false;
    bool picks(FindMatch a, FindMatch b) => b._probes.any((p) => a.identity.pickAllMatches([p]).isNotEmpty);
    return picks(this, other) || picks(other, this);
  }

  void absorb(FindMatch other) {
    titles.addAll(other.titles);
    sources.addAll(other.sources);
    year ??= other.year;
    kind ??= other.kind;
    qid ??= other.qid;
    seerr ??= other.seerr;
    if (snippet.isEmpty) snippet = other.snippet;
    ids = ExternalIds(
      tmdb: ids.tmdb ?? other.ids.tmdb,
      imdb: ids.imdb ?? other.ids.imdb,
      tvdb: ids.tvdb ?? other.ids.tvdb,
    );
    addLibrary(other.library);
    if (other.plotScore > plotScore) plotScore = other.plotScore;
    plotLead |= other.plotLead;
  }

  void addLibrary(Iterable<MediaItem> items) {
    for (final item in items) {
      if (!library.any((i) => i.serverId == item.serverId && i.id == item.id)) library.add(item);
    }
    if (items.isNotEmpty) sources.add(FindSource.library);
  }
}

/// Adds [m] to [matches], or folds it into the match naming the same title.
/// Two matches that both hold library copies are left apart here: those are
/// grouped by the unified catalog's identity pipeline once their ids are in.
FindMatch addMatch(List<FindMatch> matches, FindMatch m) {
  for (final existing in matches) {
    if (existing.library.isNotEmpty && m.library.isNotEmpty) continue;
    if (existing.namesSameTitle(m)) return existing..absorb(m);
  }
  matches.add(m);
  return m;
}

/// Library copies become one title through the unified catalog's own
/// identity pipeline (resolver evidence, then `groupUnifiedMediaSources`), as
/// search_catalog and compare_servers group them: matches whose copies land
/// in one group are folded together. [fetchExternalIds] serves the resolver.
Future<void> groupLibraryMatches(
  List<FindMatch> matches,
  Future<ExternalIds> Function(String serverId, String targetId) fetchExternalIds,
) async {
  final owners = <String, List<FindMatch>>{};
  final items = <MediaItem>[];
  for (final m in matches) {
    for (final item in m.library) {
      if (item.kind != MediaKind.movie && item.kind != MediaKind.show) continue;
      final owned = owners[item.globalKey] ??= [];
      if (owned.isEmpty) items.add(item);
      owned.add(m);
    }
  }
  if (owners.length < 2) return;
  final evidence = await UnifiedIdentityResolver(fetchExternalIds: fetchExternalIds).resolveEvidence([
    for (final item in items)
      ResolvableItem(
        item: item,
        identity: canonicalIdentityOf(item),
        scope: (canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque()).granularity.name,
        externalIdTarget: normalizeStableGuid(item.guid) == null ? (serverId: item.serverId!, targetId: item.id) : null,
      ),
  ]);
  final groups = groupUnifiedMediaSources([
    for (var i = 0; i < items.length; i++)
      GroupingCandidate(source: UnifiedMediaSource.fromItem(items[i]), evidence: evidence[i]),
  ]);
  for (final group in groups) {
    final same = {for (final s in group.sources) ...?owners[s.sourceKey]}.where(matches.contains).toList();
    for (final other in same.skip(1)) {
      same.first.absorb(other);
      matches.remove(other);
    }
  }
}

/// A match without library copies (the model's, Wikipedia's, the web's,
/// Seerr's) joins the match it names by [FindMatch.namesSameTitle]: a shared
/// TMDB id from Seerr or Wikidata, or the title.
void attachLooseMatches(List<FindMatch> matches) {
  for (final loose in [
    for (final m in matches)
      if (m.library.isEmpty) m,
  ]) {
    final home = matches.where((m) => !identical(m, loose) && m.namesSameTitle(loose)).firstOrNull;
    if (home == null) continue;
    home.absorb(loose);
    matches.remove(loose);
  }
}

/// "Inception (2010) - IMDb" → ("Inception", 2010): a web page title read
/// as a film title, site names and separators cut off.
({String title, int? year}) webTitle(String raw) {
  var title = raw.split(RegExp(r'\s[-|–—:]\s')).first.trim();
  final year = RegExp(r'\((1[89]\d\d|20\d\d)\)').firstMatch(title);
  if (year != null) title = title.substring(0, year.start).trim();
  title = title.replaceAll(RegExp(r'\s*\((film|tv series|miniseries|movie)\)$', caseSensitive: false), '');
  return (title: title, year: year == null ? null : int.parse(year.group(1)!));
}
