import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/media_server_http_client.dart';

void main() {
  group('PlexAuthService', () {
    test('getUserProfile accepts a text review language without losing audio preferences', () async {
      final client = MediaServerHttpClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'profile': {
                'mediaReviewsLanguages': 'en',
                'defaultAudioLanguages': ['nld'],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.close);
      final auth = PlexAuthService.forTesting(http: client);

      final profile = await auth.getUserProfile('account-token');

      expect(profile.mediaReviewsLanguages, ['en']);
      expect(profile.defaultAudioLanguages, ['nld']);
    });

    for (final status in [401, 403]) {
      test('switchToUser still rejects HTTP $status', () async {
        final client = MediaServerHttpClient(
          client: MockClient(
            (request) async => http.Response('{"errors":[]}', status, headers: {'content-type': 'application/json'}),
          ),
        );
        addTearDown(client.close);
        final auth = PlexAuthService.forTesting(http: client);

        await expectLater(
          auth.switchToUser('home-user', 'account-token', pin: '1234'),
          throwsA(isA<MediaServerHttpException>().having((e) => e.statusCode, 'statusCode', status)),
        );
      });
    }

    for (final admin in [true, false]) {
      for (final languages in <Object?>[
        'en',
        <String>['en', 'nl'],
        null,
      ]) {
        test('switchToUser parses review languages $languages for homeAdmin=$admin', () async {
          final client = MediaServerHttpClient(
            client: MockClient((request) async {
              expect(request.url.path, '/api/v2/home/users/home-user/switch');
              return http.Response(
                jsonEncode(_userSwitchJson(admin: admin, reviewLanguages: languages)),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          addTearDown(client.close);
          final auth = PlexAuthService.forTesting(http: client);

          final user = await auth.switchToUser('home-user', 'account-token', pin: '1234');

          expect(user.authToken, 'user-token');
          expect(user.homeAdmin, admin);
          expect(user.protected, isTrue);
          expect(user.profile.mediaReviewsLanguages, languages is String ? [languages] : languages);
          expect(user.profile.defaultAudioLanguages, ['nld']);
          expect(user.profile.defaultSubtitleLanguages, ['eng']);
        });
      }
    }

    test('fetchServers retries resources through plex.tv after clients host transport failure', () async {
      final hosts = <String>[];
      final client = MediaServerHttpClient(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          if (request.url.host == 'clients.plex.tv') {
            throw http.ClientException('DNS failed', request.url);
          }
          return http.Response(jsonEncode([_serverJson()]), 200, headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(client.close);
      final auth = PlexAuthService.forTesting(http: client);

      final servers = await auth.fetchServers('token');

      expect(hosts, ['clients.plex.tv', 'plex.tv']);
      expect(servers.single.clientIdentifier, 'srv-1');
    });

    test('fetchServers does not retry canonical host for HTTP auth failures', () async {
      final hosts = <String>[];
      final client = MediaServerHttpClient(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response('{"errors":[]}', 401, headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(client.close);
      final auth = PlexAuthService.forTesting(http: client);

      await expectLater(
        auth.fetchServers('bad-token'),
        throwsA(isA<MediaServerHttpException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(hosts, ['clients.plex.tv']);
    });

    /// A resource Plex lists but this client cannot use, no access token, no
    /// parseable connection, is dropped so the servers that *are* usable
    /// still bind. Dropping it without a word is the problem: the account has
    /// two servers, the app shows one, and every surface downstream (the
    /// sidebar, the source filter of Films and Series) honestly reports the
    /// one server it was given. Nothing in the log says the second existed.
    test('fetchServers names each resource it drops, instead of losing it silently', () async {
      MemoryLogOutput.clearLogs();
      final client = MediaServerHttpClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode([_serverJson(), _serverJson(name: 'Zolder', id: 'srv-2', accessToken: null)]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.close);
      final auth = PlexAuthService.forTesting(http: client);

      final servers = await auth.fetchServers('token');

      // The usable server still binds, one bad resource must not take the
      // account down with it.
      expect(servers.map((s) => s.clientIdentifier), ['srv-1']);

      final warnings = MemoryLogOutput.getLogs().map((e) => e.message).join('\n');
      expect(warnings, contains('Zolder'));
      expect(warnings, contains('srv-2'));
    });

    /// The label is built by hand rather than by dumping the resource map,
    /// because that map carries `accessToken`. A log line the user is asked to
    /// paste into an issue must not be the thing that leaks their token.
    test('fetchServers never puts a resource access token in the log', () async {
      MemoryLogOutput.clearLogs();
      final client = MediaServerHttpClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode([
              _serverJson(name: 'Zolder', id: 'srv-2', accessToken: 'super-secret-token', connections: const []),
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.close);
      final auth = PlexAuthService.forTesting(http: client);

      await expectLater(auth.fetchServers('token'), throwsA(isA<ServerParsingException>()));

      final logged = MemoryLogOutput.getLogs().map((e) => '${e.message} ${e.error ?? ''}').join('\n');
      expect(logged, contains('Zolder'));
      expect(logged, isNot(contains('super-secret-token')));
    });
  });
}

Map<String, dynamic> _userSwitchJson({required bool admin, Object? reviewLanguages}) => {
  'id': 1,
  'uuid': 'home-user',
  'title': 'Test Home user',
  'confirmed': true,
  'joinedAt': 0,
  'emailOnlyAuth': false,
  'hasPassword': true,
  'protected': true,
  'thumb': '',
  'authToken': 'user-token',
  'restricted': !admin,
  'home': true,
  'guest': false,
  'homeSize': 2,
  'homeAdmin': admin,
  'maxHomeSize': 15,
  'twoFactorEnabled': false,
  'backupCodesCreated': false,
  'defaultAudioLanguages': ['nld'],
  'defaultSubtitleLanguages': ['eng'],
  'mediaReviewsLanguages': reviewLanguages,
};

Map<String, dynamic> _serverJson({
  String name = 'Home Server',
  String id = 'srv-1',
  String? accessToken = 'server-token',
  List<Map<String, dynamic>>? connections,
}) => {
  'name': name,
  'clientIdentifier': id,
  'accessToken': ?accessToken,
  'owned': true,
  'provides': 'server',
  'connections':
      connections ??
      const [
        {
          'protocol': 'https',
          'address': '192.168.1.3',
          'port': 32400,
          'uri': 'https://192-168-1-3.machine.plex.direct:32400',
          'local': true,
          'relay': false,
          'IPv6': false,
        },
      ],
};
