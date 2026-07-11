import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pairing.dart';
import 'scanner.dart';

/// Headless Pleya Share host. Speaks the exact HTTP protocol of the in-app
/// host (`lib/services/pleya_share/pleya_share_host_service.dart`):
///
///   GET  /info · POST /pair/start · POST /pair/complete
///   POST /auth/start · POST /auth/complete
///   GET  /library · GET /stream/<b64url(path)> (Range) · POST /watch · GET /ping
///
/// State (paired guests, per-guest watch state) lives as JSON files in
/// [dataDir]. Discovery beacons broadcast on UDP 48633.
class PleyaShareServer {
  final List<MediaRoot> roots;
  final String name;
  final int port;
  final Directory dataDir;

  /// Fixed pairing code (headless-friendly). When null a random code is
  /// generated and printed at startup; it rotates after each pairing.
  final String? fixedCode;

  PleyaShareServer({
    required this.roots,
    required this.name,
    required this.port,
    required this.dataDir,
    this.fixedCode,
  });

  static const discoveryPort = 48633;
  static const beaconApp = 'pleya-share';
  static const version = 1;
  static const _challengeTtl = Duration(minutes: 1);

  HttpServer? _http;
  RawDatagramSocket? _beaconSocket;
  Timer? _beaconTimer;
  Timer? _rescanTimer;

  late String _pairCode;
  List<int> _pairSalt = PleyaSharePairing.randomBytes(16);

  final Map<String, Map<String, Object?>> _guests = {};
  final Map<String, String> _tokens = {};
  final Map<String, ({List<int> hostNonce, DateTime issued})> _challenges = {};
  final _limiter = PairingRateLimiter();

  List<Map<String, Object?>> _catalog = [];
  final Map<String, Map<String, Object?>> _catalogById = {};

  /// Actual bound port (differs from [port] when constructed with port 0).
  int? get boundPort => _http?.port;

  File get _guestsFile => File('${dataDir.path}/guests.json');
  File _watchFile(String pairId) => File('${dataDir.path}/watch_$pairId.json');

  Future<void> start() async {
    dataDir.createSync(recursive: true);
    _loadGuests();
    _rescan();
    _rescanTimer = Timer.periodic(const Duration(minutes: 10), (_) => _rescan());
    _rotateCode(initial: true);

    _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http!.listen(_handle, onError: (Object e) => stderr.writeln('server error: $e'));
    stdout.writeln('pleya-share-server "$name" listening on :$port '
        '(${_catalog.length} items from ${roots.length} root(s))');
    stdout.writeln('pairing code: $_pairCode${fixedCode != null ? ' (fixed)' : ''}');

    await _startBeacon();
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _rescanTimer?.cancel();
    _beaconSocket?.close();
    await _http?.close(force: true);
  }

