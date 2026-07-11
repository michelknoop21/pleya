import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../media/media_item.dart';
import '../../utils/app_logger.dart';
import '../../utils/udp_broadcast_sockets.dart';
import '../../i18n/strings.g.dart';
import '../local_folder_client.dart';
import 'pleya_share_byte_source.dart';
import 'pleya_share_foreground.dart';
import 'pleya_share_pairing.dart';
import 'pleya_share_protocol.dart';

/// A paired guest device, persisted across host restarts.
class PleyaShareGuest {
  final String pairId;
  final String secretB64;
  final String deviceName;
  final int addedAt;

  const PleyaShareGuest({
    required this.pairId,
    required this.secretB64,
    required this.deviceName,
    required this.addedAt,
  });

  Map<String, Object?> toJson() => {'pairId': pairId, 'secret': secretB64, 'name': deviceName, 'addedAt': addedAt};

  factory PleyaShareGuest.fromJson(Map<String, dynamic> json) => PleyaShareGuest(
    pairId: json['pairId'] as String,
    secretB64: json['secret'] as String,
    deviceName: json['name'] as String? ?? 'Pleya',
    addedAt: json['addedAt'] as int? ?? 0,
  );
}

/// Hosts this device's local folder sources as a mini media server for other
/// Pleya clients on the same LAN/hotspot. Plain HTTP on port 48634 (see
/// [PleyaShareProtocol] for the route map) + UDP discovery beacons.
///
/// Multi-client by construction: every paired guest gets its own session
/// token, every /stream request is an independent range-read, and watch
/// state is namespaced per pairId.
class PleyaShareHostService extends ChangeNotifier {
  PleyaShareHostService._();
  static final instance = PleyaShareHostService._();

  static const _guestsPrefsKey = 'pleya_share_guests';
  static String _watchPrefsKey(String pairId) => 'pleya_share_watch_$pairId';
  static const _challengeTtl = Duration(minutes: 1);

  HttpServer? _server;
  UdpBroadcastSocketSet? _beaconSockets;
  Timer? _beaconTimer;

  List<LocalFolderClient> Function()? _clientsResolver;
  String _deviceName = 'Pleya';

  String? _pairCode;
  List<int>? _pairSalt;

  final Map<String, PleyaShareGuest> _guests = {};
  bool _guestsLoaded = false;

  /// Session token → pairId. In-memory only; guests re-auth after restart.
  final Map<String, String> _tokens = {};

  /// challenge key (pairId|clientNonce) → (hostNonce, issued).
  final Map<String, ({List<int> hostNonce, DateTime issued})> _challenges = {};

  final _limiter = PairingRateLimiter();

  bool get isRunning => _server != null;
  int get port => _server?.port ?? PleyaShareProtocol.sharePort;
  String? get pairCode => _pairCode;
  String get deviceName => _deviceName;
  List<PleyaShareGuest> get pairedGuests => List.unmodifiable(_guests.values);

  /// Guests with a live session token (seen since host start).
  Set<String> get activePairIds => _tokens.values.toSet();

