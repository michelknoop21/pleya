import 'dart:async';
import 'dart:math';

import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';

/// A local plot index over the profile's own films and series, so Big P can
/// find "the film where ..." when no title comes to mind.
///
/// Built on the device from the paged library listings every backend already
/// serves: title, original title, overview, genres, year and the cast the
/// page carries. What each backend fills in differs: Plex's `/all` carries
/// summary, genres and the first roles; Jellyfin carries Overview and Genres
/// (asked with `withTasteFields`), no People; Pleya Server pages carry title
/// and year only. Searched with BM25 over folded tokens; no service, no
/// embeddings.
class AssistantPlotIndex {
  AssistantPlotIndex(List<AssistantPlotDoc> docs, {this.partial = false}) : _docs = docs {
    for (final (i, doc) in docs.indexed) {
      final tf = <String, int>{};
      for (final token in doc.tokens) {
        tf[token] = (tf[token] ?? 0) + 1;
      }
      _tf.add(tf);
      for (final token in tf.keys) {
        (_postings[token] ??= []).add(i);
      }
      _length += doc.tokens.length;
    }
  }

  final List<AssistantPlotDoc> _docs;
  final List<Map<String, int>> _tf = [];
  final Map<String, List<int>> _postings = {};
  var _length = 0;

  /// A library did not answer, the time budget ran out or the cap was hit.
  final bool partial;

  int get length => _docs.length;

  /// The best [limit] documents for [phrases], highest BM25 first. A phrase
  /// counts once per token; a doc that matches nothing is left out.
  List<({AssistantPlotDoc doc, double score})> search(Iterable<String> phrases, {int limit = 15, MediaKind? kind}) {
    final query = {for (final p in phrases) ...plotTokens(p)};
    if (query.isEmpty || _docs.isEmpty) return const [];
    const k1 = 1.2, b = 0.75;
    final avg = _length / _docs.length;
    final scores = <int, double>{};
    for (final token in query) {
      final docs = _postings[token];
      if (docs == null) continue;
      final idf = log(1 + (_docs.length - docs.length + 0.5) / (docs.length + 0.5));
      for (final i in docs) {
        if (kind != null && _docs[i].item.kind != kind) continue;
        final tf = _tf[i][token]!;
        final norm = tf + k1 * (1 - b + b * _docs[i].tokens.length / avg);
        scores[i] = (scores[i] ?? 0) + idf * tf * (k1 + 1) / norm;
      }
    }
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ranked.take(limit)) (doc: _docs[e.key], score: e.value)];
  }
}

/// One indexed title and the server it came from.
class AssistantPlotDoc {
  AssistantPlotDoc(this.serverId, this.item) : tokens = _docTokens(item);
  final String serverId;
  final MediaItem item;
  final List<String> tokens;

  // Field weight by repetition (a cheap BM25F): a word in the title or the
  // cast says more about the title than the same word deep in a summary.
  static List<String> _docTokens(MediaItem i) => [
    for (var n = 0; n < 3; n++) ...plotTokens('${i.title ?? ''} ${i.originalTitle ?? ''}'),
    for (var n = 0; n < 2; n++)
      ...plotTokens([...?i.genres, for (final r in (i.roles ?? const []).take(5)) r.tag].join(' ')),
    ...plotTokens(i.summary),
    if (i.year != null) '${i.year}',
  ];
}

const _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', 'ç': 'c', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
  'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ß': 'ss', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe',
};

/// Lower case with accents folded, so "Amélie" and "amelie" meet.
String foldText(String? value) =>
    (value ?? '').toLowerCase().replaceAllMapped(RegExp('[${_fold.keys.join()}]'), (m) => _fold[m[0]]!);

/// A title as a comparison key: folded, only letters and digits.
String titleKey(String? title) => foldText(title).replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

