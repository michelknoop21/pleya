import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import 'automation_event_log.dart';
import 'automation_focus_log.dart';
import 'automation_registry.dart';
import 'automation_screen.dart';
import 'automation_wait.dart';
import 'pleya_verify.dart';

/// `PLEYA_VERIFY_PORT` dart-define, or the first free port from this one
/// (walked upward) when unset/occupied. Matches the fixed-port-plus-walk
/// contract `scripts/tvos_sim.sh` already expects.
const int _kBasePort = int.fromEnvironment('PLEYA_VERIFY_PORT', defaultValue: 47317);
const int _kPortWalkAttempts = 10;

/// Bearer token required on `Authorization` when `PLEYA_VERIFY_TOKEN` is set
/// at build time (used on shared CI runners). Empty locally.
const String _kToken = String.fromEnvironment('PLEYA_VERIFY_TOKEN');

const String _kGitCommit = String.fromEnvironment('GIT_COMMIT');

/// Loopback-only HTTP control plane for Pleya Verify. Only ever constructed
/// when [kPleyaVerify] is true — see [AutomationBootstrap].
///
/// Authentication contract (see pleya_verify/contract/verify_api_v1.md):
///  - `X-Pleya-Verify: <kAutomationProtocolMarker>` is always the protocol
///    marker, never a secret. Missing/wrong → 403.
///  - `Host` must be a loopback host. Wrong → 403.
///  - `Authorization: Bearer <token>` is the actual auth, only enforced when
///    `PLEYA_VERIFY_TOKEN` was set at build time. Missing/wrong → 401.
class AutomationServer {
  HttpServer? _server;
  final DateTime _bootedAt = DateTime.now();

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    HttpServer? bound;
    var attemptPort = _kBasePort;
    for (var i = 0; i < _kPortWalkAttempts && bound == null; i++, attemptPort++) {
      try {
        bound = await HttpServer.bind(InternetAddress.loopbackIPv4, attemptPort);
      } on SocketException {
        // Port taken — try the next one.
      }
    }
    if (bound == null) {
      appLogger.w('[PleyaVerify] no free port in $_kBasePort..${_kBasePort + _kPortWalkAttempts - 1}');
      return;
    }
    _server = bound;
    bound.listen(_handle, onError: (Object e) => appLogger.d('[PleyaVerify] server error', error: e));
    await _writeDiscoveryFile(bound.port);
    // NSLog-friendly marker line, in the same style as the tvOS press-hook
    // marker AppDelegate.swift logs on boot — scripts/tvos_sim.sh greps for
    // exactly this kind of line.
    appLogger.i('[PleyaVerify] listening on 127.0.0.1:${bound.port}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _writeDiscoveryFile(int port) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory('${tempDir.path}/pleya-verify');
      await dir.create(recursive: true);
      final file = File('${dir.path}/instance.json');
      await file.writeAsString(jsonEncode({'port': port, 'protocolVersion': 1, 'pid': pid}));
    } catch (e) {
      appLogger.d('[PleyaVerify] could not write discovery file', error: e);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await _route(request);
    } catch (e, st) {
      // A route handler that throws must still answer — an unanswered
      // request hangs the caller forever instead of failing fast.
      appLogger.d('[PleyaVerify] route handler error', error: e, stackTrace: st);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _route(HttpRequest request) async {
    final host = request.headers.host ?? '';
    if (!(host.startsWith('127.0.0.1') || host.startsWith('localhost'))) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (request.headers.value('X-Pleya-Verify') != kAutomationProtocolMarker) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (_kToken.isNotEmpty) {
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth != 'Bearer $_kToken') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
    }

    switch (request.uri.path) {
      case '/v1/health':
        await _respondJson(request, {
          'protocolVersion': 1,
          'commit': _kGitCommit,
          'platform': defaultTargetPlatform.name,
          'port': port,
          'booted': true,
          'bootedAt': _bootedAt.toIso8601String(),
        });
      case '/v1/ui_tree':
        await _respondJson(request, AutomationRegistry.instance.snapshot());
      case '/v1/focus':
        await _respondJson(request, AutomationRegistry.instance.focusSnapshot() ?? {'focused': false});
      case '/v1/screens':
        await _respondJson(request, {'screens': AutomationScreenRegistry.instance.snapshot()});
      case '/v1/focus/log':
        await _respondJson(request, {
          'entries': [for (final e in AutomationFocusLog.instance.since(_sinceParam(request))) e.toJson()],
        });
      case '/v1/events':
        await _respondJson(request, {
          'events': [for (final e in AutomationEventLog.instance.since(_sinceParam(request))) e.toJson()],
        });
      case '/v1/wait':
        final body = await _readJsonBody(request);
        await _respondJson(request, await const AutomationWait().resolve(body));
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  int _sinceParam(HttpRequest request) => int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;

  Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, Object?>() : const {};
  }

  Future<void> _respondJson(HttpRequest request, Map<String, Object?> body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}
