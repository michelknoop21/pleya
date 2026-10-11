// ignore_for_file: close_sinks — stub sockets are force-closed by stop().
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/pleya_share/pleya_share_channel.dart';
import 'package:pleya/services/pleya_share/pleya_share_host_service.dart';
import 'package:pleya/services/pleya_share/pleya_share_relay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Relay stand-in that records every peer that dials it. Pleya Share is local
/// only (see [PleyaShareRelay.enabled]), so in these tests it must stay idle.
class _CountingRelay {
  HttpServer? _server;
  final Map<String, Map<String, WebSocket>> _rooms = {};
  final List<String> creates = [];
  final List<String> joins = [];

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      String? room;
      String? peerId;
      socket.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          switch (msg['type'] as String?) {
            case 'create':
              room = msg['sessionId'] as String;
              peerId = msg['peerId'] as String;
              creates.add(peerId!);
              (_rooms[room!] ??= {})[peerId!] = socket;
              socket.add(jsonEncode({'type': 'created', 'sessionId': room}));
            case 'join':
              room = msg['sessionId'] as String;
              peerId = msg['peerId'] as String;
              joins.add(peerId!);
              final members = _rooms[room!];
              if (members == null || members.isEmpty) {
                socket.add(jsonEncode({'type': 'error', 'code': 'room_not_found', 'message': 'Room does not exist'}));
                return;
              }
              socket.add(jsonEncode({'type': 'joined', 'sessionId': room, 'peers': members.keys.toList()}));
              for (final other in members.values) {
                other.add(jsonEncode({'type': 'peerJoined', 'peerId': peerId}));
              }
              members[peerId!] = socket;
            case 'sendTo':
              final target = _rooms[room]?[msg['to'] as String];
              target?.add(jsonEncode({'type': 'message', 'from': peerId, 'payload': msg['payload']}));
            case 'ping':
              socket.add(jsonEncode({'type': 'pong'}));
          }
        },
        onDone: () {
          if (room != null && peerId != null) {
            _rooms[room]?.remove(peerId);
            for (final other in (_rooms[room] ?? {}).values) {
              other.add(jsonEncode({'type': 'peerLeft', 'peerId': peerId}));
            }
          }
        },
      );
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

/// A "LAN path" that can be switched off and on: TCP forwarder on its own
/// port to the host's HTTP server. Down = connections are dropped.
class _SwitchableLan {
  ServerSocket? _server;
  bool up = false;
  int connections = 0;
  final List<Socket> _live = [];
  int get port => _server!.port;

  /// Take the path down and cut established (keep-alive) connections too.
  void drop() {
    up = false;
    for (final socket in _live) {
      socket.destroy();
    }
    _live.clear();
  }

