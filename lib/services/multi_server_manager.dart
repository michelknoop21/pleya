import 'dart:async';
import '../media/ids.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../media/media_backend.dart';
import '../media/media_server_client.dart';
import '../services/api_cache.dart';
import 'jellyfin_client.dart';
import 'jellyfin_endpoint_discovery.dart';
import 'local_folder_client.dart';
import 'secure_folder_service.dart';
import 'pleya_share/pleya_share_client.dart';
import 'pleya_share/pleya_share_host_service.dart';
import 'pleya_server_client.dart';
import 'plex_client.dart';
import 'server_matchable_client.dart';
import '../models/plex/plex_config.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_timeouts.dart';
import '../utils/future_extensions.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'plex_auth_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Manages multiple media-server connections simultaneously.
///
/// The internal map and public accessors are typed against the
/// [MediaServerClient] interface so consumers don't depend on the concrete
/// backend. Onboarding helpers branch on backend (Plex `PlexServer`,
/// Jellyfin `JellyfinConnection`) and instantiate the matching client.
class MultiServerManager {
  FutureOr<void> Function(JellyfinConnection connection)? onJellyfinConnectionUpdated;
  FutureOr<void> Function(PleyaShareConnection connection)? onPleyaShareConnectionUpdated;

  /// Persists a Pleya Server connection whose refresh token has rotated.
  ///
  /// Not optional in practice. The protocol retires a refresh token the moment
  /// it is used, so a rotation that is not written back leaves the row holding a
  /// dead token and the next launch spends it on a revocation.
  FutureOr<void> Function(PleyaServerConnection connection)? onPleyaServerConnectionUpdated;

  final Map<String, MediaServerClient> _clients = {};

  final Map<String, PlexServer> _plexServers = {};

  final Map<String, bool> _serverStatus = {};

  /// Servers whose last health probe rejected the auth token (HTTP 401/403).
  /// These rows also have `_serverStatus[serverId] == false` — auth errors are
  /// a *kind* of offline. Surfaces through [authErrorServerIds] so UI can
  /// show a "Sign in again" banner instead of a generic offline state.
  final Set<String> _authErrorServers = {};

  /// Ownership token per server id — the "connection generation".
  ///
  /// Every async task that will write server state back when it finishes (a
  /// health probe, a reconnect race, a share poll) takes the token for its
  /// server *before* it awaits, and drops its result if the token has moved on
  /// by the time it returns. Removing a server releases its token, so a probe
  /// that outlived a deliberate disconnect cannot mark that server online
  /// again, cannot re-raise its auth-error banner, and cannot put a client back
  /// into [_clients]. Re-adding the same id mints a *new* token rather than
  /// reusing the old one, so the stale task loses that race too.
  ///
  /// Identity checks (`_clients[id] != client`) cover the "client was
  /// replaced" case but not "the server is gone" or "the server came back as a
  /// different connection", which is exactly what a manual disconnect looks
  /// like from inside an in-flight probe.
  final Map<String, int> _serverGenerations = {};
  int _nextGeneration = 0;

  /// The current token for [serverId], minting one if this is the first async
  /// task to ask. Call before awaiting; pass the result to [ownsGeneration].
  int generationFor(ServerId serverId) => _serverGenerations[serverId] ??= ++_nextGeneration;

  /// Whether [generation] is still the live token for [serverId]. False once
  /// the server has been removed, and false again if it was re-added since.
  bool ownsGeneration(ServerId serverId, int generation) => _serverGenerations[serverId] == generation;

  /// Drop [serverId]'s token. Every removal path must call this, or an
  /// in-flight task will still believe it owns the server.
  void _releaseGeneration(ServerId serverId) => _serverGenerations.remove(serverId);

  /// Stream controller for server status changes
  final _statusController = StreamController<Map<String, bool>>.broadcast();

  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  /// Per-server connect progress during a bind. Unlike [statusStream] — whose
  /// first emission means "the binder's first connect pass finished" and which
  /// triggers libraries/live-tv work per emission — this fires as each
  /// individual server lands so the startup splash can flip its checkmarks
  /// incrementally without disturbing those contracts.
  final _connectProgressController = StreamController<({String serverId, bool online})>.broadcast();

  Stream<({String serverId, bool online})> get connectProgressStream => _connectProgressController.stream;

  /// Servers whose authentication has failed (token rejected). A re-auth flow
  /// should be offered for these — they will remain "offline" until the user
  /// signs in again. Cleared once a probe succeeds.
  Set<String> get authErrorServerIds => Set.unmodifiable(_authErrorServers);

  /// Connectivity subscription for network monitoring
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Map of serverId to active optimization futures
  final Map<String, Future<void>> _activeOptimizations = {};

  /// Per-server clientIdentifier. Plex servers added via [addPlexAccount]
  /// register their owning account's clientIdentifier here so reconnects +
  /// endpoint optimization use the right identity (each account has its own
  /// device row on plex.tv).
  final Map<String, String> _clientIdByServer = {};

  String? _resolveClientIdentifier(ServerId serverId) => _clientIdByServer[serverId];

  /// All Jellyfin clients ever added, keyed by the compound connection id
  /// (`{serverMachineId}/{userId}`). Lets two users on the same Jellyfin
  /// server coexist — adding the second user's client won't tear down the
  /// first user's in-flight operations. [_clients] holds the currently
  /// "active" entry per machineId for everyone-pass-machineId-as-serverId
  /// consumers (cache resolver, visibility filter, MediaItem.serverId).
  final Map<String, JellyfinClient> _jellyfinByCompoundId = {};
  final Map<String, String> _activeJellyfinMachine = {};
  final Map<String, HealthStatus> _jellyfinHealthByCompoundId = {};

  /// Debounce timers for endpoint-exhaustion-triggered reconnection (per server)
  final Map<String, Timer> _reconnectDebounce = {};

  /// Coalescing guard for checkServerHealth — prevents concurrent health checks
  Future<void>? _activeHealthCheck;

  /// Coalescing guard for reconnectOfflineServers — prevents concurrent reconnect sweeps
  Future<void>? _activeReconnect;

  /// Debounce timer for connectivity events — collapses rapid network flapping
  Timer? _connectivityDebounce;

  /// When each server last exhausted every endpoint candidate without a single
  /// one answering.
  ///
  /// Startup asks for the same server from several directions — bind from
  /// cached metadata, then reconcile once the resource fetch lands, then the
  /// health sweep — and each of those used to run the full candidate race. For
  /// a server that is simply down that meant three or four races of ~2.3s each
  /// within seven seconds, all reaching the same conclusion, plus a warning per
  /// candidate per race. Remembering the verdict briefly makes the second and
  /// third caller fail instantly instead.
  final Map<String, DateTime> _unreachableSince = {};

  /// How long that verdict is trusted. Short on purpose: it exists to collapse
  /// one burst of startup callers, not to keep a server marked dead after the
  /// user has plugged the network back in.
  static const _unreachableMemory = Duration(seconds: 30);

  /// Forgets the "nothing answered" verdicts, so the next attempt races for
  /// real. Anything that means "the network may be different now" calls this.
  void _clearUnreachableMemory() => _unreachableSince.clear();