const _stopwords = {
  // English
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'for', 'from', 'has', 'he', 'her', 'his', 'in', 'into',
  'is', 'it', 'its', 'of', 'on', 'or', 'she', 'that', 'the', 'their', 'they', 'this', 'to', 'was', 'who', 'with',
  'film', 'movie', 'series', 'show',
  // Dutch
  'de', 'het', 'een', 'en', 'van', 'op', 'te', 'dat', 'die', 'er', 'zijn', 'met', 'voor', 'aan', 'als', 'bij',
  'door', 'naar', 'om', 'over', 'uit', 'tot', 'ze', 'zij', 'hij', 'wie', 'waar', 'waarin', 'wordt', 'werd', 'hun',
  'haar', 'ook', 'nog', 'niet', 'maar', 'dan', 'serie',
};

/// Folded word tokens, stopwords and single letters out.
List<String> plotTokens(String? text) => [
  for (final t in foldText(text).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
    if (t.length > 1 && !_stopwords.contains(t)) t,
];

/// One library the index reads: already through the same visibility rules
/// as Home and the catalog (`eligibleCatalogLibraries`: visible server, not
/// hidden for this profile), with the client that serves it.
typedef AssistantPlotSource = ({MediaServerClient client, String libraryId, MediaKind kind});

/// The index of the libraries a profile sees right now, built once and kept
/// for [ttl]. A different set (a profile switch, a library hidden, a server
/// coming online) builds a new one.
class AssistantPlotIndexCache {
  AssistantPlotIndexCache({
    this.ttl = const Duration(minutes: 30),
    this.budget = const Duration(seconds: 20),
    this.cap = 20000,
    this.pageSize = 200,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration ttl;

  /// The whole build stops here and the index is marked partial.
  final Duration budget;
  final int cap;
  final int pageSize;
  final DateTime Function() _now;

  List<AssistantPlotSource> _sources = const [];
  DateTime? _builtAt;
  Future<AssistantPlotIndex>? _index;

  /// Shared by the whole app: one profile session, one index.
  static final shared = AssistantPlotIndexCache();

  /// [stop] ends a build early, between two pages (the asking run was
  /// cancelled). Such a build is not kept: the next ask builds anew.
  Future<AssistantPlotIndex> indexFor(List<AssistantPlotSource> sources, {bool Function()? stop}) {
    final same = sources.length == _sources.length && sources.every(_sources.contains);
    final fresh = _builtAt != null && _now().difference(_builtAt!) < ttl;
    if (_index != null && same && fresh) return _index!;
    _sources = List.of(sources);
    _builtAt = _now();
    var stopped = false;
    bool halt() => stopped = stopped || (stop?.call() ?? false);
    // _build never throws: a library that fails is left out and flagged.
    final build = _index = _build(sources, halt);
    unawaited(
      build.then((_) {
        if (stopped && identical(_index, build)) _index = null;
      }),
    );
    return build;
  }

  Future<AssistantPlotIndex> _build(List<AssistantPlotSource> sources, bool Function() halt) async {
    final deadline = _now().add(budget);
    final docs = <AssistantPlotDoc>[];
    var partial = false;
    bool full() => docs.length >= cap;

    // One worker per server, its libraries in turn: bounded by the server
    // count, and no server gets more than one page request at a time.
    Future<void> walk(List<AssistantPlotSource> libraries) async {
      for (final source in libraries) {
        try {
          var offset = 0;
          while (!full()) {
            final left = deadline.difference(_now());
            if (left <= Duration.zero || halt()) {
              partial = true;
              return;
            }
            final page = await source.client
                .fetchLibraryContent(
                  source.libraryId,
                  LibraryQuery(kind: source.kind, offset: offset, limit: pageSize, withTasteFields: true),
                )
                .timeout(left);
            for (final item in page.items) {
              if (item.kind == MediaKind.movie || item.kind == MediaKind.show) {
                docs.add(AssistantPlotDoc(source.client.serverId.value, item));
              }
            }
            offset += page.items.length;
            if (page.items.isEmpty || offset >= page.totalCount) break;
          }
          if (full()) {
            partial = true;
            return;
          }
        } catch (e) {
          partial = true;
          appLogger.w('Assistant: plot index left a library out', error: e.runtimeType);
        }
      }
    }

    final byServer = <ServerId, List<AssistantPlotSource>>{};
    for (final s in sources) {
      (byServer[s.client.serverId] ??= []).add(s);
    }
    await Future.wait(byServer.values.map(walk));
    return AssistantPlotIndex(docs.take(cap).toList(), partial: partial);
  }
}