  Future<void> start({required List<LocalFolderClient> Function() clients, required String deviceName}) async {
    if (isRunning) return;
    _clientsResolver = clients;
    _deviceName = deviceName;
    await _loadGuests();

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, PleyaShareProtocol.sharePort);
    } catch (_) {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server = server;
    server.listen(_handleRequest, onError: (Object e) => appLogger.w('PleyaShare: server error', error: e));

    regeneratePairCode(notify: false);
    await _startBeacon();
    // Android: a native foreground service (notification + wifi/wake locks)
    // keeps the server alive in the background. Elsewhere the OS suspends
    // backgrounded apps, so keep the screen awake while sharing is on.
    await PleyaShareForeground.start(
      title: t.pleyaShare.notificationTitle,
      text: t.pleyaShare.notificationText,
    );
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    appLogger.i('PleyaShare: hosting on port ${server.port}');
    notifyListeners();
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    await _beaconSockets?.close();
    _beaconSockets = null;
    await _server?.close(force: true);
    _server = null;
    _tokens.clear();
    _challenges.clear();
    _pairCode = null;
    _pairSalt = null;
    await PleyaShareForeground.stop();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    appLogger.i('PleyaShare: hosting stopped');
    notifyListeners();
  }

  void regeneratePairCode({bool notify = true}) {
    _pairCode = PleyaSharePairing.generatePairCode();
    _pairSalt = PleyaSharePairing.randomBytes(16);
    if (notify) notifyListeners();
  }

  Future<void> revokeGuest(String pairId) async {
    _guests.remove(pairId);
    _tokens.removeWhere((_, v) => v == pairId);
    await _persistGuests();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_watchPrefsKey(pairId));
    } catch (_) {}
    notifyListeners();
  }

  // ── Persistence ──

  Future<void> _loadGuests() async {
    if (_guestsLoaded) return;
    _guestsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_guestsPrefsKey);
      if (raw == null) return;
      for (final entry in (jsonDecode(raw) as List)) {
        final guest = PleyaShareGuest.fromJson(entry as Map<String, dynamic>);
        _guests[guest.pairId] = guest;
      }
    } catch (e) {
      appLogger.w('PleyaShare: failed to load guests', error: e);
    }
  }

  Future<void> _persistGuests() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guestsPrefsKey, jsonEncode([for (final g in _guests.values) g.toJson()]));
    } catch (e) {
      appLogger.w('PleyaShare: failed to persist guests', error: e);
    }
  }

  // ── Discovery beacon ──

  Future<void> _startBeacon() async {
    _beaconSockets = await UdpBroadcastSockets.bind();
    _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sendBeacon());
    _sendBeacon();
  }

  void _sendBeacon() {
    final sockets = _beaconSockets;
    if (sockets == null || sockets.isEmpty) return;
    final beacon = jsonEncode({
      'app': PleyaShareProtocol.beaconApp,
      'v': PleyaShareProtocol.version,
      'name': _deviceName,
      'port': port,
    });
    sockets.send(utf8.encode(beacon), UdpBroadcastSockets.limitedBroadcastAddress, PleyaShareProtocol.discoveryPort);
  }

  // ── HTTP handling ──

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final segments = request.uri.pathSegments;
      switch ((request.method, path)) {
        case ('GET', '/info'):
          return _json(request, {
            'app': PleyaShareProtocol.beaconApp,
            'v': PleyaShareProtocol.version,
            'name': _deviceName,
          });
        case ('POST', '/pair/start'):
          return _handlePairStart(request);
        case ('POST', '/pair/complete'):
          return _handlePairComplete(request);
        case ('POST', '/auth/start'):
          return _handleAuthStart(request);
        case ('POST', '/auth/complete'):
          return _handleAuthComplete(request);
      }

      // Everything below requires a valid session token.
      final pairId = _authorize(request);
      if (pairId == null) return _status(request, HttpStatus.unauthorized);

      if (request.method == 'GET' && path == '/ping') {
        return _json(request, {'ok': true});
      }
      if (request.method == 'GET' && path == '/library') {
        return _handleLibrary(request, pairId);
      }
      if (request.method == 'GET' && segments.length == 2 && segments[0] == 'stream') {
        return _handleStream(request, segments[1]);
      }
      if (request.method == 'POST' && path == '/watch') {
        return _handleWatch(request, pairId);
      }
      return _status(request, HttpStatus.notFound);
    } catch (e, st) {
      appLogger.w('PleyaShare: request failed ${request.method} ${request.uri.path}', error: e, stackTrace: st);
      return _status(request, HttpStatus.internalServerError);
    }
  }

  String? _authorize(HttpRequest request) {
    var token = request.uri.queryParameters['token'];
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (token == null && header != null && header.startsWith('Bearer ')) {
      token = header.substring(7);
    }
    if (token == null) return null;
    return _tokens[token];
  }

  String _remoteIp(HttpRequest request) {
    try {
      return request.connectionInfo?.remoteAddress.address ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  static const _maxOpenChallenges = 32;

  void _pruneChallenges() {
    final now = DateTime.now();
    _challenges.removeWhere((_, c) => now.difference(c.issued) > _challengeTtl);
    // Client-chosen keys — cap the map so a LAN peer can't grow it unbounded.
    while (_challenges.length >= _maxOpenChallenges) {
      _challenges.remove(_challenges.keys.first);
    }
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _handlePairStart(HttpRequest request) async {
    if (_pairCode == null) return _status(request, HttpStatus.conflict);
    if (_limiter.isLockedOut(_remoteIp(request))) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final clientNonce = body['clientNonce'] as String?;
    if (clientNonce == null) return _status(request, HttpStatus.badRequest);
    _pruneChallenges();
    final hostNonce = PleyaSharePairing.randomBytes(32);
    _challenges['pair|$clientNonce'] = (hostNonce: hostNonce, issued: DateTime.now());
    return _json(request, {'hostNonce': base64Encode(hostNonce), 'salt': base64Encode(_pairSalt!)});
  }

  Future<void> _handlePairComplete(HttpRequest request) async {
    final ip = _remoteIp(request);
    if (_limiter.isLockedOut(ip)) return _status(request, HttpStatus.tooManyRequests);
    final code = _pairCode;
    final salt = _pairSalt;
    if (code == null || salt == null) return _status(request, HttpStatus.conflict);

    final body = await _body(request);
    final clientNonceB64 = body['clientNonce'] as String?;
    final authTag = body['authTag'] as String?;
    final guestName = (body['deviceName'] as String?)?.trim();
    final challenge = clientNonceB64 == null ? null : _challenges.remove('pair|$clientNonceB64');
    if (clientNonceB64 == null || authTag == null || challenge == null) {
      return _status(request, HttpStatus.badRequest);
    }

    final clientNonce = base64Decode(clientNonceB64);
    final pairingKey = await PleyaSharePairing.derivePairingKey(code, salt);
    final valid = PleyaSharePairing.verifyAuthTag(
      received: authTag,
      key: pairingKey,
      hostNonce: challenge.hostNonce,
      clientNonce: clientNonce,
      context: 'pair',
    );
    if (!valid) {
      _limiter.recordFailure(ip);
      appLogger.w('PleyaShare: pairing attempt with wrong code from $ip');
      return _status(request, HttpStatus.forbidden);
    }

    _limiter.reset(ip);
    final pairId = base64UrlEncode(PleyaSharePairing.randomBytes(12)).replaceAll('=', '');
    final pairSecret = PleyaSharePairing.randomBytes(32);
    final token = _issueToken(pairId);
    _guests[pairId] = PleyaShareGuest(
      pairId: pairId,
      secretB64: base64Encode(pairSecret),
      deviceName: guestName?.isNotEmpty == true ? guestName! : 'Pleya',
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistGuests();

    // Code is single-use: a successful pairing rotates it.
    regeneratePairCode(notify: false);

    final sessionKey = await PleyaSharePairing.deriveSessionKey(pairingKey, challenge.hostNonce, clientNonce);
    final payload = await PleyaSharePairing.encryptPayload(sessionKey, {
      'pairId': pairId,
      'pairSecret': base64Encode(pairSecret),
      'token': token,
      'name': _deviceName,
    });
    notifyListeners();
    return _json(request, {'payload': payload});
  }

  Future<void> _handleAuthStart(HttpRequest request) async {
    if (_limiter.isLockedOut(_remoteIp(request))) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final pairId = body['pairId'] as String?;
    final clientNonce = body['clientNonce'] as String?;
    if (pairId == null || clientNonce == null) return _status(request, HttpStatus.badRequest);
    await _loadGuests();
    if (!_guests.containsKey(pairId)) return _status(request, HttpStatus.forbidden);
    _pruneChallenges();
    final hostNonce = PleyaSharePairing.randomBytes(32);
    _challenges['auth|$pairId|$clientNonce'] = (hostNonce: hostNonce, issued: DateTime.now());
    return _json(request, {'hostNonce': base64Encode(hostNonce)});
  }

  Future<void> _handleAuthComplete(HttpRequest request) async {
    final ip = _remoteIp(request);
    if (_limiter.isLockedOut(ip)) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final pairId = body['pairId'] as String?;
    final clientNonceB64 = body['clientNonce'] as String?;
    final authTag = body['authTag'] as String?;
    final guest = pairId == null ? null : _guests[pairId];
    final challenge = (pairId == null || clientNonceB64 == null)
        ? null
        : _challenges.remove('auth|$pairId|$clientNonceB64');
    if (guest == null || challenge == null || authTag == null || clientNonceB64 == null) {
      return _status(request, HttpStatus.badRequest);
    }

    final clientNonce = base64Decode(clientNonceB64);
    final secret = base64Decode(guest.secretB64);
    final valid = PleyaSharePairing.verifyAuthTag(
      received: authTag,
      key: secret,
      hostNonce: challenge.hostNonce,
      clientNonce: clientNonce,
      context: 'reconnect',
    );
    if (!valid) {
      _limiter.recordFailure(ip);
      return _status(request, HttpStatus.forbidden);
    }
    _limiter.reset(ip);
    final token = _issueToken(guest.pairId);
    final sessionKey = await PleyaSharePairing.deriveSessionKey(secret, challenge.hostNonce, clientNonce);
    final payload = await PleyaSharePairing.encryptPayload(sessionKey, {'token': token, 'name': _deviceName});
    return _json(request, {'payload': payload});
  }

  String _issueToken(String pairId) {
    // One live token per guest keeps the map bounded.
    _tokens.removeWhere((_, v) => v == pairId);
    final token = base64UrlEncode(PleyaSharePairing.randomBytes(32)).replaceAll('=', '');
    _tokens[token] = pairId;
    return token;
  }

  // ── Library / stream / watch ──

  Future<List<MediaItem>> _allItems() async {
    final clients = _clientsResolver?.call() ?? const [];
    final items = <MediaItem>[];
    for (final client in clients) {
      items.addAll(await client.scanAllItems());
    }
    return items;
  }

  Future<void> _handleLibrary(HttpRequest request, String pairId) async {
    final items = await _allItems();
    final watchState = await _loadWatchState(pairId);
    final serialized = <Map<String, dynamic>>[];
    for (final item in items) {
      var json = item.toJson();
      final state = watchState[item.id];
      if (state != null) {
        // Guest-specific watch state replaces the host's own.
        json = Map<String, dynamic>.from(json)
          ..['viewOffsetMs'] = state.progressMs
          ..['viewCount'] = state.watched ? 1 : 0;
      } else {
        json = Map<String, dynamic>.from(json)
          ..remove('viewOffsetMs')
          ..['viewCount'] = 0;
      }
      serialized.add(json);
    }
    return _json(request, {'v': PleyaShareProtocol.version, 'name': _deviceName, 'items': serialized});
  }

  Future<void> _handleStream(HttpRequest request, String encodedId) async {
    final String id;
    try {
      id = PleyaShareProtocol.decodeItemId(encodedId);
    } catch (_) {
      return _status(request, HttpStatus.badRequest);
    }
    // Only serve files that are actually part of a shared library.
    final items = await _allItems();
    final item = items.where((i) => i.id == id).firstOrNull;
    if (item == null) return _status(request, HttpStatus.notFound);
    final knownSize = item.mediaVersions?.firstOrNull?.parts.firstOrNull?.sizeBytes;
    await PleyaShareByteSource.serve(request, id, knownSize: knownSize);
  }

  Future<void> _handleWatch(HttpRequest request, String pairId) async {
    final body = await _body(request);
    final itemId = body['itemId'] as String?;
    if (itemId == null) return _status(request, HttpStatus.badRequest);
    final state = await _loadWatchState(pairId);
    final progressMs = (body['progressMs'] as num?)?.toInt() ?? 0;
    var watched = body['watched'] as bool? ?? false;
    // Progress mid-rewatch reports watched:false with progress > 0; that must
    // not clear an earlier watched flag (explicit unwatch sends progress 0).
    if (!watched && progressMs > 0) {
      watched = state[itemId]?.watched ?? false;
    }
    state[itemId] = (progressMs: progressMs, watched: watched);
    await _persistWatchState(pairId, state);
    return _json(request, {'ok': true});
  }

  Future<Map<String, ({int progressMs, bool watched})>> _loadWatchState(String pairId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_watchPrefsKey(pairId));
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, (progressMs: (v['p'] as num?)?.toInt() ?? 0, watched: v['w'] as bool? ?? false)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistWatchState(String pairId, Map<String, ({int progressMs, bool watched})> state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _watchPrefsKey(pairId),
        jsonEncode(state.map((k, v) => MapEntry(k, {'p': v.progressMs, 'w': v.watched}))),
      );
    } catch (e) {
      appLogger.w('PleyaShare: failed to persist guest watch state', error: e);
    }
  }

  // ── Response helpers ──

  Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _status(HttpRequest request, int code) async {
    request.response.statusCode = code;
    await request.response.close();
  }
}