  /// Get all registered server IDs (Plex + Jellyfin).
  ///
  /// Sourced from [_clients] rather than [_plexServers] because
  /// [_plexServers] only holds the Plex-specific [PlexServer] structs
  /// (host/port metadata used for connection-racing). Jellyfin connections
  /// are registered as clients only — falling back to [_plexServers] would
  /// silently exclude them and callers (the active-profile binder, library
  /// refresh gates) would behave as if the manager were empty for
  /// Jellyfin-only profiles.
  List<String> get serverIds => _clients.keys.toList();

  List<String> get onlineServerIds => _serverStatus.entries.where((e) => e.value).map((e) => e.key).toList();

  List<String> get offlineServerIds => _serverStatus.entries.where((e) => !e.value).map((e) => e.key).toList();

  /// Get client for specific server.
  MediaServerClient? getClient(ServerId serverId) => _clients[serverId];

  /// Server ids visible to the active profile; `null` means no restriction.
  /// Owned here rather than on `MultiServerProvider` so non-UI consumers
  /// (the download client resolver) apply the same filter the UI does —
  /// the provider delegates its filter state to this field.
  Set<String>? _visibleServerIds;

  Set<String>? get visibleServerIds => _visibleServerIds;

  void setVisibleServerIds(Set<String>? ids) => _visibleServerIds = ids;

  bool isServerVisible(ServerId serverId) => _visibleServerIds?.contains(serverId) ?? true;

  /// Resolve the client for a queued download: scope-aware (Jellyfin compound
  /// connection ids) and restricted to servers visible to the active profile,
  /// so background downloads never run against another profile's server
  /// during or after a profile switch.
  MediaServerClient? resolveDownloadClient(ServerId serverId, {String? clientScopeId}) {
    if (!isServerVisible(serverId)) return null;
    if (clientScopeId != null && clientScopeId.isNotEmpty) {
      return getJellyfinClientByCompoundId(clientScopeId) ?? getClient(serverId);
    }
    return getClient(serverId);
  }

  /// Get the [PlexClient] for a server, or `null` if the server is Jellyfin
  /// (or not registered). Use for Plex-only flows (Live TV, server prefs,
  /// endpoint optimization) that don't yet have a backend-neutral
  /// equivalent on [MediaServerClient].
  PlexClient? getPlexClient(ServerId serverId) {
    final client = _clients[serverId];
    return client is PlexClient ? client : null;
  }

  void updatePlexLanguage(String languageCode) {
    for (final client in _clients.values) {
      if (client is PlexClient) {
        client.applyLanguageUpdate(languageCode);
      }
    }
  }

  String? get _currentPlexLanguageCode => SettingsService.instanceOrNull?.read(SettingsService.appLocale).languageCode;

  @visibleForTesting
  void debugRegisterJellyfinClientForTesting(JellyfinClient client, {bool online = true}) {
    _wireJellyfinConnectionUpdates(client);
    final compoundId = client.connection.id;
    final machineId = client.connection.serverMachineId;
    _jellyfinByCompoundId[compoundId] = client;
    _jellyfinHealthByCompoundId[compoundId] = online ? HealthStatus.online : HealthStatus.offline;
    _clients[machineId] = client;
    _activeJellyfinMachine[machineId] = compoundId;
    _serverStatus[machineId] = online;
  }

  @visibleForTesting
  void debugRegisterClientForTesting(MediaServerClient client, {bool online = true}) {
    _clients[client.serverId] = client;
    _serverStatus[client.serverId] = online;
  }

  @visibleForTesting
  void debugMarkAuthErrorForTesting(ServerId serverId) {
    _serverStatus[serverId] = false;
    _authErrorServers.add(serverId);
    _statusController.add(Map.from(_serverStatus));
  }

  /// Mark every cached Plex server on [connection] as auth-rejected without
  /// requiring a live client. Startup auth failures happen before a client can
  /// exist, but the UI still needs a server id/name for the re-auth banner.
  void markPlexConnectionAuthError(PlexAccountConnection connection) {
    for (final server in connection.servers) {
      final id = server.clientIdentifier;
      _clientIdByServer[id] = connection.clientIdentifier;
      _plexServers[id] = server;
      _serverStatus[id] = false;
      _authErrorServers.add(id);
    }
    _statusController.add(Map.from(_serverStatus));
  }

  /// Plex-specific server config (name, machineId, connection candidates,
  /// `owned` flag). Returns `null` for Jellyfin server ids — Jellyfin has no
  /// `PlexServer` analogue. For "is this server registered?" use
  /// [getClient] (works for both backends).
  PlexServer? getPlexServer(ServerId serverId) => _plexServers[serverId];

  String serverDisplayName(ServerId serverId) =>
      _clients[serverId]?.serverName ?? _plexServers[serverId]?.name ?? serverId;

  /// Backend-neutral "is this user an owner/admin on [serverId]?" probe used
  /// by UI gates that hide destructive admin entries (delete, edit metadata,
  /// match/unmatch). Returns:
  ///   - Plex: `PlexServer.owned` for the server (the matching profile-level
  ///     `plexAdmin` check stays at the call site so it can fold in
  ///     `ActiveProfileProvider`).
  ///   - Jellyfin: `JellyfinConnection.isAdministrator` captured at sign-in.
  ///   - Unknown server: `false`.
  bool isOwnerOrAdmin(ServerId serverId) {
    final client = _clients[serverId];
    if (client is PlexClient) {
      return _plexServers[serverId]?.owned == true;
    }
    if (client is JellyfinClient) {
      return client.connection.isAdministrator;
    }
    return false;
  }

  /// Get all online clients
  Map<String, MediaServerClient> get onlineClients {
    final result = <String, MediaServerClient>{};
    for (final serverId in onlineServerIds) {
      final client = _clients[serverId];
      if (client != null) {
        result[serverId] = client;
      }
    }
    return result;
  }

  /// Plex servers known to the manager. Jellyfin servers are NOT included
  /// here — they have no `PlexServer` analogue (single-URL connections,
  /// not connection-raced multi-endpoint structs). For an all-backends
  /// view of online servers use [serverIds] or [onlineClients].
  Map<String, PlexServer> get plexServers => Map.unmodifiable(_plexServers);

  /// Check if a server is online
  bool isServerOnline(ServerId serverId) => _serverStatus[serverId] ?? false;

  /// Check whether the active or scoped client for [serverId] is online.
  bool isClientOnline(ServerId serverId, {String? clientScopeId}) {
    if (clientScopeId != null && clientScopeId.isNotEmpty) {
      return _jellyfinHealthByCompoundId[clientScopeId] == HealthStatus.online;
    }
    return isServerOnline(serverId);
  }

