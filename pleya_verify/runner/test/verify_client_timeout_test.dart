import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya_verify_runner/src/transport/verify_client.dart';
import 'package:test/test.dart';

/// An app that answers every call, but only after [delay]: a loaded
/// simulator, not a dead one.
VerifyClient _slowApp(Duration delay) => VerifyClient(
  baseUri: Uri.parse('http://127.0.0.1:47317'),
  timeout: const Duration(milliseconds: 50),
  signinTimeout: const Duration(seconds: 2),
  httpClient: MockClient((request) async {
    await Future<void>.delayed(delay);
    return http.Response(jsonEncode({'ok': true}), 200);
  }),
);

void main() {
  test('sign_in gets its own longer deadline instead of the 10 s registry-read one (A-01)', () async {
    final client = _slowApp(const Duration(milliseconds: 300));

    final result = await client.signin(baseUrl: 'http://fixture', username: 'u', password: 'p');

    expect(result['ok'], isTrue);
  });

  test('ordinary reads keep the short deadline (A-01)', () async {
    final client = _slowApp(const Duration(milliseconds: 300));

    await expectLater(client.health(), throwsA(isA<VerifyClientTimeoutException>()));
  });
}
