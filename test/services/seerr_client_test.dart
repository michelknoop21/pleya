import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';

import '../test_helpers/prefs.dart';

SeerrSession _session({
  SeerrAuthMode mode = SeerrAuthMode.plex,
  String? cookie = 'connect.sid=abc',
  String? apiKey,
  String? email,
  String? password,
}) {
  return SeerrSession(
    baseUrl: 'https://seerr.example',
    authMode: mode,
    cookie: cookie,
    apiKey: apiKey,
    email: email,
    password: password,
  );
}

http.Response _json(Object body, int status, {Map<String, String> headers = const {}}) {
  return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  group('SeerrConstants.normalizeBaseUrl', () {
    test('adds https scheme when missing', () {
      expect(SeerrConstants.normalizeBaseUrl('seerr.local:5055'), 'https://seerr.local:5055');
    });

    test('keeps an explicit http scheme', () {
      expect(SeerrConstants.normalizeBaseUrl('http://seerr.local:5055'), 'http://seerr.local:5055');
    });

    test('strips trailing slashes and a pasted /api/v1 suffix', () {
      expect(SeerrConstants.normalizeBaseUrl('https://x.example/api/v1/'), 'https://x.example');
      expect(SeerrConstants.normalizeBaseUrl('https://x.example///'), 'https://x.example');
    });

    test('leaves a bare /api reverse-proxy path alone', () {
      expect(SeerrConstants.normalizeBaseUrl('https://x.example/api'), 'https://x.example/api');
    });
  });

  group('SeerrPermission', () {
    test('admin implies every flag', () {
      expect(SeerrPermission.has(SeerrPermission.admin, SeerrPermission.manageRequests), isTrue);
      expect(SeerrPermission.has(SeerrPermission.admin, SeerrPermission.anyRequest4k), isTrue);
    });

    test('non-admin only has explicit flags', () {
      expect(SeerrPermission.has(SeerrPermission.request, SeerrPermission.request), isTrue);
      expect(SeerrPermission.has(SeerrPermission.request, SeerrPermission.manageRequests), isFalse);
    });

    test('anyRequest4k matches each 4k variant', () {
      for (final flag in [SeerrPermission.request4k, SeerrPermission.request4kMovie, SeerrPermission.request4kTv]) {
        expect(SeerrPermission.has(flag, SeerrPermission.anyRequest4k), isTrue);
      }
    });
  });

  group('SeerrRequestStatus/SeerrMediaStatus', () {
    test('unknown media status codes fall back to unknown', () {
      expect(SeerrMediaStatus.fromValue(99), SeerrMediaStatus.unknown);
      expect(SeerrMediaStatus.fromValue(null), SeerrMediaStatus.unknown);
    });
  });

  group('SeerrSession encode/decode', () {
    test('round-trips with protected secrets', () async {
      final session = _session(mode: SeerrAuthMode.local, email: 'a@b.c', password: 'geheim');
      final raw = await session.encode();
      // Secrets never persist in plaintext.
      expect(raw.contains('geheim'), isFalse);
      final decoded = await SeerrSession.decode(raw);
      expect(decoded.baseUrl, session.baseUrl);
      expect(decoded.authMode, SeerrAuthMode.local);
      expect(decoded.cookie, session.cookie);
      expect(decoded.password, 'geheim');
    });

    test('throws on an unrecognized auth_mode', () async {
      final raw = jsonEncode({'base_url': 'https://x', 'auth_mode': 'bogus'});
      await expectLater(SeerrSession.decode(raw), throwsA(anything));
    });
  });

  group('SeerrClient auth & error mapping', () {
    test('401 in cookie mode silently re-auths and retries once', () async {
      var statusCalls = 0;
      var authCalls = 0;
      final client = SeerrClient(
        _session(),
        plexTokenProvider: () async => 'plex-token',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/plex')) {
            authCalls++;
            return _json({'id': 7, 'displayName': 'M'}, 200, headers: {'set-cookie': 'connect.sid=fresh; Path=/'});
          }
          statusCalls++;
          final authed = request.headers['Cookie'] == 'connect.sid=fresh';
          return authed ? _json({'version': '1'}, 200) : _json({'message': 'nope'}, 401);
        }),
      );
      final status = await client.getStatus(force: true);
      expect(status['version'], '1');
      expect(authCalls, 1);
      expect(statusCalls, 2);
      expect(client.session.cookie, 'connect.sid=fresh');
    });

    test('401 with failing re-auth surfaces SeerrException.auth', () async {
      final client = SeerrClient(
        _session(),
        plexTokenProvider: () async => null,
        httpClient: MockClient((request) async => _json({'message': 'unauthorized'}, 401)),
      );
      await expectLater(
        client.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });

    test('apiKey mode sends X-Api-Key and never re-auths on 401', () async {
      var calls = 0;
      final client = SeerrClient(
        _session(mode: SeerrAuthMode.apiKey, cookie: null, apiKey: 'k'),
        httpClient: MockClient((request) async {
          calls++;
          expect(request.headers['X-Api-Key'], 'k');
          return _json({'message': 'unauthorized'}, 401);
        }),
      );
      await expectLater(
        client.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
      expect(calls, 1);
    });

    test('403 maps to forbidden and server message is surfaced on other errors', () async {
      final forbidden = SeerrClient(
        _session(),
        plexTokenProvider: () async => null,
        httpClient: MockClient((request) async => _json({}, 403)),
      );
      await expectLater(
        forbidden.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isForbidden, 'isForbidden', isTrue)),
      );

      final serverError = SeerrClient(
        _session(),
        plexTokenProvider: () async => null,
        httpClient: MockClient((request) async => _json({'message': 'Quota exceeded'}, 409)),
      );
      await expectLater(
        serverError.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.message, 'message', 'Quota exceeded')),
      );
    });

    test('transport failure maps to a network SeerrException', () async {
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async => throw http.ClientException('boom')),
      );
      await expectLater(
        client.getStatus(force: true),
        throwsA(isA<SeerrException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });

    test('getRequests threads requestedBy into the query', () async {
      Uri? seen;
      final client = SeerrClient(
        _session(),
        httpClient: MockClient((request) async {
          seen = request.url;
          return _json({'results': [], 'pageInfo': {'pages': 1}}, 200);
        }),
      );
      await client.getRequests(requestedBy: 42);
      expect(seen!.queryParameters['requestedBy'], '42');

      await client.getRequests();
      expect(seen!.queryParameters.containsKey('requestedBy'), isFalse);
    });
  });
}