  /// Creates and initializes a PlexClient for a given server
  ///
  /// Handles finding working connection, loading cached endpoint,
  /// creating config, and building client with failover support.
  Future<PlexClient> _createClientForServer({required PlexServer server, required String clientIdentifier}) async {
    final serverId = server.clientIdentifier;
    final stopwatch = Stopwatch()..start();

    final lastFailure = _unreachableSince[serverId];
    if (lastFailure != null && DateTime.now().difference(lastFailure) < _unreachableMemory) {
      throw Exception('No working connection found (${server.name} was unreachable moments ago)');
    }

    // Get storage and load cached endpoint for this server
    final storage = await StorageService.getInstance();
    final cachedEndpoint = storage.getServerEndpoint(ServerId(serverId));

    // The connection race already hits `/` on the winning endpoint — capture
    // `transcoderVideo` from that response so PlexClient.create can skip the
    // redundant warm-up probe.
    bool? observedTranscoderVideo;

    // Find best working connection, passing cached endpoint for fast-path
    final streamIterator = StreamIterator(
      server.findBestWorkingConnection(
        preferredUri: cachedEndpoint,
        clientIdentifier: clientIdentifier,
        onTranscoderCapability: (b) => observedTranscoderVideo = b,
      ),
    );

    if (!await streamIterator.moveNext()) {
      _unreachableSince[serverId] = DateTime.now();
      throw Exception('No working connection found');
    }
    _unreachableSince.remove(serverId);

    final workingConnection = streamIterator.current;
    final baseUrl = workingConnection.uri;
    final firstConnectionMs = stopwatch.elapsedMilliseconds;

    // Create PlexClient with failover support
    final prioritizedEndpoints = server.prioritizedEndpointUrls(preferredFirst: baseUrl);
    final config = await PlexConfig.create(
      baseUrl: baseUrl,
      token: server.accessToken,
      clientIdentifier: clientIdentifier,
      languageCode: _currentPlexLanguageCode,
    );

    final client = await PlexClient.create(
      config,
      serverId: ServerId(serverId),
      serverName: server.name,
      prioritizedEndpoints: prioritizedEndpoints,
      onEndpointChanged: (newUrl) async {
        await storage.saveServerEndpoint(ServerId(serverId), newUrl);
        appLogger.i('Updated endpoint for ${server.name} after failover: $newUrl');
      },
      onAllEndpointsExhausted: () => _onServerEndpointsExhausted(ServerId(serverId)),
      seedTranscoderVideoSupport: observedTranscoderVideo,
    );

    // Save the initial endpoint
    await storage.saveServerEndpoint(ServerId(serverId), baseUrl);

    appLogger.i(
      'Connected ${server.name}',
      error: {
        'uri': baseUrl,
        'hadCachedEndpoint': cachedEndpoint != null,
        'firstConnectionMs': firstConnectionMs,
        'totalMs': stopwatch.elapsedMilliseconds,
      },
    );

    // Drain remaining stream values in background to apply better connections
    _drainOptimizationStream(streamIterator, client: client, server: server, storage: storage);

    return client;
  }

  /// Persists a new endpoint, rebuilds the failover list, and switches the client.
  Future<void> _promoteEndpoint({
    required PlexClient client,
    required PlexServer server,
    required StorageService storage,
    required String newUrl,
  }) async {
    await storage.saveServerEndpoint(ServerId(server.clientIdentifier), newUrl);
    final newEndpoints = server.prioritizedEndpointUrls(preferredFirst: newUrl);
    await client.updateEndpointPreferences(newEndpoints, switchToFirst: true);
  }

  /// Continues draining the connection optimization stream in the background,
  /// switching the client to any better endpoint found.
  void _drainOptimizationStream(
    StreamIterator<PlexConnection> streamIterator, {
    required PlexClient client,
    required PlexServer server,
    required StorageService storage,
  }) {
    () async {
      try {
        while (await streamIterator.moveNext()) {
          final connection = streamIterator.current;
          final newUrl = connection.uri;

          if (newUrl == client.config.baseUrl) {
            appLogger.d('Background optimization confirmed current endpoint for ${server.name}');
            continue;
          }

          appLogger.i(
            'Background optimization found better endpoint for ${server.name}',
            error: {'from': client.config.baseUrl, 'to': newUrl, 'type': connection.displayType},
          );

          await _promoteEndpoint(client: client, server: server, storage: storage, newUrl: newUrl);
        }
      } catch (e, stackTrace) {
        appLogger.w('Background connection optimization failed for ${server.name}', error: e, stackTrace: stackTrace);
      } finally {
        await streamIterator.cancel();
      }
    }();
  }

  /// Remove a server connection
  void removeServer(ServerId serverId) {
    final jellyfinCompoundIds = _jellyfinByCompoundId.entries
        .where((entry) => entry.value.connection.serverMachineId == serverId)
        .map((entry) => entry.key)
        .toList();
    if (jellyfinCompoundIds.isNotEmpty) {
      final closed = <JellyfinClient>{};
      _clients.remove(serverId);
      _activeJellyfinMachine.remove(serverId);
      for (final compoundId in jellyfinCompoundIds) {
        final client = _jellyfinByCompoundId.remove(compoundId);
        _jellyfinHealthByCompoundId.remove(compoundId);
        if (client != null && closed.add(client)) {
          _closeClient(client);
        }
      }
    } else {
      final client = _clients.remove(serverId);
      if (client != null) _closeClient(client);
    }
    _plexServers.remove(serverId);
    _serverStatus.remove(serverId);
    _authErrorServers.remove(serverId);
    _releaseGeneration(serverId);
    _statusController.add(Map.from(_serverStatus));
    appLogger.i('Removed server: $serverId');
  }

  void _closeClient(MediaServerClient client) {
    if (client case final GracefullyCloseable graceful) {
      unawaited(graceful.closeGracefully());
    } else {
      client.close();
    }
  }

  Future<void> _closeClientGracefully(
    MediaServerClient client, {
    Duration drainTimeout = const Duration(seconds: 2),
  }) async {
    if (client case final GracefullyCloseable graceful) {
      await graceful.closeGracefully(drainTimeout: drainTimeout);
    } else {
      client.close();
    }
  }

  /// Connect every server attached to a Plex account in parallel. Each
  /// account has its own `clientIdentifier` (registered as a separate
  /// device on plex.tv), and we keep that mapping per-server in
  /// [_clientIdByServer] so subsequent reconnects + endpoint optimization
  /// race connections from the right identity.
  Future<int> addPlexAccount(
    PlexAccountConnection connection, {
    Duration timeout = MediaServerTimeouts.perServerConnect,
    Function(ServerId serverId, bool success)? onServerStatus,
  }) async {
    if (connection.servers.isEmpty) return 0;
    appLogger.i(
      'Connecting Plex account ${connection.accountLabel} '
      '(${connection.servers.length} server${connection.servers.length == 1 ? '' : 's'})',
    );

    int connected = 0;
    final futures = connection.servers.map((server) async {
      final serverId = server.clientIdentifier;
      _clientIdByServer[serverId] = connection.clientIdentifier;
      _plexServers[serverId] = server;
      try {
        final client = await _createClientForServer(
          server: server,
          clientIdentifier: connection.clientIdentifier,
        ).namedTimeout(timeout, operation: 'connect to ${server.name}');
        final oldClient = _clients[serverId];
        if (oldClient != null) _closeClient(oldClient);
        _clients[serverId] = client;
        _serverStatus[serverId] = true;
        onServerStatus?.call(ServerId(serverId), true);
        connected++;
      } catch (e, stackTrace) {
        appLogger.e('Failed to connect ${server.name}', error: e, stackTrace: stackTrace);
        _serverStatus[serverId] = false;
        onServerStatus?.call(ServerId(serverId), false);
      }
    });

    await Future.wait(futures);
    _statusController.add(Map.from(_serverStatus));
    if (connected > 0 && _connectivitySubscription == null) {
      _startNetworkMonitoring();
    }
    return connected;
  }

