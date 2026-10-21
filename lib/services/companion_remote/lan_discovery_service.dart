import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../utils/app_logger.dart';
import '../../utils/udp_broadcast_sockets.dart';
import 'remote_auth_context.dart';
import 'remote_auth_service.dart';

/// A host discovered on the LAN via UDP broadcast.
class DiscoveredHost {
  final String authContextId;
  final String clientId;
  final String name;
  final String platform;
  final int port;
  final List<String> ips;
  DateTime lastSeen;

  DiscoveredHost({
    required this.authContextId,
    required this.clientId,
    required this.name,
    required this.platform,
    required this.port,
    required this.ips,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  List<String> get addresses => ips.map((ip) => '$ip:$port').toList();
}

/// UDP-based LAN discovery for companion remote.
///
/// Hosts broadcast authenticated beacons; clients listen and filter
/// by matching Plex home membership.
class LanDiscoveryService {
  static const int discoveryPort = 48633;
  static const int _broadcastIntervalSeconds = 3;
  static const int _staleTimeoutSeconds = 10;
  static const int _beaconVersion = 1;

  // Broadcaster state (host)
  UdpBroadcastSocketSet? _broadcastSockets;
  Timer? _broadcastTimer;

  // Listener state (client)
  RawDatagramSocket? _listenSocket;
  StreamSubscription<RawSocketEvent>? _listenSubscription;
  Timer? _staleCleanupTimer;
  final Map<String, DiscoveredHost> _discoveredHosts = {};
  final _hostsController = StreamController<List<DiscoveredHost>>.broadcast();

  /// Whether the broadcaster is currently active.
  bool get isBroadcasting => _broadcastTimer != null;

  /// Whether the listener is currently active.
  bool get isListening => _listenSocket != null;

  // ── Host: Broadcasting ──

  Future<void> startBroadcasting({
    required List<int> discoveryKey,
    required String deviceName,
    required String platform,
    required String clientId,
    required int wsPort,
    required List<String> ips,
  }) async {
    return startBroadcastingForContexts(
      contexts: [
        RemoteAuthContext(
          id: clientId,
          backend: 'legacy',
          connectionId: clientId,
          homeSecret: const [],
          discoveryKey: discoveryKey,
          clientIdentifier: clientId,
          userUuid: '',
          allowedUserUuids: const [],
        ),
      ],
      deviceName: deviceName,
      platform: platform,
      wsPort: wsPort,
      ips: ips,
    );
  }

  Future<void> startBroadcastingForContexts({
    required List<RemoteAuthContext> contexts,
    required String deviceName,
    required String platform,
    required int wsPort,
    required List<String> ips,
    bool answerBeacons = false,
  }) async {
    await stopBroadcasting();
    if (contexts.isEmpty) return;

    try {
      _broadcastSockets = await UdpBroadcastSockets.bind();
      if (_broadcastSockets!.isEmpty) return;

      appLogger.d('LanDiscovery: Broadcasting started on port $discoveryPort');

      if (answerBeacons) {
        unawaited(_bindAnswerSocket(contexts, deviceName, platform, wsPort, ips));
      }

      // Send immediately, then periodically
      for (final context in contexts) {
        _sendBeacon(context, deviceName, platform, wsPort, ips);
      }
      _broadcastTimer = Timer.periodic(const Duration(seconds: _broadcastIntervalSeconds), (_) {
        for (final context in contexts) {
          _sendBeacon(context, deviceName, platform, wsPort, ips);
        }
      });
    } catch (e) {
      appLogger.e('LanDiscovery: Failed to start broadcasting', error: e);
      await stopBroadcasting();
    }
  }

  void _sendBeacon(RemoteAuthContext context, String deviceName, String platform, int wsPort, List<String> ips) {
    final broadcastSockets = _broadcastSockets;
    if (broadcastSockets == null || broadcastSockets.isEmpty) return;

    try {
      final data = _encodeBeacon(context, deviceName, platform, wsPort, ips);
      broadcastSockets.send(data, UdpBroadcastSockets.limitedBroadcastAddress, discoveryPort);
    } catch (e) {
      appLogger.e('LanDiscovery: Failed to send beacon', error: e);
    }
  }

  List<int> _encodeBeacon(RemoteAuthContext context, String deviceName, String platform, int wsPort, List<String> ips) {
    final auth = RemoteAuthService.instance;
    final discoveryKey = context.discoveryKey;
    final clientId = context.clientIdentifier;
    final homeHash = auth.computeDiscoveryTag(discoveryKey);

    final beaconHmac = auth.computeBeaconHmac(
      discoveryKey: discoveryKey,
      version: _beaconVersion,
      homeHash: homeHash,
      name: deviceName,
      platform: platform,
      clientId: clientId,
      port: wsPort,
      ips: ips,
    );

    return utf8.encode(
      jsonEncode({
        'app': 'pleya',
        'v': _beaconVersion,
        'homeHash': homeHash,
        'name': deviceName,
        'platform': platform,
        'clientId': clientId,
        'port': wsPort,
        'ips': ips,
        'hmac': beaconHmac,
      }),
    );
  }

  Future<void> stopBroadcasting() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _closeAnswerSocket();
    await _broadcastSockets?.close();
    _broadcastSockets = null;
    appLogger.d('LanDiscovery: Broadcasting stopped');
  }

  // ── Host: answering beacons ──

  /// A phone's own broadcast does not reliably reach the Apple TV: iOS may drop
  /// a broadcast from an app without the multicast entitlement, with no error
  /// to the sender. What does work is receiving the TV's broadcast and sending
  /// unicast, so a host that [startBroadcastingForContexts] with
  /// `answerBeacons` also listens for beacons of an Apple TV in its own home
  /// and answers each with its beacon, straight to the TV (A-23d).
  RawDatagramSocket? _answerSocket;
  StreamSubscription<RawSocketEvent>? _answerSubscription;
  final Map<String, DateTime> _lastAnswerAt = {};
  // A bind that finishes after a stop (or after a newer start) must close its socket.
  int _answerGeneration = 0;
  static const Duration _answerInterval = Duration(seconds: 2);

  Future<void> _bindAnswerSocket(
    List<RemoteAuthContext> contexts,
    String deviceName,
    String platform,
    int wsPort,
    List<String> ips,
  ) async {
    final generation = ++_answerGeneration;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      // Stopped, or replaced by a newer start, while binding: nobody wants this
      // socket (or its stale contexts) any more.
      if (generation != _answerGeneration || _broadcastTimer == null) {
        socket.close();
        return;
      }
      _answerSocket = socket;
      _answerSubscription = socket.listenDatagrams(
        (datagram) => _answerDatagram(socket, datagram, contexts, deviceName, platform, wsPort, ips),
        debugLabel: 'LanDiscovery answer',
      );
      appLogger.d('LanDiscovery: Answering Apple TV beacons on port $discoveryPort');
    } catch (e) {
      appLogger.w('LanDiscovery: Failed to bind the answer socket', error: e);
    }
  }