  Future<void> start(int targetPort) async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((client) async {
      if (!up) {
        client.destroy();
        return;
      }
      connections++;
      try {
        final upstream = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
        _live
          ..add(client)
          ..add(upstream);
        // A drop() mid-response destroys both ends; swallow the resulting
        // socket errors so they don't fail the test zone.
        unawaited(client.done.catchError((_) {}));
        unawaited(upstream.done.catchError((_) {}));
        client.listen(upstream.add, onDone: upstream.destroy, onError: (_) => upstream.destroy());
        upstream.listen(client.add, onDone: client.destroy, onError: (_) => client.destroy());
      } catch (_) {
        client.destroy();
      }
    });
  }

  Future<void> stop() async {
    drop();
    await _server?.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  late File videoFile;
  late _CountingRelay relay;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;
  const fileSize = 2 * 1024 * 1024;

  Future<void> startHost({String? relayBase}) async {
    host.relayBaseUrlOverride = relayBase ?? relay.baseUrl;
    PleyaShareChannel.relayBaseUrlOverride = relayBase ?? relay.baseUrl;
    final connection = LocalFolderConnection(
      id: 'local-host',
      directoryUri: 'file://${tmp.path}',
      displayName: 'Host Folder',
      createdAt: DateTime(2026),
    );
    final client = LocalFolderClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
    client.cacheItemForTest(
      MediaItem(
        id: videoFile.path,
        backend: MediaBackend.local,
        kind: MediaKind.movie,
        title: 'Clip',
        serverId: connection.id,
      ),
    );
    await host.start(clients: () => [client], deviceName: 'test-host');
    for (final guest in host.pairedGuests.toList()) {
      await host.revokeGuest(guest.pairId);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<PleyaShareConnection> pairOverLan() =>
      PleyaShareChannel.pair(ip: '127.0.0.1', port: host.port, code: host.pairCode!, deviceName: 'probe-guest');

  Future<int> fetchAll(String url, {String? range}) async {
    final http = HttpClient();
    try {
      final req = await http.getUrl(Uri.parse(url));
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      return await resp.fold<int>(0, (n, c) => n + c.length).timeout(const Duration(seconds: 20));
    } finally {
      http.close(force: true);
    }
  }

  setUp(() async {
    PleyaShareChannel.discoveryDisabledForTest = true;
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    relay = _CountingRelay();
    await relay.start();
    tmp = Directory.systemTemp.createTempSync('pleya-share-probe');
    videoFile = File('${tmp.path}/clip.mp4')..writeAsBytesSync(List<int>.generate(fileSize, (i) => i % 256));
  });

  tearDown(() async {
    await host.stop();
    PleyaShareRelay.enabled = false;
    host.relayBaseUrlOverride = null;
    PleyaShareChannel.relayBaseUrlOverride = null;
    await relay.stop();
    HttpOverrides.global = savedOverrides;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('turning sharing on does not dial the relay', () async {
    await startHost();
    expect(host.relayListener, isNull);
    expect(relay.creates, isEmpty);
    // The id still exists: the QR and Wi-Fi Aware identify the host by it.
    expect(host.relayHostId, isNotNull);
  });

  test('LAN guest pairs, browses, streams and seeks without a relay connection', () async {
    await startHost();
    final connection = await pairOverLan();
    final channel = PleyaShareChannel(connection);
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue);
    expect(channel.baseUrl, 'http://127.0.0.1:${host.port}');
    expect((await channel.request('GET', '/library'))!['items'], isNotEmpty);
    expect(await fetchAll(channel.streamUrl(videoFile.path)), fileSize);
    expect(await fetchAll(channel.streamUrl(videoFile.path), range: 'bytes=1000000-1000999'), 1000);
    expect(relay.creates, isEmpty);
    expect(relay.joins, isEmpty);
  });

  test('a LAN blip never moves the guest to the relay, and it recovers on the LAN', () async {
    await startHost();
    final lan = _SwitchableLan();
    await lan.start(host.port);
    addTearDown(lan.stop);
    final paired = await pairOverLan();
    final channel = PleyaShareChannel(paired.copyWith(lastKnownIps: ['127.0.0.1'], port: lan.port));
    addTearDown(channel.close);
    final lanBase = 'http://127.0.0.1:${lan.port}';

    lan.up = true;
    expect(await channel.ensureConnected(), isTrue);
    expect(channel.baseUrl, lanBase);

    // Two failed requests tear the channel down, the third reconnects.
    lan.drop();
    for (var i = 0; i < 3; i++) {
      expect(await channel.request('GET', '/ping'), isNull);
    }
    expect(relay.joins, isEmpty);

    lan.up = true;
    expect((await channel.request('GET', '/ping'))?['ok'], true);
    expect(channel.baseUrl, lanBase);
    expect(await fetchAll(channel.streamUrl(videoFile.path), range: 'bytes=0-9999'), 10000);
    expect(relay.joins, isEmpty);
  });

  test('a guest polling a host that is off does not dial the relay', () async {
    await startHost();
    final connection = await pairOverLan();
    await host.stop();
    final channel = PleyaShareChannel(connection);
    addTearDown(channel.close);
    for (var i = 0; i < 3; i++) {
      expect(await channel.request('GET', '/ping'), isNull);
    }
    expect(relay.joins, isEmpty);
  });

  test('QR pairing with no reachable address fails instead of pairing over the relay', () async {
    await startHost();
    // A closed loopback port: no LAN path, and it fails at once.
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    await expectLater(
      PleyaShareChannel.pairAny(
        ips: ['127.0.0.1'],
        port: deadPort,
        code: host.pairCode!,
        deviceName: 'far-guest',
        relayHostId: host.relayHostId,
        saltB64: host.pairSaltB64,
      ),
      throwsA(isA<PleyaSharePairException>()),
    );
    expect(host.pairedGuests, isEmpty);
    expect(relay.joins, isEmpty);
  });

  test('with the relay switched on but unreachable, the LAN path still works', () async {
    PleyaShareRelay.enabled = true;
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    await startHost(relayBase: 'http://127.0.0.1:$deadPort');
    expect(host.relayListener!.isConnected, isFalse);
    final connection = await pairOverLan();
    final channel = PleyaShareChannel(connection);
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue);
    expect((await channel.request('GET', '/library'))!['items'], isNotEmpty);
    expect(await fetchAll(channel.streamUrl(videoFile.path)), fileSize);
  });
}
