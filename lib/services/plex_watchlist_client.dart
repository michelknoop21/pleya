import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../media/media_item.dart';
import '../utils/external_ids.dart';
import 'plex_cloud_http_client.dart';
import 'plex_mappers.dart';

/// Which slice of the watchlist to ask for. The value is a **path segment**,
/// not a `filter=` query parameter: a `filter=available` on `/all` is silently
/// ignored and returns the full list.
///
/// [available] is deliberately absent. Measured against the live API it means
/// "watchable on a streaming service Plex knows about" (Netflix, Rakuten and
/// friends), which has nothing to do with the servers the user owns. Offering
/// it here would invite exactly the mix-up the availability resolver exists to
/// avoid. See `test/fixtures/watchlist/README.md`.
enum PlexWatchlistFilter {
  all,
  released;

  String get pathSegment => name;
}

/// One title as `discover.provider.plex.tv` describes it.
///
/// [item] carries no `serverId`, because a discover title lives in Plex's
/// catalogue and not on any server. Its image paths are already absolute
/// public CDN URLs, so nothing here needs a token to render.
class PlexWatchlistItem {
  final MediaItem item;
  final ExternalIds externalIds;

  const PlexWatchlistItem({required this.item, required this.externalIds});

  String? get guid => item.guid;

  /// Absolute poster URL, or null when the catalogue entry has no artwork.
  String? get posterUrl => item.thumbPath;
}

/// Thin HTTP layer over the Plex cloud watchlist.
///
/// Two things keep this out of [PlexClient]. The watchlist belongs to a
/// plex.tv account plus a Home user, not to a server; and the token it needs is
/// the account token, while `PlexClient` puts the **server** token in
/// `defaultHeaders`, which `MediaServerHttpClient` merges into every request
/// including absolute-URL ones. That property is not this client's own doing:
/// it lives in [PlexCloudHttpClient], which every plex.tv caller shares.
///
/// The client stays deliberately dumb. It does not decide which token it may
/// use; `PlexAccountWatchlistSource` resolves scoped auth per operation and
/// hands over a bare token, so no caller can accidentally reach the list of
/// the account owner while a Home user is active.
class PlexWatchlistClient {
  static const String discoverBase = 'https://discover.provider.plex.tv';
  static const String metadataBase = 'https://metadata.provider.plex.tv';

  /// Page size for the paginating [fetch]. Plex returns the whole list when no
  /// size is given, but that is not a documented promise and a 300-title list
  /// that silently stops at some server-side cap looks exactly like a working
  /// feature.
  static const int pageSize = 100;

  /// Hard stop on the pagination loop, so a server that keeps reporting a
  /// total it never delivers cannot spin forever.
  static const int _maxPages = 100;

  final PlexCloudHttpClient _cloud;

  PlexWatchlistClient._(this._cloud);

  factory PlexWatchlistClient({required String clientIdentifier, String product = 'Pleya'}) {
    return PlexWatchlistClient._(PlexCloudHttpClient(clientIdentifier: clientIdentifier, product: product));
  }

  @visibleForTesting
  factory PlexWatchlistClient.forTesting({
    required http.Client httpClient,
    String clientIdentifier = 'test-client',
    String product = 'Pleya',
  }) {
    return PlexWatchlistClient._(
      PlexCloudHttpClient(clientIdentifier: clientIdentifier, product: product, httpClient: httpClient),
    );
  }

  void dispose() => _cloud.dispose();

  /// The complete allowed header set for every call this client makes.
  ///
  /// No extra headers are declared, so this is exactly the four the transport
  /// boundary sends by default: what `PlexAuthService` already uses. Anything
  /// beyond that would leak device or server detail to plex.tv that the
  /// watchlist does not need, and a test pins this set exactly.
  Map<String, String> headersForToken(String token) => _cloud.headersForToken(token);

