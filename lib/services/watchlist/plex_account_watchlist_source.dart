import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/watchlist_entry.dart';
import '../../media/watchlist_key.dart';
import '../../media/watchlist_scope.dart';
import '../../media/watchlist_source.dart';
import '../plex_watchlist_client.dart';

/// Resolves the plex.tv auth for the profile that is active right now.
///
/// A function rather than a stored value, because the answer changes when the
/// user switches profile and a source that cached it would keep serving the
/// previous user's list.
typedef PlexAccountAuthResolver =
    Future<({String token, String profileId, String accountId, String userId, bool isUserScoped})?> Function();

/// The Plex account watchlist as a [WatchlistSource].
///
/// This class owns the scope check, and that is its main job. `PlexWatchlistClient`
/// is a dumb HTTP layer that will happily use any token handed to it, and
/// `UserProfileProvider`'s resolver has a documented fallback to the account
/// owner's token when the Home-user binder has not run. Combine those two
/// without a guard and the app quietly shows a child the parent's watchlist,
/// and worse, writes to it.
///
/// So auth is resolved again on **every** operation, refused when it is not
/// user-scoped, and only the bare token is passed on. No caller can reach the
/// client without coming past here.
class PlexAccountWatchlistSource implements WatchlistSource {
  final PlexWatchlistClient client;
  final PlexAccountAuthResolver resolveAuth;

  PlexAccountWatchlistSource({required this.client, required this.resolveAuth, required this.scope});

  @override
  final WatchlistScopeId scope;

  /// Build the scope for the profile that is active right now, or null when
  /// there is no user-scoped Plex auth to build it from.
  static Future<WatchlistScopeId?> resolveScope({
    required PlexAccountAuthResolver resolveAuth,
    required String profileId,
  }) async {
    final auth = await resolveAuth();
    if (auth == null || !auth.isUserScoped) return null;
    return WatchlistScopeId(
      profileId: profileId,
      backend: MediaBackend.plex,
      accountId: auth.accountId,
      userId: auth.userId,
    );
  }

  @override
  bool accepts(MediaItem item) {
    if (item.backend != MediaBackend.plex) return false;
    if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return false;
    // Without a `plex://` guid there is no discover rating key, and the
    // watchlist endpoints take nothing else.
    return discoverRatingKeyFromGuid(item.guid) != null;
  }

  @override
  Future<List<WatchlistEntry>> fetch() async {
    final token = await _scopedToken();
    final items = await client.fetch(token: token);

    final entries = <WatchlistEntry>[];
    for (final item in items) {
      final key = watchlistKeyForItem(item.item, externalIds: item.externalIds);
      final remoteKey = discoverRatingKeyFromGuid(item.guid) ?? item.item.id;
      if (key == null || remoteKey.isEmpty) continue;
      entries.add(
        WatchlistEntry(
          key: key,
          kind: item.item.kind,
          item: item.item,
          guid: item.guid,
          externalIds: item.externalIds,
          posterRef: item.posterUrl,
          // The list arrives newest-first and carries no timestamps, so the
          // index is the recency signal. It stays an index; see
          // [WatchlistMembership.sourcePosition].
          memberships: [WatchlistMembership(scope: scope, remoteKey: remoteKey, sourcePosition: entries.length)],
        ),
      );
    }
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    final ratingKey = discoverRatingKeyFromGuid(item.guid);
    if (ratingKey == null) {
      throw UnsupportedError('A Plex item without a plex:// guid cannot go on the account watchlist');
    }
    final token = await _scopedToken();
    await client.add(token: token, ratingKey: ratingKey);
    return WatchlistMembership(scope: scope, remoteKey: ratingKey);
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {
    final token = await _scopedToken();
    await client.remove(token: token, ratingKey: membership.remoteKey);
  }

  @override
  Future<bool?> contains(MediaItem item) async {
    final ratingKey = discoverRatingKeyFromGuid(item.guid);
    if (ratingKey == null) return false;
    final token = await _scopedToken();
    return await client.fetchWatchlistedAt(token: token, ratingKey: ratingKey) != null;
  }

  /// The account token, but only when it provably belongs to the user this
  /// source was built for.
  Future<String> _scopedToken() async {
    final auth = await resolveAuth();
    if (auth == null) {
      throw const WatchlistScopeUnavailable('no Plex account is connected for this profile');
    }
    if (!auth.isUserScoped) {
      throw const WatchlistScopeUnavailable(
        'the Home user binding has not completed, so only the account owner token is available',
      );
    }
    // The active identity may have moved on since this source was built, for
    // instance when a profile switch raced a refresh. Serving the new user's
    // list under the old scope would file it under the wrong key.
    if (auth.accountId != scope.accountId || auth.userId != scope.userId || auth.profileId != scope.profileId) {
      throw const WatchlistScopeUnavailable('the active Plex identity no longer matches this source');
    }
    return auth.token;
  }
}
