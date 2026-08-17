import '../../media/live_tv_support.dart';
import '../../models/livetv_channel.dart';
import '../plex_account_auth.dart';
import '../plex_epg_client.dart';

/// There is no user-scoped Plex identity to act as right now.
///
/// Not the same as "the list is empty". The caller has to keep those apart,
/// because writing an empty list back is exactly how a favorites list gets
/// erased.
class PlexFavoritesUnavailable implements Exception {
  const PlexFavoritesUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'PlexFavoritesUnavailable: $reason';
}

/// Owns the Plex cloud favorites for one profile.
///
/// Same division of labour as `PlexAccountWatchlistSource`: [PlexEpgClient] is
/// dumb and will use whatever token it is handed, and this layer decides
/// whether a token may be used at all. Without user-scoped auth there is no
/// store, and Live TV favorites are then absent rather than broken.
class PlexFavoriteChannelsService {
  PlexFavoriteChannelsService({
    required this.profileId,
    required this.resolveAuth,
    required this.clientIdentifier,
    PlexEpgClient Function(String clientIdentifier)? clientBuilder,
  }) : _clientBuilder = clientBuilder ?? ((id) => PlexEpgClient(clientIdentifier: id));

  final String profileId;
  final PlexAccountAuthResolver resolveAuth;
  final Future<String> Function() clientIdentifier;
  final PlexEpgClient Function(String clientIdentifier) _clientBuilder;

  PlexEpgClient? _client;
  PlexFavoriteChannelsStore? _store;

  /// The store for the user that is active right now, or null when there is no
  /// user-scoped Plex auth. Makes no HTTP call of its own.
  ///
  /// Invariant: while `accountId` and `userId` stay the same this returns the
  /// exact same instance. Without that, the screen's dedupe would only work by
  /// accident through equal store keys, and object identity could later be
  /// trusted where it should not be. With it, key equality and instance
  /// equality give the same answer.
  Future<PlexFavoriteChannelsStore?> resolveStore() async {
    final auth = await resolveAuth();
    if (auth == null || !auth.isUserScoped || auth.profileId != profileId) {
      return null;
    }

    final existing = _store;
    if (existing != null && existing.accountId == auth.accountId && existing.userId == auth.userId) {
      return existing;
    }

    _client ??= _clientBuilder(await clientIdentifier());
    return _store = PlexFavoriteChannelsStore._(
      client: _client!,
      resolveAuth: resolveAuth,
      profileId: profileId,
      accountId: auth.accountId,
      userId: auth.userId,
    );
  }

  void dispose() {
    _client?.dispose();
    _client = null;
    _store = null;
  }
}

/// The Plex cloud favorites of one account plus Home user.
///
/// A store never quietly changes its own identity. Token rotation and identity
/// rotation are different events: a new token for the same user is fine and the
/// operation goes through, but a different user means this store is finished
/// and the caller has to ask the service for a new one. Sliding along would
/// mean writing one family member's list under another's name.
class PlexFavoriteChannelsStore implements LiveTvFavoritesStore {
  PlexFavoriteChannelsStore._({
    required this.client,
    required this.resolveAuth,
    required this.profileId,
    required this.accountId,
    required this.userId,
  });

  final PlexEpgClient client;
  final PlexAccountAuthResolver resolveAuth;
  final String profileId;
  final String accountId;
  final String userId;

  /// Every component is percent-encoded before being joined, so a value that
  /// happens to contain the separator cannot shift the boundary: `a` plus `b:c`
  /// and `a:b` plus `c` must never produce the same key. Same reasoning, and
  /// the same shape, as `WatchlistScopeId.storageKey`.
  @override
  String get favoriteStoreKey => 'plex-account:${Uri.encodeComponent(accountId)}:${Uri.encodeComponent(userId)}';

  /// One write replaces the whole account list; Plex has no per-entry endpoint.
  @override
  FavoriteChannelPersistenceMode get favoritePersistenceMode => FavoriteChannelPersistenceMode.sharedFullList;

  @override
  Future<List<FavoriteChannel>> fetchFavoriteChannels() async {
    return client.fetchFavoriteChannels(token: await _scopedToken());
  }

  @override
  Future<void> setFavoriteChannels(List<FavoriteChannel> channels) async {
    return client.setFavoriteChannels(token: await _scopedToken(), channels: channels);
  }

  /// Resolve auth again, for every single operation, and refuse anything that
  /// is not this store's own user.
  ///
  /// No token is kept, not in a field and not in a closure. The owner fallback
  /// is refused outright: using it would show one Home user another's
  /// favorites, which is the failure this whole boundary exists to prevent.
  Future<String> _scopedToken() async {
    final auth = await resolveAuth();
    if (auth == null) {
      throw const PlexFavoritesUnavailable('no Plex account is connected for this profile');
    }
    if (!auth.isUserScoped) {
      throw const PlexFavoritesUnavailable(
        'the Home user binding has not completed, so only the account owner token is available',
      );
    }
    if (auth.profileId != profileId || auth.accountId != accountId || auth.userId != userId) {
      throw const PlexFavoritesUnavailable('the active Plex identity no longer matches this store');
    }
    return auth.token;
  }
}
