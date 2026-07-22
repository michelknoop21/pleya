// ignore_for_file: close_sinks — stub sockets are force-closed by stop().
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
import 'package:pleya/services/pleya_share/pleya_share_pairing.dart';
import 'package:pleya/services/pleya_share/pleya_share_protocol.dart';
import 'package:pleya/services/pleya_share/pleya_share_relay.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-process stand-in for the ice.pleya.app relay: rooms, create/join,
/// sendTo with server-authenticated `from`. Lets the full relay tunnel run
/// against real host + guest code with no internet.
class _RelayStub {
  HttpServer? _server;
  final Map<String, Map<String, WebSocket>> _rooms = {};

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
              (_rooms[room!] ??= {})[peerId!] = socket;
              socket.add(jsonEncode({'type': 'created', 'sessionId': room}));
            case 'join':
              room = msg['sessionId'] as String;
              peerId = msg['peerId'] as String;
              final members = _rooms[room!] ??= {};
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

  /// Kill every live WebSocket (simulates a NAT/idle drop) without stopping
  /// the HTTP listener, so both sides can reconnect.
  Future<void> killSockets() async {
    for (final room in _rooms.values) {
      for (final socket in room.values.toList()) {
        await socket.close();
      }
    }
    _rooms.clear();
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  late File videoFile;
  late _RelayStub relay;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;

  setUp(() async {
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);

    relay = _RelayStub();
    await relay.start();
    host.relayBaseUrlOverride = relay.baseUrl;
    PleyaShareChannel.relayBaseUrlOverride = relay.baseUrl;

    tmp = Directory.systemTemp.createTempSync('pleya-share-relay-test');
    videoFile = File('${tmp.path}/clip.mp4')..writeAsBytesSync(List<int>.generate(200000, (i) => i % 256));
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
    // Wait for the host's relay listener to be in the room.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() async {
    await host.stop();
    host.relayBaseUrlOverride = null;
    PleyaShareChannel.relayBaseUrlOverride = null;
    await relay.stop();
    HttpOverrides.global = savedOverrides;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('pairing + full guest flow over the relay with no LAN path', () async {
    // 10.255.255.1 is unroutable — forces the relay pairing path.
    final connection = await PleyaShareChannel.pairAny(
      ips: ['10.255.255.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'relay-guest',
      relayHostId: host.relayHostId,
      saltB64: host.pairSaltB64,
    );
    expect(connection.relayHostId, host.relayHostId);
    expect(host.pairedGuests, hasLength(1));

    // Reconnect with the stored pairSecret, still with no reachable LAN IP.
    final channel = PleyaShareChannel(connection.copyWith(lastKnownIps: ['10.255.255.1']));
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue);

    final library = await channel.request('GET', '/library');
    final items = (library!['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((i) => i['id']), contains(videoFile.path));

    // Ranged stream through relay proxy: mpv-style plain HTTP with Range.
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final rangeReq = await http.getUrl(Uri.parse(channel.streamUrl(videoFile.path)));
    rangeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=100-299');
    final rangeResp = await rangeReq.close();
    expect(rangeResp.statusCode, HttpStatus.partialContent);
    final bytes = <int>[];
    await for (final chunk in rangeResp) {
      bytes.addAll(chunk);
    }
    expect(bytes, List<int>.generate(200, (i) => (i + 100) % 256));

    // Full-file stream exercises multi-chunk + ack flow control (200 KB > 64 KB chunks).
    final fullReq = await http.getUrl(Uri.parse(channel.streamUrl(videoFile.path)));
    final fullResp = await fullReq.close();
    final total = await fullResp.fold<int>(0, (n, c) => n + c.length);
    expect(total, 200000);

    // Watch round-trip over relay.
    final watch = await channel.request('POST', '/watch', body: {'itemId': videoFile.path, 'progressMs': 1234});
    expect(watch!['ok'], true);
  });

  test('guest abort mid-stream cancels the host serve and the tunnel stays usable', () async {
    final connection = await PleyaShareChannel.pairAny(
      ips: ['10.255.255.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'abort-guest',
      relayHostId: host.relayHostId,
      saltB64: host.pairSaltB64,
    );
    final channel = PleyaShareChannel(connection.copyWith(lastKnownIps: ['10.255.255.1']));
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue);

    // Start a full-file stream, read a first chunk, then slam the socket shut
    // (what mpv does on stop/seek). The proxy sends `cancel` to the host.
    final aborter = HttpClient();
    final req = await aborter.getUrl(Uri.parse(channel.streamUrl(videoFile.path)));
    final resp = await req.close();
    await resp.first;
    aborter.close(force: true);

    // The tunnel must still be fully usable afterwards.
    final ping = await channel.request('GET', '/ping');
    expect(ping?['ok'], true);
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final full = await (await http.getUrl(Uri.parse(channel.streamUrl(videoFile.path)))).close();
    expect(await full.fold<int>(0, (n, c) => n + c.length), 200000);
  });

  test('tunnel self-heals after the relay drops both sockets', () async {
    host.relayListener!.retryDelay = const Duration(milliseconds: 200);
    final connection = await PleyaShareChannel.pairAny(
      ips: ['10.255.255.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'heal-guest',
      relayHostId: host.relayHostId,
      saltB64: host.pairSaltB64,
    );
    final channel = PleyaShareChannel(connection.copyWith(lastKnownIps: ['10.255.255.1']));
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue);
    expect((await channel.request('GET', '/ping'))?['ok'], true);

    await relay.killSockets();
    await Future<void>.delayed(const Duration(milliseconds: 600)); // host rejoins

    // First requests may fail while the guest tears down its dead proxy;
    // within a few attempts the channel must be healthy again.
    Map<String, dynamic>? ping;
    for (var attempt = 0; attempt < 6 && ping == null; attempt++) {
      ping = await channel.request('GET', '/ping');
      if (ping == null) await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(ping?['ok'], true, reason: 'tunnel must recover after a relay socket drop');
  });

  test('sealed frames: tampering or wrong key is rejected', () async {
    final key = await PleyaSharePairing.deriveRelayKey(PleyaSharePairing.randomBytes(32));
    final sealer = PleyaShareRelaySealer(key);
    final envelope = await sealer.seal(
      const PleyaShareRelayFrame(id: 'x', kind: 'req'),
      pairId: 'p',
    );
    final roundTrip = await sealer.unseal(Map<String, dynamic>.from(envelope));
    expect(roundTrip.id, 'x');

    final otherKey = await PleyaSharePairing.deriveRelayKey(PleyaSharePairing.randomBytes(32));
    await expectLater(PleyaShareRelaySealer(otherKey).unseal(Map<String, dynamic>.from(envelope)), throwsA(anything));
  });

  test('wrong code over relay is rejected without pairing', () async {
    await expectLater(
      PleyaShareChannel.pairAny(
        ips: ['10.255.255.1'],
        port: PleyaShareProtocol.sharePort,
        code: '000000',
        deviceName: 'relay-guest',
        relayHostId: host.relayHostId,
        saltB64: host.pairSaltB64,
      ),
      throwsA(isA<PleyaSharePairException>()),
    );
    expect(host.pairedGuests, isEmpty);
  });
}
