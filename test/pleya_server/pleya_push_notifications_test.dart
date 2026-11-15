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
    PleyaPushNotifications.resetForTesting();
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
        if (request.url.path.contains('/push-installations')) {
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
    final push = PleyaPushNotifications(
      'alice',
      profile,
      servers,
      sessions: () async => [client.connection],
      profileSessions: (id) async => id == 'alice' ? {client.connection.id} : const {},
      reach: (connection, action) async {
        if (servers.onlineServerIds.isEmpty) throw StateError('offline');
        await action(client);
      },
    );
    addTearDown(profile.dispose);
    addTearDown(servers.dispose);
    addTearDown(push.dispose);
    await BaseSharedPreferencesService.sharedCache();
    await pumpEventQueue();
    Iterable<http.Request> puts() => requests.where((request) => request.method == 'PUT');
    final source = push.sources.single;
    expect(push.choices(source), PleyaPushNotifications.off);
    expect(prompts, isEmpty, reason: 'no permission prompt before the user asks for push');
    expect(puts(), isEmpty);

    await push.setChoices(source, (movies: true, episodes: false));
    expect(prompts, [true]);
    expect(puts(), isEmpty, reason: 'permission denied: nothing registered');
    expect(push.choices(source), PleyaPushNotifications.off);

    allow = true;
    await push.setChoices(source, (movies: true, episodes: false));
    expect(prompts.first, isTrue);
    final registration = puts().single;
    expect(registration.url.scheme, 'https');
    expect(registration.followRedirects, isFalse);
    expect(jsonDecode(registration.body), containsPair('movies', true));
    expect(jsonDecode(registration.body), containsPair('episodes', false));
    expect(prompts.where((prompted) => prompted), hasLength(2), reason: 'only the two user actions prompt');

    servers.setOnline(false);
    await pumpEventQueue();
    expect(push.sources.single, source);
    requests.clear();
    await push.setChoices(source, PleyaPushNotifications.off);
    expect(requests, isEmpty);
    expect(push.pending(source), isTrue, reason: 'the opt-out waits for the server');
    expect(push.choices(source), PleyaPushNotifications.off);

    servers.setOnline(true);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests.map((request) => '${request.method} ${request.url.pathSegments.last}'), [
      'DELETE push-installations',
    ]);
    expect(push.pending(source), isFalse);
  });
}
