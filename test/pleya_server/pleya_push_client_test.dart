import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

// What a withdrawal may treat as final depends on who answered: Pleya's own
// envelope, or a proxy, WAF or captive portal in front of it.
void main() {
  http.Response envelope(int status, String code) => http.Response(
    jsonEncode({
      'error': {'code': code, 'message': code, 'retryable': false},
    }),
    status,
    headers: {'content-type': 'application/json'},
  );

  PleyaServerClient client(http.Response Function(http.Request request) answer) {
    final fake = PleyaFakeServer();
    final client = PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.srv-1.alice',
        baseUrl: 'https://nas.example.org',
        serverId: 'srv-1',
        serverName: 'Zolder',
        userName: 'alice',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026, 8, 19),
      ),
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.contains('/push-installations') || request.url.path.endsWith('/auth/refresh')) {
          return answer(request);
        }
        return fake.handle(request);
      }),
    );
    addTearDown(client.close);
    return client;
  }

  http.Response refreshed(http.Request request) => http.Response(
    jsonEncode({'access_token': 'at-1', 'refresh_token': 'rt-2', 'token_type': 'bearer', 'expires_in_ms': 900000}),
    200,
    headers: {'content-type': 'application/json'},
  );

  test('a 403 with an auth.* envelope is Pleya rejecting the session', () async {
    final pleya = client(
      (r) => r.url.path.endsWith('/auth/refresh') ? refreshed(r) : envelope(403, 'auth.token_invalid'),
    );
    await expectLater(pleya.removePushInstallation('x'), throwsA(isA<PleyaAuthRejectedException>()));
  });

  test('a bare 403 without an envelope stays a plain auth failure', () async {
    final proxy = client((r) => r.url.path.endsWith('/auth/refresh') ? refreshed(r) : http.Response('<html>', 403));
    final error = await proxy.removePushInstallation('x').then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<MediaServerAuthException>());
    expect(error, isNot(isA<PleyaAuthRejectedException>()));
  });

  test('library.not_found on the DELETE means there is nothing to withdraw', () async {
    final noPush = client(
      (r) => r.url.path.endsWith('/auth/refresh') ? refreshed(r) : envelope(404, 'library.not_found'),
    );
    await noPush.removePushInstallation('x');
  });

  test('a 404 on the refresh is not taken for an absent installation', () async {
    final lost = client((r) => envelope(404, 'library.not_found'));
    await expectLater(lost.removePushInstallation('x'), throwsA(isA<MediaServerException>()));
  });

  test('withdrawing push is one session-wide DELETE on a server that has it', () async {
    final paths = <String>[];
    final current = client((r) {
      if (r.url.path.endsWith('/auth/refresh')) return refreshed(r);
      paths.add('${r.method} ${r.url.path}');
      return http.Response('', 204);
    });
    await current.withdrawPush(knownIds: ['x']);
    expect(paths, ['DELETE /pleya/v1/users/me/push-installations']);
  });

  test('an older server without the route gets the known id instead', () async {
    final paths = <String>[];
    final older = client((r) {
      if (r.url.path.endsWith('/auth/refresh')) return refreshed(r);
      paths.add('${r.method} ${r.url.path}');
      return r.url.path.endsWith('/push-installations') ? envelope(404, 'library.not_found') : http.Response('', 204);
    });
    await older.withdrawPush(knownIds: ['x']);
    expect(paths, ['DELETE /pleya/v1/users/me/push-installations', 'DELETE /pleya/v1/users/me/push-installations/x']);
  });
}
