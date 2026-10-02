import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/services/jellyfin_client.dart';

JellyfinConnection _connection({required bool emby}) => JellyfinConnection(
  id: 'srv/admin',
  baseUrl: 'https://media.example.com',
  serverName: 'Home',
  serverMachineId: emby ? 'emby-srv' : 'jf-srv',
  userId: 'admin',
  userName: 'admin',
  accessToken: 'tok',
  deviceId: 'dev',
  isAdministrator: true,
  isEmby: emby,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A policy as the server returns it, with fields Pleya does not know about.
Map<String, dynamic> _policy() => {
  'IsAdministrator': false,
  'IsDisabled': false,
  'EnableAllFolders': true,
  'EnabledFolders': <String>[],
  'BlockedMediaFolders': ['blocked-1'],
  'AuthenticationProviderId': 'Auth.Default',
  'PasswordResetProviderId': 'Reset.Default',
  'ExcludedSubFolders': ['sub-1'],
  'SomeFutureField': {'kept': true},
};

void main() {
  late List<http.Request> requests;
  late Map<String, http.Response Function(http.Request r)> routes;

  JellyfinClient client({required bool emby, bool admin = true}) {
    requests = [];
    final c = JellyfinClient.forTesting(
      connection: _connection(emby: emby),
      httpClient: MockClient((request) async {
        requests.add(request);
        final route = routes['${request.method} ${request.url.path}'];
        return route == null ? http.Response('', 404) : route(request);
      }),
    );
    c.canAdministerServer = () => admin;
    addTearDown(c.close);
    return c;
  }

  setUp(() => routes = {});
  tearDown(embyServerIds.clear);

  Iterable<String> calls() => requests.map((r) => '${r.method} ${r.url.path}');

  group('Jellyfin', () {
    test('scanLibrary posts a default refresh without a body', () async {
      routes['POST /Items/lib-1/Refresh'] = (_) => http.Response('', 204);
      await client(emby: false).scanLibrary('lib-1');
      final r = requests.single;
      expect(r.url.queryParameters, {
        'metadataRefreshMode': 'Default',
        'imageRefreshMode': 'Default',
        'replaceAllMetadata': 'false',
        'replaceAllImages': 'false',
      });
      expect(r.body, isEmpty);
    });

    test('refreshItemMetadata posts a full refresh', () async {
      routes['POST /Items/item-1/Refresh'] = (_) => http.Response('', 204);
      await client(emby: false).refreshItemMetadata('item-1');
      expect(requests.single.url.queryParameters['metadataRefreshMode'], 'FullRefresh');
      expect(requests.single.url.queryParameters.containsKey('Recursive'), isFalse);
    });

    test('listJobs maps scheduled tasks and drops hidden ones', () async {
      routes['GET /ScheduledTasks'] = (_) => _json([
        {'Id': 't1', 'Name': 'Scan', 'State': 'Running', 'CurrentProgressPercentage': 42.0},
        {
          'Id': 't2',
          'Name': 'Trickplay',
          'State': 'Idle',
          'LastExecutionResult': {'Status': 'Failed', 'ErrorMessage': 'boom', 'EndTimeUtc': '2026-10-01T10:00:00Z'},
        },
        {'Id': 't3', 'Name': 'Hidden', 'State': 'Idle', 'IsHidden': true},
        {
          'Id': 't4',
          'Name': 'Cleanup',
          'State': 'Idle',
          'LastExecutionResult': {'Status': 'Completed'},
        },
      ]);
      final jobs = await client(emby: false).listJobs();
      expect(jobs.map((j) => j.id), ['t1', 't2', 't4']);
      expect(jobs[0].state, ServerJobState.running);
      expect(jobs[0].progress, closeTo(0.42, 1e-9));
      expect(jobs[0].cancellable, isTrue);
      expect(jobs[0].retryable, isFalse);
      expect(jobs[1].state, ServerJobState.failed);
      expect(jobs[1].error, 'boom');
      expect(jobs[1].updatedAt, DateTime.utc(2026, 10, 1, 10));
      expect(jobs[1].retryable, isTrue);
      expect(jobs[1].progress, isNull);
      expect(jobs[2].state, ServerJobState.succeeded);
    });

    test('retry starts and cancel stops a task', () async {
      routes['POST /ScheduledTasks/Running/t1'] = (_) => http.Response('', 204);
      routes['DELETE /ScheduledTasks/Running/t1'] = (_) => http.Response('', 204);
      final c = client(emby: false);
      await c.retryJob('t1');
      await c.cancelJob('t1');
      expect(calls(), ['POST /ScheduledTasks/Running/t1', 'DELETE /ScheduledTasks/Running/t1']);
    });

    test('listUsers maps role, disabled and folders from /Users', () async {
      routes['GET /Users'] = (_) => _json([
        {
          'Id': 'u1',
          'Name': 'Admin',
          'Policy': {'IsAdministrator': true, 'EnableAllFolders': true},
        },
        {
          'Id': 'u2',
          'Name': 'Kid',
          'Policy': {
            'IsDisabled': true,
            'EnableAllFolders': false,
            'EnabledFolders': ['lib-1'],
          },
        },
      ]);
      final users = await client(emby: false).listUsers();
      expect(users[0].role, ServerUserRole.admin);
      expect(users[0].allLibraries, isTrue);
      expect(users[1].role, ServerUserRole.member);
      expect(users[1].disabled, isTrue);
      expect(users[1].libraryIds, ['lib-1']);
      expect(calls(), ['GET /Users']);
    });

    test('createUser sends the password in the create call', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New', 'Policy': _policy()});
      routes['GET /Users/u9'] = (_) => _json({'Id': 'u9', 'Policy': _policy()});
      routes['POST /Users/u9/Policy'] = (_) => http.Response('', 204);
      final user = await client(emby: false).createUser(name: 'New', password: 'pw');
      expect(jsonDecode(requests.first.body), {'Name': 'New', 'Password': 'pw'});
      expect(user.id, 'u9');
      expect(user.role, ServerUserRole.member);
      expect(user.allLibraries, isFalse);
    });

    test('createUser closes the default access to every library', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New'});
      routes['GET /Users/u9'] = (_) => _json({'Id': 'u9', 'Policy': _policy()});
      routes['POST /Users/u9/Policy'] = (_) => http.Response('', 204);
      await client(emby: false).createUser(name: 'New');
      expect(calls(), ['POST /Users/New', 'GET /Users/u9', 'POST /Users/u9/Policy']);
      final policy = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(policy['EnableAllFolders'], isFalse);
      expect(policy['EnabledFolders'], isEmpty);
    });

    test('createUser sets the requested library in the same policy write', () async {
      routes['GET /Library/VirtualFolders'] = (_) => _json([
        {'Name': 'Kids', 'ItemId': 'kids1111'},
      ]);
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'Sam'});
      routes['GET /Users/u9'] = (_) => _json({'Id': 'u9', 'Policy': _policy()});
      routes['POST /Users/u9/Policy'] = (_) => http.Response('', 204);
      final user = await client(emby: false).createUser(name: 'Sam', libraryIds: ['kids1111']);
      expect(calls().where((c) => c == 'POST /Users/u9/Policy'), hasLength(1));
      final policy = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(policy['EnableAllFolders'], isFalse);
      expect(policy['EnabledFolders'], ['kids1111']);
      expect(user.libraryIds, ['kids1111']);
    });

    test('an unknown library stops the create before any user exists', () async {
      routes['GET /Library/VirtualFolders'] = (_) => _json([
        {'Name': 'Kids', 'ItemId': 'kids1111'},
      ]);
      await expectLater(
        client(emby: false).createUser(name: 'Sam', libraryIds: ['nope']),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(calls(), ['GET /Library/VirtualFolders']);
    });

    test('a failed lock-down deletes the new user', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New'});
      routes['GET /Users/u9'] = (_) => http.Response('', 500);
      routes['DELETE /Users/u9'] = (_) => http.Response('', 204);
      await expectLater(client(emby: false).createUser(name: 'New'), throwsA(isA<MediaServerHttpException>()));
      expect(calls(), ['POST /Users/New', 'GET /Users/u9', 'DELETE /Users/u9']);
    });

    test('a failed rollback reports the account that is left behind', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New'});
      routes['GET /Users/u9'] = (_) => http.Response('', 500);
      routes['DELETE /Users/u9'] = (_) => http.Response('', 500);
      await expectLater(
        client(emby: false).createUser(name: 'New'),
        throwsA(isA<MediaServerHttpException>().having((e) => e.message, 'message', contains('could not be removed'))),
      );
    });

    test('setUserLibraryAccess replaces the policy, keeping unknown fields', () async {
      routes['GET /Library/VirtualFolders'] = (_) => _json([
        {'Name': 'Films', 'ItemId': 'aaaa1111'},
        {'Name': 'Series', 'ItemId': 'bbbb2222'},
      ]);
      routes['GET /Users/u2'] = (_) => _json({'Id': 'u2', 'Policy': _policy()});
      routes['POST /Users/u2/Policy'] = (_) => http.Response('', 204);
      await client(emby: false).setUserLibraryAccess('u2', allLibraries: false, libraryIds: ['AAAA1111']);
      expect(calls(), ['GET /Library/VirtualFolders', 'GET /Users/u2', 'POST /Users/u2/Policy']);
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body, {
        ..._policy(),
        'EnableAllFolders': false,
        'EnabledFolders': ['aaaa1111'],
        'BlockedMediaFolders': <String>[],
      });
    });

    test('an unknown library id throws before any write', () async {
      routes['GET /Library/VirtualFolders'] = (_) => _json([
        {'ItemId': 'aaaa1111'},
      ]);
      await expectLater(
        client(emby: false).setUserLibraryAccess('u2', allLibraries: false, libraryIds: ['nope']),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(calls().where((c) => c.startsWith('POST')), isEmpty);
    });

    test('deleteUser sends DELETE /Users/{id}', () async {
      routes['DELETE /Users/u2'] = (_) => http.Response('', 204);
      await client(emby: false).deleteUser('u2');
      expect(calls(), ['DELETE /Users/u2']);
    });

    test('an error status throws', () async {
      routes['DELETE /Users/u2'] = (_) => http.Response('', 403);
      await expectLater(client(emby: false).deleteUser('u2'), throwsA(isA<MediaServerHttpException>()));
    });
  });

  group('Emby', () {
    test('scanLibrary adds Recursive and an empty refresh body', () async {
      routes['POST /Items/7/Refresh'] = (_) => http.Response('', 204);
      await client(emby: true).scanLibrary('7');
      final r = requests.single;
      expect(r.url.queryParameters['Recursive'], 'true');
      expect(r.url.queryParameters['metadataRefreshMode'], 'Default');
      expect(jsonDecode(r.body), <String, dynamic>{});
    });

    test('refreshItemMetadata sends a full refresh with a body', () async {
      routes['POST /Items/42/Refresh'] = (_) => http.Response('', 204);
      await client(emby: true).refreshItemMetadata('42');
      expect(requests.single.url.queryParameters['metadataRefreshMode'], 'FullRefresh');
      expect(jsonDecode(requests.single.body), <String, dynamic>{});
    });

    test('listUsers reads /Users/Query and translates folder Guids to app ids', () async {
      routes['GET /Users/Query'] = (_) => _json({
        'Items': [
          {
            'Id': 'u2',
            'Name': 'Kid',
            'Policy': {
              'EnableAllFolders': false,
              'EnabledFolders': ['guid-films', 'guid-gone'],
            },
          },
        ],
        'TotalRecordCount': 1,
      });
      routes['GET /Library/SelectableMediaFolders'] = (_) => _json([
        {'Name': 'Films', 'Id': '7', 'Guid': 'guid-films'},
      ]);
      final users = await client(emby: true).listUsers();
      expect(users.single.libraryIds, ['7']);
      expect(calls(), ['GET /Users/Query', 'GET /Library/SelectableMediaFolders']);
    });

    test('createUser sets the password in a second call', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New'});
      routes['POST /Users/u9/Password'] = (_) => http.Response('', 204);
      routes['GET /Users/u9'] = (_) => _json({'Id': 'u9', 'Policy': _policy()});
      routes['POST /Users/u9/Policy'] = (_) => http.Response('', 204);
      await client(emby: true).createUser(name: 'New', password: 'pw');
      expect(calls(), ['POST /Users/New', 'POST /Users/u9/Password', 'GET /Users/u9', 'POST /Users/u9/Policy']);
      expect(jsonDecode(requests[0].body), {'Name': 'New'});
      expect(jsonDecode(requests[1].body), {'Id': 'u9', 'NewPw': 'pw', 'ResetPassword': false});
    });

    test('createUser without a password sets no password', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New'});
      routes['GET /Users/u9'] = (_) => _json({'Id': 'u9', 'Policy': _policy()});
      routes['POST /Users/u9/Policy'] = (_) => http.Response('', 204);
      await client(emby: true).createUser(name: 'New');
      expect(calls(), ['POST /Users/New', 'GET /Users/u9', 'POST /Users/u9/Policy']);
    });

    test('a failed password call deletes the new user', () async {
      routes['POST /Users/New'] = (_) => _json({'Id': 'u9', 'Name': 'New'});
      routes['POST /Users/u9/Password'] = (_) => http.Response('', 500);
      routes['DELETE /Users/u9'] = (_) => http.Response('', 204);
      await expectLater(
        client(emby: true).createUser(name: 'New', password: 'pw'),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(calls(), ['POST /Users/New', 'POST /Users/u9/Password', 'DELETE /Users/u9']);
    });

    test('setUserLibraryAccess posts folder Guids and leaves BlockedMediaFolders alone', () async {
      routes['GET /Library/SelectableMediaFolders'] = (_) => _json([
        {'Name': 'Films', 'Id': '7', 'Guid': 'guid-films'},
        {'Name': 'Series', 'Id': '8', 'Guid': 'guid-series'},
      ]);
      routes['GET /Users/u2'] = (_) => _json({'Id': 'u2', 'Policy': _policy()});
      routes['POST /Users/u2/Policy'] = (_) => http.Response('', 204);
      await client(emby: true).setUserLibraryAccess('u2', allLibraries: false, libraryIds: ['8']);
      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(body, {
        ..._policy(),
        'EnableAllFolders': false,
        'EnabledFolders': ['guid-series'],
      });
    });

    test('an unmappable library id throws and sends no POST', () async {
      routes['GET /Library/SelectableMediaFolders'] = (_) => _json([
        {'Name': 'Films', 'Id': '7', 'Guid': 'guid-films'},
      ]);
      await expectLater(
        client(emby: true).setUserLibraryAccess('u2', allLibraries: false, libraryIds: ['99']),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(calls(), ['GET /Library/SelectableMediaFolders']);
    });
  });

  test('without administer rights every method refuses before the network', () async {
    for (final emby in [false, true]) {
      final c = client(emby: emby, admin: false);
      final ops = <Future<Object?> Function()>[
        () => c.scanLibrary('1'),
        () => c.refreshItemMetadata('1'),
        c.listJobs,
        () => c.cancelJob('1'),
        () => c.retryJob('1'),
        c.listUsers,
        () => c.createUser(name: 'x'),
        () => c.setUserLibraryAccess('u', allLibraries: true),
        () => c.deleteUser('u'),
      ];
      for (final op in ops) {
        await expectLater(op(), throwsA(isA<MediaServerAuthException>()));
      }
      expect(requests, isEmpty);
    }
  });

  test('capabilities', () {
    final c = client(emby: false);
    expect(c.supportsServerAdministration, isTrue);
    expect(c.createUserRequiresPassword, isFalse);
    expect(c, isA<MediaServerClient>());
  });
}
