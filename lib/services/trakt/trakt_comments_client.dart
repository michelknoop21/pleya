import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'trakt_constants.dart';

/// One public reaction on a title, as a card shows it.
@immutable
class TraktComment {
  const TraktComment({
    required this.id,
    required this.author,
    required this.text,
    required this.likes,
    this.createdAt,
    this.season,
  });

  final int id;
  final String author;
  final String text;
  final int likes;
  final DateTime? createdAt;

  /// The season this reaction is on; null when it is on the title as a whole.
  final int? season;
}

/// What one title's routes gave. Not [complete] when a season failed.
typedef _TitleComments = ({List<TraktComment> comments, bool complete});

/// What [TraktCommentsClient._get] hands back for a 404.
const Object _notFound = Object();

/// Trakt answered that it does not know the title by this id.
final class _UnknownTitle implements Exception {
  const _UnknownTitle();
}

/// Reads the public reactions on a title from Trakt.
///
/// Reading comments needs the app's public `trakt-api-key` and no account, so
/// this client never sends a token and has no session: what leaves the device
/// is a title's public id and the device's IP address. A title is found by its
/// IMDb id or its TMDB id and never by name, because a name can be another film.
///
/// Null means there is nothing to say about what Trakt thinks, and the page
/// shows no section: no key in this build, no id to look a title up by, an
/// answer that failed. Only an answer is cached, so a failure is tried again the
/// next time the title opens.
class TraktCommentsClient {
  TraktCommentsClient({
    http.Client? httpClient,
    this.clientId = TraktConstants.clientId,
    this.baseUrl = TraktConstants.apiBase,
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  /// The one a page reads through, so the cache outlives the page.
  static TraktCommentsClient shared = TraktCommentsClient();

  /// A Verify build reads the fixture's copy of these routes, with a key of its
  /// own: a build carries no real one.
  factory TraktCommentsClient.forVerify(String baseUrl) => TraktCommentsClient(clientId: 'verify', baseUrl: baseUrl);

  /// How many reactions a title asks for, per list.
  static const int pageSize = 30;

  /// How many reactions a title shows.
  static const int maxComments = 20;

  /// How many seasons of a series are asked for, newest first.
  static const int maxSeasons = 5;

  static const Duration requestTimeout = Duration(seconds: 8);
  static const Duration cacheLifetime = Duration(hours: 6);
  static const int cacheSize = 64;

  /// A title may hold an inline `[spoiler]…[/spoiler]` in a reaction that is not
  /// flagged as one, and "Hide spoilers" or not, those stay out.
  static final RegExp _spoilerTag = RegExp(r'\[/?spoiler\]', caseSensitive: false);

  final http.Client _http;
  final String clientId;
  final String baseUrl;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({DateTime at, List<TraktComment> comments})> _answers = LinkedHashMap();

  bool get isConfigured => clientId.isNotEmpty;

  /// The reactions on a film, most liked first.
  Future<List<TraktComment>?> movieComments(ExternalIds ids) => _load('movie', ids, const [], (id) async {
    final comments = await _comments('/movies/$id/comments/likes');
    return comments == null ? null : (comments: comments, complete: true);
  });

  /// The reactions on a series and on the seasons in [seasons], most liked
  /// first. A season Trakt does not know is left out, and one that failed too:
  /// the series itself decides whether there is an answer at all. An answer
  /// that misses a season is not kept, so the next visit asks for it again.
  Future<List<TraktComment>?> showComments(ExternalIds ids, {List<int> seasons = const []}) {
    final asked = ([...seasons]..sort()).reversed.take(maxSeasons).toList();
    return _load('show', ids, asked, (id) async {
      final show = await _comments('/shows/$id/comments/likes');
      if (show == null) return null;
      final perSeason = await Future.wait([
        for (final season in asked)
          _comments('/shows/$id/seasons/$season/comments/likes', season: season, missingIsEmpty: true),
      ]);
      return (comments: [...show, for (final list in perSeason) ...?list], complete: !perSeason.contains(null));
    });
  }

  Future<List<TraktComment>?> _load(
    String type,
    ExternalIds ids,
    List<int> seasons,
    Future<_TitleComments?> Function(String id) read,
  ) async {
    if (!isConfigured) return null;
    final key = _titleKey(ids);
    if (key == null) return null;
    final cacheKey = '$type:$key:${seasons.join(',')}';
    final cached = _answers[cacheKey];
    if (cached != null && _now().difference(cached.at) < cacheLifetime) return cached.comments;

    final id = await _traktId(type, ids);
    if (id == null) return null;
    final answer = await _readTitle(type, ids, id, read);
    if (answer == null) return null;
    final all = [...answer.comments]..sort((a, b) => b.likes.compareTo(a.likes));
    final comments = List<TraktComment>.unmodifiable(all.take(maxComments));
    if (!answer.complete) return comments;
    _answers.remove(cacheKey);
    _answers[cacheKey] = (at: _now(), comments: comments);
    while (_answers.length > cacheSize) {
      _answers.remove(_answers.keys.first);
    }
    return comments;
  }

  /// [read] on [id]. An IMDb id Trakt has never heard of says nothing about the
  /// title itself, so that one case gets a second try through the TMDB id.
  Future<_TitleComments?> _readTitle(
    String type,
    ExternalIds ids,
    String id,
    Future<_TitleComments?> Function(String id) read,
  ) async {
    try {
      return await read(id);
    } on _UnknownTitle {
      if (ids.imdb?.isNotEmpty != true) return null;
    }
    final found = await _traktIdFromTmdb(type, ids.tmdb);
    if (found == null) return null;
    try {
      return await read(found);
    } on _UnknownTitle {
      return null;
    }
  }

  String? _titleKey(ExternalIds ids) {
    if (ids.imdb case final imdb? when imdb.isNotEmpty) return imdb;
    if (ids.tmdb case final tmdb?) return 'tmdb:$tmdb';
    return null;
  }

  /// What Trakt's own routes take: an IMDb id goes straight in, a TMDB id is
  /// looked up first.
  Future<String?> _traktId(String type, ExternalIds ids) async {
    if (ids.imdb case final imdb? when imdb.isNotEmpty) return Uri.encodeComponent(imdb);
    return _traktIdFromTmdb(type, ids.tmdb);
  }

  Future<String?> _traktIdFromTmdb(String type, int? tmdb) async {
    if (tmdb == null) return null;
    final body = await _get('/search/tmdb/$tmdb', query: {'type': type});
    if (body is! List) return null;
    for (final hit in body) {
      if (hit is! Map || hit['type'] != type) continue;
      final title = hit[type];
      if (title is! Map) continue;
      final ids = title['ids'];
      if (ids is Map && ids['trakt'] is int) return '${ids['trakt']}';
    }
    return null;
  }

  Future<List<TraktComment>?> _comments(String path, {int? season, bool missingIsEmpty = false}) async {
    final body = await _get(path, query: {'page': '1', 'limit': '$pageSize'}, missingIsEmpty: missingIsEmpty);
    if (identical(body, _notFound)) throw const _UnknownTitle();
    if (body is! List) return null;
    return [
      for (final raw in body)
        if (raw is Map<String, dynamic>) ?_parse(raw, season),
    ];
  }

  TraktComment? _parse(Map<String, dynamic> json, int? season) {
    if (json['spoiler'] == true) return null;
    final raw = json['comment'];
    if (raw is! String || raw.isEmpty || _spoilerTag.hasMatch(raw)) return null;
    final user = json['user'];
    final username = user is Map ? user['username'] : null;
    final name = user is Map ? user['name'] : null;
    final author = username is String && username.isNotEmpty ? username : (name is String ? name : '');
    final text = plainComment(raw);
    if (author.isEmpty || text.isEmpty) return null;
    final id = json['id'];
    final likes = json['likes'];
    final createdAt = json['created_at'];
    return TraktComment(
      id: id is int ? id : 0,
      author: author,
      text: text,
      likes: likes is int ? likes : 0,
      createdAt: createdAt is String ? DateTime.tryParse(createdAt) : null,
      season: season,
    );
  }

  /// Trakt writes reactions in markdown. A card and the panel draw plain text,
  /// so the markers go and what they mark stays.
  @visibleForTesting
  static String plainComment(String markdown) => markdown
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (match) => match[1]!)
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
      .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (match) => match[2]!)
      .replaceAllMapped(RegExp(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])'), (match) => match[1]!)
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Future<Object?> _get(String path, {required Map<String, String> query, bool missingIsEmpty = false}) async {
    try {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final response = await _http
          .get(uri, headers: TraktConstants.headers(clientId: clientId))
          .timeout(requestTimeout);
      if (response.statusCode == 404) return missingIsEmpty ? const <Object?>[] : _notFound;
      if (response.statusCode != 200) {
        appLogger.d('Trakt comments: ${response.statusCode}');
        return null;
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      appLogger.d('Trakt comments failed', error: e);
      return null;
    }
  }
}