  /// Apply a freshly-fetched [PlexAccountConnection] to the manager,
  /// rotating per-server access tokens in place when possible.
  ///
  /// Used by [ActiveProfileBinder] on profile switch: after Plex hands us
  /// the new home-user-scoped per-server tokens, we swap the [PlexConfig]
  /// on existing healthy [PlexClient]s instead of tearing them down and
  /// reconnecting. Auth-error clients can also be reused because the failure
  /// was the old token; other offline servers fall through to the standard
  /// [_createClientForServer] path so they get a fresh handshake.
  ///
  /// Returns the [clientIdentifier]s that ended up actually bound (token
  /// reused or freshly connected). Failed servers are excluded so the
  /// caller's visibility filter doesn't surface unreachable servers.
  Future<Set<String>> refreshTokensForProfile(
    PlexAccountConnection connection, {
    Duration timeout = MediaServerTimeouts.perServerConnect,
  }) async {
    if (connection.servers.isEmpty) return const {};
    final bound = <String>{};
    final futures = connection.servers.map((server) async {
      final serverId = server.clientIdentifier;
      _clientIdByServer[serverId] = connection.clientIdentifier;
      _plexServers[serverId] = server;
      final existing = _clients[serverId];
      if (existing is PlexClient && ((_serverStatus[serverId] ?? false) || _authErrorServers.contains(serverId))) {
        // Rotate the X-Plex-Token in-place so the server treats requests
        // as the new user. `applyTokenUpdate` updates both config and
        // _http.defaultHeaders — leaving headers stale would silently
        // keep authenticating as the previous user.
        await existing.applyTokenUpdate(server.accessToken);
        _authErrorServers.remove(serverId);
        _serverStatus[serverId] = true;
        bound.add(serverId);
        _connectProgressController.add((serverId: serverId, online: true));
        return;
      }
      try {
        final client = await _createClientForServer(
          server: server,
          clientIdentifier: connection.clientIdentifier,
        ).namedTimeout(timeout, operation: 'connect to ${server.name}');
        final oldClient = _clients[serverId];
        if (oldClient != null) _closeClient(oldClient);
        _clients[serverId] = client;
        _serverStatus[serverId] = true;
        _authErrorServers.remove(serverId);
        bound.add(serverId);
        _connectProgressController.add((serverId: serverId, online: true));
      } catch (e, stackTrace) {
        appLogger.e('refreshTokensForProfile: failed to connect ${server.name}', error: e, stackTrace: stackTrace);
        _serverStatus[serverId] = false;
        _connectProgressController.add((serverId: serverId, online: false));
      }
    });
    await Future.wait(futures);
    _statusController.add(Map.from(_serverStatus));
    if (bound.isNotEmpty && _connectivitySubscription == null) {
      _startNetworkMonitoring();
    }
    return bound;
  }

  /// Tear down all servers belonging to the given Plex account. Called when
  /// the user removes the account from the Connections screen. Idempotent —
  /// servers already gone are silently skipped.
  void removePlexAccount(PlexAccountConnection connection) {
    for (final server in connection.servers) {
      final id = server.clientIdentifier;
      final client = _clients.remove(id);
      if (client != null) _closeClient(client);
      _plexServers.remove(id);
      _serverStatus.remove(id);
      _authErrorServers.remove(id);
      _clientIdByServer.remove(id);
      _unreachableSince.remove(id);
      _releaseGeneration(ServerId(id));
    }
    _statusController.add(Map.from(_serverStatus));
  }

