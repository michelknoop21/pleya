/// Title facts for Big P: age ratings, genres, runtime, cast, score and
/// streaming services, gathered along a fixed chain. The own server comes
/// first, then Seerr, then (only with "online" on) TMDB with the user's own
/// key, Trakt, TVmaze and Wikidata. An earlier source always wins a field.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../services/seerr/seerr_client.dart';
import '../services/tmdb/tmdb_client.dart';
import '../services/trakt/trakt_constants.dart';
import '../utils/app_logger.dart';
import 'assistant_age_gate.dart';
import 'assistant_title_facts_cache.dart';
import 'assistant_title_facts_sources.dart';

/// One title to look up. Ids may be missing; the server item fills them.
class TitleRef {
  const TitleRef({
    required this.kind,
    required this.title,
    this.year,
    this.tmdbId,
    this.imdb,
    this.tvdb,
    this.item,
    this.serverId,
  });

  final TmdbKind kind;
  final String title;
  final int? year;
  final int? tmdbId;
  final String? imdb;
  final int? tvdb;

  /// The library item when the title is on a server; its fields come first.
  final MediaItem? item;
  final String? serverId;

  String get dedupeKey => tmdbId != null
      ? '${kind.path}:tmdb:$tmdbId'
      : imdb != null
      ? '${kind.path}:imdb:$imdb'
      : tvdb != null
      ? '${kind.path}:tvdb:$tvdb'
      : '${kind.path}:${serverId ?? ''}:${item?.id ?? '${title.toLowerCase()}:$year'}';
}

/// Facts about one title. [certifications] maps a country code to its age
/// rating; a server rating whose country is unknown sits under [anyCountry].
/// [origin] names the source per filled field (`cert:NL`, `genres`, ...).
class TitleFacts {
  const TitleFacts({
    this.certifications = const {},
    this.genres = const [],
    this.runtimeMin,
    this.cast = const [],
    this.score,
    this.votes,
    this.popularity,
    this.providers = const {},
    this.sources = const {},
    this.origin = const {},
  });

  /// Every non-empty field is credited to [source].
  factory TitleFacts.from(
    String source, {
    Map<String, String> certifications = const {},
    List<String> genres = const [],
    int? runtimeMin,
    List<String> cast = const [],
    double? score,
    int? votes,
    double? popularity,
    Map<String, List<String>> providers = const {},
  }) {
    final facts = TitleFacts(
      certifications: certifications,
      genres: genres,
      runtimeMin: runtimeMin != null && runtimeMin > 0 ? runtimeMin : null,
      cast: cast.take(5).toList(),
      score: score != null && score > 0 ? score : null,
      votes: votes,
      popularity: popularity,
      providers: providers,
    );
    final fields = facts._filled();
    return fields.isEmpty
        ? const TitleFacts()
        : TitleFacts(
            certifications: facts.certifications,
            genres: facts.genres,
            runtimeMin: facts.runtimeMin,
            cast: facts.cast,
            score: facts.score,
            votes: facts.votes,
            popularity: facts.popularity,
            providers: facts.providers,
            sources: {source},
            origin: {for (final f in fields) f: source},
          );
  }

  static const anyCountry = '*';

  final Map<String, String> certifications;
  final List<String> genres;
  final int? runtimeMin;
  final List<String> cast;
  final double? score;
  final int? votes;
  final double? popularity;

  /// Region code to subscription (flatrate) service names.
  final Map<String, List<String>> providers;
  final Set<String> sources;
  final Map<String, String> origin;

  bool get isEmpty => sources.isEmpty;

  List<String> _filled() => [
    for (final c in certifications.keys) 'cert:$c',
    if (genres.isNotEmpty) 'genres',
    if (runtimeMin != null) 'runtime',
    if (cast.isNotEmpty) 'cast',
    if (score != null) 'score',
    if (votes != null) 'votes',
    if (popularity != null) 'popularity',
    for (final r in providers.keys) 'providers:$r',
  ];

