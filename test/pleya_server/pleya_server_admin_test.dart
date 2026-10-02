import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/services/pleya_server_client.dart';

/// Server administration over Pleya Protocol: every call hits the route the
/// server has, refuses before the network without admin authority, and throws
/// on a failed answer instead of looking like it worked.
void main() {
  const prefix = '/pleya/v1';

  http.Response json(Object? body, {int status = 200}) =>
      http.Response(body == null ? '' : jsonEncode(body), status, headers: const {'content-type': 'application/json'});

  /// Requests other than token minting, as `METHOD path` plus the decoded body.
  late List<(String, Object?)> sent;

  PleyaServerClient client(
    http.Response Function(http.Request request) answer, {
    bool admin = true,
    bool administration = true,
  }) {
    sent = [];
    final c = PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.srv-1',
        baseUrl: 'http://nas.lan:8832',
        serverId: 'srv-1',
        serverName: 'Zolder',
        userName: 'michel',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026, 8, 19),
      ),
      httpClientFactory: () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/auth/refresh')) {
          return json(const {
            'access_token': 'at',
            'refresh_token': 'rt-2',
            'token_type': 'bearer',
            'expires_in_ms': 900000,
          });
        }
        if (path.endsWith('/info')) {
          return json({
            'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
            'server': {'id': 'srv-1'},
            'capabilities': {
              'browse': true,
              'search': true,
              'artwork': true,
              'watch_state': true,
              'administration': administration,
            },
            'auth': {
              'methods': ['password'],
              'setup_required': false,
            },
          });
        }
        sent.add((
          '${request.method} ${path.substring(prefix.length)}',
          request.body.isEmpty ? null : jsonDecode(request.body),
        ));
        return answer(request);
      }),
    );
    c.canAdministerServer = () => admin;
    return c;
  }

  group('supportsServerAdministration', () {
    test('follows the administration capability', () async {
      final on = client((_) => json(null));
      expect(on.supportsServerAdministration, isFalse, reason: 'nothing is known before /info');
      await on.refreshCapabilities();
      expect(on.supportsServerAdministration, isTrue);

      final off = client((_) => json(null), administration: false);
      await off.refreshCapabilities();
      expect(off.supportsServerAdministration, isFalse);
    });
  });

  group('without admin authority', () {
    test('every method refuses before the network', () async {
      final c = client((_) => json(null), admin: false);
      final calls = <Future<Object?> Function()>[
        () => c.scanLibrary('lib-1'),
        () => c.listJobs(),
        () => c.cancelJob('job-1'),
        () => c.retryJob('job-1'),
        () => c.listUsers(),
        () => c.createUser(name: 'kim', password: 'secret123'),
        () => c.setUserLibraryAccess('u-2', allLibraries: true),
        () => c.deleteUser('u-2'),
      ];
      for (final call in calls) {
        await expectLater(call(), throwsA(isA<MediaServerAuthException>()));
      }
      expect(sent, isEmpty);
    });
  });

  group('scans and jobs', () {
    test('scanLibrary posts the scan route', () async {
      final c = client((_) => json(const {'id': 'scan-1'}, status: 202));
      await c.scanLibrary('lib-1');
      expect(sent, [('POST /libraries/lib-1/scan', null)]);
    });

    test('listJobs maps states, and an unknown state stays unknown', () async {
      final c = client(
        (_) => json({
          'items': [
            {
              'id': 'j1',
              'kind': 'scan_library',
              'state': 'running',
              'created_at': '2026-09-30T10:00:00Z',
              'finished_at': null,
              'last_error': null,
              'library_id': 'lib-1',
            },
            {
              'id': 'j2',
              'kind': 'scan_library',
              'state': 'failed',
              'created_at': '2026-09-30T10:00:00Z',
              'finished_at': '2026-09-30T10:05:00Z',
              'last_error': 'disk gone',
            },
            {'id': 'j3', 'kind': 'thumbs', 'state': 'paused', 'created_at': '2026-09-30T10:00:00Z'},
          ],
          'next_cursor': null,
        }),
      );
      final jobs = await c.listJobs();
      expect(sent.single.$1, 'GET /jobs');
      expect(jobs.map((j) => j.state), [ServerJobState.running, ServerJobState.failed, ServerJobState.unknown]);
      expect(jobs[0].libraryId, 'lib-1');
      expect(jobs[0].cancellable, isTrue);
      expect(jobs[0].retryable, isFalse);
      expect(jobs[1].error, 'disk gone');
      expect(jobs[1].retryable, isTrue);
      expect(jobs[1].updatedAt, DateTime.utc(2026, 9, 30, 10, 5));
      expect(jobs[2].cancellable || jobs[2].retryable, isFalse);
    });

    test('cancel and retry post their routes', () async {
      final c = client((_) => json(const {'id': 'j1'}));
      await c.cancelJob('j1');
      await c.retryJob('j1');
      expect(sent.map((r) => r.$1), ['POST /jobs/j1/cancel', 'POST /jobs/j1/retry']);
    });

    test('an error status throws', () async {
      final c = client(
        (_) => json(const {
          'error': {'code': 'job.not_cancellable', 'message': 'finished', 'retryable': false},
        }, status: 409),
      );
      await expectLater(
        c.cancelJob('j1'),
        throwsA(
          isA<MediaServerHttpException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', 'job.not_cancellable'),
        ),
      );
    });

    test('the 404 a non-admin gets throws too', () async {
      final c = client(
        (_) => json(const {
          'error': {'code': 'auth.user_not_found', 'message': 'not found', 'retryable': false},
        }, status: 404),
      );
      await expectLater(c.listJobs(), throwsA(isA<MediaServerHttpException>()));
    });
  });

  group('users', () {
    test('listUsers maps roles; owner and admin see every library', () async {
      final c = client(
        (_) => json(const {
          'items': [
            {'id': 'u1', 'username': 'michel', 'role': 'owner'},
            {'id': 'u2', 'username': 'anna', 'role': 'admin'},
            {'id': 'u3', 'username': 'kim', 'role': 'member'},
            {'id': 'u4', 'username': 'tim', 'role': 'restricted'},
            {'id': 'u5', 'username': 'x', 'role': 'superuser'},
          ],
        }),
      );
      final users = await c.listUsers();
      expect(sent.single.$1, 'GET /users');
      expect(users.map((u) => u.role), [
        ServerUserRole.owner,
        ServerUserRole.admin,
        ServerUserRole.member,
        ServerUserRole.restricted,
        ServerUserRole.unknown,
      ]);
      expect(users.map((u) => u.allLibraries), [true, true, false, false, false]);
      expect(users[2].name, 'kim');
    });

    test('createUser always sends role member', () async {
      final c = client((_) => json(const {'id': 'u9', 'username': 'kim', 'role': 'member'}));
      final user = await c.createUser(name: 'kim', password: 'secret123');
      expect(sent.single.$1, 'POST /users');
      expect(sent.single.$2, {'username': 'kim', 'password': 'secret123', 'role': 'member'});
      expect(user.id, 'u9');
      expect(user.role, ServerUserRole.member);
      expect(c.createUserRequiresPassword, isTrue);
    });

    test('createUser refuses without a password before the network', () async {
      final c = client((_) => json(null));
      await expectLater(c.createUser(name: 'kim'), throwsArgumentError);
      await expectLater(c.createUser(name: 'kim', password: ''), throwsArgumentError);
      expect(sent, isEmpty);
    });

    test('setUserLibraryAccess grants view on the given libraries', () async {
      final c = client((_) => json(const {'items': []}));
      await c.setUserLibraryAccess('u3', allLibraries: false, libraryIds: ['lib-1', 'lib-2']);
      expect(sent.single.$1, 'PUT /users/u3/permissions');
      expect(sent.single.$2, {
        'permissions': [
          {'library_id': 'lib-1', 'permission': 'view'},
          {'library_id': 'lib-2', 'permission': 'view'},
        ],
      });
    });

    test('all libraries becomes one view grant per current library', () async {
      final c = client((request) {
        if (request.method == 'GET') {
          return json(const {
            'items': [
              {'id': 'lib-1', 'title': 'Films', 'kind': 'movies', 'item_count': 3},
              {'id': 'lib-2', 'title': 'Series', 'kind': 'shows', 'item_count': 1},
            ],
          });
        }
        return json(const {'items': []});
      });
      await c.setUserLibraryAccess('u3', allLibraries: true);
      expect(sent.map((r) => r.$1), ['GET /libraries', 'PUT /users/u3/permissions']);
      expect(sent.last.$2, {
        'permissions': [
          {'library_id': 'lib-1', 'permission': 'view'},
          {'library_id': 'lib-2', 'permission': 'view'},
        ],
      });
    });

    test('deleteUser deletes the user', () async {
      final c = client((_) => http.Response('', 204));
      await c.deleteUser('u3');
      expect(sent.single.$1, 'DELETE /users/u3');
    });

    test('a refused delete throws', () async {
      final c = client(
        (_) => json(const {
          'error': {'code': 'auth.owner_immutable', 'message': 'no', 'retryable': false},
        }, status: 409),
      );
      await expectLater(c.deleteUser('u1'), throwsA(isA<MediaServerHttpException>()));
    });
  });
}
