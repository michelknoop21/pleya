import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/plex_sharing_service.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../test_helpers/prefs.dart';

const _machine = 'machine-1';

const _serverXml = '''
<MediaContainer><Server machineIdentifier="machine-1">
  <Section id="9001" key="1" title="Films" type="movie"/>
  <Section id="9002" key="2" title="Series" type="show"/>
</Server></MediaContainer>''';

const _sharedXml = '''
<MediaContainer>
  <SharedServer id="555" userID="77" username="friend" email="f@example.com" allLibraries="0">
    <Section id="9001" key="1" title="Films" shared="1"/>
    <Section id="9002" key="2" title="Series" shared="0"/>
  </SharedServer>
</MediaContainer>''';

const _homeXml = '''
<MediaContainer>
  <User id="1" title="Admin" admin="1" restricted="0"/>
  <User id="88" title="Kid" admin="0" restricted="1"/>
</MediaContainer>''';

class _Fake {
  final requests = <http.Request>[];
  final Map<String, http.Response Function(http.Request)> routes;
  _Fake(this.routes);

  late final service = PlexSharingService(
    accountToken: 'account-token',
    clientIdentifier: 'device-1',
    machineIdentifier: _machine,
    canAdminister: () => allowed,
    http: MediaServerHttpClient(
      client: MockClient((request) async {
        requests.add(request);
        final route = routes['${request.method} ${request.url.path}'];
        if (route == null) return http.Response('not found', 404);
        return route(request);
      }),
    ),
  );
  bool allowed = true;

  List<http.Request> get mutations => requests.where((r) => r.method != 'GET').toList();
}

http.Response _xml(String body) => http.Response(body, 200, headers: {'content-type': 'application/xml'});

Map<String, http.Response Function(http.Request)> _reads({String shared = _sharedXml}) => {
  'GET /api/servers/$_machine': (_) => _xml(_serverXml),
  'GET /api/servers/$_machine/shared_servers': (_) => _xml(shared),
  'GET /api/home/users': (_) => _xml(_homeXml),
};

