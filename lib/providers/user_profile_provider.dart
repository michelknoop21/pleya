import 'dart:async';
import '../media/ids.dart';

import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../i18n/strings.g.dart';
import '../media/media_server_user_profile.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_connection.dart';
import '../profiles/profile_connection_registry.dart';
import '../services/jellyfin_client.dart';
import '../services/multi_server_manager.dart';
import '../services/plex_auth_service.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';

/// Holds the *current user's playback preferences* (audio/subtitle language
/// defaults) for the active profile. Plex profiles fetch from
/// `https://clients.plex.tv/api/v2/user`; Jellyfin profiles fetch from
/// `/Users/Me` on the bound Jellyfin server.
///
/// Profile *identity* and *switching* are owned by [ActiveProfileProvider]
/// and [ActiveProfileBinder]. This provider is just the settings cache so
/// the video player can apply the active user's defaults.
///
/// Plex settings are fetched with the *active Home user's token* (minted via
/// `/home/users/{uuid}/switch` and cached in
/// the parent [ProfileConnection.userToken], or stored on the
/// [ProfileConnection] row for local profiles). Falling back to the
/// account-owner's token would silently return the *owner's* settings —
/// wrong defaults for kid profiles, parental restrictions, etc.
class UserProfileProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  UserProfileProvider({this._storageService});

  MediaServerUserProfile? _profileSettings;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  MediaServerUserProfile? get profileSettings => _profileSettings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  PlexAuthService? _authService;
  StorageService? _storageService;
  ConnectionRegistry? _connectionRegistry;
  ProfileConnectionRegistry? _profileConnectionRegistry;
  ActiveProfileProvider? _activeProfile;
  MultiServerManager? _serverManager;
  String? _lastSeenActiveId;
  StreamSubscription<List<ProfileConnection>>? _profileConnectionSubscription;
  String? _watchedProfileConnectionProfileId;
  ProfileConnectionRegistry? _watchedProfileConnectionRegistry;

  /// Wire the dependencies needed to resolve the active user's token / client.
  /// May be called multiple times (proxy provider re-builds) — only the
  /// most recent values are kept; we re-attach the listener on the new
  /// [activeProfile] each time so settings refresh whenever the active
  /// profile changes (or the binder finishes wiring up its token).
  void attach({
    required ConnectionRegistry connections,
    required ActiveProfileProvider activeProfile,
    required ProfileConnectionRegistry profileConnections,
    MultiServerManager? serverManager,
  }) {
    _connectionRegistry = connections;
    final profileConnectionsChanged = !identical(_profileConnectionRegistry, profileConnections);
    _profileConnectionRegistry = profileConnections;
    _serverManager = serverManager;
    if (!identical(_activeProfile, activeProfile)) {
      _activeProfile?.removeListener(_onActiveProfileChanged);
      _activeProfile = activeProfile;
      _lastSeenActiveId = activeProfile.activeId;
      activeProfile.addListener(_onActiveProfileChanged);
    }
    if (profileConnectionsChanged) {
      _profileConnectionSubscription?.cancel();
      _profileConnectionSubscription = null;
      _watchedProfileConnectionProfileId = null;
      _watchedProfileConnectionRegistry = null;
    }
    _watchActiveProfileConnections(activeProfile.active);
  }

  void _onActiveProfileChanged() {
    final ap = _activeProfile;
    if (ap == null) return;
    // Only refresh on actual profile change, not on every binding-state
    // tick — refreshProfileSettings awaits awaitBindingSettle internally
    // so it'll always read the fresh post-bind token.
    final id = ap.activeId;
    if (id == _lastSeenActiveId) return;
    _lastSeenActiveId = id;
    _watchActiveProfileConnections(ap.active);
    if (_isInitialized) unawaited(refreshProfileSettings());
  }

  void _watchActiveProfileConnections(Profile? profile) {
    final registry = _profileConnectionRegistry;
    final profileId = profile?.id;
    if (identical(_watchedProfileConnectionRegistry, registry) && _watchedProfileConnectionProfileId == profileId) {
      return;
    }

    _profileConnectionSubscription?.cancel();
    _profileConnectionSubscription = null;
    _watchedProfileConnectionRegistry = registry;
    _watchedProfileConnectionProfileId = profileId;

    if (registry == null || profileId == null) return;
    _profileConnectionSubscription = registry.watchForProfile(profileId).listen((_) {
      if (_isInitialized) unawaited(refreshProfileSettings());
    });
  }

  Future<void> initialize() async {
    if (_isInitialized && _profileSettings != null) {
      return;
    }
    appLogger.d('UserProfileProvider: initializing');
    try {
      _storageService = await StorageService.getInstance();

      try {
        await refreshProfileSettings();
      } catch (e) {
        appLogger.w('UserProfileProvider: failed to fetch profile settings during initialization', error: e);
      }

      _isInitialized = true;
    } catch (e) {
      appLogger.e('UserProfileProvider: critical initialization failure', error: e);
      _setError(t.profiles.initializeServicesFailed);
      _authService = null;
      _storageService = null;
      _isInitialized = false;
    }
  }

  /// Fetch the user's profile settings from the API. Best-effort: failures
  /// leave [profileSettings] unchanged (cached or null).
  Future<void> refreshProfileSettings() async {
    _storageService ??= await StorageService.getInstance();

    // Wait for the binder to finish wiring up the active profile so we
    // read the freshly-minted user-token rather than racing the cache.
    await _activeProfile?.awaitBindingSettle();

    final settingsConnection = await _resolveActiveSettingsConnection();
    final connection = settingsConnection?.connection;
    if (connection is JellyfinConnection) {
      final jellyfinClient = _resolveJellyfinClient(connection);
      if (jellyfinClient == null) {
        appLogger.d('UserProfileProvider: default Jellyfin client unavailable, skipping settings refresh');
        return;
      }
      final profile = await jellyfinClient.fetchUserProfile();
      if (profile != null) {
        _profileSettings = profile;
        safeNotifyListeners();
      }
      return;
    }

    final userToken = await _resolveActivePlexUserToken(preferred: settingsConnection);
    if (userToken == null || userToken.isEmpty) {
      appLogger.d('UserProfileProvider: no token for active profile, skipping settings refresh');
      return;
    }

    try {
      _authService ??= await PlexAuthService.create();
      final profile = await _authService!.getUserProfile(userToken);
      _profileSettings = profile;
      safeNotifyListeners();
    } catch (e) {
      appLogger.w('UserProfileProvider: failed to fetch user profile settings', error: e);
    }
  }

  JellyfinClient? _resolveJellyfinClient(JellyfinConnection conn) {
    final manager = _serverManager;
    if (manager == null) return null;
    final client = manager.getClient(ServerId(conn.serverMachineId));
    return client is JellyfinClient ? client : null;
  }

  /// Resolve the *active Home user's* plex.tv token, in priority order:
  ///   1. The [ProfileConnection]'s `userToken`. For Plex Home profiles
  ///      this is the parent connection's row (written by
  ///      `_bindPlexHome`); for local profiles bound to a Plex account
  ///      it's the default join row (`listForProfile` orders default
  ///      first).
  ///   2. The parent / first plex account's token as a last resort —
  ///      wrong user identity, but at least keeps the call from
  ///      no-op'ing for fresh installs that haven't completed a bind yet.
  /// Returns `null` only when the device has no Plex account at all
  /// (Jellyfin-only setup) or no profile is active.
  Future<String?> _resolveActivePlexUserToken({
    ({ProfileConnection profileConnection, Connection connection})? preferred,
  }) async {
    return (await _resolvePlexAuth(preferred: preferred))?.token;
  }

  /// [_resolveActivePlexUserToken] with the identity it resolved to, and
  /// whether that identity is the one the caller actually asked for.
  ///
  /// The token alone cannot tell those apart. Both branches below can end at
  /// the account owner's token: once as the correct answer for a local profile
  /// bound to a plain account, and once as a stopgap for a Home profile whose
  /// binder has not run. For settings that difference is cosmetic. For
  /// account-scoped data such as the watchlist it is not, because the fallback
  /// silently shows one family member the list of another. Callers that cannot
  /// live with that check [isUserScoped] and refuse.
  Future<({String token, String profileId, String accountId, String userId, bool isUserScoped})?> _resolvePlexAuth({
    ({ProfileConnection profileConnection, Connection connection})? preferred,
  }) async {
    final connections = _connectionRegistry;
    final activeProfile = _activeProfile;
    if (connections == null || activeProfile == null) return null;

    final profile = activeProfile.active;
    if (profile == null) return null;

    // A Pleya Server profile has no plex.tv identity, and the chain below ends
    // at the account owner's token when it cannot find a better one. On a
    // device with both a Plex account and a Pleya Server sign-in that fallback
    // would answer a question about one identity with the credential of
    // another (architecture 4.1). Refusing here is the whole point of the
    // separate PleyaServerCredentialResolver: there is nothing to fall back to,
    // so nothing is returned.
    if (profile.kind == ProfileKind.pleyaServer) return null;

    final plexAccounts = (await connections.list()).whereType<PlexAccountConnection>().toList();
    if (plexAccounts.isEmpty) return null;

    final pcRegistry = _profileConnectionRegistry;

    if (profile.kind == ProfileKind.plexHome) {
      final parentId = profile.parentConnectionId;
      final uuid = profile.plexHomeUserUuid;
      if (parentId == null || uuid == null) return null;
      final parent = plexAccounts.where((a) => a.id == parentId).firstOrNull;
      if (pcRegistry != null) {
        final pc = await pcRegistry.get(profile.id, parentId);
        final token = pc?.userToken;
        if (pc?.hasToken == true && token != null) {
          return (
            token: token,
            profileId: profile.id,
            accountId: parent?.accountUuid ?? _bareAccountId(parentId),
            userId: uuid,
            isUserScoped: true,
          );
        }
      }
      // Pre-bind fallback: the binder hasn't run yet (or it failed), so
      // there's no user-scoped token. Return the parent account token —
      // it'll fetch the *owner's* settings, but that's still better than
      // no settings at all on first launch.
      if (parent == null) return null;
      return (
        token: parent.accountToken,
        profileId: profile.id,
        accountId: parent.accountUuid,
        userId: uuid,
        isUserScoped: false,
      );
    }

    // Local profile — read the user-token off the default ProfileConnection
    // (listForProfile orders default first). Each connection persists its
    // own minted token, so this is already user-scoped.
    final resolved = preferred ?? await _resolveActiveSettingsConnection();
    final resolvedConnection = resolved?.connection;
    if (resolvedConnection is PlexAccountConnection && resolved!.profileConnection.hasToken) {
      final token = resolved.profileConnection.userToken;
      if (token != null) {
        return (
          token: token,
          profileId: profile.id,
          accountId: resolvedConnection.accountUuid,
          userId: _userIdentityFor(resolvedConnection, resolved.profileConnection),
          isUserScoped: true,
        );
      }
    }
    if (resolvedConnection is PlexAccountConnection) {
      return _ownerAuth(profile.id, resolvedConnection);
    }
    // No bound connection at all. With more than one Plex account on the
    // device, picking the first is a guess about identity, not an answer.
    final auth = _ownerAuth(profile.id, plexAccounts.first);
    if (plexAccounts.length == 1) return auth;
    return (
      token: auth.token,
      profileId: auth.profileId,
      accountId: auth.accountId,
      userId: auth.userId,
      isUserScoped: false,
    );
  }

  /// The account owner acting as themselves. Scoped unless the connection has
  /// switched into a Home user, in which case the owner token would act as
  /// somebody other than the user the app is showing.
  ({String token, String profileId, String accountId, String userId, bool isUserScoped}) _ownerAuth(
    String profileId,
    PlexAccountConnection connection,
  ) {
    final home = connection.activeProfile;
    return (
      token: connection.accountToken,
      profileId: profileId,
      accountId: connection.accountUuid,
      userId: home?.uuid.isNotEmpty == true ? home!.uuid : connection.accountUuid,
      isUserScoped: home == null,
    );
  }

  String _userIdentityFor(PlexAccountConnection connection, ProfileConnection profileConnection) {
    final identifier = profileConnection.userIdentifier;
    if (identifier.isNotEmpty) return identifier;
    final home = connection.activeProfile;
    return home != null && home.uuid.isNotEmpty ? home.uuid : connection.accountUuid;
  }

  static String _bareAccountId(String connectionId) =>
      connectionId.startsWith('plex.') ? connectionId.substring('plex.'.length) : connectionId;

  Future<({ProfileConnection profileConnection, Connection connection})?> _resolveActiveSettingsConnection() async {
    final pcRegistry = _profileConnectionRegistry;
    final activeProfile = _activeProfile;
    final connections = _connectionRegistry;
    if (pcRegistry == null || activeProfile == null || connections == null) return null;

    final profile = activeProfile.active;
    if (profile == null || profile.kind == ProfileKind.plexHome) return null;

    final pcs = await pcRegistry.listForProfile(profile.id);
    if (pcs.isEmpty) return null;

    final connectionsList = await connections.list();
    final byId = {for (final c in connectionsList) c.id: c};
    for (final pc in pcs) {
      final conn = byId[pc.connectionId];
      if (conn != null) return (profileConnection: pc, connection: conn);
    }
    return null;
  }

  @visibleForTesting
  Future<Connection?> debugResolveActiveSettingsConnectionForTesting() async {
    return (await _resolveActiveSettingsConnection())?.connection;
  }

  @visibleForTesting
  Future<String?> debugResolveActivePlexUserTokenForTesting() {
    return _resolveActivePlexUserToken();
  }

  /// The active Home user's Plex token, used by the seerr integration for
  /// one-tap Plex login and silent re-auth. Null on Jellyfin-only setups.
  Future<String?> currentPlexUserToken() => _resolveActivePlexUserToken();

  /// The active profile's plex.tv auth together with the identity it belongs
  /// to. Null on Jellyfin-only setups or when no profile is active.
  ///
  /// Read [isUserScoped] before touching anything account-scoped: `false`
  /// means the resolver fell back to the account owner while a different user
  /// is active, which for the watchlist would mean showing one Home user the
  /// list of another.
  Future<({String token, String profileId, String accountId, String userId, bool isUserScoped})?>
  currentPlexAccountAuth() => _resolvePlexAuth();

  @visibleForTesting
  String? get debugWatchedProfileConnectionProfileId => _watchedProfileConnectionProfileId;

  /// Logout — clear settings and credentials. Called from the discover
  /// screen "sign out" action; the rest of the teardown (clearing
  /// connections, profiles, etc.) happens in the screen's logout flow.
  Future<void> logout() async {
    _isLoading = true;
    safeNotifyListeners();
    try {
      _storageService ??= await StorageService.getInstance();
      await _storageService!.clearUserData();
      _profileSettings = null;
      _authService = null;
      _storageService = null;
      _isInitialized = false;
      _clearError();
      appLogger.i('UserProfileProvider: logged out');
    } catch (e) {
      appLogger.e('UserProfileProvider: logout error', error: e);
    } finally {
      _isLoading = false;
      safeNotifyListeners();
    }
  }

  void _setError(String error) {
    _error = error;
    safeNotifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  @override
  void dispose() {
    _activeProfile?.removeListener(_onActiveProfileChanged);
    _profileConnectionSubscription?.cancel();
    super.dispose();
  }
}
