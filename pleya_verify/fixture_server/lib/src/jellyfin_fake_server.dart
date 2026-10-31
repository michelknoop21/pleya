import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'fixtures/deterministic_png.dart';

/// One film the way `/Items` reports it.
class JellyfinFakeMovie {
  const JellyfinFakeMovie({
    required this.id,
    required this.title,
    required this.year,
    this.criticRating,
    this.communityRating,
    this.officialRating,
    this.runTimeMinutes = 100,
  });

  final String id;
  final String title;
  final int year;
  final double? criticRating;
  final double? communityRating;
  final String? officialRating;
  final int runTimeMinutes;

  Map<String, Object?> toJson(String serverId) => {
    'Id': id,
    'ServerId': serverId,
    'Name': title,
    'SortName': title.toLowerCase(),
    'Type': 'Movie',
    'ProductionYear': year,
    'PremiereDate': '$year-06-01T00:00:00.0000000Z',
    'DateCreated': '2026-01-01T00:00:00.0000000Z',
    'CriticRating': ?criticRating,
    'CommunityRating': ?communityRating,
    'OfficialRating': ?officialRating,
    'RunTimeTicks': runTimeMinutes * 60 * 10000000,
    'ImageTags': {'Primary': id},
    'UserData': {'Played': false, 'PlayCount': 0, 'PlaybackPositionTicks': 0},
  };
}

/// The part of a Jellyfin server the catalog needs, under `/jellyfin`.
///
/// Pleya Protocol has no scores, so `PleyaFakeServer` cannot put a tomato on a
/// card. This is what lets a scenario run the score sort through the real
/// mappers, translator and merge. It sends titles without a value first on an
/// ascending sort and last on a descending one, which is one of the two
/// placements the merge has to survive and not a statement about Jellyfin.
class JellyfinFakeServer {
  static const serverId = 'verify-jellyfin';
  static const userId = 'verify-jellyfin-user';
  static const libraryId = 'verify-jellyfin-movies';

  final List<JellyfinFakeMovie> movies = [];

  /// Every `/Items` query, for a test that wants to see what the app asked for.
  final List<Map<String, String>> itemQueries = [];

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst('/jellyfin', '');
    if (path == '/System/Info/Public') {
      return _json({
        'Id': serverId,
        'ServerName': 'Verify Jellyfin',
        'Version': '10.11.0',
        'ProductName': 'Jellyfin Server',
      });
    }
    if (path == '/Users/AuthenticateByName') {
      return _json({
        'AccessToken': 'verify-jellyfin-token',
        'ServerId': serverId,
        'User': {
          'Id': userId,
          'Name': 'verify-owner',
          'Policy': {'IsAdministrator': false},
        },
      });
    }
    if (path == '/Users/$userId/Views' || path == '/UserViews') {
      return _list([
        {'Id': libraryId, 'Name': 'Movies', 'CollectionType': 'movies', 'Type': 'CollectionFolder'},
      ]);
    }
    if (path == '/Items' && request.url.queryParameters['ParentId'] == libraryId) {
      return _items(request.url.queryParameters);
    }
    if (path.contains('/Images/')) {
      final digest = sha256.convert(utf8.encode(path.split('/')[2])).bytes;
      return http.Response.bytes(
        solidColorPng(width: 32, height: 32, r: digest[0], g: digest[1], b: digest[2]),
        200,
        headers: {'content-type': 'image/png'},
      );
    }
    // Home asks for resume, next up and latest. An empty list is an honest
    // answer from a server that has watched nothing.
    return _list(const []);
  }

  http.Response _items(Map<String, String> query) {
    itemQueries.add(query);
    // Both are lists, as on Jellyfin: a key without an order of its own takes the
    // first one (measured on 12.4.0), so one value runs the SortName behind the
    // field the same way.
    final orders = (query['SortOrder'] ?? '').split(',');
    final descending = orders.first == 'Descending';
    final tieDescending = (orders.length > 1 ? orders[1] : orders.first) == 'Descending';
    int tie(JellyfinFakeMovie a, JellyfinFakeMovie b) =>
        tieDescending ? b.title.compareTo(a.title) : a.title.compareTo(b.title);
    Comparable<Object>? key(JellyfinFakeMovie movie) => switch (query['SortBy']?.split(',').first) {
      'CriticRating' => movie.criticRating,
      'CommunityRating' => movie.communityRating,
      'ProductionYear' => movie.year,
      'Runtime' => movie.runTimeMinutes,
      'OfficialRating' => movie.officialRating,
      _ => movie.title.toLowerCase(),
    };
    final sorted = [...movies]
      ..sort((a, b) {
        final (ka, kb) = (key(a), key(b));
        if (ka == null || kb == null) {
          if (ka == null && kb == null) return tie(a, b);
          // SQLite's order: NULL below every value.
          final nullFirst = ka == null ? -1 : 1;
          return descending ? -nullFirst : nullFirst;
        }
        final cmp = ka.compareTo(kb);
        return cmp != 0 ? (descending ? -cmp : cmp) : tie(a, b);
      });
    final start = int.tryParse(query['StartIndex'] ?? '') ?? 0;
    final limit = int.tryParse(query['Limit'] ?? '') ?? sorted.length;
    final page = sorted.skip(start).take(limit).map((movie) => movie.toJson(serverId)).toList();
    return _json({'Items': page, 'TotalRecordCount': sorted.length, 'StartIndex': start});
  }

  http.Response _list(List<Object?> items) => _json({'Items': items, 'TotalRecordCount': items.length});

  http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
}