  void _answerDatagram(
    RawDatagramSocket socket,
    Datagram datagram,
    List<RemoteAuthContext> contexts,
    String deviceName,
    String platform,
    int wsPort,
    List<String> ips,
  ) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (!shouldAnswerBeacon(json, ownClientIds: contexts.map((c) => c.clientIdentifier).toSet())) return;
      final matched = _matchContext(json, contexts);
      if (matched == null) return;

      final address = datagram.address.address;
      final now = DateTime.now();
      final last = _lastAnswerAt[address];
      if (last != null && now.difference(last) < _answerInterval) return;
      _lastAnswerAt[address] = now;

      // Only the home the TV proved to share; other homes' beacons stay unanswered.
      socket.send(_encodeBeacon(matched, deviceName, platform, wsPort, ips), datagram.address, discoveryPort);
      appLogger.d('LanDiscovery: Answered the beacon of ${json['name']} at $address');
    } catch (e) {
      // Ignore malformed packets
    }
  }

  void _closeAnswerSocket() {
    _answerGeneration++;
    _answerSubscription?.cancel();
    _answerSubscription = null;
    _answerSocket?.close();
    _answerSocket = null;
    _lastAnswerAt.clear();
  }

  /// Whether a beacon is one an iPhone answers: from an Apple TV, and not its own.
  @visibleForTesting
  static bool shouldAnswerBeacon(Map<String, dynamic> beacon, {required Set<String> ownClientIds}) {
    if (beacon['app'] != 'pleya') return false;
    if (beacon['platform'] != 'tvOS') return false;
    final clientId = beacon['clientId'];
    return clientId is! String || !ownClientIds.contains(clientId);
  }

  // ── Client: Listening ──

  /// Start listening for host beacons.
  /// Returns a stream of currently-visible hosts, updated on each beacon or stale cleanup.
  Stream<List<DiscoveredHost>> startListening({required List<int> discoveryKey}) {
    return startListeningForContexts([
      RemoteAuthContext(
        id: '',
        backend: 'legacy',
        connectionId: '',
        homeSecret: const [],
        discoveryKey: discoveryKey,
        clientIdentifier: '',
        userUuid: '',
        allowedUserUuids: const [],
      ),
    ]);
  }

  Stream<List<DiscoveredHost>> startListeningForContexts(List<RemoteAuthContext> contexts) {
    _stopListeningInternal();
    _discoveredHosts.clear();

    _bindListener(contexts);

    // Periodically remove stale hosts
    _staleCleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      final staleIds = <String>[];
      for (final entry in _discoveredHosts.entries) {
        if (now.difference(entry.value.lastSeen).inSeconds > _staleTimeoutSeconds) {
          staleIds.add(entry.key);
        }
      }
      if (staleIds.isNotEmpty) {
        for (final id in staleIds) {
          _discoveredHosts.remove(id);
        }
        _emitHosts();
      }
    });

    return _hostsController.stream;
  }

  Future<void> _bindListener(List<RemoteAuthContext> contexts) async {
    try {
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );

      appLogger.d('LanDiscovery: Listening on port $discoveryPort');

      _listenSubscription = _listenSocket!.listenDatagrams(
        (datagram) => _handleDatagram(datagram, contexts),
        debugLabel: 'LanDiscovery listener',
      );
    } catch (e) {
      appLogger.e('LanDiscovery: Failed to bind listener', error: e);
    }
  }

  /// The context whose home key verifies [json], or null for another home.
  RemoteAuthContext? _matchContext(Map<String, dynamic> json, List<RemoteAuthContext> contexts) {
    final version = json['v'] as int? ?? 0;
    final homeHash = json['homeHash'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final platform = json['platform'] as String? ?? '';
    final clientId = json['clientId'] as String? ?? '';
    final port = json['port'] as int? ?? 0;
    final ips = (json['ips'] as List<dynamic>?)?.cast<String>() ?? [];
    final hmac = json['hmac'] as String? ?? '';

    final auth = RemoteAuthService.instance;
    for (final context in contexts) {
      final discoveryKey = context.discoveryKey;
      if (!auth.verifyBeaconHmac(
        receivedHmac: hmac,
        discoveryKey: discoveryKey,
        version: version,
        homeHash: homeHash,
        name: name,
        platform: platform,
        clientId: clientId,
        port: port,
        ips: ips,
      )) {
        continue;
      }
      if (!auth.matchesDiscoveryTag(homeHash, discoveryKey)) continue;
      return context;
    }
    return null;
  }

  void _handleDatagram(Datagram datagram, List<RemoteAuthContext> contexts) {
    try {
      final packet = utf8.decode(datagram.data);
      final json = jsonDecode(packet) as Map<String, dynamic>;

      if (json['app'] != 'pleya') return;

      final name = json['name'] as String? ?? '';
      final platform = json['platform'] as String? ?? '';
      final clientId = json['clientId'] as String? ?? '';
      final port = json['port'] as int? ?? 0;
      final ips = (json['ips'] as List<dynamic>?)?.cast<String>() ?? [];

      final matchedContext = _matchContext(json, contexts);
      if (matchedContext == null) {
        // Not for this home, or a beacon that does not verify; the sender's
        // address says whose it is when a device never shows up.
        appLogger.d(
          'LanDiscovery: Ignored a beacon from ${datagram.address.address} (${json['platform']}): no matching home',
        );
        return;
      }

      // Valid beacon from same home
      final hostKey = clientId;
      if (_discoveredHosts.containsKey(hostKey)) {
        final existing = _discoveredHosts[hostKey]!;
        existing.lastSeen = DateTime.now();
        // Only emit if fields actually changed
        if (existing.name != name || existing.port != port) {
          _discoveredHosts[hostKey] = DiscoveredHost(
            authContextId: existing.authContextId,
            clientId: clientId,
            name: name,
            platform: platform,
            port: port,
            ips: ips,
          );
          _emitHosts();
        }
      } else {
        _discoveredHosts[hostKey] = DiscoveredHost(
          authContextId: matchedContext.id,
          clientId: clientId,
          name: name,
          platform: platform,
          port: port,
          ips: ips,
        );
        appLogger.d('LanDiscovery: Discovered host: $name ($platform) at ${ips.join(", ")}:$port');
        _emitHosts();
      }
    } catch (e) {
      // Ignore malformed packets
    }
  }

  void _emitHosts() {
    _hostsController.add(_discoveredHosts.values.toList());
  }

  void stopListening() {
    _stopListeningInternal();
    _discoveredHosts.clear();
    _emitHosts();
  }

  void _stopListeningInternal() {
    _staleCleanupTimer?.cancel();
    _staleCleanupTimer = null;
    _listenSubscription?.cancel();
    _listenSubscription = null;
    _listenSocket?.close();
    _listenSocket = null;
    appLogger.d('LanDiscovery: Listening stopped');
  }

  void dispose() {
    stopBroadcasting();
    stopListening();
    _hostsController.close();
  }
}
