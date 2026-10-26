import '../../automation/pleya_verify.dart';
import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_server_client.dart';
import '../../media/watchlist_scope.dart';
import '../../media/watchlist_source.dart';
import '../../utils/app_logger.dart';
import '../jellyfin_client.dart';
import '../plex_watchlist_client.dart';
import '../pleya_server_client.dart';
import 'jellyfin_favorites_source.dart';
import 'plex_account_watchlist_source.dart';
import 'verify_watchlist_source.dart';

/// Builds the watchlist sources for one profile.
///
/// Sources are not a fixed set. A profile has at most one Plex account
/// watchlist, plus one Jellyfin favorites list per connected Jellyfin server,
/// so the composition follows the connections and has to be rebuilt whenever
/// the active profile changes.
///
/// The Plex source comes first on purpose. Its list arrives newest-first and
/// the repository keeps first-seen order, so putting it in front is what makes
/// "recently added" mean anything at all.
class WatchlistSourceFactory {
  WatchlistSourceFactory({
    required this.profileId,
    required this.resolvePlexAuth,
    required this.clientIdentifier,
    required this.clientsById,
    this.plexClientBuilder,
    this.verifyWatchlist = kPleyaVerify,
  });

  final String profileId;
  final PlexAccountAuthResolver resolvePlexAuth;

  /// Per-device identifier, the same one `PlexAuthService` uses, so plex.tv
  /// does not register a new device for every watchlist call.
  final String clientIdentifier;

  /// Every media client of the active profile, keyed by server id.
  final Map<String, MediaServerClient> Function() clientsById;

  /// Overridable for tests, which must not open a real socket to plex.tv.
  final PlexWatchlistClient Function()? plexClientBuilder;

  /// Whether a Pleya Server may contribute the Pleya Verify fixture's
  /// kijklijst ([VerifyWatchlistSource]). Only a `PLEYA_VERIFY` build sets it;
  /// a test passes it to cover both sides of the gate.
  final bool verifyWatchlist;

  PlexWatchlistClient? _plexClient;

  /// The sources this profile can actually use right now.
  ///
  /// No Plex source is a normal outcome rather than an error: a Jellyfin-only
  /// setup has none, and neither does a Home profile whose binder has not
  /// finished, because until then only the account owner's token exists and
  /// using it would put one user in front of another's list.
  Future<List<WatchlistSource>> build() async {
    final sources = <WatchlistSource>[];

    final plexScope = await PlexAccountWatchlistSource.resolveScope(resolveAuth: resolvePlexAuth, profileId: profileId);
    if (plexScope != null) {
      _plexClient ??= plexClientBuilder?.call() ?? PlexWatchlistClient(clientIdentifier: clientIdentifier);
      sources.add(PlexAccountWatchlistSource(client: _plexClient!, resolveAuth: resolvePlexAuth, scope: plexScope));
    }

    for (final entry in clientsById().entries) {
      final client = entry.value;
      if (client is! JellyfinClient || !client.capabilities.serverFavorites) continue;

      final connection = client.connection;
      if (connection.serverMachineId.isEmpty || connection.userId.isEmpty) {
        // Without both halves the scope cannot separate two profiles on the
        // same server, which is exactly the mix-up the scope exists to stop.
        appLogger.d('Skipping Jellyfin favorites for ${entry.key}: incomplete server or user identity');
        continue;
      }

      sources.add(
        JellyfinFavoritesSource(
          client: client,
          serverId: ServerId(entry.key),
          scope: WatchlistScopeId(
            profileId: profileId,
            backend: MediaBackend.jellyfin,
            accountId: connection.serverMachineId,
            userId: connection.userId,
          ),
        ),
      );
    }

    if (verifyWatchlist) sources.addAll(await _verifySources());

    return sources;
  }

  /// One [VerifyWatchlistSource] per Pleya Server that serves a non-empty
  /// fixture kijklijst. An empty list adds nothing, so a scenario without
  /// `watchlist.studio.v1` sees the same "no kijklijst" state as production.
  Future<List<WatchlistSource>> _verifySources() async {
    final sources = <WatchlistSource>[];
    for (final MapEntry(key: serverId, value: client) in clientsById().entries) {
      if (client is! PleyaServerClient) continue;
      if ((await client.fetchVerifyWatchlistIds()).isEmpty) continue;
      // The client is looked up again on every call. A profile rebind swaps
      // the client for a new one; the old one refreshing its own session
      // would retire the new one's token on the single-session fixture.
      PleyaServerClient? current() => switch (clientsById()[serverId]) {
        final PleyaServerClient c => c,
        _ => null,
      };
      final connection = client.connection;
      sources.add(
        VerifyWatchlistSource(
          scope: WatchlistScopeId(
            profileId: profileId,
            backend: MediaBackend.pleyaServer,
            accountId: connection.serverId,
            userId: connection.userName,
          ),
          fetchIds: () async => await current()?.fetchVerifyWatchlistIds() ?? const [],
          fetchItem: (id) async => current()?.fetchItem(id),
        ),
      );
    }
    return sources;
  }

  /// Release the cloud client. The Jellyfin sources borrow clients owned by
  /// the server manager, so those are deliberately left alone.
  void dispose() {
    _plexClient?.dispose();
    _plexClient = null;
  }
}
