/// The sources behind [TitleFacts], one function each. Each returns what it
/// found or null; errors go up to the service, which swallows and logs them.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../media/media_item.dart';
import '../models/seerr/seerr_detail_facts.dart';
import '../services/seerr/seerr_client.dart';
import '../services/tmdb/tmdb_client.dart';
import 'assistant_title_facts.dart';

const _usRatings = {'G', 'PG', 'PG-13', 'R', 'NC-17', 'TV-Y', 'TV-Y7', 'TV-G', 'TV-PG', 'TV-14', 'TV-MA'};

/// The library item's own fields. Plex writes a foreign rating as `de/12`;
/// a bare MPA or TV rating counts as US, anything else as unknown country.
TitleFacts serverFacts(MediaItem? item) {
  if (item == null) return const TitleFacts();
  final rating = item.contentRating?.trim() ?? '';
  final slash = rating.indexOf('/');
  final certifications = rating.isEmpty
      ? const <String, String>{}
      : slash == 2
      ? {rating.substring(0, 2).toUpperCase(): rating.substring(3)}
      : {_usRatings.contains(rating.toUpperCase()) ? 'US' : TitleFacts.anyCountry: rating};
  return TitleFacts.from(
    'server',
    certifications: certifications,
    genres: item.genres ?? const [],
    runtimeMin: item.durationMs == null ? null : (item.durationMs! / 60000).round(),
    cast: [for (final r in item.roles ?? const []) r.tag],
    score: item.rating ?? (item is PlexMediaItem ? item.audienceRating : null),
  );
}

Future<TitleFacts> seerrFacts(SeerrClient seerr, TmdbKind kind, int tmdbId) async {
  final d = await seerr.getMediaDetail(tmdbId: tmdbId, isMovie: kind == TmdbKind.movie);
  return TitleFacts.from(
    'seerr',
    certifications: d.certifications,
    genres: d.genres,
    runtimeMin: d.runtimeMinutes,
    cast: [for (final c in d.cast) c.name],
    score: d.voteAverage,
    popularity: d.popularity,
    providers: d.providers,
  );
}

/// The TMDB id behind an IMDb or TVDB id, through `/find`.
Future<int?> tmdbFind(TmdbClient tmdb, TmdbKind kind, {String? imdb, int? tvdb}) async {
  final body = imdb != null
      ? await tmdb.findByExternal(imdb, 'imdb_id')
      : await tmdb.findByExternal('$tvdb', 'tvdb_id');
  final results = body[kind == TmdbKind.movie ? 'movie_results' : 'tv_results'];
  final first = results is List && results.isNotEmpty ? results.first : null;
  return first is Map ? (first['id'] as num?)?.toInt() : null;
}

/// One `details` call with release_dates or content_ratings, credits,
/// watch/providers and external_ids appended.
Future<({TitleFacts facts, String? imdb, int? tvdb})> tmdbFacts(
  TmdbClient tmdb,
  TmdbKind kind,
  int tmdbId,
  String language,
) async {
  final j = await tmdb.details(kind, tmdbId, language: language);
  final runTimes = j['episode_run_time'];
  final credits = j['credits'];
  final cast = credits is Map ? credits['cast'] : null;
  final regions = j['watch/providers'] is Map ? (j['watch/providers'] as Map)['results'] : null;
  final ids = j['external_ids'] is Map ? j['external_ids'] as Map : const {};
  final facts = TitleFacts.from(
    'tmdb',
    // Same shapes as Seerr's releases / contentRatings, which proxy TMDB.
    certifications: parseSeerrCertifications(
      kind == TmdbKind.movie ? {'releases': j['release_dates']} : {'contentRatings': j['content_ratings']},
    ),
    genres: _names(j['genres'], 'name'),
    runtimeMin:
        (j['runtime'] as num?)?.toInt() ??
        (runTimes is List && runTimes.isNotEmpty ? (runTimes.first as num?)?.toInt() : null),
    cast: _names(cast, 'name'),
    score: (j['vote_average'] as num?)?.toDouble(),
    votes: (j['vote_count'] as num?)?.toInt(),
    popularity: (j['popularity'] as num?)?.toDouble(),
    providers: {
      if (regions is Map)
        for (final e in regions.entries)
          if (e.value is Map && _names((e.value as Map)['flatrate'], 'provider_name').isNotEmpty)
            '${e.key}': _names((e.value as Map)['flatrate'], 'provider_name'),
    },
  );
  final imdb = ids['imdb_id'] ?? j['imdb_id'];
  return (facts: facts, imdb: imdb is String && imdb.isNotEmpty ? imdb : null, tvdb: (ids['tvdb_id'] as num?)?.toInt());
}