  /// Fills only what this one lacks: the earlier source in the chain wins,
  /// per country for ratings and per region for services.
  TitleFacts merge(TitleFacts other) {
    if (other.isEmpty) return this;
    if (isEmpty) return other;
    return TitleFacts(
      certifications: {...other.certifications, ...certifications},
      genres: genres.isNotEmpty ? genres : other.genres,
      runtimeMin: runtimeMin ?? other.runtimeMin,
      cast: cast.isNotEmpty ? cast : other.cast,
      score: score ?? other.score,
      votes: votes ?? other.votes,
      popularity: popularity ?? other.popularity,
      providers: {...other.providers, ...providers},
      sources: {...sources, ...other.sources},
      origin: {...other.origin, ...origin},
    );
  }

  /// What the model gets: the age rating for [region] and the US, the
  /// minimum age [AgeGate] reads from those, the genres, runtime, three
  /// cast names, score and the region's services.
  Map<String, Object?> toModelJson(String region) {
    final age = {
      for (final c in {region, 'US'})
        if (certifications[c] != null) c: certifications[c],
    };
    if (age.isEmpty && certifications[anyCountry] != null) age['server'] = certifications[anyCountry];
    final ageMin = AgeGate.minimumAge(this, region);
    return {
      if (age.isNotEmpty) 'age': age,
      'age_min': ?ageMin,
      if (genres.isNotEmpty) 'genres': genres,
      if (runtimeMin != null) 'runtime_min': runtimeMin,
      if (cast.isNotEmpty) 'cast': cast.take(3).toList(),
      if (score != null) 'score': (score! * 10).round() / 10,
      if (providers[region] case final p? when p.isNotEmpty) 'providers': p,
    };
  }

  Map<String, Object?> toJson() => {
    'certifications': certifications,
    'genres': genres,
    'runtimeMin': runtimeMin,
    'cast': cast,
    'score': score,
    'votes': votes,
    'popularity': popularity,
    'providers': providers,
    'sources': sources.toList(),
    'origin': origin,
  };

  factory TitleFacts.fromJson(Map<String, dynamic> json) {
    Map<String, String> strings(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is String) '${e.key}': e.value as String,
    };
    List<String> list(Object? v) => v is List ? v.whereType<String>().toList() : const [];
    final providers = json['providers'];
    return TitleFacts(
      certifications: strings(json['certifications']),
      genres: list(json['genres']),
      runtimeMin: (json['runtimeMin'] as num?)?.toInt(),
      cast: list(json['cast']),
      score: (json['score'] as num?)?.toDouble(),
      votes: (json['votes'] as num?)?.toInt(),
      popularity: (json['popularity'] as num?)?.toDouble(),
      providers: {
        if (providers is Map)
          for (final e in providers.entries) '${e.key}': list(e.value),
      },
      sources: list(json['sources']).toSet(),
      origin: strings(json['origin']),
    );
  }
}

/// Gathers [TitleFacts] for one ask. Build one per ask: the budget of
/// external lookups is spent over its lifetime. [online] off keeps every
/// call besides the own server and Seerr out; TMDB also needs [tmdbKey].
class TitleFactsService {
  TitleFactsService({
    required this.cache,
    this.clientFor,
    this.seerr,
    String? Function()? tmdbKey,
    bool Function()? online,
    String Function()? language,
    this.budget = 20,
    this.traktClientId = TraktConstants.clientId,
    http.Client? httpClient,
  }) : tmdbKey = tmdbKey ?? (() => null),
       online = online ?? (() => true),
       language = language ?? (() => 'en'),
       _http = httpClient ?? _sharedHttp;

  final TitleFactsCache cache;
  final MediaServerClient? Function(ServerId serverId)? clientFor;
  final SeerrClient? Function()? seerr;
  final String? Function() tmdbKey;
  final bool Function() online;
  final String Function() language;

  /// External lookups (TMDB, Trakt, TVmaze, Wikidata) left for this ask.
  int budget;

  /// Empty skips Trakt; it only needs the public `trakt-api-key` header.
  final String traktClientId;

  static const concurrency = 4;
  static const sourceTimeout = Duration(seconds: 4);
  static final _sharedHttp = http.Client();

  final http.Client _http;
  final _inFlight = <String, Future<TitleFacts>>{};
  bool _tmdbRejected = false;

  /// A TMDB client on the user's own key; null without a key, offline or
  /// after the key was rejected.
  TmdbClient? tmdb() {
    final key = tmdbKey();
    return online() && key != null && key.isNotEmpty && !_tmdbRejected ? TmdbClient(key, httpClient: _http) : null;
  }

