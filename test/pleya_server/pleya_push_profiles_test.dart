import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_push_notifications.dart';
import 'package:pleya/services/pleya_server_client.dart';

import '../test_helpers/prefs.dart';
import 'pleya_fake_server.dart';

/// One Pleya session on a fake server: what it holds for this device, and
/// whether it answers.
class _Session {
  _Session(this.connection);

  final PleyaServerConnection connection;
  final registered = <String>{};
  late final PleyaServerClient client;
  bool online = true;
  bool failPut = false;
  bool failDelete = false;
  Completer<void>? holdPut;
  final requests = <String>[];
  final rejectIds = <String>{};
  // Rotation model: a short-lived client spends the refresh token once. A
  // lost answer leaves the device on the old token, and spending that again
  // gets the session revoked, as the real server does after its grace.
  bool mayHold = false;
  int rotations = 0;
  bool loseNext = false;
  bool burned = false;
  bool revoked = false;

  Future<void> start() async {
    final fake = PleyaFakeServer();
    client = PleyaServerClient.create(
      connection,
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path.contains('/push-installations')) {
          final id = request.url.pathSegments.last;
          requests.add(request.method);
          if (request.method == 'PUT') {
            mayHold = true;
            await holdPut?.future;
            if (failPut) return http.Response('', 503);
            if (rejectIds.contains(id)) {
              return http.Response(
                jsonEncode({
                  'error': {'code': 'session.invalid', 'message': 'invalid push installation', 'retryable': false},
                }),
                400,
                headers: {'content-type': 'application/json'},
              );
            }
            registered.add(id);
          } else {
            if (failDelete) return http.Response('', 503);
            if (id == 'push-installations') {
              registered.clear();
              mayHold = false;
            } else {
              registered.remove(id);
            }
          }
          return http.Response('', 204);
        }
        final response = await fake.handle(request);
        if (!request.url.path.endsWith('/info')) return response;
        final info = jsonDecode(response.body) as Map<String, dynamic>;
        (info['capabilities'] as Map<String, dynamic>)['push_notifications'] = true;
        return http.Response(jsonEncode(info), 200, headers: {'content-type': 'application/json'});
      }),
    );
    await client.refreshCapabilities();
  }
}

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  String? _activeId = 'alice';
  bool _binding = false;

  @override
  String? get activeId => _activeId;

  @override
  bool get isBinding => _binding;

  void switchTo(String? id) {
    _activeId = id;
    notifyListeners();
  }

  set binding(bool value) {
    _binding = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The bound clients: the active profile's sessions whose server is online
/// and whose bind succeeded.
class _Servers extends ChangeNotifier implements MultiServerProvider {
  _Servers(this.bound);

  final List<_Session> Function() bound;

  @override
  List<String> get onlineServerIds => [
    for (final session in bound())
      if (session.online) session.connection.serverId,
  ];

  @override
  MediaServerClient? getClientForServer(ServerId serverId) {
    for (final session in bound()) {
      if (session.online && session.connection.serverId == serverId.value) return session.client;
    }
    return null;
  }

  void changed() => notifyListeners();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PleyaServerConnection _connection(String server, String account) => PleyaServerConnection(
  id: 'pleyaServer.$server.$account',
  baseUrl: 'https://$server.example.org',
  serverId: server,
  serverName: server,
  userName: account,
  refreshToken: 'rt-1',
  createdAt: DateTime.utc(2026, 8, 19),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // alice and the kid profile share one session (same connection row).
  final aliceOwn = _connection('srv-1', 'alice');
  final bobOwn = _connection('srv-2', 'bob');
  final shared = _connection('srv-3', 'alice');
  final profileSessions = {
    'alice': {aliceOwn.id, shared.id},
    'bob': {bobOwn.id},
    'kid': {shared.id},
  };
  late Map<String, _Session> sessions;
  late _Profile profile;
  late _Servers servers;
  late Set<String> unbound;
  late List<String> violations;
  late Map<String, String> deviceToken;
  PleyaPushNotifications? push;

  setUp(() async {
    resetSharedPreferencesForTest();
    PleyaPushNotifications.resetForTesting();
    sessions = {};
    for (final connection in [aliceOwn, bobOwn, shared]) {
      final session = _Session(connection);
      await session.start();
      addTearDown(session.client.close);
      sessions[connection.id] = session;
    }
    unbound = {};
    violations = [];
    deviceToken = {'token': 'aabb', 'environment': 'sandbox'};
    profile = _Profile();
    servers = _Servers(
      () => [
        for (final id in profileSessions[profile.activeId] ?? const <String>{})
          if (!unbound.contains(id)) sessions[id]!,
      ],
    );
    const channel = MethodChannel('com.pleya/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => deviceToken);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(() {
      push?.dispose();
      push = null;
    });
  });

  PleyaPushNotifications open(String profileId) {
    push?.dispose();
    final instance = PleyaPushNotifications(
      profileId,
      profile,
      servers,
      sessions: () async => [for (final session in sessions.values) session.connection],
      profileSessions: (id) async => profileSessions[id] ?? const {},
      // Bound client or short-lived: in this fake the same client either way.
      reach: (connection, action) async {
        final session = sessions[connection.id]!;
        if (!session.online) throw StateError('offline');
        final bound = servers.bound().contains(session);
        if (!bound) {
          // A short-lived client: it spends the refresh token.
          if (!session.mayHold && session.registered.isEmpty) {
            violations.add('${connection.id} got a client while holding nothing');
          }
          if (session.revoked || session.burned) {
            session.revoked = true;
            throw StateError('session revoked');
          }
          session.rotations++;
          if (session.loseNext) {
            session
              ..loseNext = false
              ..burned = true;
            throw StateError('answer lost');
          }
        }
        await action(session.client);
      },
      retryBackoff: const Duration(milliseconds: 20),
    );
    push = instance;
    return instance;
  }

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// What an earlier PUT leaves: the server holds [id] and the session is marked.
  Future<void> leftBehind(PleyaServerConnection connection, String id) async {
    sessions[connection.id]!
      ..registered.add(id)
      ..mayHold = true;
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList(
      'pleya.push.registered',
      {...?prefs.getStringList('pleya.push.registered'), connection.id}.toList(),
    );
  }

  PushSource sourceFor(PleyaPushNotifications instance, PleyaServerConnection connection) =>
      instance.sources.firstWhere((source) => source.id == connection.id);

  /// What the server must hold: the active profile's opt-ins, nothing else.
  Future<void> expectDesired(String activeProfile, {bool skipRevoked = false}) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    for (final session in sessions.values) {
      // A revoked session needs a new sign-in; the server ends what it held.
      if (skipRevoked && session.revoked) continue;
      final id = session.connection.id;
      final stored = prefs.getStringList('pleya.push/$activeProfile/${Uri.encodeComponent(id)}');
      final wanted = (profileSessions[activeProfile] ?? const {}).contains(id) && stored != null
          ? {stored.first}
          : <String>{};
      expect(session.registered, wanted, reason: '$id for active $activeProfile');
    }
  }

  test('starting a profile empties every session it did not opt in on', () async {
    await leftBehind(bobOwn, 'left-behind');
    await leftBehind(shared, 'left-behind-too');
    open('alice');
    await settle();
    await expectDesired('alice');
  });

  test('opting in registers once; opting out empties the session', () async {
    final alice = open('alice');
    await settle();
    await alice.setChoices(sourceFor(alice, aliceOwn), (movies: true, episodes: false));
    expect(sessions[aliceOwn.id]!.registered, hasLength(1));
    await alice.setChoices(sourceFor(alice, aliceOwn), PleyaPushNotifications.off);
    expect(sessions[aliceOwn.id]!.registered, isEmpty);
  });

  // Review reproduction (I1): alice's PUT lands after bob took over, and the
  // withdrawal of it fails once. It must be retried while the app stays up.
  test('a PUT that lands after a switch is withdrawn, and retried when that fails', () async {
    final alice = open('alice');
    await settle();
    final session = sessions[aliceOwn.id]!;
    session.holdPut = Completer<void>();
    final enabling = alice.setChoices(sourceFor(alice, aliceOwn), (movies: true, episodes: false));
    await pumpEventQueue();
    profile.switchTo('bob');
    open('bob');
    await pumpEventQueue();
    session.failDelete = true;
    session.holdPut!.complete();
    await enabling;
    await settle();
    expect(session.registered, isNotEmpty, reason: 'precondition: the late PUT landed and the DELETE failed');
    session.failDelete = false;
    await settle();
    await expectDesired('bob');
  });

  test('a failed withdrawal is retried after a pause while the servers stay online', () async {
    await leftBehind(bobOwn, 'left-behind');
    sessions[bobOwn.id]!.failDelete = true;
    open('alice');
    await settle();
    expect(sessions[bobOwn.id]!.registered, isNotEmpty);
    sessions[bobOwn.id]!.failDelete = false;
    await settle();
    await expectDesired('alice');
  });

  test('a bind that failed does not stop emptying the sessions (I3)', () async {
    // The active profile's shared session is not bound (its server was down
    // at bind time), and alice has no opt-in there.
    unbound.add(shared.id);
    await leftBehind(shared, 'kid-left-this');
    open('alice');
    await settle();
    expect(sessions[shared.id]!.registered, isEmpty, reason: 'emptied through a short-lived client');
  });

  test('while the binder binds, the active profile\'s sessions wait for it', () async {
    profile.binding = true;
    await leftBehind(aliceOwn, 'stale');
    await leftBehind(bobOwn, 'other');
    open('alice');
    await settle();
    expect(sessions[aliceOwn.id]!.requests, isEmpty, reason: 'the binder holds this token');
    expect(sessions[bobOwn.id]!.registered, isEmpty, reason: 'another profile\'s session does not wait');
    profile.binding = false;
    await settle();
    await expectDesired('alice');
  });

  test('one account per server: the screen says who gets push, and turning it on here drops the other', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    const other = 'pleyaServer.srv-1.carol';
    await prefs.setStringList('pleya.push/alice/${Uri.encodeComponent(other)}', ['install-carol', 'carol', 'movies']);
    final alice = open('alice');
    await settle();
    final mine = sourceFor(alice, aliceOwn);
    expect(alice.sharedWith(mine), 'carol');

    await alice.setChoices(mine, (movies: true, episodes: false));

    expect(alice.sources.map((source) => source.id), isNot(contains(other)));
    expect(prefs.containsKey('pleya.push/alice/${Uri.encodeComponent(other)}'), isFalse);
    expect(alice.sharedWith(mine), isNull);
  });

  test('an unreachable session is pending and converges when its server comes online', () async {
    final alice = open('alice');
    await settle();
    await alice.setChoices(sourceFor(alice, aliceOwn), (movies: true, episodes: false));
    sessions[aliceOwn.id]!.online = false;
    servers.changed();
    await alice.setChoices(sourceFor(alice, aliceOwn), PleyaPushNotifications.off);
    expect(alice.pending((id: aliceOwn.id, name: 'srv-1')), isTrue);
    sessions[aliceOwn.id]!.online = true;
    servers.changed();
    await settle();
    expect(sessions[aliceOwn.id]!.registered, isEmpty);
    expect(alice.pending((id: aliceOwn.id, name: 'srv-1')), isFalse);
  });

  test('app-wide sign-out withdraws push on every Pleya session and forgets the choices', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final calls = <String>[];
    final manager = MultiServerManager();
    addTearDown(manager.dispose);
    manager.debugPleyaServerHttpClientFactory = () => MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        return http.Response(
          jsonEncode({'access_token': 'at', 'refresh_token': 'rt-2', 'token_type': 'bearer', 'expires_in_ms': 900000}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      calls.add('${request.url.host} ${request.method} ${request.url.path}');
      return http.Response('', 204);
    });
    await prefs.setStringList('pleya.push/bob/${Uri.encodeComponent(bobOwn.id)}', ['id-b', 'bob', 'movies']);

    await PleyaPushNotifications.signOut([aliceOwn, bobOwn], manager);

    for (final connection in [aliceOwn, bobOwn]) {
      final host = Uri.parse(connection.baseUrl).host;
      expect(
        calls,
        containsAll(['$host DELETE /pleya/v1/users/me/push-installations', '$host POST /pleya/v1/auth/logout']),
      );
    }
    expect(prefs.keys.where((key) => key.startsWith('pleya.push/')), isEmpty);
  });

  // Review reproduction (C1): alice removes the session she shares with the
  // kid. It stays (the kid uses it), and the DELETE fails at first; the kid's
  // reconcile must still empty it, without a marker to remember.
  test('a shared session one profile let go of is emptied, also after a failed DELETE', () async {
    final alice = open('alice');
    await settle();
    await alice.setChoices(sourceFor(alice, shared), (movies: true, episodes: false));
    expect(sessions[shared.id]!.registered, hasLength(1));
    profile.switchTo('kid');
    sessions[shared.id]!.failDelete = true;
    open('kid');
    await PleyaPushNotifications.forgetConnection('alice', shared.id);
    await settle();
    expect(sessions[shared.id]!.registered, hasLength(1), reason: 'precondition: the DELETE failed');
    sessions[shared.id]!.failDelete = false;
    await settle();
    await expectDesired('kid');
  });

  test('dispose cancels a pending retry', () async {
    await leftBehind(bobOwn, 'left-behind');
    sessions[bobOwn.id]!.failDelete = true;
    final alice = open('alice');
    await settle();
    expect(alice.debugRetryPending, isTrue, reason: 'precondition: a failed DELETE waits for a retry');
    alice.dispose();
    push = null;
    expect(alice.debugRetryPending, isFalse);
  });

  test('resume registers again what the server lost', () async {
    final alice = open('alice');
    await settle();
    await alice.setChoices(sourceFor(alice, aliceOwn), (movies: true, episodes: false));
    sessions[aliceOwn.id]!.registered.clear(); // e.g. a restored server database
    alice.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(sessions[aliceOwn.id]!.registered, hasLength(1));
  });

  test('a new APNs token registers again at once', () async {
    final alice = open('alice');
    await settle();
    await alice.setChoices(sourceFor(alice, aliceOwn), (movies: true, episodes: false));
    final puts = sessions[aliceOwn.id]!.requests.where((method) => method == 'PUT').length;
    deviceToken = {'token': 'ccdd', 'environment': 'sandbox'};
    servers.changed();
    alice.retry();
    await settle();
    expect(sessions[aliceOwn.id]!.requests.where((method) => method == 'PUT').length, puts + 1);
  });

  test('a PUT the server refuses as session.invalid is tried once under a fresh id', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final key = 'pleya.push/alice/${Uri.encodeComponent(aliceOwn.id)}';
    await prefs.setStringList(key, ['taken-id', 'srv-1', 'movies']);
    sessions[aliceOwn.id]!.rejectIds.add('taken-id');
    open('alice');
    await settle();
    final stored = prefs.getStringList(key)!;
    expect(stored.first, isNot('taken-id'));
    expect(sessions[aliceOwn.id]!.registered, {stored.first});
  });

  test('a PUT without a bound client while the server is online is tried again', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList('pleya.push/alice/${Uri.encodeComponent(aliceOwn.id)}', ['id-a', 'srv-1', 'movies']);
    unbound.add(aliceOwn.id); // online, but the bind has not produced its client yet
    open('alice');
    await settle();
    expect(sessions[aliceOwn.id]!.registered, isEmpty);
    unbound.remove(aliceOwn.id); // the client is there now, without any notification
    await settle();
    expect(sessions[aliceOwn.id]!.registered, {'id-a'});
  });

  test('without an active profile every marked session is emptied', () async {
    final alice = open('alice');
    await settle();
    await alice.setChoices(sourceFor(alice, aliceOwn), (movies: true, episodes: false));
    expect(sessions[aliceOwn.id]!.registered, hasLength(1));
    profile.switchTo(null); // the profile picker
    alice.dispose();
    push = null;
    await settle();
    expect(sessions[aliceOwn.id]!.registered, isEmpty);
  });

  // Whatever happens in between, once requests succeed again the server holds
  // exactly the active profile's opt-ins.
  test('random switches, choices and failures converge to the desired state', () async {
    final random = Random(656);
    const profiles = ['alice', 'bob', 'kid'];
    var current = 'alice';
    var instance = open(current);
    await settle();
    for (var step = 0; step < 300; step++) {
      switch (random.nextInt(7)) {
        case 0:
          current = profiles[random.nextInt(profiles.length)];
          profile.switchTo(current);
          instance = open(current);
        case 1:
        case 2:
          final options = instance.sources;
          if (options.isNotEmpty) {
            final source = options[random.nextInt(options.length)];
            final choice = [
              PleyaPushNotifications.off,
              (movies: true, episodes: false),
              (movies: false, episodes: true),
              (movies: true, episodes: true),
            ][random.nextInt(4)];
            await instance.setChoices(source, choice);
          }
        case 3:
          final session = sessions.values.elementAt(random.nextInt(sessions.length));
          session
            ..failPut = random.nextBool()
            ..failDelete = random.nextBool();
        case 4:
          final session = sessions.values.elementAt(random.nextInt(sessions.length));
          session.online = random.nextInt(4) != 0;
          servers.changed();
        case 5 when random.nextInt(4) == 0:
          sessions.values.elementAt(random.nextInt(sessions.length)).loseNext = true;
        default:
          await pumpEventQueue();
      }
      if (step % 25 == 0) await settle();
    }
    for (final session in sessions.values) {
      session
        ..online = true
        ..failPut = false
        ..failDelete = false
        ..loseNext = false;
    }
    servers.changed();
    instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    await settle();
    expect(violations, isEmpty, reason: 'a short-lived client only for a session that may hold something');
    await expectDesired(current, skipRevoked: true);
  });
}
