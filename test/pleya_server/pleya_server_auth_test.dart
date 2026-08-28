import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/models/pleya_server/pleya_wire.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
import 'package:pleya/services/pleya_server_session.dart';

/// Auth is the one part of PS-3 where a mistake is expensive rather than
/// merely visible. The refresh token rotates on every use, so a second
/// concurrent refresh is by definition a reuse, and the server is allowed to
/// revoke the whole chain when it sees one. These tests pin that behaviour.
void main() {
  const infoBody = {
    'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
    'server': {'id': 'srv-1'},
    'capabilities': {'browse': true, 'search': true, 'artwork': true, 'watch_state': false},
    'auth': {
      'methods': ['password'],
      'setup_required': false,
    },
  };

  Map<String, dynamic> tokenPair(String access, String refresh) => {
    'access_token': access,
    'refresh_token': refresh,
    'token_type': 'bearer',
    'expires_in_ms': 900000,
  };

  http.Response json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

  group('normaliseBaseUrl', () {
    test('adds a scheme, drops a trailing slash', () {
      expect(PleyaServerAuthService.normaliseBaseUrl('nas.lan:8832'), 'http://nas.lan:8832');
      expect(PleyaServerAuthService.normaliseBaseUrl('http://nas.lan:8832/'), 'http://nas.lan:8832');
      expect(PleyaServerAuthService.normaliseBaseUrl(' https://pleya.example.com  '), 'https://pleya.example.com');
    });

    test('drops a pasted /pleya/v1 instead of doubling it', () {
      expect(PleyaServerAuthService.normaliseBaseUrl('http://nas.lan:8832/pleya/v1'), 'http://nas.lan:8832');
      expect(PleyaServerAuthService.normaliseBaseUrl('http://nas.lan:8832/pleya/v1/'), 'http://nas.lan:8832');
    });

    test('an empty address is rejected rather than turned into http://', () {
      expect(() => PleyaServerAuthService.normaliseBaseUrl('   '), throwsA(isA<MediaServerUrlException>()));
    });
  });

  group('probe', () {
    test('reads capabilities and the setup flag off /info', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          expect(request.url.path, '/pleya/v1/info');
          return json(infoBody);
        }),
      );
      final info = await service.probe('http://nas.lan:8832');
      expect(info.serverId, 'srv-1');
      expect(info.capabilities.browse, isTrue);
      expect(info.capabilities.watchState, isFalse);
      expect(info.auth.setupRequired, isFalse);
    });

    test('a server that is not Pleya fails as a URL problem, not an auth problem', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async => http.Response('<html>Jellyfin</html>', 200)),
      );
      await expectLater(service.probe('http://nas.lan:8096'), throwsA(isA<MediaServerUrlException>()));
    });

    test('a future major version is refused instead of half-spoken', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient(
          (_) async => json({
            ...infoBody,
            'protocol': {'major': 2, 'feature_level': 4, 'profile': 'full'},
          }),
        ),
      );
      await expectLater(service.probe('http://nas.lan:8832'), throwsA(isA<MediaServerUrlException>()));
    });
  });

  group('login', () {
    test('returns the token pair and the probed info', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody);
          expect(request.url.path, '/pleya/v1/auth/login');
          expect(jsonDecode(request.body), {'username': 'michel', 'password': 'hunter22'});
          return json(tokenPair('at-1', 'rt-1'));
        }),
      );
      final result = await service.login(baseUrl: 'http://nas.lan:8832', username: 'michel', password: 'hunter22');
      expect(result.tokens.accessToken, 'at-1');
      expect(result.tokens.refreshToken, 'rt-1');
      expect(result.userName, 'michel');
      expect(result.baseUrl, 'http://nas.lan:8832');
      expect(result.info.serverId, 'srv-1');
    });

    test('a wrong password is an auth failure with the status attached', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody);
          return json(const {
            'error': {'code': 'auth.invalid_credentials', 'message': 'no', 'retryable': false},
          }, status: 401);
        }),
      );
      await expectLater(
        service.login(baseUrl: 'http://nas.lan:8832', username: 'michel', password: 'wrong'),
        throwsA(isA<MediaServerAuthException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('a rate limit carries retry_after_ms through instead of losing it', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody);
          return json(const {
            'error': {
              'code': 'auth.rate_limited',
              'message': 'Too many attempts',
              'retryable': true,
              'details': {'retry_after_ms': 30000},
            },
          }, status: 429);
        }),
      );
      await expectLater(
        service.login(baseUrl: 'http://nas.lan:8832', username: 'michel', password: 'x'),
        throwsA(isA<PleyaRateLimitedException>().having((e) => e.retryAfterMs, 'retryAfterMs', 30000)),
      );
    });
  });

  group('setup', () {
    test('posts the setup code and yields a token pair', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) {
            return json({
              ...infoBody,
              'auth': {
                'methods': ['password'],
                'setup_required': true,
              },
            });
          }
          expect(request.url.path, '/pleya/v1/auth/setup');
          expect(jsonDecode(request.body), {
            'setup_code': 'ABCD-EFGH',
            'username': 'michel',
            'password': 'a-long-enough-one',
          });
          return json(tokenPair('at-setup', 'rt-setup'));
        }),
      );
      final result = await service.completeSetup(
        baseUrl: 'http://nas.lan:8832',
        setupCode: 'ABCD-EFGH',
        username: 'michel',
        password: 'a-long-enough-one',
      );
      expect(result.tokens.refreshToken, 'rt-setup');
      expect(result.info.auth.setupRequired, isTrue);
    });

    test('a server that already has an owner says so instead of failing generically', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody);
          return json(const {
            'error': {'code': 'auth.setup_already_done', 'message': 'owner exists', 'retryable': false},
          }, status: 409);
        }),
      );
      await expectLater(
        service.completeSetup(baseUrl: 'http://nas.lan:8832', setupCode: 'X', username: 'm', password: 'aaaaaaaa'),
        throwsA(isA<MediaServerAuthException>().having((e) => e.statusCode, 'statusCode', 409)),
      );
    });
  });

  group('PleyaServerSession', () {
    PleyaServerConnection connectionWith(String refreshToken) => PleyaServerConnection(
      id: 'pleyaServer.srv-1',
      baseUrl: 'http://nas.lan:8832',
      serverId: 'srv-1',
      serverName: 'Zolder',
      userName: 'michel',
      refreshToken: refreshToken,
      createdAt: DateTime.utc(2026, 8, 19),
    );

    test('a restart mints an access token from the stored refresh token', () async {
      var refreshCalls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          refreshCalls++;
          expect(request.url.path, '/pleya/v1/auth/refresh');
          expect(jsonDecode(request.body), {'refresh_token': 'rt-stored'});
          return json(tokenPair('at-fresh', 'rt-rotated'));
        }),
      );
      final persisted = <PleyaServerConnection>[];
      final session = PleyaServerSession(
        connection: connectionWith('rt-stored'),
        auth: service,
        onTokensRotated: (connection) async => persisted.add(connection),
      );
      expect(await session.accessToken(), 'at-fresh');
      expect(refreshCalls, 1);
      expect(persisted.single.refreshToken, 'rt-rotated');
      expect(persisted.single.status, ConnectionStatus.online);
    });

    test('a valid access token is reused instead of spending a rotation', () async {
      var refreshCalls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          refreshCalls++;
          return json(tokenPair('at-$refreshCalls', 'rt-$refreshCalls'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith('rt-0'), auth: service);
      expect(await session.accessToken(), 'at-1');
      expect(await session.accessToken(), 'at-1');
      expect(await session.accessToken(), 'at-1');
      expect(refreshCalls, 1);
    });

    test('four concurrent callers cause exactly one refresh', () async {
      var refreshCalls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return json(tokenPair('at-$refreshCalls', 'rt-$refreshCalls'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith('rt-0'), auth: service);
      final tokens = await Future.wait([
        session.accessToken(),
        session.accessToken(),
        session.accessToken(),
        session.accessToken(),
      ]);
      expect(refreshCalls, 1, reason: 'a second concurrent refresh is a reuse and can revoke the chain');
      expect(tokens.toSet(), {'at-1'});
    });

    test('an expired access token triggers exactly one more refresh', () async {
      var refreshCalls = 0;
      var clock = DateTime.utc(2026, 8, 19, 12);
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          refreshCalls++;
          return json(tokenPair('at-$refreshCalls', 'rt-$refreshCalls'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith('rt-0'), auth: service, now: () => clock);
      expect(await session.accessToken(), 'at-1');
      clock = clock.add(const Duration(minutes: 20));
      expect(await session.accessToken(), 'at-2');
      expect(refreshCalls, 2);
    });

    test('a token inside the refresh margin is treated as already expired', () async {
      var refreshCalls = 0;
      var clock = DateTime.utc(2026, 8, 19, 12);
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          refreshCalls++;
          return json(tokenPair('at-$refreshCalls', 'rt-$refreshCalls'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith('rt-0'), auth: service, now: () => clock);
      await session.accessToken();
      // 900000 ms of life, minus a 30 s margin: at 14:50 the token is still
      // valid on paper but not worth starting a request with.
      clock = clock.add(const Duration(minutes: 14, seconds: 50));
      await session.accessToken();
      expect(refreshCalls, 2);
    });

    test('a reused refresh token stops this session and keeps the token on disk', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient(
          (_) async => json(const {
            'error': {'code': 'auth.refresh_token_reused', 'message': 'seen before', 'retryable': false},
          }, status: 401),
        ),
      );
      final persisted = <PleyaServerConnection>[];
      final session = PleyaServerSession(
        connection: connectionWith('rt-dead'),
        auth: service,
        onTokensRotated: (connection) async => persisted.add(connection),
      );
      await expectLater(session.accessToken(), throwsA(isA<PleyaRefreshChainRevokedException>()));
      expect(session.isRevoked, isTrue);
      // "Reused" is also what a rotation whose response was lost looks like,
      // and what a second session spending the same token looks like. Erasing
      // the row on that evidence turned a bad minute into a dead connection
      // that no restart could repair.
      expect(persisted, isEmpty, reason: 'a failed refresh writes nothing at all');
      expect(session.connection.refreshToken, 'rt-dead');
      // A second attempt must not go near the network again.
      await expectLater(session.accessToken(), throwsA(isA<PleyaRefreshChainRevokedException>()));
    });

    test('a fresh session may try the kept token again after a restart', () async {
      var attempt = 0;
      PleyaServerAuthService service() => PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          attempt++;
          // The first launch is told the token was reused; the second gets a
          // real answer, which is what a lost rotation response looks like
          // once the server has moved on.
          if (attempt == 1) {
            return json(const {
              'error': {'code': 'auth.refresh_token_reused', 'message': 'seen before', 'retryable': false},
            }, status: 401);
          }
          return json(tokenPair('at-live', 'rt-next'));
        }),
      );

      final first = PleyaServerSession(connection: connectionWith('rt-kept'), auth: service());
      await expectLater(first.accessToken(), throwsA(isA<PleyaRefreshChainRevokedException>()));

      // Restart: the row still carries the token, so a new session can try it.
      final second = PleyaServerSession(connection: connectionWith('rt-kept'), auth: service());
      expect(await second.accessToken(), 'at-live');
      expect(second.isRevoked, isFalse);
    });

    test('a plain 401 on refresh stops the session without touching the row', () async {
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient(
          (_) async => json(const {
            'error': {'code': 'auth.invalid_token', 'message': 'no', 'retryable': false},
          }, status: 401),
        ),
      );
      final persisted = <PleyaServerConnection>[];
      final session = PleyaServerSession(
        connection: connectionWith('rt-old'),
        auth: service,
        onTokensRotated: (connection) async => persisted.add(connection),
      );
      await expectLater(session.accessToken(), throwsA(isA<MediaServerAuthException>()));
      expect(session.isRevoked, isTrue);
      // A 401 can come from a proxy, a captive portal or a gateway that Pleya
      // never spoke to. None of those is a reason to destroy a credential.
      expect(persisted, isEmpty);
      expect(session.connection.refreshToken, 'rt-old');
    });

    test('an unreachable server does not revoke anything', () async {
      final session = PleyaServerSession(
        connection: connectionWith('rt-fine'),
        auth: PleyaServerAuthService(httpClientFactory: () => MockClient((_) async => throw const SocketishError())),
      );
      await expectLater(session.accessToken(), throwsA(anything));
      expect(session.isRevoked, isFalse, reason: 'offline is not the same as signed out');
    });

    test('a connection with no stored token asks for a sign-in instead of calling refresh', () async {
      var calls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          calls++;
          return json(tokenPair('at', 'rt'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith(''), auth: service);
      await expectLater(session.accessToken(), throwsA(isA<MediaServerAuthException>()));
      expect(calls, 0);
    });

    test('adopting a fresh sign-in avoids a rotation on the first request', () async {
      var calls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          calls++;
          return json(tokenPair('at-refresh', 'rt-refresh'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith(''), auth: service);
      session.adoptTokens(PleyaTokenPair.fromJson(tokenPair('at-login', 'rt-login')));
      expect(await session.accessToken(), 'at-login');
      expect(calls, 0);
      expect(session.connection.refreshToken, 'rt-login');
    });

    test('a failed persist fails the call instead of handing out an unstored token', () async {
      var refreshCalls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          refreshCalls++;
          return json(tokenPair('at-$refreshCalls', 'rt-$refreshCalls'));
        }),
      );
      final session = PleyaServerSession(
        connection: connectionWith('rt-0'),
        auth: service,
        onTokensRotated: (_) async => throw Exception('disk full'),
      );
      await expectLater(session.accessToken(), throwsA(isA<Exception>()));
      expect(session.isRevoked, isFalse, reason: 'a storage failure is not an auth rejection');
      // The rotated token lives on in memory even though the write failed, so
      // a retry spends it rather than presenting the server with something
      // already spent.
      expect(session.connection.refreshToken, 'rt-1');
    });

    test('a retry after a failed persist reuses the unstored token and can still succeed', () async {
      var refreshCalls = 0;
      var failPersist = true;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((request) async {
          refreshCalls++;
          expect(jsonDecode(request.body), {'refresh_token': refreshCalls == 1 ? 'rt-0' : 'rt-1'});
          return json(tokenPair('at-$refreshCalls', 'rt-$refreshCalls'));
        }),
      );
      final persisted = <PleyaServerConnection>[];
      final session = PleyaServerSession(
        connection: connectionWith('rt-0'),
        auth: service,
        onTokensRotated: (connection) async {
          if (failPersist) throw Exception('disk full');
          persisted.add(connection);
        },
      );
      await expectLater(session.accessToken(), throwsA(isA<Exception>()));
      failPersist = false;
      expect(await session.accessToken(), 'at-2');
      expect(refreshCalls, 2);
      expect(persisted.single.refreshToken, 'rt-2');
    });

    test('invalidating the access token forces one refresh and keeps the chain', () async {
      var calls = 0;
      final service = PleyaServerAuthService(
        httpClientFactory: () => MockClient((_) async {
          calls++;
          return json(tokenPair('at-$calls', 'rt-$calls'));
        }),
      );
      final session = PleyaServerSession(connection: connectionWith('rt-0'), auth: service);
      expect(await session.accessToken(), 'at-1');
      session.invalidateAccessToken();
      expect(await session.accessToken(), 'at-2');
      expect(session.isRevoked, isFalse);
    });
  });
}

/// A transport failure that is not an HTTP answer. Named rather than reusing a
/// dart:io type so the test does not depend on the platform's socket errors.
class SocketishError implements Exception {
  const SocketishError();
}
