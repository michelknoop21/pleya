import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_push_notifications.dart';

import 'pleya_fake_server.dart';
import '../test_helpers/prefs.dart';

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  String? get activeId => 'parent';
  @override
  bool get isBinding => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Servers extends ChangeNotifier implements MultiServerProvider {
  @override
  List<String> get onlineServerIds => const [];
  @override
  MediaServerClient? getClientForServer(ServerId serverId) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The kid's session: the kid profile is NOT active, the parent is.
  final kid = PleyaServerConnection(
    id: 'pleyaServer.srv-1.kid',
    baseUrl: 'https://nas.example.org',
    serverId: 'srv-1',
    serverName: 'Zolder',
    userName: 'kid',
    refreshToken: 'rt-1',
    createdAt: DateTime.utc(2026, 8, 19),
  );
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late MultiServerManager manager;
  late String current; // what the server holds as the live refresh token
  late List<String> presented;
  late List<String> calls;
  late bool sessionRevoked;
  late bool loseNextRefreshResponse;
  Completer<void>? holdDelete;
  late bool failDelete;
  PleyaPushNotifications? push;

  setUp(() async {
    resetSharedPreferencesForTest();
    PleyaPushNotifications.resetForTesting();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    manager = MultiServerManager();
    manager.onPleyaServerConnectionUpdated = connections.upsert;
    manager.pleyaConnectionExists = (id) async => await connections.get(id) != null;
    await connections.upsert(kid);
    await profileConnections.upsert(ProfileConnection(profileId: 'kid', connectionId: kid.id, userIdentifier: 'kid'));
    current = 'rt-1';
    presented = [];
    calls = [];
    sessionRevoked = false;
    loseNextRefreshResponse = false;
    holdDelete = null;
    failDelete = false;
    final fake = PleyaFakeServer();
    manager.debugPleyaServerHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.endsWith('/info')) return fake.handle(request);
      if (request.url.path.endsWith('/auth/refresh')) {
        final token = (jsonDecode(request.body) as Map<String, dynamic>)['refresh_token'] as String;
        presented.add(token);
        if (sessionRevoked || token != current) {
          // Real server: outside the 2-minute grace this revokes the session.
          sessionRevoked = true;
          return http.Response(
            jsonEncode({
              'error': {'code': 'auth.refresh_token_reused', 'message': 'seen before', 'retryable': false},
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        current = 'rt-${presented.length + 1}';
        if (loseNextRefreshResponse) {
          loseNextRefreshResponse = false;
          // The server committed the rotation; the answer never arrives.
          throw http.ClientException('connection reset');
        }
        return http.Response(
          jsonEncode({
            'access_token': 'at-${presented.length}',
            'refresh_token': current,
            'token_type': 'bearer',
            'expires_in_ms': 900000,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'DELETE') {
        await holdDelete?.future;
        if (failDelete) return http.Response('', 503);
      }
      return http.Response('', 204);
    });
    const channel = MethodChannel('com.pleya/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => {'token': 'aabb', 'environment': 'sandbox'});
  });

  tearDown(() async {
    push?.dispose();
    push = null;
    manager.dispose();
    await db.close();
  });

  PleyaPushNotifications open() => push = PleyaPushNotifications(
    'parent',
    _Profile(),
    _Servers(),
    sessions: connections.listPleyaServers,
    profileSessions: (id) async => {for (final row in await profileConnections.listForProfile(id)) row.connectionId},
    reach: (connection, action) => manager.withPleyaServerClient(connection, action),
    retryBackoff: const Duration(hours: 1),
  );

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  // A session that may hold a registration: what an earlier PUT leaves.
  Future<void> markKid() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList('pleya.push.registered', [kid.id]);
  }

  Future<bool> kidMarked() async =>
      (await BaseSharedPreferencesService.sharedCache()).getStringList('pleya.push.registered')?.contains(kid.id) ??
      false;

  // Review reproduction (I1): every start and resume rotated the token of an
  // inactive session that holds nothing.
  test('an empty inactive session costs no client and no rotation, at start and on three resumes', () async {
    final instance = open();
    await settle();
    for (var i = 0; i < 3; i++) {
      instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
    }
    expect(presented, isEmpty, reason: 'no short-lived client, so no refresh token spent');
    expect(calls, isEmpty);
  });

  test('a marked session is emptied once, then left alone', () async {
    await markKid();
    final instance = open();
    await settle();
    expect(calls, ['DELETE /pleya/v1/users/me/push-installations']);
    expect(await kidMarked(), isFalse);
    for (var i = 0; i < 3; i++) {
      instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
    }
    expect(presented, ['rt-1'], reason: 'one rotation for the one DELETE that was needed');
  });

  test('a marked session stays marked after a failed DELETE and is tried again', () async {
    await markKid();
    failDelete = true;
    final instance = open();
    await settle();
    expect(await kidMarked(), isTrue, reason: 'the server may still hold a registration');
    failDelete = false;
    instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(await kidMarked(), isFalse);
    expect(calls.where((call) => call.startsWith('DELETE')), hasLength(2));
    expect(sessionRevoked, isFalse);
  });

  test('a follow-up run reads the connection again and presents the rotated token', () async {
    await markKid();
    failDelete = true;
    holdDelete = Completer<void>();
    final instance = open(); // run 1: rotates rt-1 -> rt-2 and persists it, DELETE held
    await settle();
    instance.didChangeAppLifecycleState(AppLifecycleState.resumed); // queues the follow-up
    await settle();
    holdDelete!.complete(); // run 1's DELETE fails; the follow-up runs
    holdDelete = null;
    await settle();
    expect(presented, ['rt-1', 'rt-2'], reason: 'the follow-up presents the token run 1 rotated to');
    expect(sessionRevoked, isFalse);
  });

  test('a short-lived client does not bring back a connection removed while it ran', () async {
    // The row goes while a short-lived client for it is still on its way.
    final stale = await connections.get(kid.id) as PleyaServerConnection;
    await connections.remove(kid.id);
    await manager.withPleyaServerClient(stale, (client) => client.withdrawPush());
    expect(presented, ['rt-1'], reason: 'precondition: it rotated the token');
    expect(await connections.get(kid.id), isNull);
  });
}
