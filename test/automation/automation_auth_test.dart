import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pleya/automation/automation_server.dart';
import 'package:pleya/automation/pleya_verify.dart';

/// A minimal `path_provider` fake so `AutomationServer._writeDiscoveryFile`
/// has somewhere real to write `instance.json` under `flutter test` (which
/// has no platform channel to answer the real plugin's call). Points at a
/// fresh temp dir per test so runs never see each other's discovery files.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this._tempDir);
  final Directory _tempDir;

  @override
  Future<String?> getTemporaryPath() async => _tempDir.path;
}

Future<HttpClientResponse> _send(
  int port, {
  String method = 'GET',
  String path = '/v1/health',
  String? host,
  String? marker = kAutomationProtocolMarker,
  String? bearer,
}) async {
  final client = HttpClient();
  final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
  if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
  if (marker != null) request.headers.set('X-Pleya-Verify', marker);
  if (bearer != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  final response = await request.close();
  await response.drain<void>();
  return response;
}

void main() {
  late Directory tempDir;
  late AutomationServer server;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pleya-verify-auth-test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    server = AutomationServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File discoveryFile() => File('${tempDir.path}/pleya-verify/instance.json');

  test('missing X-Pleya-Verify marker is rejected with 403', () async {
    final response = await _send(server.port, marker: null);
    expect(response.statusCode, HttpStatus.forbidden);
  });

  test('wrong X-Pleya-Verify marker is rejected with 403', () async {
    final response = await _send(server.port, marker: 'not-the-marker');
    expect(response.statusCode, HttpStatus.forbidden);
  });

  test('a non-loopback Host is rejected with 403', () async {
    final response = await _send(server.port, host: 'evil.example.com');
    expect(response.statusCode, HttpStatus.forbidden);
  });

  test('a loopback Host on either accepted spelling is not rejected on Host grounds', () async {
    for (final host in ['127.0.0.1:${server.port}', 'localhost:${server.port}']) {
      final response = await _send(server.port, host: host, bearer: server.debugToken);
      expect(response.statusCode, isNot(HttpStatus.forbidden), reason: 'Host: $host should pass the loopback check');
    }
  });

  // The control plane is fail-closed unconditionally now — there is no
  // "token configured" branch to gate these on. A control plane that could
  // ever start with auth optional or empty is exactly what this closes.
  group('per-instance Authorization, always required', () {
    test('no Authorization header at all is rejected with 401', () async {
      final response = await _send(server.port, bearer: null);
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('a wrong Bearer token is rejected with 401', () async {
      final response = await _send(server.port, bearer: 'wrong-token');
      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('the correct, freshly-minted per-instance token is accepted', () async {
      final token = server.debugToken;
      expect(token, isNotNull, reason: 'start() must have minted a token by now');
      final response = await _send(server.port, bearer: token);
      expect(response.statusCode, isNot(HttpStatus.unauthorized));
    });

    test('X-Pleya-Verify alone, without a correct Authorization, is still 401', () async {
      // The explicit negative the auth contract calls out: a fully correct
      // protocol marker is never a substitute for the bearer token.
      final response = await _send(server.port, bearer: null);
      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('token lifecycle', () {
    test('two instances never mint the same token', () async {
      final other = AutomationServer();
      await other.start();
      addTearDown(other.stop);

      expect(server.debugToken, isNot(equals(other.debugToken)));
    });

    test('the discovery file carries the token, and it matches what auth actually checks', () async {
      expect(discoveryFile().existsSync(), isTrue);
      final decoded = jsonDecode(discoveryFile().readAsStringSync()) as Map<String, Object?>;
      expect(decoded['token'], server.debugToken);

      final response = await _send(server.port, bearer: decoded['token'] as String);
      expect(response.statusCode, isNot(HttpStatus.unauthorized));
    });

    test('the token never appears in /v1/health', () async {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/v1/health'));
      request.headers.set('X-Pleya-Verify', kAutomationProtocolMarker);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${server.debugToken}');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(body, isNot(contains(server.debugToken!)));
    });

    test('stop() deletes the discovery file, so a leftover token cannot be read by a later launch', () async {
      expect(discoveryFile().existsSync(), isTrue);
      await server.stop();
      expect(discoveryFile().existsSync(), isFalse);
    });
  });
}
