import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  String _activeId = 'alice';

  @override
  String get activeId => _activeId;

  void switchTo(String id) {
    _activeId = id;
    notifyListeners();
  }

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

// The device token is one per device and the server keeps one installation
// per token, so push follows the active profile and one account per server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectionId = 'pleyaServer.srv-1.alice';
  late List<http.Request> requests;
  late Completer<void>? holdPut;

  Future<PleyaServerClient> client() async {
    final fake = PleyaFakeServer();
    final client = PleyaServerClient.create(
      PleyaServerConnection(
        id: connectionId,
        baseUrl: 'https://nas.example.org',
        serverId: 'srv-1',
        serverName: 'Zolder',
        userName: 'alice',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026, 8, 19),
      ),
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.contains('/push-installations/')) {
          requests.add(request);
          if (request.method == 'PUT') await holdPut?.future;
          return http.Response('', 204);
        }
        final response = await fake.handle(request);
        if (!request.url.path.endsWith('/info')) return response;
        final info = jsonDecode(response.body) as Map<String, dynamic>;
        (info['capabilities'] as Map<String, dynamic>)['push_notifications'] = true;
        return http.Response(jsonEncode(info), 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.close);
    await client.refreshCapabilities();
    return client;
  }

  setUp(() {
    resetSharedPreferencesForTest();
    requests = [];
    holdPut = null;
    const channel = MethodChannel('com.pleya/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => {'token': 'aabb', 'environment': 'sandbox'});
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  Future<(PleyaPushNotifications, _Profile)> start({Future<void> Function(String, String)? releaseElsewhere}) async {
    final profile = _Profile();
    final servers = _Servers(await client());
    final push = PleyaPushNotifications('alice', profile, servers, releaseElsewhere: releaseElsewhere);
    addTearDown(profile.dispose);
    addTearDown(servers.dispose);
    addTearDown(push.dispose);
    await BaseSharedPreferencesService.sharedCache();
    await Future<void>.delayed(Duration.zero);
    return (push, profile);
  }

  test('a profile switch during the PUT withdraws the installation right after', () async {
    final (push, profile) = await start();
    holdPut = Completer<void>();
    final enabling = push.setChoices(push.sources.single, (movies: true, episodes: false));
    await Future<void>.delayed(Duration.zero);
    expect(requests.map((r) => r.method), ['PUT']);
    profile.switchTo('bob');
    holdPut!.complete();
    await enabling;
    await Future<void>.delayed(Duration.zero);
    expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
    expect(requests.last.url, requests.first.url);
  });

  test('starting a profile withdraws the installations other profiles left behind, once', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final bobKey = 'pleya.push/bob/${Uri.encodeComponent('pleyaServer.srv-2.bob')}';
    await prefs.setStringList(bobKey, ['install-bob', 'bob · Kelder', 'movies']);
    final released = <(String, String)>[];
    Future<void> record(String connection, String installation) async => released.add((connection, installation));
    await start(releaseElsewhere: record);
    await Future<void>.delayed(Duration.zero);
    expect(released, [('pleyaServer.srv-2.bob', 'install-bob')]);
    // Bob's choice stays for his return; only the withdrawal is recorded.
    expect(prefs.getStringList(bobKey), ['install-bob', 'bob · Kelder', 'movies', 'released']);

    await start(releaseElsewhere: record);
    await Future<void>.delayed(Duration.zero);
    expect(released, hasLength(1), reason: 'a withdrawn installation costs no further token rotation');
  });

  test('a withdrawal that fails offline is retried on resume', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final bobKey = 'pleya.push/bob/${Uri.encodeComponent('pleyaServer.srv-2.bob')}';
    await prefs.setStringList(bobKey, ['install-bob', 'bob · Kelder', 'movies']);
    var online = false;
    var attempts = 0;
    final (push, _) = await start(
      releaseElsewhere: (_, _) async {
        attempts++;
        if (!online) throw StateError('offline');
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);
    expect(prefs.getStringList(bobKey), isNot(contains('released')));

    online = true;
    push.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 2);
    expect(prefs.getStringList(bobKey), contains('released'));
  });

  test('one account per server: the screen says who gets push, and turning it on here drops the other', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    const other = 'pleyaServer.srv-1.carol';
    await prefs.setStringList('pleya.push/alice/${Uri.encodeComponent(other)}', [
      'install-carol',
      'carol · Zolder',
      'movies',
    ]);
    final (push, _) = await start();
    final alice = push.sources.firstWhere((source) => source.id == connectionId);
    expect(push.sharedWith(alice), 'carol · Zolder');

    await push.setChoices(alice, (movies: true, episodes: false));

    expect(requests.map((r) => r.method), ['PUT']);
    expect(push.sources.map((source) => source.id), [connectionId]);
    expect(prefs.containsKey('pleya.push/alice/${Uri.encodeComponent(other)}'), isFalse);
    expect(push.sharedWith(alice), isNull);
  });
}