  /// Add a Jellyfin server backed by an authenticated [JellyfinConnection].
  /// Returns true on success.
  ///
  /// Jellyfin clients use the shared endpoint-racing flow when multiple URLs
  /// are configured, then instantiate the client against the lowest-latency
  /// reachable URL.
  ///
  /// Two users on the same Jellyfin server are tracked separately in
  /// [_jellyfinByCompoundId]; only one is "active" per machineId at a time.
  /// Adding the second user's connection doesn't close the first user's
  /// client (preserves any in-flight operations on the prior profile).
  Future<bool> addJellyfinConnection(JellyfinConnection connection) async {
    try {
      var resolvedConnection = connection;
      if (connection.baseUrls.length > 1) {
        try {
          final endpoint = await JellyfinEndpointDiscovery().raceEndpoints(
            connection.baseUrls,
            preferredUrl: connection.baseUrl,
            expectedMachineId: connection.serverMachineId,
          );
          resolvedConnection = connection.copyWith(
            baseUrl: endpoint.activeBaseUrl,
            baseUrls: endpoint.baseUrls,
            serverName: endpoint.serverInfo.serverName,
          );
        } catch (e, st) {
          appLogger.w('Jellyfin endpoint race failed; using stored active URL', error: e, stackTrace: st);
        }
      }

      final exhaustedMachineId = resolvedConnection.serverMachineId;
      final exhaustedCompoundId = resolvedConnection.id;
      final client = await JellyfinClient.create(
        resolvedConnection,
        onAllEndpointsExhausted: () => _onJellyfinEndpointsExhausted(exhaustedMachineId, exhaustedCompoundId),
      );
      // Admin status can change server-side; re-broadcast and persist so
      // admin-gated UI survives app restarts without requiring re-auth.
      _wireJellyfinConnectionUpdates(client);
      if (resolvedConnection.baseUrl != connection.baseUrl ||
          !listEquals(resolvedConnection.baseUrls, connection.baseUrls)) {
        await onJellyfinConnectionUpdated?.call(resolvedConnection);
      }
      final compoundId = resolvedConnection.id;
      final machineId = resolvedConnection.serverMachineId;

      // Replace any prior client for this exact compound id (re-add of the
      // same user — e.g., token refresh or settings re-add).
      final oldClient = _jellyfinByCompoundId[compoundId];
      if (oldClient != null) _closeClient(oldClient);
      _jellyfinByCompoundId[compoundId] = client;

      // Bind this user as the active client for its machine. A previously
      // active client for a *different* compound id stays alive in
      // [_jellyfinByCompoundId] so a future profile switch can re-bind it.
      _clients[machineId] = client;
      _activeJellyfinMachine[machineId] = compoundId;

      final health = await client.checkHealth();
      final healthy = health == HealthStatus.online;
      _jellyfinHealthByCompoundId[compoundId] = health;
      _applyHealth(ServerId(machineId), health);

      appLogger.i('Added Jellyfin server: ${resolvedConnection.serverName}${healthy ? '' : ' (unhealthy)'}');
      if (_connectivitySubscription == null && healthy) {
        _startNetworkMonitoring();
      }
      return healthy;
    } catch (e, stackTrace) {
      appLogger.e('Failed to add Jellyfin server ${connection.serverName}', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Add a Pleya Server connection as a media source.
  ///
  /// One endpoint, one identity, so this is closer to the Jellyfin path than to
  /// the Plex one: no candidate race, no discovery, and the connection id is
  /// the server id.
  ///
  /// The health probe runs before the client counts as added, so a server that
  /// is up with a dead session lands on [HealthStatus.authError] and gets the
  /// re-auth banner rather than being hidden as offline.
  Future<bool> addPleyaServerConnection(PleyaServerConnection connection) async {
    try {
      final client = PleyaServerClient.create(
        connection,
        onConnectionUpdated: (updated) async {
          final persist = onPleyaServerConnectionUpdated;
          if (persist == null) return;
          try {
            await Future.sync(() => persist(updated));
          } catch (e, st) {
            appLogger.w('Failed to persist Pleya Server connection update', error: e, stackTrace: st);
          }
        },
      );
      final serverId = connection.serverId;
      final oldClient = _clients[serverId];
      if (oldClient != null) _closeClient(oldClient);
      _clients[serverId] = client;

      final health = await client.checkHealth();
      _applyHealth(ServerId(serverId), health);
      final healthy = health == HealthStatus.online;
      appLogger.i('Added Pleya Server: ${connection.serverName}${healthy ? '' : ' ($health)'}');
      if (_connectivitySubscription == null && healthy) {
        _startNetworkMonitoring();
      }
      return healthy;
    } catch (e, stackTrace) {
      appLogger.e('Failed to add Pleya Server ${connection.serverName}', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Tear down a Pleya Server source's runtime client.
  void removePleyaServerSource(PleyaServerConnection connection) {
    final client = _clients.remove(connection.serverId);
    if (client != null) _closeClient(client);
    _serverStatus.remove(connection.serverId);
    // A rejected session is what sends people to "disconnect" in the first
    // place, so this is the common path, not the edge: leave the id in
    // [_authErrorServers] and the re-auth bar keeps standing over a connection
    // that no longer exists. Releasing the generation stops an in-flight probe
    // from putting it back.
    _authErrorServers.remove(connection.serverId);
    _releaseGeneration(ServerId(connection.serverId));
    _statusController.add(Map.from(_serverStatus));
  }

  /// Add a local folder source. Always "online" — no health check needed.
  Future<bool> addLocalSource(LocalFolderConnection connection) async {
    // A hosting session must see new folders immediately, not after the TTL.
    PleyaShareHostService.instance.invalidateScanCache();
    try {
      final cache = ApiCache.forBackend(MediaBackend.plex);
      final client = LocalFolderClient(connection: connection, cache: cache);
      final oldClient = _clients[connection.id];
      if (oldClient != null) _closeClient(oldClient);
      _clients[connection.id] = client;
      _serverStatus[connection.id] = true;
      _statusController.add(Map.from(_serverStatus));
      _connectProgressController.add((serverId: connection.id, online: true));
      appLogger.i('Added local folder source: ${connection.displayName}');
      return true;
    } catch (e, stackTrace) {
      appLogger.e('Failed to add local folder source ${connection.displayName}', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Add a paired Pleya Share host as a media source. Health follows the
  /// host's reachability; the client itself falls back to its persisted
  /// catalog when the host is offline.
  Future<bool> addPleyaShareSource(PleyaShareConnection connection) async {
    try {
      final cache = ApiCache.forBackend(MediaBackend.plex);
      final client = PleyaShareClient(connection: connection, cache: cache);
      client.channel.onConnectionUpdated = (updated) {
        final persist = onPleyaShareConnectionUpdated;
        if (persist == null) return;
        Future.sync(() => persist(updated)).catchError((Object e, StackTrace st) {
          appLogger.w('Failed to persist Pleya Share connection update', error: e, stackTrace: st);
        });
      };
      final oldClient = _clients[connection.id];
      if (oldClient != null) _closeClient(oldClient);
      _clients[connection.id] = client;
      // Optimistically online (the persisted catalog keeps browsing usable);
      // the async ping corrects the badge and starts polling when the host
      // is actually away.
      _serverStatus[connection.id] = true;
      _statusController.add(Map.from(_serverStatus));
      _connectProgressController.add((serverId: connection.id, online: true));
      unawaited(
        client.checkHealth().then((health) {
          if (_clients[connection.id] != client) return;
          _applyHealth(ServerId(connection.id), health);
          _ensureSharePolling();
        }),
      );
      appLogger.i('Added Pleya Share source: ${connection.hostName}');
      return true;
    } catch (e, stackTrace) {
      appLogger.e('Failed to add Pleya Share source ${connection.hostName}', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Tear down a Pleya Share source's runtime client.
  void removePleyaShareSource(PleyaShareConnection connection) {
    final client = _clients.remove(connection.id);
    if (client != null) _closeClient(client);
    _serverStatus.remove(connection.id);
    // A share host that rejected our pairing sits in [_authErrorServers]. It
    // has to come out here too, or unpairing the host leaves the re-auth
    // banner up for a connection the user has just deleted — with the raw id
    // where its name used to be, because the client that carried the name is
    // gone.
    _authErrorServers.remove(connection.id);
    _releaseGeneration(ServerId(connection.id));
    _statusController.add(Map.from(_serverStatus));
    _ensureSharePolling();
  }

  Timer? _sharePollTimer;
  bool _sharePollInProgress = false;

  /// Keep retrying offline Pleya Share hosts while the app is open. The
  /// resume/connectivity health sweeps only fire on those events; this timer
  /// covers "host comes online while the guest sits idle". One /ping (plus
  /// candidate discovery inside ensureConnected) per offline host per tick;
  /// stops itself as soon as every share host is reachable again.
  /// Exponential backoff for the share poll: every tick runs a discovery
  /// round (UDP bind + probes), which costs radio time — no point burning
  /// battery every 45s when the host has been gone for an hour. Resets on
  /// connectivity change / reconnect sweeps so recovery stays instant.
  static Duration nextSharePollDelay(Duration previous) {
    final doubled = previous * 2;
    return doubled > const Duration(minutes: 3) ? const Duration(minutes: 3) : doubled;
  }

  static const sharePollInitialDelay = Duration(seconds: 45);
  Duration _sharePollDelay = sharePollInitialDelay;

  @visibleForTesting
  Duration get debugSharePollDelay => _sharePollDelay;

  @visibleForTesting
  void debugSetSharePollDelayForTesting(Duration delay) => _sharePollDelay = delay;

  /// The last recorded health for one Jellyfin user's client, or `null` when
  /// no row is held for it.
  HealthStatus? getJellyfinHealthForConnection(String compoundId) => _jellyfinHealthByCompoundId[compoundId];

  void resetSharePollBackoff() {
    _sharePollDelay = sharePollInitialDelay;
    if (_sharePollTimer != null) {
      _sharePollTimer?.cancel();
      _sharePollTimer = null;
      _ensureSharePolling();
    }
  }

  void _ensureSharePolling() {
    final offlineShares = _clients.entries
        .where((e) => e.value is PleyaShareClient && !(_serverStatus[e.key] ?? false))
        .toList();
    if (offlineShares.isEmpty) {
      _sharePollTimer?.cancel();
      _sharePollTimer = null;
      _sharePollDelay = sharePollInitialDelay;
      return;
    }
    _sharePollTimer ??= Timer(_sharePollDelay, () async {
      _sharePollTimer = null;
      _sharePollDelay = nextSharePollDelay(_sharePollDelay);
      // Re-entrancy guard: a sweep slower than the tick interval (discovery
      // inside ensureConnected can take seconds per host) must not overlap
      // the next tick's sweep.
      if (_sharePollInProgress) return;
      _sharePollInProgress = true;
      try {
        final entries = _clients.entries
            .where((e) => e.value is PleyaShareClient && !(_serverStatus[e.key] ?? false))
            .toList();
        for (final entry in entries) {
          final generation = generationFor(ServerId(entry.key));
          final health = await entry.value.checkHealth();
          if (_clients[entry.key] != entry.value) continue;
          if (!ownsGeneration(ServerId(entry.key), generation)) continue;
          _applyHealth(ServerId(entry.key), health);
        }
      } finally {
        _sharePollInProgress = false;
      }
      _ensureSharePolling();
    });
  }

  /// All registered local folder clients — the sources Pleya Share hosting
  /// serves to guests.
  List<LocalFolderClient> get localFolderClients => _clients.values.whereType<LocalFolderClient>().toList();

  /// Clients whose items the sync bridge matches against Plex/Jellyfin
  /// (local folders + Pleya Share guests).
  List<ServerMatchableClient> get serverMatchableClients => _clients.values.whereType<ServerMatchableClient>().toList();

  /// Tear down a local folder source's runtime client.
  void removeLocalSource(LocalFolderConnection connection) {
    PleyaShareHostService.instance.invalidateScanCache();
    final client = _clients.remove(connection.id);
    if (client != null) _closeClient(client);
    // Drop the cached security-scope path so a re-added folder with the same
    // id resolves its bookmark fresh instead of reusing a dead scope.
    SecureFolderService.instance.forget(connection.id);
    _serverStatus.remove(connection.id);
    _authErrorServers.remove(connection.id);
    _releaseGeneration(ServerId(connection.id));
    _statusController.add(Map.from(_serverStatus));
    appLogger.i('Removed local folder source: ${connection.displayName}');
  }

  void _wireJellyfinConnectionUpdates(JellyfinClient client) {
    client.onConnectionUpdated = (updated) async {
      if (_jellyfinByCompoundId[updated.id] != client) {
        appLogger.d('Ignoring stale Jellyfin connection update for ${updated.serverName}');
        return;
      }
      final persist = onJellyfinConnectionUpdated;
      if (persist != null) {
        try {
          await Future.sync(() => persist(updated));
        } catch (e, st) {
          appLogger.w('Failed to persist Jellyfin connection update', error: e, stackTrace: st);
        }
      }
      _statusController.add(Map.from(_serverStatus));
    };
  }

  /// Look up a tracked Jellyfin client by its compound id
  /// (`{serverMachineId}/{userId}`). Returns `null` if no Jellyfin
  /// connection with that id has been added. Useful for callers that need
  /// the *specific* user's client, not whichever is currently active for
  /// the machine.
  JellyfinClient? getJellyfinClientByCompoundId(String compoundId) => _jellyfinByCompoundId[compoundId];

  /// Tear down a specific Jellyfin user's client. If it was the active one
  /// for its machine, the machine slot is cleared.
  void removeJellyfinConnection(JellyfinConnection connection) {
    final compoundId = connection.id;
    final machineId = connection.serverMachineId;
    final client = _jellyfinByCompoundId.remove(compoundId);
    _jellyfinHealthByCompoundId.remove(compoundId);
    if (client != null) _closeClient(client);
    if (_activeJellyfinMachine[machineId] == compoundId) {
      _activeJellyfinMachine.remove(machineId);
      _clients.remove(machineId);
      _serverStatus.remove(machineId);
      _authErrorServers.remove(machineId);
      _releaseGeneration(ServerId(machineId));
      _statusController.add(Map.from(_serverStatus));
    }
  }

  /// Update server status (used for health monitoring).
  ///
  /// Clears the auth-error flag — callers that observed an auth failure
  /// should use [_applyHealth] instead.
  void updateServerStatus(ServerId serverId, bool isOnline) {
    final prevOnline = _serverStatus[serverId];
    final hadAuthError = _authErrorServers.remove(serverId);
    if (prevOnline != isOnline || hadAuthError) {
      _serverStatus[serverId] = isOnline;
      _statusController.add(Map.from(_serverStatus));
      appLogger.d('Server $serverId status changed to: $isOnline');
    }
  }

  /// Apply a health-probe outcome to both online state and auth-error
  /// tracking. Used by the manager's own health checks; external callers
  /// without an auth-distinct signal should use [updateServerStatus].
  void _applyHealth(ServerId serverId, HealthStatus status) {
    final isOnline = status == HealthStatus.online;
    final isAuthError = status == HealthStatus.authError;
    final prevOnline = _serverStatus[serverId];
    final hadAuthError = _authErrorServers.contains(serverId);

    _serverStatus[serverId] = isOnline;
    if (isAuthError) {
      _authErrorServers.add(serverId);
    } else {
      _authErrorServers.remove(serverId);
    }

    final changed = prevOnline != isOnline || hadAuthError != isAuthError;
    if (changed) {
      _statusController.add(Map.from(_serverStatus));
      if (isAuthError) {
        appLogger.w('Server $serverId auth rejected — token expired or revoked');
      } else {
        appLogger.d('Server $serverId status changed to: $isOnline');
      }
    }
  }

  /// Test connection health for all servers. The probe is backend-defined:
  /// Plex hits `/identity` (HTTP 200), Jellyfin hits `/Users/Me` (auth-required)
  /// so a server with a revoked token is correctly reported as offline.
  Future<void> checkServerHealth() async {
    // Coalesce concurrent calls — return the in-flight future if one exists
    if (_activeHealthCheck != null) return _activeHealthCheck!;

    _activeHealthCheck = _doCheckServerHealth();
    try {
      await _activeHealthCheck;
    } finally {
      _activeHealthCheck = null;
    }
  }

  Future<void> _doCheckServerHealth() async {
    appLogger.d('Checking health for ${_clients.length} servers');

    final healthChecks = _clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;
      final expectedJellyfinCompoundId = client is JellyfinClient ? client.connection.id : null;
      // Taken before the await: a probe against an unreachable server runs to
      // its timeout, and the user disconnecting that server is exactly what
      // they do while they wait.
      final generation = generationFor(ServerId(serverId));

      final status = await client.checkHealth();
      // Ownership first, and before the per-user health row is written: that
      // row is what `isClientOnline` reads, so writing it for a machine the
      // user disconnected reports a deleted connection as online.
      if (!ownsGeneration(ServerId(serverId), generation)) {
        appLogger.d('Ignoring health result for $serverId — the connection was closed while the probe ran');
        return;
      }
      if (client is JellyfinClient) {
        final compoundId = expectedJellyfinCompoundId ?? client.connection.id;
        _jellyfinHealthByCompoundId[compoundId] = status;
        if (_activeJellyfinMachine[serverId] != compoundId) {
          appLogger.d('Ignoring stale Jellyfin health result for ${client.connection.serverName}');
          return;
        }
      }
      if (_clients[serverId] != client) {
        appLogger.d('Ignoring health result for $serverId — its client was replaced while the probe ran');
        return;
      }
      _applyHealth(ServerId(serverId), status);
      if (status != HealthStatus.online) {
        appLogger.w('Server $serverId health check failed: ${status.name}');
      }
    });

    await Future.wait(healthChecks);
    _ensureSharePolling();
  }

  /// Start monitoring network connectivity for all servers
  void _startNetworkMonitoring() {
    if (_connectivitySubscription != null) {
      appLogger.d('Network monitoring already active');
      return;
    }

    appLogger.i('Starting network monitoring for all servers');
    try {
      final connectivity = Connectivity();
      _connectivitySubscription = connectivity.onConnectivityChanged.listen(
        (results) {
          final status = results.isNotEmpty ? results.first : ConnectivityResult.none;

          if (status == ConnectivityResult.none) {
            appLogger.w('Connectivity lost, pausing optimization until network returns');
            return;
          }

          // Debounce rapid connectivity events (e.g. WiFi flapping) into a single trigger
          _connectivityDebounce?.cancel();
          _connectivityDebounce = Timer(const Duration(seconds: 2), () {
            _connectivityDebounce = null;

            appLogger.d(
              'Connectivity change detected, re-optimizing all servers',
              error: {
                'status': status.name,
                'interfaces': results.map((r) => r.name).toList(),
                'serverCount': _plexServers.length,
              },
            );

            // A different network is exactly the case where a remembered
            // "nothing answered" is worthless: the candidates that timed out
            // on the old one may be the right ones here.
            _clearUnreachableMemory();

            // Re-optimize all servers and re-probe offline ones
            _reoptimizeAllServers(reason: 'connectivity:${status.name}');
            resetSharePollBackoff();
            checkServerHealth();
          });
        },
        onError: (error, stackTrace) {
          appLogger.w('Connectivity listener error', error: error, stackTrace: stackTrace);
        },
      );
    } catch (e) {
      appLogger.w('Connectivity monitoring unavailable', error: e);
    }
  }

  /// Stop monitoring network connectivity
  void _stopNetworkMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityDebounce?.cancel();
    _connectivityDebounce = null;
    appLogger.i('Stopped network monitoring');
  }

  /// Re-optimize all connected servers and attempt reconnection for offline ones
  /// The Plex servers a connectivity-driven sweep should touch: everything
  /// except the ones whose token was rejected. Same reasoning as
  /// [reconnectCandidateServerIds] — a new network does not repair an expired
  /// session, and WiFi flapping would otherwise start a full candidate race
  /// per flap for as long as the session stays expired.
  List<String> reoptimizeCandidateServerIds() =>
      _plexServers.keys.where((id) => !_authErrorServers.contains(id)).toList();

  void _reoptimizeAllServers({required String reason}) {
    for (final serverId in reoptimizeCandidateServerIds()) {
      final server = _plexServers[serverId];
      if (server == null) continue;

      // Skip if optimization/reconnection already running for this server
      if (_activeOptimizations.containsKey(serverId)) {
        appLogger.d('Optimization already running for ${server.name}, skipping', error: {'reason': reason});
        continue;
      }

      if (!isServerOnline(ServerId(serverId))) {
        // Attempt reconnection for offline servers
        _activeOptimizations[serverId] = _reconnectServer(ServerId(serverId), server).whenComplete(() {
          _activeOptimizations.remove(serverId);
        });
      } else {
        // Re-optimize online servers
        _activeOptimizations[serverId] = _reoptimizeServer(serverId: ServerId(serverId), server: server, reason: reason)
            .whenComplete(() {
              _activeOptimizations.remove(serverId);
            });
      }
    }

    // Jellyfin re-probes offline servers here. Online clients keep their current
    // endpoint and can still fail over per request through JellyfinClient.
    for (final entry in _activeJellyfinMachine.entries) {
      final serverId = entry.key;
      if (_activeOptimizations.containsKey(serverId)) continue;
      if (isServerOnline(ServerId(serverId))) continue;

      final client = _jellyfinByCompoundId[entry.value];
      if (client == null) continue;

      _activeOptimizations[serverId] = _reconnectJellyfinServer(serverId, client).whenComplete(() {
        _activeOptimizations.remove(serverId);
      });
    }
  }

  /// Re-optimize connection for a specific server.
  ///
  /// Today this only runs against Plex servers — the connection-racing logic
  /// is built around [PlexServer.findBestWorkingConnection]. Non-Plex
  /// clients short-circuit until a backend-agnostic equivalent lands.
  Future<void> _reoptimizeServer({
    required ServerId serverId,
    required PlexServer server,
    required String reason,
  }) async {
    final storage = await StorageService.getInstance();
    final raw = _clients[serverId];
    final client = raw is PlexClient ? raw : null;
    if (raw != null && client == null) {
      // Non-Plex client registered for this serverId — no Plex-style optimizer to run.
      return;
    }
    final cachedEndpoint = storage.getServerEndpoint(serverId);

    try {
      appLogger.d('Starting connection optimization for ${server.name}', error: {'reason': reason});

      await for (final connection in server.findBestWorkingConnection(
        preferredUri: cachedEndpoint,
        clientIdentifier: _resolveClientIdentifier(serverId),
      )) {
        final newUrl = connection.uri;

        // Check if this is actually a better connection than current
        if (client != null && client.config.baseUrl == newUrl) {
          appLogger.d('Already using optimal endpoint for ${server.name}: $newUrl');
          continue;
        }

        if (client != null) {
          await _promoteEndpoint(client: client, server: server, storage: storage, newUrl: newUrl);
          appLogger.i('Switched ${server.name} to better endpoint: $newUrl', error: {'type': connection.displayType});
        } else {
          await storage.saveServerEndpoint(serverId, newUrl);
          appLogger.i('Updated optimal endpoint for ${server.name}: $newUrl', error: {'type': connection.displayType});
        }
      }
    } catch (e, stackTrace) {
      appLogger.w('Connection optimization failed for ${server.name}', error: e, stackTrace: stackTrace);
    }
  }

  /// Attempt full reconnection for a single offline server
  Future<void> _reconnectServer(ServerId serverId, PlexServer server) async {
    final clientId = _resolveClientIdentifier(serverId);
    if (clientId == null) {
      appLogger.w('Cannot reconnect ${server.name}: no client identifier cached');
      return;
    }

    final generation = generationFor(serverId);
    try {
      appLogger.d('Attempting reconnection for ${server.name}');
      final client = await _createClientForServer(server: server, clientIdentifier: clientId);

      // The candidate race can take the full 15s budget. If the user
      // disconnected this server in the meantime, the connection it belongs to
      // no longer exists: close what we just built instead of putting a live
      // client back under a server the user removed.
      if (!ownsGeneration(serverId, generation)) {
        appLogger.d('Discarding reconnect for ${server.name} — the connection was closed while it ran');
        _closeClient(client);
        return;
      }

      final oldClient = _clients[serverId];
      if (oldClient != null) _closeClient(oldClient);
      _clients[serverId] = client;
      updateServerStatus(serverId, true);
      appLogger.i('Successfully reconnected to ${server.name}');
    } catch (e) {
      appLogger.d('Reconnection failed for ${server.name}: $e');
      // Leave status as offline — will retry on next trigger
    }
  }

  /// Attempt reconnection for a single offline Jellyfin server.
  ///
  /// Jellyfin has a single fixed base URL — there's no connection-racing to
  /// run, just a health round-trip. The existing [JellyfinClient] is reused
  /// (the access token persists in [JellyfinConnection]); on success we flip
  /// the machine slot back to online so MediaServer-aware UI un-greys the
  /// entry.
  Future<void> _reconnectJellyfinServer(String machineId, JellyfinClient client) async {
    final expectedCompoundId = client.connection.id;
    final generation = generationFor(ServerId(machineId));
    try {
      appLogger.d('Attempting reconnection for Jellyfin server ${client.connection.serverName}');
      final status = await client.checkHealth();
      if (!ownsGeneration(ServerId(machineId), generation)) {
        appLogger.d('Ignoring Jellyfin reconnection result for $machineId — the connection was closed while it ran');
        return;
      }
      _jellyfinHealthByCompoundId[expectedCompoundId] = status;
      if (_activeJellyfinMachine[machineId] != expectedCompoundId) {
        appLogger.d('Ignoring stale Jellyfin reconnection result for ${client.connection.serverName}');
        return;
      }
      _applyHealth(ServerId(machineId), status);
      if (status == HealthStatus.online) {
        appLogger.i('Successfully reconnected to ${client.connection.serverName}');
      } else {
        appLogger.d('Reconnection probe for ${client.connection.serverName} returned ${status.name}');
      }
    } catch (e) {
      appLogger.d('Reconnection failed for ${client.connection.serverName}: $e');
      // Leave status as offline — will retry on next trigger
    }
  }

  /// Attempt reconnection for all offline servers.
  ///
  /// When [forceRediscovery] is true, the cached endpoint is cleared before
  /// reconnecting so the fast-path is skipped and a full candidate race runs.
  /// Used by the manual reconnect button when the cached URL may be stale
  /// (e.g. after a network change while the app was backgrounded).
  Future<void> reconnectOfflineServers({bool forceRediscovery = false}) async {
    resetSharePollBackoff();
    // Asking to reconnect is asking to try again for real — the same reason
    // AudioOutputCoordinator.onModeChanged clears its remembered failure.
    _clearUnreachableMemory();
    // Coalesce concurrent calls — but a force call must not silently degrade
    // to a running non-force sweep (the user pressed "reconnect" exactly
    // because cached endpoints are stale). Wait it out, then run force.
    if (_activeReconnect != null) {
      if (!forceRediscovery) return _activeReconnect!;
      await _activeReconnect;
    }

    _activeReconnect = _doReconnectOfflineServers(forceRediscovery: forceRediscovery);
    try {
      await _activeReconnect;
    } finally {
      _activeReconnect = null;
    }
  }

  /// The offline servers an automatic sweep should actually retry.
  ///
  /// A rejected token is not a transport problem, and racing every endpoint
  /// candidate against it again cannot repair it — it only produces a fresh
  /// round of failures on every resume, connectivity flap and health sweep,
  /// for as long as the session stays expired. Those servers wait for the
  /// re-auth banner instead.
  ///
  /// An explicit "reconnect" from the user ([forceRediscovery]) still includes
  /// them: they may have repaired the session elsewhere — a Plex Home switch,
  /// a token refresh — and asking again is exactly what they asked for.
  List<String> reconnectCandidateServerIds({required bool forceRediscovery}) =>
      forceRediscovery ? offlineServerIds : offlineServerIds.where((id) => !_authErrorServers.contains(id)).toList();

  Future<void> _doReconnectOfflineServers({required bool forceRediscovery}) async {
    final offline = reconnectCandidateServerIds(forceRediscovery: forceRediscovery);
    if (offline.isEmpty) return;

    appLogger.d('Attempting reconnection for ${offline.length} offline servers');
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(message: 'Reconnecting ${offline.length} offline server(s)', category: 'servers'),
      ),
    );

    if (forceRediscovery) {
      final storage = await StorageService.getInstance();
      await Future.wait(offline.map((id) => storage.clearServerEndpoint(ServerId(id))));
    }

    final futures = offline.map((serverId) {
      // Skip if already running
      if (_activeOptimizations.containsKey(serverId)) return Future<void>.value();

      final server = _plexServers[serverId];
      if (server != null) {
        final future = _reconnectServer(ServerId(serverId), server)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                appLogger.d('Reconnection timed out for $serverId');
              },
            )
            .whenComplete(() => _activeOptimizations.remove(serverId));

        _activeOptimizations[serverId] = future;
        return future;
      }

      // Jellyfin offline path — no `_plexServers` entry, but the active
      // [JellyfinClient] is keyed by machineId in `_clients` and tracked in
      // `_activeJellyfinMachine`. Run the same auth probe used at add time.
      final activeCompoundId = _activeJellyfinMachine[serverId];
      final jellyfinClient = activeCompoundId != null ? _jellyfinByCompoundId[activeCompoundId] : null;
      if (jellyfinClient != null) {
        final future = _reconnectJellyfinServer(serverId, jellyfinClient)
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                appLogger.d('Jellyfin reconnection timed out for $serverId');
              },
            )
            .whenComplete(() => _activeOptimizations.remove(serverId));

        _activeOptimizations[serverId] = future;
        return future;
      }

      return Future<void>.value();
    });

    await Future.wait(futures);
  }

  /// Called when all failover endpoints are exhausted for a server.
  /// Debounced per-server to prevent cascading reconnections from parallel failures.
  void _onServerEndpointsExhausted(ServerId serverId) {
    // Cancel any existing debounce timer for this server
    _reconnectDebounce[serverId]?.cancel();

    _reconnectDebounce[serverId] = Timer(const Duration(seconds: 5), () {
      _reconnectDebounce.remove(serverId);

      final plexServer = _plexServers[serverId];
      final jellyfinCompoundId = _activeJellyfinMachine[serverId];
      final jellyfinClient = jellyfinCompoundId != null ? _jellyfinByCompoundId[jellyfinCompoundId] : null;
      if (plexServer == null && jellyfinClient == null) return;

      appLogger.i('All endpoints exhausted for $serverId, triggering reconnection');
      updateServerStatus(serverId, false);

      // Guard with _activeOptimizations to prevent duplicate reconnections
      if (_activeOptimizations.containsKey(serverId)) return;

      final reconnect = plexServer != null
          ? _reconnectServer(serverId, plexServer)
          : _reconnectJellyfinServer(serverId, jellyfinClient!);
      _activeOptimizations[serverId] = reconnect.whenComplete(() {
        _activeOptimizations.remove(serverId);
      });
    });
  }

  /// Jellyfin clients outlive their active binding (a previous profile's
  /// client stays in [_jellyfinByCompoundId]); only the currently bound
  /// client's exhaustion may flip the machine's status.
  void _onJellyfinEndpointsExhausted(String machineId, String compoundId) {
    if (_activeJellyfinMachine[machineId] != compoundId) {
      appLogger.d('Ignoring endpoint exhaustion from inactive Jellyfin client', error: compoundId);
      return;
    }
    _onServerEndpointsExhausted(ServerId(machineId));
  }

  /// Disconnect all servers
  void disconnectAll() {
    appLogger.i('Disconnecting all servers');
    final clients = _detachAllClients();
    for (final client in clients) {
      _closeClient(client);
    }
  }

  Future<void> disconnectAllGracefully({Duration drainTimeout = const Duration(seconds: 5)}) async {
    appLogger.i('Gracefully disconnecting all servers');
    final clients = _detachAllClients();
    await Future.wait(
      clients.map((client) => _closeClientGracefully(client, drainTimeout: drainTimeout)),
      eagerError: false,
    );
  }

  Set<MediaServerClient> _detachAllClients() {
    _stopNetworkMonitoring();
    for (final timer in _reconnectDebounce.values) {
      timer.cancel();
    }
    _reconnectDebounce.clear();
    _activeHealthCheck = null;
    _activeReconnect = null;
    final clients = <MediaServerClient>{..._clients.values, ..._jellyfinByCompoundId.values};
    _clients.clear();
    _jellyfinByCompoundId.clear();
    _activeJellyfinMachine.clear();
    _jellyfinHealthByCompoundId.clear();
    _plexServers.clear();
    _serverStatus.clear();
    _authErrorServers.clear();
    _serverGenerations.clear();
    _clientIdByServer.clear();
    _activeOptimizations.clear();
    _sharePollTimer?.cancel();
    _sharePollTimer = null;
    // Not just the timer: a delay that had backed off to three minutes would
    // be inherited by the next session, so a share host that is away after a
    // profile switch takes minutes to be noticed instead of 45 seconds.
    _sharePollDelay = sharePollInitialDelay;
    if (!_statusController.isClosed) {
      _statusController.add({});
    }
    return clients;
  }

  /// Dispose resources
  void dispose() {
    _sharePollTimer?.cancel();
    _sharePollTimer = null;
    disconnectAll();
    if (!_statusController.isClosed) {
      _statusController.close();
    }
    if (!_connectProgressController.isClosed) {
      _connectProgressController.close();
    }
  }
}
