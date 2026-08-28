import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'pleya_fake_server.dart';

/// A real, loopback-only `dart:io` HTTP server around a [PleyaFakeServer]:
/// `/pleya/v1/*` goes straight to [PleyaFakeServer.handle], `/__verify/*` is
/// a separate control plane for scenario setup/mutation/assertion.
///
/// Auth is a single, unambiguous contract: [controlToken] is required as
/// `Authorization: Bearer <token>` on every `/__verify/*` request. The
/// `/pleya/v1/*` surface has its own, entirely separate bearer contract
/// (`at-N` access tokens minted by `POST /auth/refresh`) — the control token
/// is never accepted there, and vice versa.
class FixtureHttpServer {
  FixtureHttpServer({required this.server, required this.controlToken});

  final PleyaFakeServer server;
  final String controlToken;

  HttpServer? _bound;

  int get port => _bound?.port ?? 0;

  static String generateControlToken() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(24, (_) => random.nextInt(256)));
  }

  Future<void> start({int port = 0}) async {
    _bound = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _bound!.listen(_handle);
  }

  Future<void> stop() async {
    await _bound?.close(force: true);
    _bound = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path.startsWith('/__verify')) {
        await _handleControlPlane(request);
      } else {
        await _handlePleyaApi(request);
      }
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': '$e'}));
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePleyaApi(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final outbound = http.Request(request.method, request.requestedUri)..body = body;
    request.headers.forEach((name, values) {
      if (values.isNotEmpty) outbound.headers[name] = values.first;
    });

    http.Response response;
    try {
      response = await server.handle(outbound);
    } on PleyaFakeServerUnreachable {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    request.response.statusCode = response.statusCode;
    response.headers.forEach((name, value) => request.response.headers.set(name, value));
    request.response.add(response.bodyBytes);
    await request.response.close();
  }

  Future<void> _handleControlPlane(HttpRequest request) async {
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth != 'Bearer $controlToken') {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    switch (request.uri.path) {
      case '/__verify/reset':
        server.reset();
        await _json(request, {'ok': true});
      case '/__verify/requests':
        final since = int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
        await _json(request, {'requests': server.requests.skip(since).toList(), 'total': server.requests.length});
      case '/__verify/state':
        await _json(request, {
          'requestCount': server.requests.length,
          'libraryCount': server.libraries.length,
          'itemCount': server.items.length,
          'snapshotHash': _snapshotHash(),
        });
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  /// Deterministic over library/item/watch-state content only — never
  /// `requests` (that's client-driven, not fixture state) — so two runs
  /// that seeded the same fixture and diverged only in *how* the client
  /// asked for it still hash equal.
  String _snapshotHash() {
    final sortedItems = {for (final key in server.items.keys.toList()..sort()) key: server.items[key]};
    final sortedWatchStates = {
      for (final key in server.watchStates.keys.toList()..sort()) key: server.watchStates[key],
    };
    final payload = jsonEncode({'items': sortedItems, 'libraries': server.libraries, 'watchStates': sortedWatchStates});
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
