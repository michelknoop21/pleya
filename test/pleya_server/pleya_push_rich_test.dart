import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/pleya_push_notifications.dart';
import 'package:pleya/services/pleya_server_client.dart';

import '../test_helpers/prefs.dart';
import 'pleya_fake_server.dart';

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  String get activeId => 'alice';

  @override
  bool get isBinding => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  _Servers(this.client);

  final PleyaServerClient client;

  @override
  List<String> get onlineServerIds => [client.connection.serverId];

  @override
  MediaServerClient? getClientForServer(ServerId serverId) => client;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Rich push (DEC-XXX): on iOS the registration carries the installation's key
// when the server offers it, and an opt-out takes the key off the device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> run({required bool serverOffersRich}) async {
    resetSharedPreferencesForTest();
    PleyaPushNotifications.resetForTesting();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fake = PleyaFakeServer();
    final puts = <http.Request>[];
    final client = PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.srv-1.alice',
        baseUrl: 'https://nas.example.org',
        serverId: 'srv-1',
        serverName: 'Zolder',
        userName: 'alice',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026, 11, 10),
      ),
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.contains('/push-installations')) {
          if (request.method == 'PUT') puts.add(request);
          return http.Response('', 204);
        }
        final response = await fake.handle(request);
        if (!request.url.path.endsWith('/info')) return response;
        final info = jsonDecode(response.body) as Map<String, dynamic>;
        final capabilities = info['capabilities'] as Map<String, dynamic>;
        capabilities['push_notifications'] = true;
        if (serverOffersRich) capabilities['push_rich_content'] = true;
        return http.Response(jsonEncode(info), 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.close);
    await client.refreshCapabilities();

    final keyRequests = <Map<Object?, Object?>>[];
    final kept = <List<Object?>>[];
    final key = '${'A' * 43}=';
    const channel = MethodChannel('com.pleya/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'deviceToken':
          return {'token': 'aabb', 'environment': 'production'};
        case 'contentKey':
          keyRequests.add(call.arguments as Map<Object?, Object?>);
          return key;
        case 'retainContentKeys':
          kept.add(call.arguments as List<Object?>);
          return null;
      }
      fail('unexpected ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final profile = _Profile();
    final servers = _Servers(client);
    final push = PleyaPushNotifications(
      'alice',
      profile,
      servers,
      sessions: () async => [client.connection],
      profileSessions: (id) async => id == 'alice' ? {client.connection.id} : const {},
      reach: (connection, action) => action(client),
    );
    addTearDown(profile.dispose);
    addTearDown(servers.dispose);
    addTearDown(push.dispose);
    await BaseSharedPreferencesService.sharedCache();
    await pumpEventQueue();

    final source = push.sources.single;
    await push.setChoices(source, (movies: true, episodes: false));
    final body = jsonDecode(puts.single.body) as Map<String, dynamic>;
    final installation = puts.single.url.pathSegments.last;
    if (serverOffersRich) {
      expect(body['content_key'], key);
      expect(keyRequests.single, {'installation': installation, 'base': 'https://nas.example.org'});
      expect(kept.last, [installation], reason: 'the opted-in installation keeps its key');
    } else {
      expect(body.containsKey('content_key'), isFalse, reason: 'a closed body on an older server');
      expect(keyRequests, isEmpty, reason: 'no key is made for a server that cannot use it');
    }

    await push.setChoices(source, PleyaPushNotifications.off);
    expect(kept.last, isEmpty, reason: 'the opt-out takes the key off the device');
  }

  test('a server with rich push gets the installation key, and opt-out drops it', () async {
    await run(serverOffersRich: true);
  });

  test('a server without rich push never sees content_key', () async {
    await run(serverOffersRich: false);
  });
}
