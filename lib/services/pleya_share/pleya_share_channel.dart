import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../connection/connection.dart';
import '../../utils/app_logger.dart';
import '../../utils/udp_broadcast_sockets.dart';
import 'pleya_share_pairing.dart';
import 'pleya_share_protocol.dart';

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
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);

  PleyaShareChannel(this.connection);

  String? get token => _token;
  String? get baseUrl => _baseUrl;

  void close() => _http.close(force: true);

  /// Absolute stream URL for [itemId], usable by mpv and the download
  /// pipeline. Only valid after [ensureConnected].
  String streamUrl(String itemId) => '$_baseUrl/stream/${PleyaShareProtocol.encodeItemId(itemId)}?token=$_token';

  Future<bool> ensureConnected() async {
    if (_baseUrl != null && _token != null) return true;
    final base = await _findReachableBase();
    if (base == null) return false;
    _baseUrl = base;
    return await _authenticate();
  }

  Future<String?> _findReachableBase() async {
    for (final ip in connection.lastKnownIps) {
      final base = 'http://$ip:${connection.port}';
      try {
        final info = await _rawJson('GET', Uri.parse('$base/info'));
        if (info['app'] == PleyaShareProtocol.beaconApp) return base;
      } catch (_) {}
    }
    // Fall back to discovery beacons — the host may have a new DHCP lease.
    final discovered = await discoverHosts(timeout: const Duration(seconds: 3));
    for (final host in discovered) {
      if (host.name == connection.hostName || connection.lastKnownIps.isEmpty) {
        _rememberIp(host.ip, host.port);
        return 'http://${host.ip}:${host.port}';
      }
    }
    return null;
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
        return await _rawJson(method, Uri.parse('$_baseUrl$path'), body: body, bearer: _token);
      } on _HttpStatusException catch (e) {
        if (e.statusCode == HttpStatus.unauthorized && attempt == 0) {
          _token = null;
          if (!await _authenticate()) return null;
          continue;
        }
        appLogger.d('PleyaShare: $method $path → ${e.statusCode}');
        return null;
      } catch (e) {
        appLogger.d('PleyaShare: $method $path failed', error: e);
        _baseUrl = null;
        _token = null;
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

  static Future<List<DiscoveredShareHost>> _discoverHosts({required Duration timeout}) async {
    final hosts = <String, DiscoveredShareHost>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        PleyaShareProtocol.discoveryPort,
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
