/// The open-web side of find_title: Wikipedia full-text search, Wikidata as
/// the id bridge of last resort, and one optional real web search.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../media/media_kind.dart';
import '../utils/abortable_http_request.dart';
import '../utils/external_ids.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_plot_index.dart';
import 'assistant_web_search.dart';

/// A Wikipedia search hit with what its short description says about it.
typedef WikiHit = ({String title, String description, int? year, MediaKind? kind, String? qid});

/// What the UI layer hands the find route when the user allows the web.
/// Null in `AssistantToolContext.web` keeps every external call out.
class AssistantWebServices {
  const AssistantWebServices({this.client, this.search, this.languages = const ['en', 'nl']});

  /// The ollama.com key wins over OpenRouter; with neither, Wikipedia and
  /// Wikidata stay on without the web search.
  factory AssistantWebServices.forKeys({String ollamaWebKey = '', String openRouterKey = '', http.Client? client}) =>
      AssistantWebServices(
        client: client,
        search: ollamaWebKey.isNotEmpty
            ? OllamaWebSearch(ollamaWebKey, client: client)
            : openRouterKey.isNotEmpty
            ? OpenRouterWebSearch(openRouterKey, client: client)
            : null,
      );

  /// For Wikipedia and Wikidata; a shared default when null.
  final http.Client? client;

  /// The one real web search per question; null leaves it out.
  final WebSearchClient? search;

  /// Wikipedia editions, in the order the search variants are spread over.
  final List<String> languages;

  static final _defaultClient = http.Client();

  // Wikimedia asks every API client to name itself.
  static const _headers = {'User-Agent': 'Pleya/1.0 (https://pleya.app)'};

  /// Full-text search on [lang].wikipedia.org through the Action API:
  /// `generator=search` plus `pageprops` (the Wikidata item) and the short
  /// description, in one request.
  Future<List<WikiHit>> wikipedia(String query, {String lang = 'en', int limit = 5, AbortController? abort}) async {
    final body = await _get(
      abort,
      Uri.https('$lang.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'generator': 'search',
        'gsrsearch': query,
        'gsrlimit': '$limit',
        'gsrnamespace': '0',
        'prop': 'pageprops|description',
        'ppprop': 'wikibase_item',
      }),
    );
    final pages = body['query'] is Map ? (body['query'] as Map)['pages'] : null;
    if (pages is! List) return const [];
    final sorted = [
      for (final p in pages)
        if (p is Map && p['title'] is String) p,
    ]..sort((a, b) => ((a['index'] as num?) ?? 99).compareTo((b['index'] as num?) ?? 99));
    return [for (final p in sorted) wikiHit(p['title'] as String, '${p['description'] ?? ''}', p['pageprops'])];
  }

  /// TMDB, IMDb and TVDB ids for Wikidata items, in one `wbgetentities` call:
  /// P4947 TMDB movie, P4983 TMDB TV series, P345 IMDb, P4835 TheTVDB series.
  Future<Map<String, ExternalIds>> wikidataIds(Iterable<String> qids, {AbortController? abort}) async {
    final wanted = {
      for (final q in qids)
        if (RegExp(r'^Q\d+$').hasMatch(q)) q,
    };
    if (wanted.isEmpty) return const {};
    final body = await _get(
      abort,
      Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'wbgetentities',
        'format': 'json',
        'props': 'claims',
        'ids': wanted.take(50).join('|'),
      }),
    );
    final entities = body['entities'];
    if (entities is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in entities.entries)
        if (key is String && value is Map && value['claims'] is Map) key: _ids(value['claims'] as Map),
    };
  }

  static ExternalIds _ids(Map claims) {
    String? claim(String property) {
      final list = claims[property];
      final snak = list is List && list.isNotEmpty && list.first is Map ? list.first['mainsnak'] : null;
      final value = snak is Map && snak['datavalue'] is Map ? snak['datavalue']['value'] : null;
      return value is String ? value : null;
    }

    return ExternalIds(
      tmdb: int.tryParse(claim('P4947') ?? claim('P4983') ?? ''),
      imdb: claim('P345'),
      tvdb: int.tryParse(claim('P4835') ?? ''),
    );
  }

  /// A GET that [abort] really cancels on the wire, not only stops waiting for.
  Future<Map> _get(AbortController? abort, Uri uri) async {
    final response = await sendAbortableHttpRequest(
      client ?? _defaultClient,
      'GET',
      uri,
      headers: _headers,
      abortTrigger: abort?.trigger,
    );
    if (response.statusCode != 200) throw http.ClientException('${response.statusCode}', uri);
    final body = jsonDecode(response.body);
    return body is Map ? body : const {};
  }
}

/// A hit read from its page title and short description: "Inception (2010
/// film)" or "2010 film by Christopher Nolan" both read as a 2010 movie.
WikiHit wikiHit(String title, String description, Object? pageprops) {
  final paren = RegExp(r'\s*\(([^)]*)\)$').firstMatch(title);
  final hint = '${paren?.group(1) ?? ''} $description'.toLowerCase();
  final year = RegExp(r'\b(1[89]\d\d|20\d\d)\b').firstMatch(hint)?.group(1);
  final kind = RegExp(r'episode|aflevering').hasMatch(hint)
      ? MediaKind.episode
      : RegExp(r'\bseries\b|\bserie\b|sitcom|miniseries|televisieserie').hasMatch(hint)
      ? MediaKind.show
      : RegExp(r'\bfilm\b|\bmovie\b|speelfilm').hasMatch(hint)
      ? MediaKind.movie
      : null;
  final qid = pageprops is Map ? pageprops['wikibase_item'] : null;
  return (
    title: paren == null ? title : title.substring(0, paren.start),
    description: description,
    year: year == null ? null : int.parse(year),
    kind: kind,
    qid: qid is String ? qid : null,
  );
}

/// Wikipedia, Wikidata and web search answers for one profile session, keyed
/// by their normalised query and kept for [ttl], beside the plot index cache.
/// Another profile starts a new session; a failed or aborted call is not kept.
class AssistantWebCache {
  AssistantWebCache({this.ttl = const Duration(minutes: 30), DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Duration ttl;
  final DateTime Function() _now;
  String? _profile;
  final _entries = <String, ({DateTime at, Object value})>{};

  static final shared = AssistantWebCache();

  void clear() => _entries.clear();

  Future<T> get<T extends Object>(String profile, String kind, String query, Future<T> Function() fetch) async {
    if (profile != _profile) {
      _entries.clear();
      _profile = profile;
    }
    final key = '$kind:${foldText(query).trim().replaceAll(RegExp(r'\s+'), ' ')}';
    final hit = _entries[key];
    if (hit != null && _now().difference(hit.at) < ttl && hit.value is T) return hit.value as T;
    final value = await fetch();
    if (profile == _profile) _entries[key] = (at: _now(), value: value);
    return value;
  }
}