void main() {
  test('listShares maps plex.tv section ids to library keys and adds unshared Home members', () async {
    final fake = _Fake(_reads());
    final shares = await fake.service.listShares();
    expect(shares, hasLength(2));
    final friend = shares.firstWhere((s) => s.userId == '77');
    expect(friend.name, 'friend');
    expect(friend.homeMember, isFalse);
    expect(friend.libraryIds, ['1']);
    final kid = shares.firstWhere((s) => s.userId == '88');
    expect(kid.homeMember, isTrue);
    expect(kid.managed, isTrue);
    expect(kid.shared, isFalse);
    expect(fake.requests.every((r) => r.headers['X-Plex-Token'] == 'account-token'), isTrue);
  });

  test('create a managed Home user, then share two libraries with it', () async {
    final fake = _Fake({
      ..._reads(),
      'POST /api/home/users': (_) => _xml('<User id="99" title="Gast"/>'),
      'POST /api/servers/$_machine/shared_servers': (_) => _xml('<SharedServer id="600"/>'),
    });
    final id = await fake.service.createManagedHomeUser('Gast');
    expect(id, '99');
    expect(fake.mutations.first.url.queryParameters['title'], 'Gast');

    await fake.service.setShareLibraries(id, allLibraries: false, libraryIds: ['1', '2']);
    final share = fake.mutations.last;
    expect(share.method, 'POST');
    expect(jsonDecode(share.body), {
      'server_id': _machine,
      'shared_server': {
        'library_section_ids': [9001, 9002],
        'invited_id': 99,
      },
      'sharing_settings': <String, dynamic>{},
    });
  });

  test('an existing share is updated with PUT on its shared server id', () async {
    final fake = _Fake({..._reads(), 'PUT /api/servers/$_machine/shared_servers/555': (_) => _xml('<ok/>')});
    await fake.service.setShareLibraries('77', allLibraries: true);
    final put = fake.mutations.single;
    expect(jsonDecode(put.body), {
      'server_id': _machine,
      'shared_server': {
        'library_section_ids': [9001, 9002],
      },
    });
  });

  test('removeShare deletes the share; removeHomeUser deletes the Home user', () async {
    final fake = _Fake({
      ..._reads(),
      'DELETE /api/servers/$_machine/shared_servers/555': (_) => http.Response('', 200),
      'DELETE /api/home/users/88': (_) => http.Response('', 200),
    });
    await fake.service.removeShare('77');
    await fake.service.removeHomeUser('88');
    expect(fake.mutations.map((r) => '${r.method} ${r.url.path}'), [
      'DELETE /api/servers/$_machine/shared_servers/555',
      'DELETE /api/home/users/88',
    ]);
    await expectLater(fake.service.removeHomeUser('1'), throwsStateError);
    expect(fake.mutations, hasLength(2));
  });

  test('an unknown library key throws before any mutating call', () async {
    final fake = _Fake(_reads());
    await expectLater(
      fake.service.setShareLibraries('77', allLibraries: false, libraryIds: ['1', '3']),
      throwsArgumentError,
    );
    expect(fake.mutations, isEmpty);
  });

  test('unexpected or empty bodies and error statuses throw', () async {
    final empty = _Fake({'POST /api/home/users': (_) => _xml('')});
    await expectLater(empty.service.createManagedHomeUser('x'), throwsA(isA<MediaServerHttpException>()));

    final noId = _Fake({'POST /api/home/users': (_) => _xml('<User title="x"/>')});
    await expectLater(noId.service.createManagedHomeUser('x'), throwsA(isA<MediaServerHttpException>()));

    final json = _Fake({
      'GET /api/servers/$_machine': (_) => http.Response('{}', 200, headers: {'content-type': 'application/json'}),
    });
    await expectLater(json.service.listShares(), throwsA(isA<MediaServerHttpException>()));

    final broken = _Fake(_reads(shared: '<MediaContainer><SharedServer id="5"/></MediaContainer>'));
    await expectLater(broken.service.listShares(), throwsA(isA<MediaServerHttpException>()));

    final denied = _Fake({'GET /api/servers/$_machine': (_) => http.Response('nope', 401)});
    await expectLater(denied.service.listShares(), throwsA(isA<MediaServerHttpException>()));
  });

  test('without authority nothing is sent', () async {
    final fake = _Fake(_reads())..allowed = false;
    final forbidden = isA<MediaServerAuthException>().having((e) => e.statusCode, 'statusCode', 403);
    await expectLater(fake.service.listShares(), throwsA(forbidden));
    await expectLater(fake.service.createManagedHomeUser('x'), throwsA(forbidden));
    await expectLater(fake.service.setShareLibraries('77', allLibraries: true), throwsA(forbidden));
    await expectLater(fake.service.removeShare('77'), throwsA(forbidden));
    await expectLater(fake.service.removeHomeUser('88'), throwsA(forbidden));
    expect(fake.requests, isEmpty);
  });

  group('MultiServerManager.plexSharingFor', () {
    setUp(resetSharedPreferencesForTest);
    setUpAll(() {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);
    });

    Future<MultiServerManager> plexManager({required bool owned}) async {
      final m = MultiServerManager();
      addTearDown(m.dispose);
      m.debugRegisterClientForTesting(
        PlexClient.forTesting(
          config: PlexConfig(
            baseUrl: 'https://plex.example',
            token: 'switch-token',
            clientIdentifier: 'account-client',
            product: 'Pleya',
            version: '1.0.0',
          ),
          serverId: ServerId('server-1'),
          serverName: 'Plex',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        online: true,
      );
      await m.refreshTokensForProfile(
        PlexAccountConnection(
          id: 'account-1',
          accountToken: 'account-token',
          clientIdentifier: 'account-client',
          accountLabel: 'Account',
          servers: [
            PlexServer(
              name: 'Plex',
              clientIdentifier: 'server-1',
              accessToken: 'switch-token',
              connections: const [],
              owned: owned,
            ),
          ],
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      return m;
    }

    test('owned server with admin rights yields a service', () async {
      final m = await plexManager(owned: true);
      expect(m.plexSharingFor(ServerId('server-1')), isA<PlexSharingService>());
    });

    test('authority is evaluated live after the service was handed out', () async {
      final m = await plexManager(owned: true);
      final service = m.plexSharingFor(ServerId('server-1'))!;
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      await expectLater(service.listShares(), throwsA(isA<MediaServerAuthException>()));
    });

    test('not owned, restricted, Jellyfin and unknown servers yield null', () async {
      expect((await plexManager(owned: false)).plexSharingFor(ServerId('server-1')), isNull);

      final restricted = await plexManager(owned: true);
      restricted.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      expect(restricted.plexSharingFor(ServerId('server-1')), isNull);

      final jf = MultiServerManager();
      addTearDown(jf.dispose);
      jf.debugRegisterJellyfinClientForTesting(
        JellyfinClient.forTesting(
          connection: JellyfinConnection(
            id: 'jf-machine/u',
            baseUrl: 'https://jf.example.com',
            serverName: 'JF',
            serverMachineId: 'jf-machine',
            userId: 'u',
            userName: 'u',
            accessToken: 't',
            deviceId: 'd',
            isAdministrator: true,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      expect(jf.plexSharingFor(ServerId('jf-machine')), isNull);

      expect((await plexManager(owned: true)).plexSharingFor(ServerId('nope')), isNull);
    });
  });
}
