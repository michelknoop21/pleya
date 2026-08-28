import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_server.dart';
import 'package:pleya/automation/pleya_verify.dart';

/// Whether this test run was launched with
/// `--dart-define=PLEYA_VERIFY_TOKEN=<value>`. `_kToken` in
/// automation_server.dart is a `String.fromEnvironment` const, resolved at
/// compile time — a plain `flutter test` run never sets it, so the
/// `Authorization: Bearer` branch is dead code in that build and cannot be
/// exercised from inside it. The token-gated group below only runs when this
/// file itself was compiled with the define; otherwise it's skipped with an
/// explicit reason rather than silently passing on an untested branch.
const _tokenDefineSet = bool.hasEnvironment('PLEYA_VERIFY_TOKEN');

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
  late AutomationServer server;

  setUp(() async {
    server = AutomationServer();
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

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
      final response = await _send(server.port, host: host);
      expect(response.statusCode, isNot(HttpStatus.forbidden), reason: 'Host: $host should pass the loopback check');
    }
  });

  group('with PLEYA_VERIFY_TOKEN set at build time', () {
    // A correct token is threaded through --dart-define below, but its value
    // has to be a compile-time literal — it cannot be read back from
    // Platform.environment (dart-define never lands there) or interpolated
    // from _tokenDefineSet. Keep this in sync with the --dart-define in the
    // command that runs this file.
    const configuredToken = 'pleya-verify-auth-test-token';

    test(
      'X-Pleya-Verify alone, without Authorization, is rejected with 401',
      () async {
        // The explicit negative the auth contract calls out: a fully correct
        // protocol marker is not a substitute for the Bearer token once one is
        // configured. Missing the marker is 403 (tested above); missing the
        // token with the marker present is a distinct 401.
        final response = await _send(server.port, bearer: null);
        expect(response.statusCode, HttpStatus.unauthorized);
      },
      skip: _tokenDefineSet ? false : 'run with --dart-define=PLEYA_VERIFY_TOKEN=$configuredToken',
    );

    test(
      'a wrong Bearer token is rejected with 401',
      () async {
        final response = await _send(server.port, bearer: 'wrong-token');
        expect(response.statusCode, HttpStatus.unauthorized);
      },
      skip: _tokenDefineSet ? false : 'run with --dart-define=PLEYA_VERIFY_TOKEN=$configuredToken',
    );

    test(
      'the correct Bearer token is accepted',
      () async {
        final response = await _send(server.port, bearer: configuredToken);
        expect(response.statusCode, isNot(HttpStatus.unauthorized));
      },
      skip: _tokenDefineSet ? false : 'run with --dart-define=PLEYA_VERIFY_TOKEN=$configuredToken',
    );
  });
}
