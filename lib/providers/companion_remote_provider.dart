import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../i18n/strings.g.dart';
import '../models/companion_remote/remote_command.dart';
import '../models/companion_remote/remote_session.dart';
import '../models/plex/plex_home.dart';
import '../profiles/active_plex_identity.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_connection_registry.dart';
import '../services/companion_remote/companion_remote_peer_service.dart';
import '../services/companion_remote/lan_discovery_service.dart';
import '../services/companion_remote/playback_handoff.dart';
import '../services/companion_remote/remote_auth_context.dart';
import '../services/companion_remote/remote_auth_service.dart';
import '../utils/app_logger.dart';
import '../utils/error_message_utils.dart';
import '../utils/platform_detector.dart';
import '../mixins/disposable_change_notifier_mixin.dart';

export '../services/companion_remote/lan_discovery_service.dart' show DiscoveredHost;

typedef CommandReceivedCallback = void Function(RemoteCommand command);
typedef PlexHomeResolver = Future<PlexHome?> Function(String connectionId);

class CompanionRemoteProvider with ChangeNotifier, DisposableChangeNotifierMixin {
  RemoteSession? _session;
  CompanionRemotePeerService? _peerService;
  LanDiscoveryService? _discoveryService;
  String _deviceName = t.companionRemote.unknownDevice;
  String _platform = PlatformDetector.isAppleTV() ? 'tvOS' : 'unknown';
  bool _isPlayerActive = false;
  final PlaybackHandoffTracker _handoffs = PlaybackHandoffTracker();

  static const int _maxReconnectAttempts = 5;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;

  // Pleya Fly receive (A-23d): the running host takes only a fly, and the
  // owner wants one whenever this device is not a client somewhere.
  bool _handoffOnly = false;
  bool _handoffHostWanted = false;
  int? _hostPort;

  // Reconnection context (only hostAddresses and hostClientId are connection-specific)
  List<String>? _lastHostAddresses;
  String? _lastHostClientId;
  String? _lastAuthContextId;

  // Crypto context (derived in memory, never persisted)
  List<RemoteAuthContext> _authContexts = const [];
  String? _cryptoProfileId;

  int get reconnectAttempts => _reconnectAttempts;

  StreamSubscription<RemoteCommand>? _commandSubscription;
  StreamSubscription<RemoteDevice>? _deviceConnectedSubscription;
  StreamSubscription<void>? _deviceDisconnectedSubscription;
  StreamSubscription<RemotePeerError>? _errorSubscription;
  StreamSubscription<RemoteSessionStatus>? _statusSubscription;

  CommandReceivedCallback? onCommandReceived;

  /// Host side: the phone gave up on a handoff (see [handoffCancelKey]).
  void Function(String id)? onHandoffCancelled;

  bool get isInSession => _session != null && _session!.status != RemoteSessionStatus.disconnected;
  bool get isHost => _session?.isHost ?? false;
  bool get isRemote => _session?.isRemote ?? false;

  /// Connected in a session the user set up: a remote, or a host with a phone.
  /// A handoff-only host is no such session, so it never shows as connected
  /// (A-23d); [_linkUp] is the wire state the protocol itself needs.
  bool get isConnected => _linkUp && !_handoffOnly;
  bool get _linkUp => _session?.isConnected ?? false;
  RemoteSession? get session => _session;
  RemoteSessionStatus get status => _session?.status ?? RemoteSessionStatus.disconnected;
  RemoteDevice? get connectedDevice => _session?.connectedDevice;
  bool get isPlayerActive => _isPlayerActive;
  String get deviceName => _deviceName;

  /// Host side: the connected phone is the same user as the active profile here.
  bool get peerIsHostUser => _peerService?.clientIsHostUser ?? false;

  /// Host side: who the connected phone says it is, and on which connection it
  /// authenticated; together they name its profile here (A-23b).
  String? get peerUserUuid => _peerService?.clientUserUuid;
  String? get peerConnectionId => _authContextForId(_peerService?.selectedAuthContextId)?.connectionId;
  bool get isHostServerRunning => _peerService?.isServerRunning ?? false;

  /// The running host receives only a Pleya Fly (A-23d); see [startHostServer].
  bool get isHandoffOnlyHost => _handoffOnly && isHostServerRunning;

  @visibleForTesting
  int? get debugHostPort => isHostServerRunning ? _hostPort : null;

