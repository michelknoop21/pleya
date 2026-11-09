import 'dart:async';
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
  bool _online = true;

  void setOnline(bool online) {
    _online = online;
    notifyListeners();
  }

  @override
  List<String> get onlineServerIds => _online ? [client.connection.serverId] : [];

  @override
  MediaServerClient? getClientForServer(ServerId serverId) => _online ? client : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit opt-in, HTTPS push, and durable offline opt-out are profile-bound', () async {
    resetSharedPreferencesForTest();
    final fake = PleyaFakeServer();
    final requests = <http.Request>[];
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
        if (request.url.path.contains('/push-installations/')) {
          requests.add(request);
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

    final prompts = <bool>[];
    var allow = false;
    const channel = MethodChannel('com.pleya/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'deviceToken');
      prompts.add(call.arguments as bool);
      return allow ? {'token': 'aabb', 'environment': 'sandbox'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final profile = _Profile();
    final servers = _Servers(client);
    final push = PleyaPushNotifications('alice', profile, servers);
    addTearDown(profile.dispose);
    addTearDown(servers.dispose);
    addTearDown(push.dispose);
    await BaseSharedPreferencesService.sharedCache();
    await Future<void>.delayed(Duration.zero);
    final source = push.sources.single;
    expect(push.choices(source), PleyaPushNotifications.off);
    expect(prompts, isEmpty);

    await push.setChoices(source, (movies: true, episodes: false));
    expect(prompts, [true]);
    expect(requests, isEmpty);
    expect(push.choices(source), PleyaPushNotifications.off);

    allow = true;
    await push.setChoices(source, (movies: true, episodes: false));
    expect(prompts, [true, true]);
    final registration = requests.single;
    expect(registration.method, 'PUT');
    expect(registration.url.scheme, 'https');
    expect(registration.followRedirects, isFalse);
    expect(jsonDecode(registration.body), containsPair('movies', true));
    expect(jsonDecode(registration.body), containsPair('episodes', false));

    servers.setOnline(false);
    await Future<void>.delayed(Duration.zero);
    expect(push.sources.single, source);
    await push.setChoices(source, PleyaPushNotifications.off);
    expect(requests, hasLength(1));
    expect(push.pending(source), isTrue);
    expect(push.choices(source), PleyaPushNotifications.off);

    servers.setOnline(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(requests.map((request) => request.method), ['PUT', 'DELETE']);
    expect(requests.last.url, registration.url);
    expect(push.pending(source), isFalse);
    expect(prompts, [true, true]);

    await push.setChoices(source, (movies: true, episodes: false));
    servers.setOnline(false);
    await Future<void>.delayed(Duration.zero);
    final disable = push.setChoices(source, PleyaPushNotifications.off);
    scheduleMicrotask(() => servers.setOnline(true));
    await disable;
    await Future<void>.delayed(Duration.zero);
    expect(requests.map((request) => request.method), ['PUT', 'DELETE', 'PUT', 'DELETE']);
    expect(push.pending(source), isFalse);
  });
}
