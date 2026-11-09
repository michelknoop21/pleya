import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_auth_service.dart';
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

  bool settled = true;

  @override
  bool get isBinding => false;

  @override
  String? get settledProfileId => settled ? _activeId : null;

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
  late Completer<void>? holdDelete;
  var failPut = false;
  var failDelete = false;
  int? failPutsFrom;
  var putCount = 0;
  // What the server holds for this one session: PUT adds an id, DELETE with
  // an id removes it, DELETE without one removes all of them.
  late Set<String> registered;

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
        if (request.url.path.contains('/push-installations')) {
          requests.add(request);
          final id = request.url.pathSegments.last;
          if (request.method == 'PUT') {
            await holdPut?.future;
            if (failPut || (failPutsFrom != null && putCount++ >= failPutsFrom!)) return http.Response('', 503);
            registered.add(id);
          } else {
            await holdDelete?.future;
            if (failDelete) return http.Response('', 503);
            id == 'push-installations' ? registered.clear() : registered.remove(id);
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
    addTearDown(client.close);
    await client.refreshCapabilities();
    return client;
  }

  setUp(() {
    resetSharedPreferencesForTest();
    requests = [];
    holdPut = null;
    holdDelete = null;
    failPut = false;
    failDelete = false;
    failPutsFrom = null;
    putCount = 0;
    registered = {};
    const channel = MethodChannel('com.pleya/push');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => {'token': 'aabb', 'environment': 'sandbox'});
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  Future<(PleyaPushNotifications, _Profile)> start({
    Future<void> Function(String, String)? releaseElsewhere,
    Duration retryBackoff = const Duration(seconds: 30),
    bool settled = true,
  }) async {
    final profile = _Profile()..settled = settled;
    final servers = _Servers(await client());
    final push = PleyaPushNotifications(
      'alice',
      profile,
      servers,
      releaseElsewhere: releaseElsewhere,
      retryBackoff: retryBackoff,
    );
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
    expect(registered, isEmpty);
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

  test("Pleya's own verdict settles a withdrawal; a bare 403 from a proxy is retried", () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    String key(String profile, String connection) => 'pleya.push/$profile/${Uri.encodeComponent(connection)}';
    await prefs.setStringList(key('bob', 'pleyaServer.srv-2.bob'), ['install-bob', 'bob · Kelder', 'movies']);
    await prefs.setStringList(key('carol', 'pleyaServer.srv-3.carol'), ['install-carol', 'carol · Zolder', 'episodes']);
    await prefs.setStringList(key('dave', 'pleyaServer.srv-4.dave'), ['install-dave', 'dave · Schuur', 'movies']);
    final attempts = <String>[];
    final (push, _) = await start(
      releaseElsewhere: (connection, _) async {
        attempts.add(connection);
        if (connection.endsWith('bob'))
          throw const PleyaAuthRejectedException('auth.session_not_found', 'gone', statusCode: 401);
        if (connection.endsWith('carol')) throw const PleyaRefreshChainRevokedException('auth.refresh_token_reused');
        throw const MediaServerAuthException('HTTP 403', statusCode: 403);
      },
    );
    await pumpEventQueue();
    expect(prefs.getStringList(key('bob', 'pleyaServer.srv-2.bob')), contains('released'));
    expect(prefs.getStringList(key('carol', 'pleyaServer.srv-3.carol')), contains('released'));
    expect(prefs.getStringList(key('dave', 'pleyaServer.srv-4.dave')), isNot(contains('released')));

    push.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(attempts.where((c) => c.endsWith('dave')), hasLength(2), reason: 'a bare 403 is retried');
    expect(attempts, hasLength(4), reason: 'settled ones are not');
  });

  test('withdrawals for other profiles wait until the binder settled on this one', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList('pleya.push/bob/${Uri.encodeComponent('pleyaServer.srv-2.bob')}', [
      'install-bob',
      'bob · Kelder',
      'movies',
    ]);
    var attempts = 0;
    final (_, profile) = await start(releaseElsewhere: (_, _) async => attempts++, settled: false);
    await pumpEventQueue();
    expect(attempts, 0);
    profile
      ..settled = true
      ..notifyListeners();
    await pumpEventQueue();
    expect(attempts, 1);
  });

  test('switching away and straight back: whatever order the DELETE and PUT land in, push stays on', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final (push, profile) = await start();
    await push.setChoices(push.sources.single, (movies: true, episodes: false));
    final key = 'pleya.push/alice/${Uri.encodeComponent(connectionId)}';
    final id = prefs.getStringList(key)!.first;
    holdDelete = Completer<void>();
    profile.switchTo('bob');
    await pumpEventQueue();
    profile.switchTo('alice');
    await pumpEventQueue();
    expect(registered, {id}, reason: 'the new PUT went ahead');

    holdDelete!.complete();
    await pumpEventQueue();
    expect(registered, {id}, reason: 'the late session-wide DELETE is followed by a fresh PUT');
    expect(prefs.getStringList(key), isNot(contains('released')));
  });

  test('the app does not start a short-lived client while it knows it is offline', () async {
    var looked = false;
    final release = PleyaPushNotifications.releaseThrough(
      connection: (_) async {
        looked = true;
        return null;
      },
      servers: MultiServerManager(),
      offline: () => true,
      sharedWithActive: (_) async => false,
    );
    await expectLater(release('pleyaServer.srv-2.bob', 'install-bob'), throwsStateError);
    expect(looked, isFalse);
  });

  test('a connection the active profile also uses is only withdrawn through its bound client', () async {
    final manager = MultiServerManager();
    var created = 0;
    manager.debugPleyaServerHttpClientFactory = () {
      created++;
      return MockClient((_) async => http.Response('', 204));
    };
    final release = PleyaPushNotifications.releaseThrough(
      connection: (_) async => PleyaServerConnection(
        id: connectionId,
        baseUrl: 'https://nas.example.org',
        serverId: 'srv-1',
        serverName: 'Zolder',
        userName: 'alice',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026, 8, 19),
      ),
      servers: manager,
      offline: () => false,
      sharedWithActive: (_) async => true,
    );
    await expectLater(release(connectionId, 'install-bob'), throwsA(isA<PleyaClientNotBoundException>()));
    expect(created, 0, reason: 'no short-lived client next to the binding');
  });

  test('an own opt-out left for a connection without a bound client is withdrawn later', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final key = 'pleya.push/alice/${Uri.encodeComponent('pleyaServer.srv-2.alice')}';
    await prefs.setStringList(key, ['install-old', 'alice · Kelder']);
    final released = <(String, String)>[];
    await start(releaseElsewhere: (connection, installation) async => released.add((connection, installation)));
    await pumpEventQueue();
    expect(released, [('pleyaServer.srv-2.alice', 'install-old')]);
    expect(prefs.containsKey(key), isFalse);
  });

  // A fresh PUT under a new id failed, so the old registration may still be
  // live; turning push off must withdraw it too (review reproduction).
  test('opting out after a failed PUT leaves nothing on the server', () async {
    final (push, profile) = await start();
    await push.setChoices(push.sources.single, (movies: true, episodes: false));
    holdDelete = Completer<void>();
    profile.switchTo('bob');
    await pumpEventQueue();
    failPut = true;
    profile.switchTo('alice');
    await pumpEventQueue();
    failDelete = true;
    holdDelete!.complete();
    await pumpEventQueue();
    failPut = false;
    failDelete = false;

    await push.setChoices(push.sources.single, PleyaPushNotifications.off);
    await pumpEventQueue();
    expect(registered, isEmpty);
  });

  // Review reproduction (round 7): an id registered while a follow-up PUT
  // fails must still be withdrawn on opt-out.
  test('a registration made before a failed follow-up PUT is withdrawn on opt-out', () async {
    final (push, profile) = await start();
    await push.setChoices(push.sources.single, (movies: true, episodes: false));
    holdDelete = Completer<void>();
    profile.switchTo('bob');
    await pumpEventQueue();
    failPut = true;
    profile.switchTo('alice');
    await pumpEventQueue();
    failPut = false;
    putCount = 0;
    failPutsFrom = 1; // the first PUT lands, the next one fails
    await push.setChoices(push.sources.single, (movies: true, episodes: true));
    failPutsFrom = null;
    holdDelete!.complete();
    await pumpEventQueue();

    await push.setChoices(push.sources.single, PleyaPushNotifications.off);
    await pumpEventQueue();
    expect(registered, isEmpty, reason: 'the registration on the server must be withdrawn on opt-out');
  });

  test('a withdrawal that fails while the servers stay online is retried after a pause', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList('pleya.push/bob/${Uri.encodeComponent('pleyaServer.srv-2.bob')}', [
      'install-bob',
      'bob · Kelder',
      'movies',
    ]);
    var attempts = 0;
    await start(
      retryBackoff: const Duration(milliseconds: 50),
      releaseElsewhere: (_, _) async {
        if (attempts++ == 0) throw MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 503);
      },
    );
    await pumpEventQueue();
    expect(attempts, 1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(attempts, 2, reason: 'no resume and no server event, yet tried again');
    expect(prefs.getStringList('pleya.push/bob/${Uri.encodeComponent('pleyaServer.srv-2.bob')}'), contains('released'));
  });

  test('a failed withdrawal waits for resume or a server coming online, not any notification', () async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setStringList('pleya.push/bob/${Uri.encodeComponent('pleyaServer.srv-2.bob')}', [
      'install-bob',
      'bob · Kelder',
      'movies',
    ]);
    var attempts = 0;
    final (push, profile) = await start(
      releaseElsewhere: (_, _) async {
        attempts++;
        throw StateError('offline');
      },
    );
    await pumpEventQueue();
    expect(attempts, 1);
    profile.notifyListeners();
    await pumpEventQueue();
    expect(attempts, 1, reason: 'a plain status notification is no reason to try again');

    push.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(attempts, 2);
  });

  test(
    'a registration that lands after another profile released the key is withdrawn by its own DELETE only',
    () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final (push, profile) = await start();
      final key = 'pleya.push/alice/${Uri.encodeComponent(connectionId)}';
      holdPut = Completer<void>();
      final enabling = push.setChoices(push.sources.single, (movies: true, episodes: false));
      await pumpEventQueue();
      profile.switchTo('bob');
      // Bob's start withdraws alice's key before her PUT has landed.
      final bob = PleyaPushNotifications('bob', profile, _Servers(await client()), releaseElsewhere: (_, _) async {});
      addTearDown(bob.dispose);
      await pumpEventQueue();
      expect(prefs.getStringList(key), contains('released'));

      failDelete = true;
      holdPut!.complete();
      await enabling;
      await pumpEventQueue();
      expect(requests.map((r) => r.method), ['PUT', 'DELETE']);
      expect(prefs.getStringList(key), isNot(contains('released')), reason: 'the DELETE after the PUT failed');
    },
  );
}