/// Trakt's id lookup (`/search/{tmdb|imdb}/{id}`) with `extended=full`. Only
/// the public `trakt-api-key` header; Trakt's certification is the US one.
Future<TitleFacts?> traktFacts(http.Client client, String clientId, TmdbKind kind, String id) async {
  final sep = id.indexOf(':');
  final type = kind == TmdbKind.movie ? 'movie' : 'show';
  final body = await _getJson(
    client,
    Uri.https('api.trakt.tv', '/search/${id.substring(0, sep)}/${id.substring(sep + 1)}', {
      'type': type,
      'extended': 'full',
    }),
    {'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId},
  );
  final hit = body is List && body.isNotEmpty && body.first is Map ? (body.first as Map)[type] : null;
  if (hit is! Map) return null;
  final cert = hit['certification'];
  return TitleFacts.from(
    'trakt',
    certifications: cert is String && cert.isNotEmpty ? {'US': cert} : const {},
    genres: hit['genres'] is List ? (hit['genres'] as List).whereType<String>().toList() : const [],
    runtimeMin: (hit['runtime'] as num?)?.toInt(),
    score: (hit['rating'] as num?)?.toDouble(),
    votes: (hit['votes'] as num?)?.toInt(),
  );
}

/// TVmaze, series only: `/lookup/shows` answers with a redirect to
/// `/shows/{id}`, which the client follows.
Future<TitleFacts?> tvmazeFacts(http.Client client, {String? imdb, int? tvdb}) async {
  final show = await _getJson(
    client,
    Uri.https('api.tvmaze.com', '/lookup/shows', imdb != null ? {'imdb': imdb} : {'thetvdb': '$tvdb'}),
  );
  if (show is! Map) return null;
  final rating = show['rating'];
  return TitleFacts.from(
    'tvmaze',
    genres: show['genres'] is List ? (show['genres'] as List).whereType<String>().toList() : const [],
    runtimeMin: ((show['runtime'] ?? show['averageRuntime']) as num?)?.toInt(),
    score: rating is Map ? (rating['average'] as num?)?.toDouble() : null,
  );
}

/// Wikidata P1657 (MPA film rating) values, checked against wbgetentities.
const mpaRatingByQid = {
  'Q18665330': 'G',
  'Q18665334': 'PG',
  'Q18665339': 'PG-13',
  'Q18665344': 'R',
  'Q18665349': 'NC-17',
};

/// The MPA rating of a film by IMDb id: a `haswbstatement:P345` search for
/// the item, then `wbgetentities` for its P1657 claim. Two lookups, each
/// paid through [take].
Future<TitleFacts?> wikidataFacts(http.Client client, String imdb, bool Function() take) async {
  if (!take()) return null;
  final search = await _getJson(
    client,
    Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'list': 'search',
      'srsearch': 'haswbstatement:P345=$imdb',
      'srlimit': '1',
    }),
    _wikiHeaders,
  );
  final hits = search is Map && search['query'] is Map ? (search['query'] as Map)['search'] : null;
  final qid = hits is List && hits.isNotEmpty && hits.first is Map ? (hits.first as Map)['title'] : null;
  if (qid is! String || !take()) return null;
  final body = await _getJson(
    client,
    Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbgetentities',
      'format': 'json',
      'props': 'claims',
      'ids': qid,
    }),
    _wikiHeaders,
  );
  final entity = body is Map && body['entities'] is Map ? (body['entities'] as Map)[qid] : null;
  final claims = entity is Map && entity['claims'] is Map ? (entity['claims'] as Map)['P1657'] : null;
  for (final c in claims is List ? claims : const []) {
    final value = c is Map && c['mainsnak'] is Map ? (c['mainsnak'] as Map)['datavalue'] : null;
    final id = value is Map && value['value'] is Map ? (value['value'] as Map)['id'] : null;
    final rating = id is String ? mpaRatingByQid[id] : null;
    if (rating != null) return TitleFacts.from('wikidata', certifications: {'US': rating});
  }
  return null;
}

// Wikimedia asks every API client to name itself.
const _wikiHeaders = {'User-Agent': 'Pleya/1.0 (https://pleya.app)'};

List<String> _names(Object? list, String field) => [
  if (list is List)
    for (final e in list)
      if (e is Map && e[field] is String && (e[field] as String).isNotEmpty) e[field] as String,
];

/// Null on 404 (nothing known), an exception on any other failure.
Future<Object?> _getJson(http.Client client, Uri uri, [Map<String, String> headers = const {}]) async {
  final res = await client.get(uri, headers: {'Accept': 'application/json', ...headers});
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', uri);
  return jsonDecode(res.body);
}
