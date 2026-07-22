import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../connection/connection.dart';
import '../../utils/app_logger.dart';
import '../../utils/udp_broadcast_sockets.dart';
import 'pleya_share_pairing.dart';
import 'pleya_share_protocol.dart';
import 'pleya_share_relay_proxy.dart';

/// A Pleya Share host seen via UDP discovery.
class DiscoveredShareHost {
  final String name;
  final String ip;
  final int port;
  final DateTime seenAt;

  const DiscoveredShareHost({required this.name, required this.ip, required this.port, required this.seenAt});
}

/// HTTP transport to one paired Pleya Share host: finds a reachable IP,
/// authenticates with the stored pairSecret, and retries once on 401
/// (host restarts invalidate session tokens).
class PleyaShareChannel {
  PleyaShareConnection connection;

  /// Invoked when the host's reachable IP changes (new DHCP lease found via
  /// discovery) so the owner can persist the updated [connection].
  void Function(PleyaShareConnection updated)? onConnectionUpdated;

  String? _baseUrl;
  String? _token;
  Future<bool>? _connecting;
  int _consecutiveFailures = 0;
  PleyaShareRelayProxy? _relayProxy;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);

  /// Relay base URL override for tests (defaults to ice.pleya.app).
  static String? relayBaseUrlOverride;

  /// Tests run many hosts in parallel isolates on one machine; real UDP
  /// beacons and gateway probes then leak other tests' hosts into the
  /// candidate list. When true, only explicitly given IPs are used.
  @visibleForTesting
  static bool discoveryDisabledForTest = false;

  PleyaShareChannel(this.connection);

  String? get token => _token;
  String? get baseUrl => _baseUrl;

  void close() {
    _http.close(force: true);
    _relayProxy?.stop();
    _relayProxy = null;
  }

  /// Absolute stream URL for [itemId], usable by mpv and the download
  /// pipeline. Only valid after [ensureConnected].
  String streamUrl(String itemId) => '$_baseUrl/stream/${PleyaShareProtocol.encodeItemId(itemId)}?token=$_token';

  Future<bool> ensureConnected() {
    if (_baseUrl != null && _token != null) return Future.value(true);
    // Concurrent callers share one connect: parallel candidate races would
    // persist competing IPs and clobber each other's _baseUrl/_token.
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<bool> _connect() async {
    // /info only proves "some Pleya Share host" — after DHCP reuse another
    // device may answer on a cached IP. Only a successful pairId auth proves
    // it's OUR host, so try every candidate and commit on auth success.
    await for (final candidate in _candidateBases()) {
      _baseUrl = candidate.base;
      if (await _authenticate()) {
        _rememberIp(candidate.ip, candidate.port);
        return true;
      }
    }
    _baseUrl = null;
    // No LAN path — tunnel the same protocol through the internet relay.
    // The proxy serves loopback HTTP, so auth and streamUrl work unchanged.
    final relayHostId = connection.relayHostId;
    if (relayHostId != null) {
      await _relayProxy?.stop();
      final proxy = PleyaShareRelayProxy(
        relayHostId: relayHostId,
        keyMaterial: base64Decode(connection.pairSecret),
        pairId: connection.pairId,
        baseUrl: relayBaseUrlOverride,
      );
      try {
        await proxy.start();
        _relayProxy = proxy;
        _baseUrl = proxy.proxyBaseUrl;
        if (await _authenticate()) return true;
      } catch (e) {
        appLogger.d('PleyaShare: relay fallback to ${connection.hostName} failed', error: e);
      }
      await proxy.stop();
      _relayProxy = null;
      _baseUrl = null;
    }
    return false;
  }

  Stream<({String base, String ip, int port})> _candidateBases() async* {
    final seen = <String>{};
    for (final ip in connection.lastKnownIps) {
      final base = 'http://$ip:${connection.port}';
      try {
        final info = await _rawJson('GET', Uri.parse('$base/info'));
        if (info['app'] == PleyaShareProtocol.beaconApp && seen.add(base)) {
          yield (base: base, ip: ip, port: connection.port);
        }
      } catch (_) {}
    }
    if (discoveryDisabledForTest) return;
    // Fall back to discovery beacons — the host may have a new DHCP lease.
    final discovered = await discoverHosts(timeout: const Duration(seconds: 3));
    for (final host in discovered) {
      final base = 'http://${host.ip}:${host.port}';
      if (seen.add(base)) {
        yield (base: base, ip: host.ip, port: host.port);
      }
    }
    // Last resort: the subnet gateways. On a personal hotspot the host IS the
    // gateway (iOS hotspot: 172.20.10.1) and AP isolation eats the beacons.
    for (final ip in await _localGatewayCandidates()) {
      final host = await probeHost(ip, connection.port);
      if (host != null) {
        final base = 'http://${host.ip}:${host.port}';
        if (seen.add(base)) {
          yield (base: base, ip: host.ip, port: host.port);
        }
      }
    }
  }

  /// Move a freshly confirmed IP to the front of [connection.lastKnownIps]
  /// and notify the owner so future launches try it first.
  void _rememberIp(String ip, int port) {
    if (connection.lastKnownIps.firstOrNull == ip && connection.port == port) return;
    final ips = [ip, ...connection.lastKnownIps.where((existing) => existing != ip)].take(5).toList();
    connection = connection.copyWith(lastKnownIps: ips, port: port);
    onConnectionUpdated?.call(connection);
  }

  Future<bool> _authenticate() async {
    final base = _baseUrl;
    if (base == null) return false;
    try {
      final clientNonce = PleyaSharePairing.randomBytes(32);
      final start = await _rawJson(
        'POST',
        Uri.parse('$base/auth/start'),
        body: {'pairId': connection.pairId, 'clientNonce': base64Encode(clientNonce)},
      );
      final hostNonce = base64Decode(start['hostNonce'] as String);
      final secret = base64Decode(connection.pairSecret);
      final authTag = PleyaSharePairing.computeAuthTag(
        key: secret,
        hostNonce: hostNonce,
        clientNonce: clientNonce,
        context: 'reconnect',
      );
      final complete = await _rawJson(
        'POST',
        Uri.parse('$base/auth/complete'),
        body: {'pairId': connection.pairId, 'clientNonce': base64Encode(clientNonce), 'authTag': authTag},
      );
      final sessionKey = await PleyaSharePairing.deriveSessionKey(secret, hostNonce, clientNonce);
      final payload = await PleyaSharePairing.decryptPayload(sessionKey, complete['payload'] as String);
      _token = payload['token'] as String?;
      return _token != null;
    } catch (e) {
      appLogger.d('PleyaShare: auth to ${connection.hostName} failed', error: e);
      _token = null;
      return false;
    }
  }

  /// Authenticated JSON request with one re-auth retry on 401.
  Future<Map<String, dynamic>?> request(String method, String path, {Map<String, Object?>? body}) async {
    if (!await ensureConnected()) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // Bearer header keeps the token out of URIs (and thus host logs);
        // only /stream URLs handed to mpv use the query form.
        final result = await _rawJson(method, Uri.parse('$_baseUrl$path'), body: body, bearer: _token);
        _consecutiveFailures = 0;
        return result;
      } on _HttpStatusException catch (e) {
        if (e.statusCode == HttpStatus.unauthorized && attempt == 0) {
          _token = null;
          if (!await _authenticate()) return null;
          continue;
        }
        appLogger.d('PleyaShare: $method $path → ${e.statusCode}');
        // 502 = the local relay proxy lost its host. Count it like a
        // transport failure so the dead tunnel gets torn down and the next
        // request re-races LAN candidates / builds a fresh proxy.
        if (e.statusCode == HttpStatus.badGateway && ++_consecutiveFailures >= 2) {
          _baseUrl = null;
          _token = null;
          unawaited(_relayProxy?.stop());
          _relayProxy = null;
        }
        return null;
      } catch (e) {
        // One transient failure keeps _baseUrl/_token intact — an in-flight
        // streamUrl() builds from those fields, and nulling them here would
        // hand mpv a "http://null/..." URL. Repeated failures mean the host
        // moved: tear down so the next request re-races candidates.
        appLogger.d('PleyaShare: $method $path failed', error: e);
        if (++_consecutiveFailures >= 2) {
          _baseUrl = null;
          _token = null;
          unawaited(_relayProxy?.stop());
          _relayProxy = null;
        }
        return null;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _rawJson(String method, Uri uri, {Map<String, Object?>? body, String? bearer}) async {
    final request = await _http.openUrl(method, uri);
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw _HttpStatusException(response.statusCode);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  // ── Pairing (used by the join screen) ──

  /// Pair against the first reachable candidate IP. Candidates come from the
  /// scanned QR plus this device's gateway guesses (hotspot: the host often IS
  /// the gateway, e.g. 172.20.10.1, while the QR's first IP is a Wi-Fi address
  /// the guest can't reach). Probes run in parallel; the pairing handshake
  /// itself is only ever run against one host at a time so the one-time
  /// challenge is never double-consumed. A wrong code aborts immediately.
  static Future<PleyaShareConnection> pairAny({
    required List<String> ips,
    required int port,
    required String code,
    required String deviceName,
    String? relayHostId,
    String? saltB64,
  }) async {
    final candidates = <String>{...ips, if (!discoveryDisabledForTest) ...await _localGatewayCandidates()}.toList();
    // Two probe rounds: on iOS the first LAN packet triggers the local-network
    // permission dialog and fails while it's up — round two runs after Allow.
    var reachable = <String>[];
    for (var round = 0; round < 2 && reachable.isEmpty; round++) {
      if (round > 0) await Future<void>.delayed(const Duration(seconds: 2));
      final probes = await Future.wait([
        for (final ip in candidates) probeHost(ip, port, timeout: const Duration(milliseconds: 1500)),
      ]);
      reachable = [
        for (final host in probes)
          if (host != null) host.ip,
      ];
    }
    // Probes can miss hosts that still accept TCP (odd firewalls) — fall back
    // to trying every candidate directly.
    PleyaSharePairException? lastError;
    for (final ip in reachable.isNotEmpty ? reachable : candidates) {
      try {
        final connection = await pair(ip: ip, port: port, code: code, deviceName: deviceName);
        // Keep the other advertised IPs as reconnect candidates.
        final extras = [ip, ...ips.where((other) => other != ip)].take(5).toList();
        return connection.copyWith(lastKnownIps: extras);
      } on PleyaSharePairException catch (e) {
        if (e.wrongCode) rethrow;
        lastError = e;
      }
    }
    // Different networks entirely (guest on 4G, host on Wi-Fi): pair through
    // the internet relay using the code+salt from the QR as key material.
    if (relayHostId != null && saltB64 != null) {
      final pairingKey = await PleyaSharePairing.derivePairingKey(code, base64Decode(saltB64));
      final proxy = PleyaShareRelayProxy(
        relayHostId: relayHostId,
        keyMaterial: pairingKey,
        baseUrl: relayBaseUrlOverride,
      );
      try {
        await proxy.start();
        final connection = await pair(ip: '127.0.0.1', port: proxy.port, code: code, deviceName: deviceName);
        return connection.copyWith(lastKnownIps: ips.take(5).toList(), relayHostId: relayHostId);
      } on PleyaSharePairException catch (e) {
        if (e.wrongCode) rethrow;
        lastError = e;
      } catch (e) {
        appLogger.d('PleyaShare: relay pairing failed', error: e);
      } finally {
        await proxy.stop();
      }
    }
    throw lastError ?? const PleyaSharePairException(wrongCode: false);
  }

  /// Run the code-pairing flow against a host. Returns a ready-to-persist
  /// connection, or throws on wrong code / unreachable host.
  static Future<PleyaShareConnection> pair({
    required String ip,
    required int port,
    required String code,
    required String deviceName,
  }) async {
    final channel = PleyaShareChannel(
      PleyaShareConnection(
        id: 'pending',
        hostName: '',
        pairId: '',
        pairSecret: '',
        lastKnownIps: [ip],
        port: port,
        createdAt: DateTime.now(),
      ),
    );
    try {
      final base = 'http://$ip:$port';
      final clientNonce = PleyaSharePairing.randomBytes(32);
      final start = await channel._rawJson(
        'POST',
        Uri.parse('$base/pair/start'),
        body: {'clientNonce': base64Encode(clientNonce)},
      );
      final hostNonce = base64Decode(start['hostNonce'] as String);
      final salt = base64Decode(start['salt'] as String);
      final pairingKey = await PleyaSharePairing.derivePairingKey(code, salt);
      final authTag = PleyaSharePairing.computeAuthTag(
        key: pairingKey,
        hostNonce: hostNonce,
        clientNonce: clientNonce,
        context: 'pair',
      );
      final complete = await channel._rawJson(
        'POST',
        Uri.parse('$base/pair/complete'),
        body: {'clientNonce': base64Encode(clientNonce), 'authTag': authTag, 'deviceName': deviceName},
      );
      final sessionKey = await PleyaSharePairing.deriveSessionKey(pairingKey, hostNonce, clientNonce);
      final payload = await PleyaSharePairing.decryptPayload(sessionKey, complete['payload'] as String);
      final hostName = payload['name'] as String? ?? 'Pleya Share';
      return PleyaShareConnection(
        id: 'pleya-share-${payload['pairId']}',
        hostName: hostName,
        pairId: payload['pairId'] as String,
        pairSecret: payload['pairSecret'] as String,
        lastKnownIps: [ip],
        port: port,
        relayHostId: payload['relayHostId'] as String?,
        createdAt: DateTime.now(),
      );
    } on _HttpStatusException catch (e) {
      throw PleyaSharePairException(wrongCode: e.statusCode == HttpStatus.forbidden);
    } on PleyaSharePairException {
      rethrow;
    } catch (_) {
      throw const PleyaSharePairException(wrongCode: false);
    } finally {
      channel.close();
    }
  }

  static Future<List<DiscoveredShareHost>>? _discoveryInFlight;

  /// Listen for Pleya Share beacons for [timeout] and return unique hosts.
  static Future<List<DiscoveredShareHost>> discoverHosts({Duration timeout = const Duration(seconds: 4)}) {
    // Port 48633 can only be bound once per process — share one in-flight scan.
    return _discoveryInFlight ??= _discoverHosts(timeout: timeout).whenComplete(() => _discoveryInFlight = null);
  }

  /// Derive `.1` gateway candidates from this device's own IPv4 addresses.
  /// Pure and testable; excludes the device's own addresses. Link-local
  /// (169.254.x.x, direct cable) has no gateway, so no `.1` guess there.
  static List<String> gatewayCandidatesFrom(List<String> ownIps) {
    final candidates = <String>{};
    for (final ip in ownIps) {
      if (ip.startsWith('169.254.')) continue;
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      // .1 = routers/hotspots; .129 = Android USB-tethering convention;
      // .254 = Windows ICS. Probes are cheap and parallel.
      for (final last in const ['1', '129', '254']) {
        final gateway = '${parts[0]}.${parts[1]}.${parts[2]}.$last';
        if (!ownIps.contains(gateway)) candidates.add(gateway);
      }
    }
    return candidates.toList();
  }

  static Future<List<String>> _localGatewayCandidates() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final ownIps = [
        for (final iface in interfaces)
          for (final addr in iface.addresses) addr.address,
      ];
      return gatewayCandidatesFrom(ownIps);
    } catch (_) {
      return const [];
    }
  }

  /// Unicast /info probe — works where UDP broadcast is filtered (hotspot
  /// AP isolation). Returns null when [ip] isn't a Pleya Share host.
  static Future<DiscoveredShareHost?> probeHost(
    String ip,
    int port, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final http = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await http.getUrl(Uri.parse('http://$ip:$port/info'));
      final response = await request.close().timeout(timeout + const Duration(milliseconds: 500));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) return null;
      final info = jsonDecode(text) as Map<String, dynamic>;
      if (info['app'] != PleyaShareProtocol.beaconApp) return null;
      return DiscoveredShareHost(name: info['name'] as String? ?? 'Pleya', ip: ip, port: port, seenAt: DateTime.now());
    } catch (_) {
      return null;
    } finally {
      http.close(force: true);
    }
  }

  /// Sweep every /24 this device sits in with unicast /info probes. For
  /// networks whose AP isolation blocks broadcast AND where the host is not
  /// the gateway. ~3s worst case (concurrency 48, 400ms per probe).
  static Future<List<DiscoveredShareHost>> scanSubnet({int port = PleyaShareProtocol.sharePort}) async {
    final List<String> ownIps;
    try {
      final interfaces = await NetworkInterface.list(
        // Direct cable: the only subnet may be the link-local one — sweep
        // its own /24 like any other (the full /16 would be 65k probes).
        includeLinkLocal: true,
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      ownIps = [
        for (final iface in interfaces)
          for (final addr in iface.addresses) addr.address,
      ];
    } catch (_) {
      return const [];
    }
    final targets = <String>{};
    for (final ip in ownIps) {
      final parts = ip.split('.');
      if (parts.length != 4) continue;
      final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
      for (var i = 1; i <= 254; i++) {
        final candidate = '$prefix.$i';
        if (!ownIps.contains(candidate)) targets.add(candidate);
      }
    }
    final found = <DiscoveredShareHost>[];
    final queue = targets.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ip = queue.removeLast();
        final host = await probeHost(ip, port, timeout: const Duration(milliseconds: 400));
        if (host != null) found.add(host);
      }
    }

    await Future.wait([for (var i = 0; i < 48; i++) worker()]);
    return found;
  }

  static Future<List<DiscoveredShareHost>> _discoverHosts({required Duration timeout}) async {
    final hosts = <String, DiscoveredShareHost>{};
    // Hotspot fallback: AP isolation drops beacons, but the hotspot device is
    // always the gateway — probe the .1 of every subnet we're on, concurrently
    // with the UDP listen window so a probe hit doesn't wait out the timeout.
    final gatewayProbes = _localGatewayCandidates().then((ips) async {
      final probed = await Future.wait([for (final ip in ips) probeHost(ip, PleyaShareProtocol.sharePort)]);
      return probed.whereType<DiscoveredShareHost>().toList();
    });
    RawDatagramSocket? socket;
    try {
      // reuseAddress matches companion-remote's LanDiscoveryService on the
      // same port (48633), so whichever binds second doesn't fail outright
      // on platforms without reusePort. A failed bind is non-fatal either
      // way: the gateway probes below still find hotspot hosts.
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        PleyaShareProtocol.discoveryPort,
        reuseAddress: true,
        reusePort: !Platform.isAndroid && !Platform.isWindows,
      );
      socket.broadcastEnabled = true;
      final subscription = socket.listenDatagrams((datagram) {
        try {
          final decoded = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
          if (decoded['app'] != PleyaShareProtocol.beaconApp) return;
          final ip = datagram.address.address;
          hosts[ip] = DiscoveredShareHost(
            name: decoded['name'] as String? ?? 'Pleya',
            ip: ip,
            port: (decoded['port'] as num?)?.toInt() ?? PleyaShareProtocol.sharePort,
            seenAt: DateTime.now(),
          );
        } catch (_) {}
      }, debugLabel: 'PleyaShare discovery');
      await Future<void>.delayed(timeout);
      await subscription.cancel();
    } catch (e) {
      appLogger.d('PleyaShare: discovery failed', error: e);
    } finally {
      socket?.close();
    }
    for (final probed in await gatewayProbes) {
      hosts.putIfAbsent(probed.ip, () => probed);
    }
    return hosts.values.toList();
  }
}

class _HttpStatusException implements Exception {
  final int statusCode;
  const _HttpStatusException(this.statusCode);
}

/// Thrown by [PleyaShareChannel.pair]; [wrongCode] distinguishes a rejected
/// code (403) from an unreachable/incompatible host.
class PleyaSharePairException implements Exception {
  final bool wrongCode;
  const PleyaSharePairException({required this.wrongCode});
}