  /// Every title on the watchlist, across all pages.
  ///
  /// The list arrives newest-first: the order without an explicit `sort` is
  /// byte-for-byte the same as `sort=watchlistedAt:desc`. That order is the
  /// only "when was this added" signal the list endpoint gives, because the
  /// items themselves carry no `watchlistedAt` and neither `includeUserState`
  /// nor `includeFields` adds one. Per-title timestamps cost one
  /// [fetchWatchlistedAt] call each.
  Future<List<PlexWatchlistItem>> fetch({
    required String token,
    PlexWatchlistFilter filter = PlexWatchlistFilter.all,
    PlexWatchlistType? type,
    String? sort,
  }) async {
    final items = <PlexWatchlistItem>[];

    var start = 0;
    for (var page = 0; page < _maxPages; page++) {
      final response = await _cloud.get(
        '$discoverBase/library/sections/watchlist/${filter.pathSegment}',
        token: token,
        queryParameters: {
          'includeCollections': '1',
          'includeExternalMedia': '1',
          if (type != null) 'type': '${type.plexTypeId}',
          'sort': ?sort,
          'X-Plex-Container-Start': '$start',
          'X-Plex-Container-Size': '$pageSize',
        },
      );

      final container = _mediaContainer(response.data);
      if (container == null) break;

      final metadata = container['Metadata'];
      if (metadata is List) {
        for (final entry in metadata) {
          if (entry is Map<String, dynamic>) items.add(_mapItem(entry));
        }
      }

      final size = _asInt(container['size']) ?? 0;
      final totalSize = _asInt(container['totalSize']) ?? items.length;
      start += size;
      // `size == 0` with more promised would loop forever; treat it as the end.
      if (size == 0 || start >= totalSize) break;
    }

    return items;
  }

  /// Add [ratingKey] to the watchlist.
  ///
  /// [ratingKey] is the discover rating key, the tail of a `plex://movie/...`
  /// guid, not a server rating key. Adding a title that is already on the list
  /// answers 200 as well, so a caller does not have to unwind an optimistic
  /// update for a duplicate.
  Future<void> add({required String token, required String ratingKey}) {
    return _action('addToWatchlist', token: token, ratingKey: ratingKey);
  }

  /// Remove [ratingKey] from the watchlist. Removing a title that is not on
  /// the list answers 200 too.
  Future<void> remove({required String token, required String ratingKey}) {
    return _action('removeFromWatchlist', token: token, ratingKey: ratingKey);
  }

  /// When [ratingKey] was put on the watchlist, in seconds since epoch, or
  /// null when it is not on the list.
  ///
  /// The answer is a single `UserState` object under `MediaContainer`, not an
  /// array, and the `watchlistedAt` key is simply absent once a title has been
  /// removed. The call still answers 200 in that case.
  Future<int?> fetchWatchlistedAt({required String token, required String ratingKey}) async {
    final response = await _cloud.get('$metadataBase/library/metadata/$ratingKey/userState', token: token);

    final userState = _mediaContainer(response.data)?['UserState'];
    return userState is Map ? _asInt(userState['watchlistedAt']) : null;
  }

  Future<void> _action(String action, {required String token, required String ratingKey}) async {
    await _cloud.put('$discoverBase/actions/$action', token: token, queryParameters: {'ratingKey': ratingKey});
  }

  static PlexWatchlistItem _mapItem(Map<String, dynamic> json) {
    final dto = PlexMetadataDto.fromJsonWithImages(json);
    final guids = json['Guid'];
    return PlexWatchlistItem(
      item: PlexMappers.mediaItem(dto),
      externalIds: guids is List ? ExternalIds.fromGuids(guids) : const ExternalIds(),
    );
  }

  static Map<String, dynamic>? _mediaContainer(dynamic data) {
    if (data is! Map) return null;
    final container = data['MediaContainer'];
    return container is Map<String, dynamic> ? container : null;
  }

  static int? _asInt(Object? value) => switch (value) {
    final int v => v,
    final String v => int.tryParse(v),
    _ => null,
  };
}

/// The `type` values the watchlist endpoint accepts. Plex numbers its metadata
/// types; only movies and shows can be on a watchlist.
enum PlexWatchlistType {
  movie(1),
  show(2);

  const PlexWatchlistType(this.plexTypeId);

  final int plexTypeId;
}