  void _rescan() {
    final items = <Map<String, Object?>>[];
    for (final root in roots) {
      items.addAll(LibraryScanner(root).scan());
    }
    _catalog = items;
    _catalogById
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i['id'] as String, i)));
  }

  void _rotateCode({bool initial = false}) {
    _pairCode = fixedCode ?? PleyaSharePairing.generatePairCode();
    _pairSalt = PleyaSharePairing.randomBytes(16);
    if (!initial && fixedCode == null) stdout.writeln('new pairing code: $_pairCode');
  }

  // ── Beacon ──

  Future<void> _startBeacon() async {
    try {
      _beaconSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _beaconSocket!.broadcastEnabled = true;
      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sendBeacon());
      _sendBeacon();
    } catch (e) {
      stderr.writeln('beacon disabled: $e');
    }
  }

  void _sendBeacon() {
    final beacon = utf8.encode(jsonEncode({'app': beaconApp, 'v': version, 'name': name, 'port': port}));
    try {
      _beaconSocket?.send(beacon, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (_) {}
  }

  // ── State files ──

  void _loadGuests() {
    try {
      if (!_guestsFile.existsSync()) return;
      for (final entry in (jsonDecode(_guestsFile.readAsStringSync()) as List)) {
        final guest = (entry as Map).cast<String, Object?>();
        _guests[guest['pairId'] as String] = guest;
      }
      stdout.writeln('loaded ${_guests.length} paired guest(s)');
    } catch (e) {
      stderr.writeln('failed to load guests: $e');
    }
  }

  void _persistGuests() {
    _guestsFile.writeAsStringSync(jsonEncode(_guests.values.toList()));
  }

  Map<String, Map<String, Object?>> _loadWatch(String pairId) {
    try {
      final file = _watchFile(pairId);
      if (!file.existsSync()) return {};
      return (jsonDecode(file.readAsStringSync()) as Map)
          .map((k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>()));
    } catch (_) {
      return {};
    }
  }

  void _persistWatch(String pairId, Map<String, Map<String, Object?>> state) {
    _watchFile(pairId).writeAsStringSync(jsonEncode(state));
  }

  // ── HTTP ──

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final segments = request.uri.pathSegments;
      switch ((request.method, path)) {
        case ('GET', '/info'):
          return _json(request, {'app': beaconApp, 'v': version, 'name': name});
        case ('POST', '/pair/start'):
          return _pairStart(request);
        case ('POST', '/pair/complete'):
          return _pairComplete(request);
        case ('POST', '/auth/start'):
          return _authStart(request);
        case ('POST', '/auth/complete'):
          return _authComplete(request);
      }

      final pairId = _authorize(request);
      if (pairId == null) return _status(request, HttpStatus.unauthorized);

      if (request.method == 'GET' && path == '/ping') return _json(request, {'ok': true});
      if (request.method == 'GET' && path == '/library') return _library(request, pairId);
      if (request.method == 'GET' && segments.length == 2 && segments[0] == 'stream') {
        return _stream(request, segments[1]);
      }
      if (request.method == 'POST' && path == '/watch') return _watch(request, pairId);
      return _status(request, HttpStatus.notFound);
    } catch (e) {
      stderr.writeln('request failed ${request.uri}: $e');
      return _status(request, HttpStatus.internalServerError);
    }
  }

  String? _authorize(HttpRequest request) {
    var token = request.uri.queryParameters['token'];
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (token == null && header != null && header.startsWith('Bearer ')) token = header.substring(7);
    return token == null ? null : _tokens[token];
  }

  String _ip(HttpRequest r) => r.connectionInfo?.remoteAddress.address ?? 'unknown';

  Future<Map<String, dynamic>> _body(HttpRequest request) async =>
      jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;

  void _pruneChallenges() {
    final now = DateTime.now();
    _challenges.removeWhere((_, c) => now.difference(c.issued) > _challengeTtl);
  }

  Future<void> _pairStart(HttpRequest request) async {
    if (_limiter.isLockedOut(_ip(request))) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final clientNonce = body['clientNonce'] as String?;
    if (clientNonce == null) return _status(request, HttpStatus.badRequest);
    _pruneChallenges();
    final hostNonce = PleyaSharePairing.randomBytes(32);
    _challenges['pair|$clientNonce'] = (hostNonce: hostNonce, issued: DateTime.now());
    return _json(request, {'hostNonce': base64Encode(hostNonce), 'salt': base64Encode(_pairSalt)});
  }

  Future<void> _pairComplete(HttpRequest request) async {
    final ip = _ip(request);
    if (_limiter.isLockedOut(ip)) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final clientNonceB64 = body['clientNonce'] as String?;
    final authTag = body['authTag'] as String?;
    final challenge = clientNonceB64 == null ? null : _challenges.remove('pair|$clientNonceB64');
    if (clientNonceB64 == null || authTag == null || challenge == null) {
      return _status(request, HttpStatus.badRequest);
    }
    final clientNonce = base64Decode(clientNonceB64);
    final pairingKey = await PleyaSharePairing.derivePairingKey(_pairCode, _pairSalt);
    final valid = PleyaSharePairing.verifyAuthTag(
      received: authTag,
      key: pairingKey,
      hostNonce: challenge.hostNonce,
      clientNonce: clientNonce,
      context: 'pair',
    );
    if (!valid) {
      _limiter.recordFailure(ip);
      stderr.writeln('pairing attempt with wrong code from $ip');
      return _status(request, HttpStatus.forbidden);
    }
    _limiter.reset(ip);
    final pairId = base64UrlEncode(PleyaSharePairing.randomBytes(12)).replaceAll('=', '');
    final pairSecret = PleyaSharePairing.randomBytes(32);
    final token = _issueToken(pairId);
    _guests[pairId] = {
      'pairId': pairId,
      'secret': base64Encode(pairSecret),
      'name': (body['deviceName'] as String?)?.trim() ?? 'Pleya',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _persistGuests();
    _rotateCode();
    stdout.writeln('paired guest "${_guests[pairId]!['name']}" from $ip');

    final sessionKey = await PleyaSharePairing.deriveSessionKey(pairingKey, challenge.hostNonce, clientNonce);
    final payload = await PleyaSharePairing.encryptPayload(sessionKey, {
      'pairId': pairId,
      'pairSecret': base64Encode(pairSecret),
      'token': token,
      'name': name,
    });
    return _json(request, {'payload': payload});
  }

  Future<void> _authStart(HttpRequest request) async {
    if (_limiter.isLockedOut(_ip(request))) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final pairId = body['pairId'] as String?;
    final clientNonce = body['clientNonce'] as String?;
    if (pairId == null || clientNonce == null) return _status(request, HttpStatus.badRequest);
    if (!_guests.containsKey(pairId)) return _status(request, HttpStatus.forbidden);
    _pruneChallenges();
    final hostNonce = PleyaSharePairing.randomBytes(32);
    _challenges['auth|$pairId|$clientNonce'] = (hostNonce: hostNonce, issued: DateTime.now());
    return _json(request, {'hostNonce': base64Encode(hostNonce)});
  }

  Future<void> _authComplete(HttpRequest request) async {
    final ip = _ip(request);
    if (_limiter.isLockedOut(ip)) return _status(request, HttpStatus.tooManyRequests);
    final body = await _body(request);
    final pairId = body['pairId'] as String?;
    final clientNonceB64 = body['clientNonce'] as String?;
    final authTag = body['authTag'] as String?;
    final guest = pairId == null ? null : _guests[pairId];
    final challenge =
        (pairId == null || clientNonceB64 == null) ? null : _challenges.remove('auth|$pairId|$clientNonceB64');
    if (guest == null || challenge == null || authTag == null || clientNonceB64 == null) {
      return _status(request, HttpStatus.badRequest);
    }
    final clientNonce = base64Decode(clientNonceB64);
    final secret = base64Decode(guest['secret'] as String);
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
    final token = _issueToken(pairId!);
    final sessionKey = await PleyaSharePairing.deriveSessionKey(secret, challenge.hostNonce, clientNonce);
    final payload = await PleyaSharePairing.encryptPayload(sessionKey, {'token': token, 'name': name});
    return _json(request, {'payload': payload});
  }

  String _issueToken(String pairId) {
    _tokens.removeWhere((_, v) => v == pairId);
    final token = base64UrlEncode(PleyaSharePairing.randomBytes(32)).replaceAll('=', '');
    _tokens[token] = pairId;
    return token;
  }

  Future<void> _library(HttpRequest request, String pairId) async {
    final watch = _loadWatch(pairId);
    final items = <Map<String, Object?>>[];
    for (final item in _catalog) {
      final json = Map<String, Object?>.from(item);
      final state = watch[item['id']];
      if (state != null) {
        json['viewOffsetMs'] = (state['p'] as num?)?.toInt() ?? 0;
        json['viewCount'] = (state['w'] as bool? ?? false) ? 1 : 0;
      }
      items.add(json);
    }
    return _json(request, {'v': version, 'name': name, 'items': items});
  }

  Future<void> _watch(HttpRequest request, String pairId) async {
    final body = await _body(request);
    final itemId = body['itemId'] as String?;
    if (itemId == null) return _status(request, HttpStatus.badRequest);
    final state = _loadWatch(pairId);
    state[itemId] = {'p': (body['progressMs'] as num?)?.toInt() ?? 0, 'w': body['watched'] as bool? ?? false};
    _persistWatch(pairId, state);
    return _json(request, {'ok': true});
  }

  Future<void> _stream(HttpRequest request, String encodedId) async {
    final String id;
    try {
      final padded = encodedId.padRight((encodedId.length + 3) & ~3, '=');
      id = utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return _status(request, HttpStatus.badRequest);
    }
    if (!_catalogById.containsKey(id)) return _status(request, HttpStatus.notFound);
    final file = File(id);
    if (!file.existsSync()) return _status(request, HttpStatus.notFound);

    final total = file.lengthSync();
    final response = request.response;
    int start = 0;
    int end = total - 1;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    var partial = false;
    if (rangeHeader != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(rangeHeader.trim());
      if (match != null && (match.group(1)!.isNotEmpty || match.group(2)!.isNotEmpty)) {
        if (match.group(1)!.isEmpty) {
          final n = int.parse(match.group(2)!);
          if (n == 0) return _range416(request, total);
          start = total - n < 0 ? 0 : total - n;
        } else {
          start = int.parse(match.group(1)!);
          if (match.group(2)!.isNotEmpty) end = int.parse(match.group(2)!);
          if (end > total - 1) end = total - 1;
          if (start > end || start >= total) return _range416(request, total);
        }
        partial = true;
      }
    }

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.parse(_contentType(id));
    if (partial) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    response.contentLength = end - start + 1;
    try {
      await response.addStream(file.openRead(start, end + 1));
    } catch (_) {
      // Client seeks/disconnects abort the socket mid-stream — routine.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _range416(HttpRequest request, int total) async {
    request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
    await request.response.close();
  }

  String _contentType(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    return switch (ext) {
      'mp4' || 'm4v' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      'mov' => 'video/quicktime',
      'ts' || 'm2ts' => 'video/mp2t',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _status(HttpRequest request, int code) async {
    request.response.statusCode = code;
    await request.response.close();
  }
}
