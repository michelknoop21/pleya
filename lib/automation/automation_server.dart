import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/gestures.dart' show Offset;
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;

import '../main.dart' show rootNavigatorKey;
import '../utils/app_logger.dart';
import '../utils/log_redaction_manager.dart';
import 'automation_event_log.dart';
import 'automation_ids.dart';
import 'automation_input.dart';
import 'automation_overlay.dart';
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

/// One entry per `/v1/*` route, in the same order as the switch below —
/// the single source of truth `_route` checks the HTTP method against
/// before dispatch, so a wrong verb (`POST /v1/health`) 405s instead of
/// running the GET handler.
const Map<String, String> _kRouteMethods = {
  '/v1/health': 'GET',
  '/v1/ui_tree': 'GET',
  '/v1/focus': 'GET',
  '/v1/screens': 'GET',
  '/v1/focus/log': 'GET',
  '/v1/events': 'GET',
  '/v1/automation_ids': 'GET',
  '/v1/viewport': 'GET',
  '/v1/logs': 'GET',
  '/v1/wait': 'POST',
  '/v1/input/key': 'POST',
  '/v1/input/pointer': 'POST',
  '/v1/overlay': 'POST',
  '/v1/screenshot': 'GET',
};

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

    final expectedMethod = _kRouteMethods[request.uri.path];
    if (expectedMethod == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != expectedMethod) {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
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
      case '/v1/automation_ids':
        await _respondJson(request, {'ids': AutomationIds.catalog()});
      case '/v1/viewport':
        await _respondJson(request, _viewportSnapshot());
      case '/v1/logs':
        await _respondJson(request, {
          'entries': [for (final e in MemoryLogOutput.since(_sinceParam(request))) _logEntryToJson(e)],
        });
      case '/v1/wait':
        final body = await _readJsonBody(request);
        await _respondJson(request, await const AutomationWait().resolve(body));
      case '/v1/input/key':
        final body = await _readJsonBody(request);
        await _respondInputResult(request, dispatchAutomationKey(body['key'] as String? ?? ''));
      case '/v1/input/pointer':
        final body = await _readJsonBody(request);
        final x = (body['x'] as num?)?.toDouble();
        final y = (body['y'] as num?)?.toDouble();
        if (x == null || y == null) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        await _respondInputResult(request, dispatchAutomationPointerTap(Offset(x, y)));
      case '/v1/overlay':
        final body = await _readJsonBody(request);
        final current = AutomationOverlayController.instance.value;
        AutomationOverlayController.instance.value = current.copyWith(
          enabled: body['enabled'] as bool?,
          showIds: body['showIds'] as bool?,
          showBounds: body['showBounds'] as bool?,
        );
        await _respondJson(request, {'enabled': AutomationOverlayController.instance.value.enabled});
      case '/v1/screenshot':
        final png = await captureAutomationScreenshot();
        if (png == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
        await request.response.close();
      default:
        // Unreachable unless _kRouteMethods and this switch drift apart —
        // every key above is validated against _kRouteMethods before the
        // switch runs. A Dart string-switch with no matching case completes
        // silently without responding, which would hang the caller forever
        // (the same failure mode _handle's catch-all guards against), so
        // this stays as the guard against that specific drift.
        appLogger.w('[PleyaVerify] route in _kRouteMethods with no switch case: ${request.uri.path}');
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
    }
  }

  int _sinceParam(HttpRequest request) => int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;

  /// Reads `MediaQuery` off [rootNavigatorKey]'s current context — the same
  /// "survives profile-session remounts" seam `_rootPinPrompt` in main.dart
  /// already uses. `{"available": false}` before the app has a mounted
  /// `Navigator` (early boot, or a plain non-widget test), never a crash.
  Map<String, Object?> _viewportSnapshot() {
    BuildContext? context;
    try {
      // Requires a live WidgetsBinding — GlobalKey.currentContext reaches
      // into it internally. Absent before the app has booted (or in a
      // plain, non-widget test); degrade rather than fail the request.
      context = rootNavigatorKey.currentContext;
    } catch (_) {
      return {'available': false};
    }
    if (context == null || !context.mounted) return {'available': false};
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return {'available': false};
    return {
      'available': true,
      'width': mediaQuery.size.width,
      'height': mediaQuery.size.height,
      'devicePixelRatio': mediaQuery.devicePixelRatio,
      'safeArea': {
        'top': mediaQuery.padding.top,
        'right': mediaQuery.padding.right,
        'bottom': mediaQuery.padding.bottom,
        'left': mediaQuery.padding.left,
      },
    };
  }

  /// `message`/`error` already went through [LogRedactionManager.redact] once
  /// at write time (`MemoryAwareLogPrinter.log`); redacting again here is
  /// defense-in-depth against a value registered for redaction after the
  /// entry was already buffered.
  Map<String, Object?> _logEntryToJson(LogEntry entry) => {
    'seq': entry.seq,
    'at': entry.timestamp.toIso8601String(),
    'level': entry.level.name,
    'message': LogRedactionManager.redact(entry.message),
    if (entry.error != null) 'error': LogRedactionManager.redact(entry.error.toString()),
  };

  Future<void> _respondInputResult(HttpRequest request, AutomationInputResult result) async {
    switch (result) {
      case AutomationInputResult.dispatched:
        await _respondJson(request, {'result': 'dispatched'});
      case AutomationInputResult.blockedByNativeSession:
        request.response.statusCode = HttpStatus.conflict;
        await _respondJson(request, {'result': 'blockedByNativeSession'});
      case AutomationInputResult.unknownKey:
        request.response.statusCode = HttpStatus.badRequest;
        await _respondJson(request, {'result': 'unknownKey'});
    }
  }

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
