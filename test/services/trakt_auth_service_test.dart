import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/models/trackers/device_code.dart';
import 'package:pleya/services/trackers/device_code_auth_service.dart';
import 'package:pleya/services/trakt/trakt_auth_service.dart';
import 'package:pleya/services/trakt/trakt_constants.dart';

const _code = DeviceCode(
  deviceCode: 'dc',
  userCode: 'UC',
  verificationUrl: 'https://trakt.tv/activate',
  expiresIn: 600,
  interval: 5,
);

TraktAuthService _service(Future<http.Response> Function(http.Request) handler) =>
    TraktAuthService(httpClient: MockClient(handler));

void main() {
  group('TraktAuthService.probe', () {
    test('sends the device code and client id, never a client_secret key', () async {
      late Map<String, dynamic> sent;
      final service = _service((request) async {
        expect(request.url.path, '/oauth/device/token');
        sent = json.decode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 400);
      });

      await service.probe(_code);

      expect(sent.containsKey('client_secret'), isFalse);
      expect(sent['code'], 'dc');
      expect(sent.containsKey('client_id'), isTrue);
      service.dispose();
    });

    test('maps the documented statuses', () async {
      final expected = <int, Type>{
        200: DevicePollSuccess,
        400: DevicePollPending,
        404: DevicePollExpired,
        410: DevicePollExpired,
        409: DevicePollDenied,
        418: DevicePollDenied,
        429: DevicePollSlowDown,
        500: DevicePollPending,
      };
      for (final entry in expected.entries) {
        final service = _service((request) async => http.Response(entry.key == 200 ? '{}' : 'x', entry.key));
        expect((await service.probe(_code)).runtimeType, entry.value, reason: 'HTTP ${entry.key}');
        service.dispose();
      }
    });

    test('a refused client id is a hard failure, not a silent pending', () async {
      for (final status in [401, 422]) {
        final service = _service((request) async => http.Response('refused', status));
        await expectLater(service.probe(_code), throwsA(isA<DeviceCodeAuthFlowException>()), reason: 'HTTP $status');
        service.dispose();
      }
    });
  });

  test('isConfigured needs a client id and nothing else', () {
    expect(TraktConstants.configuredFor('abc'), isTrue);
    expect(TraktConstants.configuredFor(''), isFalse);
  });
}
