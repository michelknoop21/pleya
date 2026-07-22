import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:pleya/services/pleya_share/pleya_share_aware.dart';
import 'package:pleya/services/pleya_share/pleya_share_channel.dart';
import 'package:pleya/services/pleya_share/pleya_share_host_service.dart';
import 'package:pleya_aware/pleya_aware.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-process Wi-Fi Aware transport test: fake linked AwareStream pairs stand
/// in for the radio; everything else (host HTTP server, byte-pipe bridges,
/// channel auth) is the real code.
class _FakeAware {
  final incoming = StreamController<AwareStream>.broadcast();
  var nextId = 0;

  /// Creates a linked stream pair: guest side is returned, host side is
  /// emitted on [incoming] (like a real accepted Aware connection).
  Future<AwareStream> connect(AwareHost _) async {
    final guestToHost = StreamController<Uint8List>();
    final hostToGuest = StreamController<Uint8List>();
    Future<void> closeBoth() async {
      if (!guestToHost.isClosed) await guestToHost.close();
      if (!hostToGuest.isClosed) await hostToGuest.close();
    }

    final hostSide = AwareStream(
      id: nextId++,
      input: guestToHost.stream,
      write: (bytes) async {
        if (!hostToGuest.isClosed) hostToGuest.add(bytes);
      },
      close: closeBoth,
    );
    final guestSide = AwareStream(
      id: nextId++,
      input: hostToGuest.stream,
      write: (bytes) async {
        if (!guestToHost.isClosed) guestToHost.add(bytes);
      },
      close: closeBoth,
    );
    incoming.add(hostSide);
    return guestSide;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  late File videoFile;
  late _FakeAware fake;
  late PleyaShareAwareHost awareHost;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;

  setUp(() async {
    PleyaShareChannel.discoveryDisabledForTest = true;
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);

    tmp = Directory.systemTemp.createTempSync('pleya-share-aware-test');
    videoFile = File('${tmp.path}/clip.mp4')..writeAsBytesSync(List<int>.generate(200000, (i) => (i * 3) % 256));
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

    // Real host-side bridge on top of the fake radio.
    fake = _FakeAware();
    awareHost = PleyaShareAwareHost(
      hostPort: host.port,
      incomingStreams: () => fake.incoming.stream,
      isSupported: () async => true,
      publish: (_) async {},
    );
    await awareHost.start('aware-host');

    // Channel-side: aware provider returns a running proxy over the fake radio.
    PleyaShareChannel.awareProxyProvider = (hostId) async {
      final proxy = PleyaShareAwareProxy(
        host: const AwareHost(peerId: 1, serviceInfo: 'aware-host'),
        connect: fake.connect,
      );
      await proxy.start();
      return proxy;
    };
  });

  tearDown(() async {
    PleyaShareChannel.awareProxyProvider = PleyaShareChannel.defaultAwareProxyProvider;
    await awareHost.stop();
    await host.stop();
    HttpOverrides.global = savedOverrides;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('pair + browse + ranged stream over the aware byte-pipe, no LAN', () async {
    // Unroutable LAN candidate forces the aware path (relay not configured
    // in this suite; pairAny gets relayHostId purely as aware service id).
    final connection = await PleyaShareChannel.pairAny(
      ips: ['10.255.255.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'aware-guest',
      relayHostId: 'aware-host',
    );
    expect(host.pairedGuests, hasLength(1));

    final channel = PleyaShareChannel(connection.copyWith(lastKnownIps: ['10.255.255.1']));
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue, reason: 'aware transport must win with LAN dead');

    final library = await channel.request('GET', '/library');
    expect((library!['items'] as List).cast<Map<String, dynamic>>().map((i) => i['id']), contains(videoFile.path));

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
    expect(bytes, List<int>.generate(200, (i) => ((i + 100) * 3) % 256));

    final full = await (await http.getUrl(Uri.parse(channel.streamUrl(videoFile.path)))).close();
    expect(await full.fold<int>(0, (n, c) => n + c.length), 200000);
  });

  test('aware provider returning null falls through cleanly (no relay configured)', () async {
    PleyaShareChannel.awareProxyProvider = (_) async => null;
    final channel = PleyaShareChannel(
      PleyaShareConnection(
        id: 'x',
        hostName: 'h',
        pairId: 'nope',
        pairSecret: 'AAAA',
        lastKnownIps: const ['10.255.255.1'],
        port: 1,
        relayHostId: 'aware-host',
        createdAt: DateTime(2026),
      ),
    );
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isFalse);
  });
}