  /// Facts per ref, in order. Identical refs share one lookup.
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async {
    final unique = <String, TitleRef>{for (final r in refs) r.dedupeKey: r};
    final queue = unique.values.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ref = queue.removeAt(0);
        await (_inFlight[ref.dedupeKey] ??= _factsFor(ref));
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    return [for (final r in refs) await _inFlight[r.dedupeKey]!];
  }

  bool _take() => budget-- > 0;

  /// Runs [call] with the source timeout; a failure counts as no facts.
  Future<T?> _guard<T>(String source, Future<T?> Function() call) async {
    try {
      return await call().timeout(sourceTimeout);
    } on TmdbAuthException {
      _tmdbRejected = true;
      appLogger.d('Title facts: TMDB key rejected');
    } catch (e) {
      appLogger.d('Title facts: $source failed', error: e.runtimeType);
    }
    return null;
  }

  Future<TitleFacts> _factsFor(TitleRef ref) async {
    final facts = serverFacts(ref.item);
    var tmdbId = ref.tmdbId;
    var imdb = ref.imdb;
    var tvdb = ref.tvdb;
    final client = ref.serverId == null || ref.item == null ? null : clientFor?.call(ServerId(ref.serverId!));
    if (client != null && (tmdbId == null || imdb == null)) {
      final ids = await _guard('server ids', () => client.fetchExternalIds(ref.item!.id));
      tmdbId ??= ids?.tmdb;
      imdb ??= ids?.imdb;
      tvdb ??= ids?.tvdb;
    }
    final lang = language();
    final online = this.online();
    if (tmdbId != null) {
      final cached = await cache.get(ref.kind, tmdbId, lang);
      if (cached != null) return facts.merge(cached);
    }

    var external = const TitleFacts();
    final seerr = this.seerr?.call();
    if (seerr != null && tmdbId != null) {
      final id = tmdbId;
      external = external.merge(await _guard('seerr', () => seerrFacts(seerr, ref.kind, id)) ?? const TitleFacts());
    }
    if (online) {
      final key = tmdbKey();
      if (key != null && key.isNotEmpty && !_tmdbRejected) {
        final tmdb = TmdbClient(key, httpClient: _http);
        if (tmdbId == null && (imdb ?? tvdb) != null && _take()) {
          tmdbId = await _guard('tmdb find', () => tmdbFind(tmdb, ref.kind, imdb: imdb, tvdb: tvdb));
        }
        if (tmdbId != null && !_tmdbRejected && _take()) {
          final id = tmdbId;
          final got = await _guard('tmdb', () => tmdbFacts(tmdb, ref.kind, id, lang));
          external = external.merge(got?.facts ?? const TitleFacts());
          imdb ??= got?.imdb;
          tvdb ??= got?.tvdb;
        }
      }
      final merged = facts.merge(external);
      if (traktClientId.isNotEmpty && (merged.score == null || merged.certifications.isEmpty)) {
        final id = tmdbId != null ? 'tmdb:$tmdbId' : (imdb != null ? 'imdb:$imdb' : null);
        if (id != null && _take()) {
          final got = await _guard('trakt', () => traktFacts(_http, traktClientId, ref.kind, id));
          external = external.merge(got ?? const TitleFacts());
        }
      }
      final soFar = facts.merge(external);
      if (ref.kind == TmdbKind.tv &&
          (imdb ?? tvdb) != null &&
          (soFar.genres.isEmpty || soFar.runtimeMin == null || soFar.score == null) &&
          _take()) {
        external = external.merge(
          await _guard('tvmaze', () => tvmazeFacts(_http, imdb: imdb, tvdb: tvdb)) ?? const TitleFacts(),
        );
      }
      if (ref.kind == TmdbKind.movie && imdb != null && !facts.merge(external).certifications.containsKey('US')) {
        final id = imdb;
        external = external.merge(
          await _guard('wikidata', () => wikidataFacts(_http, id, _take)) ?? const TitleFacts(),
        );
      }
      if (tmdbId != null && !external.isEmpty) await cache.put(ref.kind, tmdbId, lang, external);
    }
    return facts.merge(external);
  }
}
