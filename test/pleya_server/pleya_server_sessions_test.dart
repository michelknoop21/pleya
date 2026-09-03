import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/models/pleya_server/pleya_wire.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';

/// The client half of DEC-069: a session on a Pleya Server is one device, not
/// one user, and the two fields that make that possible are negotiated rather
/// than assumed.
///
/// The negotiation is not politeness. `LoginRequest` and `SetupRequest` are
/// closed schemas, so a server without `capabilities.sessions` refuses the
/// whole request when it sees `device_id` — the sign-in fails outright instead
/// of quietly landing without a device name.
void main() {
  Map<String, dynamic> infoBody({required bool sessions}) => {
    'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
    'server': {'id': 'srv-1'},
    'capabilities': {
      'browse': true,
      'search': true,
      'artwork': true,
      'watch_state': true,
      'sessions': sessions,
      'users': sessions,
    },
    'auth': {
      'methods': ['password'],
      'setup_required': false,
    },
  };

  Map<String, dynamic> tokenPair() => {
    'access_token': 'access-1',
    'refresh_token': 'refresh-1',
    'token_type': 'bearer',
    'expires_in_ms': 900000,
  };

  http.Response json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

  /// Signs in against a server with or without the capability and returns the
  /// body that went over the wire.
  Future<Map<String, dynamic>> loginBody({required bool serverKnowsSessions}) async {
    Map<String, dynamic>? sent;
    final service = PleyaServerAuthService(
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path == '/pleya/v1/info') return json(infoBody(sessions: serverKnowsSessions));
        expect(request.url.path, '/pleya/v1/auth/login');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json(tokenPair());
      }),
    );
    await service.login(
      baseUrl: 'http://nas.lan:8832',
      username: 'sanne',
      password: 'nog-een-lang-wachtwoord',
      deviceId: 'device-abc',
      deviceName: 'iPhone van Sanne',
    );
    return sent!;
  }

  group('capabilities.sessions', () {
    test('is read off /info', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async => json(infoBody(sessions: true))),
      );
      final info = await service.probe('http://nas.lan:8832');
      expect(info.capabilities.sessions, isTrue);
    });

    test('defaults to false on a server that does not mention it', () async {
      final body = infoBody(sessions: false);
      (body['capabilities'] as Map<String, dynamic>).remove('sessions');
      final service = PleyaServerAuthService(httpClientFactory: () => MockClient((request) async => json(body)));
      final info = await service.probe('http://nas.lan:8832');
      expect(info.capabilities.sessions, isFalse);
    });
  });

  group('device identity on login', () {
    test('goes on the wire when the server advertises sessions', () async {
      final sent = await loginBody(serverKnowsSessions: true);
      expect(sent['device_id'], 'device-abc');
      expect(sent['device_name'], 'iPhone van Sanne');
      expect(sent['username'], 'sanne');
    });

    test('stays off the wire when it does not', () async {
      final sent = await loginBody(serverKnowsSessions: false);
      expect(sent.containsKey('device_id'), isFalse);
      expect(sent.containsKey('device_name'), isFalse);
      // And the request is otherwise exactly what an older client would send,
      // which is what compatibility rule 4 asks for.
      expect(sent.keys.toSet(), {'username', 'password'});
    });

    test('setup negotiates the same way', () async {
      Map<String, dynamic>? sent;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path == '/pleya/v1/info') return json(infoBody(sessions: true));
          expect(request.url.path, '/pleya/v1/auth/setup');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return json(tokenPair());
        }),
      );
      await service.completeSetup(
        baseUrl: 'http://nas.lan:8832',
        setupCode: 'K7M-2QX-91B',
        username: 'michel',
        password: 'een-lang-genoeg-wachtwoord',
        deviceId: 'device-abc',
        deviceName: 'Mac van Michel',
      );
      expect(sent!['device_id'], 'device-abc');
      expect(sent!['device_name'], 'Mac van Michel');
    });

    test('an unavailable device identity is simply omitted', () async {
      Map<String, dynamic>? sent;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path == '/pleya/v1/info') return json(infoBody(sessions: true));
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return json(tokenPair());
        }),
      );
      // Null on both, the way pleyaServerDeviceIdentity answers when the
      // preference store cannot be read. The sign-in still succeeds; what is
      // lost is telling two devices apart, not getting in.
      await service.login(baseUrl: 'http://nas.lan:8832', username: 'sanne', password: 'nog-een-lang-wachtwoord');
      expect(sent!.keys.toSet(), {'username', 'password'});
    });
  });

  group('PleyaCapabilities', () {
    test('unknown says no to sessions', () {
      expect(PleyaCapabilities.unknown.sessions, isFalse);
    });
  });
}
