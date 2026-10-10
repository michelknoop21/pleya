import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/multi_server_manager.dart';

// The manager wiring behind the assistant's rights stamp: a role the server
// changes must reach the manager's status stream, or nothing watching rights
// can see it (BP-04b).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  http.Response json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

  final connection = PleyaServerConnection(
    id: 'pleyaServer.srv-1',
    baseUrl: 'http://nas.lan:8832',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: 'michel',
    refreshToken: 'rt-1',
    createdAt: DateTime.utc(2026, 8, 19),
  );

  test(
    'a role change on the server reaches the status stream and the authority check, and so does the way back',
    () async {
      var role = 'owner';
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugPleyaServerHttpClientFactory = () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/info')) {
          return json({
            'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
            'server': {'id': 'srv-1'},
            'capabilities': {'browse': true, 'search': true, 'artwork': true, 'watch_state': false, 'users': true},
            'auth': {
              'methods': ['password'],
              'setup_required': false,
            },
          });
        }
        if (path.endsWith('/auth/refresh')) {
          return json(const {
            'access_token': 'at',
            'refresh_token': 'rt-2',
            'token_type': 'bearer',
            'expires_in_ms': 900000,
          });
        }
        if (path.endsWith('/users/me')) return json({'id': 'u1', 'username': 'michel', 'role': role});
        return json(const {'id': 'srv-1', 'name': 'Zolder', 'version': '0.2.0', 'started_at': '2026-08-18T19:25:33Z'});
      });
      expect(await manager.addPleyaServerConnection(connection), isTrue);
      final id = ServerId('srv-1');
      expect(manager.canAdministerServer(id), isTrue);

      var events = 0;
      final sub = manager.statusStream.listen((_) => events++);
      addTearDown(sub.cancel);

      role = 'member';
      await manager.getClient(id)!.checkHealth();
      await Future<void>.delayed(Duration.zero);
      expect(manager.canAdministerServer(id), isFalse);
      expect(events, greaterThan(0), reason: 'the demotion was announced');

      final afterDemotion = events;
      role = 'owner';
      await manager.getClient(id)!.checkHealth();
      await Future<void>.delayed(Duration.zero);
      expect(manager.canAdministerServer(id), isTrue);
      expect(events, greaterThan(afterDemotion), reason: 'the way back was announced too');
    },
  );
}
