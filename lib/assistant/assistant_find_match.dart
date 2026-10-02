import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_media.dart';
import '../utils/external_ids.dart';
import 'assistant_plot_index.dart';

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

  bool sameAs(FindMatch other) {
    if (kind != null && other.kind != null && kind != other.kind) return false;
    if (ids.tmdb != null && other.ids.tmdb != null) return ids.tmdb == other.ids.tmdb;
    if (ids.imdb != null && other.ids.imdb != null) return ids.imdb == other.ids.imdb;
    if (year != null && other.year != null && (year! - other.year!).abs() > 1) return false;
    final keys = {for (final t in titles) titleKey(t)};
    return other.titles.any((t) => keys.contains(titleKey(t)));
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

/// Adds [m] to [matches], or folds it into the match it is the same title as.
FindMatch addMatch(List<FindMatch> matches, FindMatch m) {
  for (final existing in matches) {
    if (existing.sameAs(m)) return existing..absorb(m);
  }
  matches.add(m);
  return m;
}

/// Folds matches that turned out to be one title once their ids are known.
void collapseMatches(List<FindMatch> matches) {
  for (var i = 0; i < matches.length; i++) {
    for (var j = matches.length - 1; j > i; j--) {
      if (matches[i].sameAs(matches[j])) matches[i].absorb(matches.removeAt(j));
    }
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
