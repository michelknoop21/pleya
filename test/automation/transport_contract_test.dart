import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_server.dart';
import 'package:pleya/automation/pleya_verify.dart';

/// Parses `### `METHOD /path`` headers out of the transport spec — the
/// minimal shape both this test and the runner-side contract test
/// (pleya_verify/runner/test/transport_contract_test.dart) read, so a new
/// endpoint added to one side without the spec fails here, and one added to
/// the spec without an app-side route fails the same way.
List<({String method, String path})> _specEndpoints(String contents) {
  final pattern = RegExp(r'^### `([A-Z]+) (/\S+)`$', multiLine: true);
  return [for (final m in pattern.allMatches(contents)) (method: m.group(1)!, path: m.group(2)!)];
}

void main() {
  final specFile = File('pleya_verify/contract/verify_api_v1.md');

  test('spec file exists and declares at least /v1/health', () {
    expect(specFile.existsSync(), isTrue, reason: 'pleya_verify/contract/verify_api_v1.md must exist');
    final endpoints = _specEndpoints(specFile.readAsStringSync());
    expect(endpoints, contains((method: 'GET', path: '/v1/health')));
  });

  group('AutomationServer against the spec', () {
    late AutomationServer server;
    late List<({String method, String path})> endpoints;

    setUp(() async {
      endpoints = _specEndpoints(specFile.readAsStringSync());
      server = AutomationServer();
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('every spec endpoint exists with the declared method', () async {
      for (final endpoint in endpoints) {
        final uri = Uri.parse('http://127.0.0.1:${server.port}${endpoint.path}');
        final request = await HttpClient().openUrl(endpoint.method, uri);
        request.headers.set('X-Pleya-Verify', kAutomationProtocolMarker);
        final response = await request.close();
        await response.drain<void>();
        expect(
          response.statusCode,
          isNot(HttpStatus.notFound),
          reason: '${endpoint.method} ${endpoint.path} from the spec has no route on AutomationServer',
        );
      }
    });

    test('a request without X-Pleya-Verify is rejected with 403', () async {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/v1/health');
      final request = await HttpClient().openUrl('GET', uri);
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.forbidden);
    });

    test('/v1/health responds with the documented shape', () async {
      final uri = Uri.parse('http://127.0.0.1:${server.port}/v1/health');
      final request = await HttpClient().openUrl('GET', uri);
      request.headers.set('X-Pleya-Verify', kAutomationProtocolMarker);
      final response = await request.close();
      final body = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      expect(response.statusCode, HttpStatus.ok);
      expect(body['protocolVersion'], 1);
      expect(body['booted'], true);
      expect(body['port'], server.port);
    });
  });
}