  @visibleForTesting
  String? get debugAuthContextId => _primaryAuthContext?.id;

  CompanionRemoteProvider() {
    _initializeDeviceInfo();
  }

  Future<void> _initializeDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final osName = await TvDetectionService.getAndroidDeviceName();
        _deviceName = osName ?? '${androidInfo.brand} ${androidInfo.model}';
        _platform = 'Android';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceName = iosInfo.name;
        _platform = 'iOS';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        _deviceName = macInfo.computerName;
        _platform = 'macOS';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        _deviceName = windowsInfo.computerName;
        _platform = 'Windows';
      } else if (Platform.isLinux) {
        final host = Platform.localHostname.trim();
        _deviceName = (host.isNotEmpty && host != 'localhost') ? host : (await deviceInfo.linuxInfo).name;
        _platform = 'Linux';
      }
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to get device info', error: e);
      _deviceName = t.companionRemote.unknownDevice;
      _platform = Platform.operatingSystem;
    }

    // The iOS runtime also hosts tvOS; the handoff picker lists only Apple TVs.
    if (PlatformDetector.isAppleTV()) _platform = 'tvOS';

    safeNotifyListeners();
  }

  /// Initialize crypto context from Plex home data plus the active profile's
  /// connection. The clientIdentifier is the parent Plex account's
  /// `clientIdentifier` (used as the LAN device id) and the userUUID is the
  /// active home user's uuid (used to scope per-user LAN traffic).
  Future<bool> initializeCrypto({
    required PlexHome? home,
    required PlexAccountConnection? account,
    required Profile? activeProfile,
    String? activeUserUuid,
  }) async {
    if (home == null || home.adminUser == null) {
      appLogger.w('CompanionRemote: Cannot init crypto — no home data');
      return false;
    }
    if (account == null) {
      appLogger.w('CompanionRemote: Cannot init crypto — no Plex account');
      return false;
    }

    try {
      final auth = RemoteAuthService.instance;
      final homeSecret = await auth.deriveHomeSecretFromHome(home);
      final discoveryKey = await auth.deriveDiscoveryKey(homeSecret);
      final userUuid = activeUserUuid ?? activeProfile?.plexHomeUserUuid ?? home.adminUser!.uuid;
      final allowedUserUuids = {
        for (final user in home.users)
          if (user.uuid.isNotEmpty) user.uuid,
        if (userUuid.isNotEmpty) userUuid,
      }.toList();
      _authContexts = [
        RemoteAuthContext(
          id: auth.computeAuthContextId(homeSecret),
          backend: 'plex',
          connectionId: account.id,
          homeSecret: homeSecret,
          discoveryKey: discoveryKey,
          clientIdentifier: account.clientIdentifier.isNotEmpty ? account.clientIdentifier : account.id,
          userUuid: userUuid,
          allowedUserUuids: allowedUserUuids,
        ),
      ];
      _cryptoProfileId = activeProfile?.id;

      appLogger.d('CompanionRemote: Crypto context initialized');
      return true;
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to init crypto', error: e);
      return false;
    }
  }

  Future<bool> initializeJellyfinCrypto({
    required JellyfinConnection connection,
    required Profile? activeProfile,
  }) async {
    if (connection.accessToken.isEmpty || connection.userId.isEmpty || connection.serverMachineId.isEmpty) {
      appLogger.w('CompanionRemote: Cannot init Jellyfin crypto — incomplete connection');
      return false;
    }

    try {
      final auth = RemoteAuthService.instance;
      final homeSecret = await auth.deriveJellyfinSecret(
        serverMachineId: connection.serverMachineId,
        userId: connection.userId,
      );
      final discoveryKey = await auth.deriveDiscoveryKey(homeSecret);
      _authContexts = [
        RemoteAuthContext(
          id: auth.computeAuthContextId(homeSecret),
          backend: 'jellyfin',
          connectionId: connection.id,
          homeSecret: homeSecret,
          discoveryKey: discoveryKey,
          clientIdentifier: connection.deviceId.isNotEmpty ? connection.deviceId : connection.id,
          userUuid: connection.userId,
          allowedUserUuids: [connection.userId],
        ),
      ];
      _cryptoProfileId = activeProfile?.id;

      appLogger.d('CompanionRemote: Jellyfin crypto context initialized');
      return true;
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to init Jellyfin crypto', error: e);
      return false;
    }
  }

  RemoteAuthContext? get _primaryAuthContext => _authContexts.isEmpty ? null : _authContexts.first;

  bool get isCryptoReady => _authContexts.isNotEmpty;

  /// Convenience: ensure crypto is initialized for every remote identity
  /// attached to the active profile.
  /// Returns true if crypto is ready (already initialized or just initialized).
  Future<bool> ensureCryptoReady(
    PlexHome? home, {
    required ConnectionRegistry connections,
    required ActiveProfileProvider activeProfile,
    required ProfileConnectionRegistry profileConnections,
    ActivePlexIdentity? identity,
    PlexAccountConnection? account,
    PlexHomeResolver? plexHomeForConnection,
  }) async {
    await activeProfile.initialize();
    final profile = activeProfile.active;
    if (profile == null) {
      appLogger.w('CompanionRemote: Cannot init crypto — no active profile');
      return false;
    }

    final nextContexts = await _buildAuthContextsForProfile(
      profile: profile,
      connections: connections,
      profileConnections: profileConnections,
      fallbackHome: home,
      identity: identity,
      preferredAccount: account,
      plexHomeForConnection: plexHomeForConnection,
    );

    if (nextContexts.isEmpty) {
      if (isCryptoReady) await _prepareForCryptoRebuild();
      appLogger.w('CompanionRemote: Cannot init crypto — no active profile identities');
      return false;
    }

    if (_cryptoProfileId == profile.id && _sameAuthContexts(_authContexts, nextContexts)) {
      return true;
    }

    // A host that ran keeps running under the new identity: a search that
    // rebuilds the identity must not leave this device unreachable (A-23d).
    final hostToRestore = isHostServerRunning ? (handoffOnly: _handoffOnly) : null;
    await _prepareForCryptoRebuild();
    _authContexts = nextContexts;
    _cryptoProfileId = profile.id;
    appLogger.d('CompanionRemote: Crypto contexts initialized (${nextContexts.length})');
    if (hostToRestore != null) await startHostServer(handoffOnly: hostToRestore.handoffOnly);
    return true;
  }

  Future<List<RemoteAuthContext>> _buildAuthContextsForProfile({
    required Profile profile,
    required ConnectionRegistry connections,
    required ProfileConnectionRegistry profileConnections,
    required PlexHome? fallbackHome,
    required ActivePlexIdentity? identity,
    required PlexAccountConnection? preferredAccount,
    required PlexHomeResolver? plexHomeForConnection,
  }) async {
    final contexts = <RemoteAuthContext>[];
    final seen = <String>{};
    final all = await connections.list();
    final byId = {for (final c in all) c.id: c};

    Future<PlexHome?> resolvePlexHome(PlexAccountConnection account) async {
      if (fallbackHome != null &&
          (identity?.account.id == account.id || preferredAccount?.id == account.id || plexHomeForConnection == null)) {
        return fallbackHome;
      }
      return plexHomeForConnection?.call(account.id);
    }

    void addContext(RemoteAuthContext? context) {
      if (context == null || seen.contains(context.id)) return;
      contexts.add(context);
      seen.add(context.id);
    }

    Future<void> addConnection(Connection connection, {String? userUuid}) async {
      switch (connection) {
        case PlexAccountConnection():
          addContext(
            await _createPlexAuthContext(
              account: connection,
              home: await resolvePlexHome(connection),
              activeProfile: profile,
              userUuid: userUuid,
            ),
          );
        case JellyfinConnection():
          addContext(await _createJellyfinAuthContext(connection: connection));
        case LocalFolderConnection():
        case PleyaShareConnection():
        case PleyaServerConnection():
          // No remote auth context: the companion protocol hands a token to
          // another device, and these three have nothing an off-device
          // client could use. Pleya Server access tokens are short-lived and
          // bound to this device's refresh chain.
          break;
      }
    }

    if (profile.parentConnectionId case final parentId?) {
      final parent = preferredAccount?.id == parentId
          ? preferredAccount
          : (identity?.account.id == parentId ? identity?.account : byId[parentId]);
      if (parent is PlexAccountConnection) {
        await addConnection(parent, userUuid: profile.plexHomeUserUuid);
      }
    }

    final pcs = await profileConnections.listForProfile(profile.id);
    for (final pc in pcs) {
      final connection = byId[pc.connectionId];
      if (connection == null) continue;
      await addConnection(connection, userUuid: pc.userIdentifier.isEmpty ? null : pc.userIdentifier);
    }

    return contexts;
  }

  Future<RemoteAuthContext?> _createPlexAuthContext({
    required PlexAccountConnection account,
    required PlexHome? home,
    required Profile activeProfile,
    required String? userUuid,
  }) async {
    if (home == null || home.adminUser == null) {
      appLogger.w('CompanionRemote: Skipping Plex remote identity — no home data for ${account.id}');
      return null;
    }

    final auth = RemoteAuthService.instance;
    final homeSecret = await auth.deriveHomeSecretFromHome(home);
    final resolvedUserUuid = userUuid != null && userUuid.isNotEmpty
        ? userUuid
        : (activeProfile.plexHomeUserUuid != null && activeProfile.plexHomeUserUuid!.isNotEmpty
              ? activeProfile.plexHomeUserUuid!
              : home.adminUser!.uuid);
    final allowedUserUuids = {
      for (final user in home.users)
        if (user.uuid.isNotEmpty) user.uuid,
      if (resolvedUserUuid.isNotEmpty) resolvedUserUuid,
    }.toList();

    return RemoteAuthContext(
      id: auth.computeAuthContextId(homeSecret),
      backend: 'plex',
      connectionId: account.id,
      homeSecret: homeSecret,
      discoveryKey: await auth.deriveDiscoveryKey(homeSecret),
      clientIdentifier: account.clientIdentifier.isNotEmpty ? account.clientIdentifier : account.id,
      userUuid: resolvedUserUuid,
      allowedUserUuids: allowedUserUuids,
    );
  }

  Future<RemoteAuthContext?> _createJellyfinAuthContext({required JellyfinConnection connection}) async {
    if (connection.accessToken.isEmpty || connection.userId.isEmpty || connection.serverMachineId.isEmpty) {
      appLogger.w('CompanionRemote: Skipping Jellyfin remote identity — incomplete connection ${connection.id}');
      return null;
    }

    final auth = RemoteAuthService.instance;
    final homeSecret = await auth.deriveJellyfinSecret(
      serverMachineId: connection.serverMachineId,
      userId: connection.userId,
    );
    return RemoteAuthContext(
      id: auth.computeAuthContextId(homeSecret),
      backend: 'jellyfin',
      connectionId: connection.id,
      homeSecret: homeSecret,
      discoveryKey: await auth.deriveDiscoveryKey(homeSecret),
      clientIdentifier: connection.deviceId.isNotEmpty ? connection.deviceId : connection.id,
      userUuid: connection.userId,
      allowedUserUuids: [connection.userId],
    );
  }

  bool _sameAuthContexts(List<RemoteAuthContext> a, List<RemoteAuthContext> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.backend != right.backend ||
          left.connectionId != right.connectionId ||
          left.clientIdentifier != right.clientIdentifier ||
          left.userUuid != right.userUuid ||
          !_sameStrings(left.allowedUserUuids, right.allowedUserUuids)) {
        return false;
      }
    }
    return true;
  }

  bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  RemoteAuthContext? _authContextForId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final context in _authContexts) {
      if (context.id == id) return context;
    }
    return null;
  }

  Future<void> _prepareForCryptoRebuild() async {
    if (isInSession || isHostServerRunning) {
      await stopHostServer();
    } else {
      stopDiscovery();
      _cleanupSubscriptions();
    }
    _clearCryptoContext();
  }

  void _clearCryptoContext() {
    _authContexts = const [];
    _cryptoProfileId = null;
  }

  /// Fully tear down network/session state and forget derived crypto material.
  /// Used by logout so an app-level provider surviving route replacement does
  /// not keep broadcasting with the previous Plex Home identity.
  Future<void> resetForLogout() async {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _lastHostAddresses = null;
    _lastHostClientId = null;
    _lastAuthContextId = null;
    _handoffHostWanted = false;
    await stopHostServer();
    stopDiscovery();
    _clearCryptoContext();
    RemoteAuthService.instance.clearCache();
    safeNotifyListeners();
  }

  @visibleForTesting
  String? get debugCryptoConnectionId => _primaryAuthContext?.connectionId;

  @visibleForTesting
  String? get debugCryptoProfileId => _cryptoProfileId;

  @visibleForTesting
  String? get debugCryptoUserUuid => _primaryAuthContext?.userUuid;

  @visibleForTesting
  List<String> get debugCryptoConnectionIds => _authContexts.map((context) => context.connectionId).toList();

  /// Starts hosting. [handoffOnly] marks a host that receives a Pleya Fly and
  /// nothing else (A-23d): the app then drops every other command, and joining
  /// another host as a client stops it for the time of that session.
  Future<void> startHostServer({bool handoffOnly = false}) async {
    // A provider torn down by a profile switch must not bind a server nobody stops.
    if (isDisposed) return;
    if (_peerService?.isServerRunning == true) return;
    if (!isCryptoReady) {
      appLogger.w('CompanionRemote: Cannot start host — crypto not initialized');
      return;
    }

    appLogger.d('CompanionRemote: Starting host server');

    _peerService ??= CompanionRemotePeerService();
    _setupPeerServiceListeners();

    try {
      final contexts = List<RemoteAuthContext>.unmodifiable(_authContexts);
      final result = await _peerService!.createSessionForContexts(_deviceName, _platform, contexts);
      if (isDisposed) {
        await _peerService?.disconnect();
        return;
      }
      _hostPort = result.port;

      _session = RemoteSession(
        role: RemoteSessionRole.host,
        status: RemoteSessionStatus.connected,
        createdAt: DateTime.now(),
      );
      _handoffOnly = handoffOnly;
      safeNotifyListeners();

      // Start LAN discovery broadcasting
      _discoveryService ??= LanDiscoveryService();
      final localIps = result.addresses.map((a) => a.split(':').first).toList();
      await _discoveryService!.startBroadcastingForContexts(
        contexts: contexts,
        deviceName: _deviceName,
        platform: _platform,
        wsPort: result.port,
        ips: localIps,
      );

      appLogger.d('CompanionRemote: Host server running, broadcasting on LAN');
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to start host server', error: e);
      _session = RemoteSession(
        role: RemoteSessionRole.host,
        status: RemoteSessionStatus.error,
        errorMessage: friendlyError(e),
        createdAt: DateTime.now(),
      );
      safeNotifyListeners();
    }
  }

  /// Stop the host server and LAN broadcasting.
  Future<void> stopHostServer() async {
    _intentionalDisconnect = true;
    await _discoveryService?.stopBroadcasting();

    if (_peerService != null) {
      await _peerService!.disconnect();
      _peerService = null;
    }
    _cleanupSubscriptions();

    _session = null;
    _handoffOnly = false;
    _isPlayerActive = false;
    _intentionalDisconnect = false;
    safeNotifyListeners();
  }

  /// Asks for a handoff-only host (A-23d). True when it may start now; false
  /// while this device is a client somewhere, or already hosts. A client
  /// session that ends brings the host back ([leaveSession]).
  Future<bool> requestHandoffOnlyHost() async {
    _handoffHostWanted = true;
    // A remote session that ended without a leave (Cancel while reconnecting,
    // giving up, a failed join) holds the peer service; clear it here.
    if (_hasDeadClientSession) await _leaveSession(restoreHandoffHost: false);
    return _session == null && _peerService == null;
  }

  bool get _hasDeadClientSession =>
      _session != null &&
      !isHost &&
      _reconnectTimer?.isActive != true &&
      (_session!.status == RemoteSessionStatus.disconnected || _session!.status == RemoteSessionStatus.error);

  /// A client session died: an iPhone that listens for Pleya Fly listens again.
  void _restoreHandoffHostAfterDeadClient() {
    if (_handoffHostWanted && _hasDeadClientSession) unawaited(_leaveSession(restoreHandoffHost: true));
  }

  /// Stops a handoff-only host and no longer wants one. A full host stays.
  Future<void> stopHandoffOnlyHost() async {
    _handoffHostWanted = false;
    if (isHandoffOnlyHost) await stopHostServer();
  }

  /// A handoff-only host gives way to a client session: both would share the
  /// one peer service, and the host would leak.
  Future<void> _yieldHandoffOnlyHost() async {
    if (isHandoffOnlyHost) await stopHostServer();
  }

  Stream<List<DiscoveredHost>>? discoverHosts() {
    if (!isCryptoReady) {
      appLogger.w('CompanionRemote: Cannot discover — crypto not initialized');
      return null;
    }

    _discoveryService ??= LanDiscoveryService();
    return _discoveryService!.startListeningForContexts(_authContexts);
  }

  /// Stop listening for host beacons.
  void stopDiscovery() {
    _discoveryService?.stopListening();
  }

  /// Connect to a discovered host as a remote client.
  Future<void> connectToDiscoveredHost(DiscoveredHost host) async {
    if (!isCryptoReady) {
      throw StateError('Crypto not initialized');
    }
    final authContext = _authContextForId(host.authContextId);
    if (authContext == null) {
      throw StateError('Matching auth context is no longer available');
    }

    await _yieldHandoffOnlyHost();
    await _leaveSession(restoreHandoffHost: false);

    _lastHostAddresses = host.addresses;
    _lastHostClientId = host.clientId;
    _lastAuthContextId = authContext.id;

    appLogger.d('CompanionRemote: Connecting to ${host.name} at ${host.addresses}');

    _peerService = CompanionRemotePeerService();
    _setupPeerServiceListeners();

    _session = RemoteSession(
      role: RemoteSessionRole.remote,
      status: RemoteSessionStatus.connecting,
      createdAt: DateTime.now(),
    );
    safeNotifyListeners();

    try {
      final winner = await _peerService!.joinSessionRacingWithContexts(
        _deviceName,
        _platform,
        host.addresses,
        _authContexts,
        authContextId: authContext.id,
        expectedHostClientId: host.clientId,
      );
      _lastHostAddresses = [winner];
      _lastAuthContextId = _peerService!.selectedAuthContextId ?? authContext.id;
      _lastHostClientId = _peerService!.selectedHostClientId ?? host.clientId;

      _session = _session?.copyWith(status: RemoteSessionStatus.connected);
      safeNotifyListeners();
      appLogger.d('CompanionRemote: Connected to ${host.name} via $winner');
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to connect to host', error: e);
      _session = _session?.copyWith(status: RemoteSessionStatus.error, errorMessage: friendlyError(e));
      safeNotifyListeners();
      rethrow;
    }
  }

  /// Connect to a host by manual IP:port entry.
  Future<void> connectToManualHost(String hostAddress) async {
    if (!isCryptoReady) {
      throw StateError('Crypto not initialized');
    }

    await _yieldHandoffOnlyHost();
    await _leaveSession(restoreHandoffHost: false);

    _lastHostAddresses = [hostAddress];
    _lastHostClientId = '';
    _lastAuthContextId = null;

    appLogger.d('CompanionRemote: Connecting to manual host $hostAddress');

    _peerService = CompanionRemotePeerService();
    _setupPeerServiceListeners();

    _session = RemoteSession(
      role: RemoteSessionRole.remote,
      status: RemoteSessionStatus.connecting,
      createdAt: DateTime.now(),
    );
    safeNotifyListeners();

    try {
      await _peerService!.joinSessionWithContexts(_deviceName, _platform, hostAddress, _authContexts);
      _lastAuthContextId = _peerService!.selectedAuthContextId;
      _lastHostClientId = _peerService!.selectedHostClientId ?? '';

      _session = _session?.copyWith(status: RemoteSessionStatus.connected);
      safeNotifyListeners();
    } catch (e) {
      appLogger.e('CompanionRemote: Failed to connect to manual host', error: e);
      _session = _session?.copyWith(status: RemoteSessionStatus.error, errorMessage: friendlyError(e));
      safeNotifyListeners();
      rethrow;
    }
  }

  void _setupPeerServiceListeners() {
    _commandSubscription = _peerService!.onCommandReceived.listen(
      (command) {
        appLogger.d('CompanionRemote: Command received: ${command.type}');

        if (command.type == RemoteCommandType.deviceInfo) {
          _handleDeviceInfo(command);
        } else if (command.type == RemoteCommandType.syncState) {
          _handleSyncState(command);
        } else if (command.type != RemoteCommandType.ping &&
            command.type != RemoteCommandType.pong &&
            command.type != RemoteCommandType.ack) {
          onCommandReceived?.call(command);
        }
      },
      onError: (error) {
        appLogger.e('CompanionRemote: Stream error', error: error);
      },
    );

    _deviceConnectedSubscription = _peerService!.onDeviceConnected.listen((device) {
      appLogger.d('CompanionRemote: Device connected: ${device.name}');
      _session = _session?.copyWith(status: RemoteSessionStatus.connected, connectedDevice: device);
      safeNotifyListeners();
    });

    _deviceDisconnectedSubscription = _peerService!.onDeviceDisconnected.listen((_) {
      _handoffs.failAll();
      appLogger.d('CompanionRemote: Device disconnected (intentional: $_intentionalDisconnect)');
      if (_intentionalDisconnect) {
        _session = _session?.copyWith(status: RemoteSessionStatus.disconnected, connectedDevice: null);
        safeNotifyListeners();
      } else if (isHost) {
        _session = _session?.copyWith(
          status: RemoteSessionStatus.reconnecting,
          connectedDevice: null,
          errorMessage: null,
        );
        safeNotifyListeners();
        appLogger.d('CompanionRemote: Host waiting for client to reconnect');
      } else {
        _session = _session?.copyWith(status: RemoteSessionStatus.reconnecting);
        safeNotifyListeners();
        _scheduleReconnect();
      }
    });

    _errorSubscription = _peerService!.onError.listen((error) {
      appLogger.e('CompanionRemote: Error: ${error.message}');
      _session = _session?.copyWith(status: RemoteSessionStatus.error, errorMessage: error.message);
      safeNotifyListeners();
    });

    _statusSubscription = _peerService!.onConnectionStateChanged.listen((status) {
      appLogger.d('CompanionRemote: Status changed: $status');
      _session = _session?.copyWith(status: status);
      safeNotifyListeners();
    });
  }

  void _handleDeviceInfo(RemoteCommand command) {
    if (command.data != null) {
      final id = command.data!['id'] as String? ?? 'unknown';
      final name = command.data!['name'] as String? ?? 'Unknown Device';
      final platform = command.data!['platform'] as String? ?? 'unknown';
      final role = command.data!['role'] as String?;

      appLogger.d('CompanionRemote: Device info - name: $name, platform: $platform, role: $role');

      final device = RemoteDevice(id: id, name: name, platform: platform, connectedAt: DateTime.now());

      _session = _session?.copyWith(connectedDevice: device);
      safeNotifyListeners();
    }
  }

  /// Pass the current playback to the connected host (A-23). Resolves when the
  /// host reports that it plays, or that it could not, or after [timeout]. The
  /// caller keeps playing until this returns [PlaybackHandoffOutcome.playing].
  /// When the host switches to this user's profile first, [onSwitching] hears
  /// it and the wait grows to the tracker's switch budget (A-23b).
  Future<PlaybackHandoffOutcome> handOffPlayback(
    PlaybackHandoffRequest request, {
    Duration timeout = const Duration(seconds: 20),
    void Function(String profile, bool pin)? onSwitching,
  }) async {
    if (!_linkUp) return PlaybackHandoffOutcome.failed;
    final answer = _handoffs.wait(request.id, timeout, onSwitching: onSwitching);
    sendCommand(RemoteCommandType.handoff, data: request.toData());
    return answer;
  }

  void _handleSyncState(RemoteCommand command) {
    _handoffs.handleSyncState(command.data);
    final cancelled = command.data?[handoffCancelKey];
    if (cancelled is String) onHandoffCancelled?.call(cancelled);
    final query = command.data?[handoffQueryKey];
    if (query is String) {
      sendCommand(RemoteCommandType.syncState, data: handoffQueryReply(playbackHandoffLedger, query));
    }
    final reported = command.data?['playerActive'];
    // Handoff answers carry no player state; they must not flip it.
    if (reported is bool && _isPlayerActive != reported) {
      final playerActive = reported;
      _isPlayerActive = playerActive;
      safeNotifyListeners();
    }
  }

  void _cleanupSubscriptions() {
    _commandSubscription?.cancel();
    _commandSubscription = null;
    _deviceConnectedSubscription?.cancel();
    _deviceConnectedSubscription = null;
    _deviceDisconnectedSubscription?.cancel();
    _deviceDisconnectedSubscription = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
  }

  void sendCommand(RemoteCommandType type, {Map<String, dynamic>? data}) {
    if (_peerService == null || !_linkUp) {
      appLogger.w('CompanionRemote: Cannot send command - not connected');
      return;
    }

    appLogger.d('CompanionRemote: Sending command $type');
    _peerService!.sendCommand(RemoteCommand(type: type, data: data));
  }

  /// The wait before the next reconnect attempt, or null to give up. While a
  /// handoff waits for a profile switch on the host, the phone keeps trying
  /// every few seconds until the tracker's switch budget ends that wait: giving
  /// up earlier would leave it playing while the host still starts (A-23b).
  @visibleForTesting
  static Duration? reconnectDelay(int attempts, {required bool waitingForSwitch}) {
    if (waitingForSwitch) return Duration(seconds: attempts < 2 ? 1 << attempts : 4);
    if (attempts >= _maxReconnectAttempts) return null;
    return Duration(seconds: 1 << attempts);
  }

  void _scheduleReconnect() {
    final delay = reconnectDelay(_reconnectAttempts, waitingForSwitch: _handoffs.switchingIds.isNotEmpty);
    if (delay == null) {
      appLogger.w('CompanionRemote: Max reconnect attempts reached');
      _handoffs.failAll(force: true);
      _session = _session?.copyWith(
        status: RemoteSessionStatus.error,
        errorMessage: t.companionRemote.errors.connectionLostAfterAttempts(attempts: _maxReconnectAttempts),
      );
      _reconnectAttempts = 0;
      safeNotifyListeners();
      _restoreHandoffHostAfterDeadClient();
      return;
    }

    _reconnectAttempts++;
    appLogger.d('CompanionRemote: Reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (_lastHostAddresses == null || !isCryptoReady) {
      appLogger.w('CompanionRemote: No stored context for reconnect');
      _handoffs.failAll(force: true);
      _session = _session?.copyWith(
        status: RemoteSessionStatus.error,
        errorMessage: t.companionRemote.errors.connectionLost,
      );
      safeNotifyListeners();
      _restoreHandoffHostAfterDeadClient();
      return;
    }

    try {
      appLogger.d('CompanionRemote: Attempting reconnect...');
      _cleanupSubscriptions();
      try {
        await _peerService?.disconnect();
      } finally {
        _peerService = CompanionRemotePeerService();
        _setupPeerServiceListeners();
      }

      final authContextId = _authContextForId(_lastAuthContextId)?.id;
      await _peerService!.joinSessionWithContexts(
        _deviceName,
        _platform,
        _lastHostAddresses!.first,
        _authContexts,
        authContextId: authContextId,
        expectedHostClientId: _lastHostClientId ?? '',
      );
      _lastAuthContextId = _peerService!.selectedAuthContextId ?? authContextId;
      _lastHostClientId = _peerService!.selectedHostClientId ?? _lastHostClientId;

      _session = _session?.copyWith(status: RemoteSessionStatus.connected, errorMessage: null);
      _reconnectAttempts = 0;
      safeNotifyListeners();
      appLogger.d('CompanionRemote: Reconnected successfully');
      // The host may have answered while it switched profile: ask again.
      for (final id in _handoffs.switchingIds) {
        sendCommand(RemoteCommandType.syncState, data: {handoffQueryKey: id});
      }
    } catch (e) {
      appLogger.e('CompanionRemote: Reconnect failed', error: e);
      // A peer error may have moved the status on; a handoff waiting for a switch still needs the host back.
      if (_session?.status == RemoteSessionStatus.reconnecting || _handoffs.switchingIds.isNotEmpty) {
        _scheduleReconnect();
      }
    }
  }

  void retryReconnectNow() {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _attemptReconnect();
  }

  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    // Deliberately stopped: nothing will answer a handoff, also not one waiting for a switch.
    _handoffs.failAll(force: true);
    _session = _session?.copyWith(status: RemoteSessionStatus.disconnected, connectedDevice: null);
    safeNotifyListeners();
    _restoreHandoffHostAfterDeadClient();
  }

  Future<void> leaveSession() => _leaveSession(restoreHandoffHost: true);

  Future<void> _leaveSession({required bool restoreHandoffHost}) async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _handoffs.failAll(force: true);

    // Don't stop the host server when leaving — only stop discovery listening
    if (_peerService != null && !isHost) {
      appLogger.d('CompanionRemote: Leaving session');
      await _peerService!.disconnect();
      _peerService = null;
    }

    _cleanupSubscriptions();

    if (!isHost) {
      _session = null;
    }
    _isPlayerActive = false;
    _intentionalDisconnect = false;
    safeNotifyListeners();
    // The client session that made a handoff-only host give way is over.
    if (restoreHandoffHost && _handoffHostWanted && _session == null && _peerService == null && isCryptoReady) {
      await startHostServer(handoffOnly: true);
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _discoveryService?.dispose();
    _peerService?.dispose();
    RemoteAuthService.instance.clearCache();
    super.dispose();
  }
}
