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
import 'package:pleya/services/pleya_share/pleya_share_client.dart';
import 'package:pleya/services/pleya_share/pleya_share_host_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One host, multiple simultaneous guests: concurrent byte-correct streams
/// and per-guest watch-state isolation — over LAN and (in the relay suite's
/// stub) over the relay tunnel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  late File videoFile;
  late List<int> videoBytes;
  var scanCount = 0;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;

  setUp(() async {
    PleyaShareChannel.discoveryDisabledForTest = true;
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);

    tmp = Directory.systemTemp.createTempSync('pleya-share-multi-test');
    videoBytes = List<int>.generate(300000, (i) => (i * 7) % 256);
    videoFile = File('${tmp.path}/clip.mp4')..writeAsBytesSync(videoBytes);
    final connection = LocalFolderConnection(
      id: 'local-host',
      directoryUri: 'file://${tmp.path}',
      displayName: 'Host Folder',
      createdAt: DateTime(2026),
    );
    final client = _CountingLocalFolderClient(
      connection: connection,
      cache: ApiCache.forBackend(MediaBackend.local),
      onScan: () => scanCount++,
    );
    client.cacheItemForTest(
      MediaItem(
        id: videoFile.path,
        backend: MediaBackend.local,
        kind: MediaKind.movie,
        title: 'Clip',
        serverId: connection.id,
      ),
    );
    scanCount = 0;
    await host.start(clients: () => [client], deviceName: 'test-host');
    for (final guest in host.pairedGuests.toList()) {
      await host.revokeGuest(guest.pairId);
    }
  });

  tearDown(() async {
    await host.stop();
    HttpOverrides.global = savedOverrides;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<PleyaShareChannel> pairGuest(String name) async {
    final connection = await PleyaShareChannel.pairAny(
      ips: ['127.0.0.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: name,
    );
    final channel = PleyaShareChannel(connection);
    addTearDown(channel.close);
    expect(await channel.ensureConnected(), isTrue);
    return channel;
  }

  test('three guests stream the same file concurrently, byte-correct', () async {
    final channels = [for (var i = 0; i < 3; i++) await pairGuest('guest-$i')];
    expect(host.pairedGuests, hasLength(3));

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    Future<List<int>> fetchAll(PleyaShareChannel channel) async {
      final resp = await (await http.getUrl(Uri.parse(channel.streamUrl(videoFile.path)))).close();
      final bytes = <int>[];
      await for (final chunk in resp) {
        bytes.addAll(chunk);
      }
      return bytes;
    }

    final results = await Future.wait(channels.map(fetchAll));
    for (final bytes in results) {
      expect(bytes.length, videoBytes.length);
      expect(bytes, videoBytes);
    }
  });

  test('watch state stays isolated per guest', () async {
    final a = await pairGuest('guest-a');
    final b = await pairGuest('guest-b');

    await a.request('POST', '/watch', body: {'itemId': videoFile.path, 'progressMs': 111});
    await b.request('POST', '/watch', body: {'itemId': videoFile.path, 'progressMs': 222});

    Future<int?> offsetFor(PleyaShareChannel channel) async {
      final lib = await channel.request('GET', '/library');
      final item = (lib!['items'] as List).cast<Map<String, dynamic>>().firstWhere((i) => i['id'] == videoFile.path);
      return (item['viewOffsetMs'] as num?)?.toInt();
    }

    expect(await offsetFor(a), 111);
    expect(await offsetFor(b), 222);
  });

  test('sync-bridge overlay: metadata + merged watch state on share items', () async {
    final connection = await PleyaShareChannel.pairAny(
      ips: ['127.0.0.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'bridge-guest',
    );
    final client = PleyaShareClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
    addTearDown(client.channel.close);

    final items = await client.scanAllItems();
    expect(items.map((i) => i.id), contains(videoFile.path));

    client.applyServerMetadata(videoFile.path, thumbUrl: 'https://plex/thumb.jpg', summary: 'Echt verhaal', year: 2024);
    var item = (await client.scanAllItems()).firstWhere((i) => i.id == videoFile.path);
    expect(item.thumbPath, 'https://plex/thumb.jpg');
    expect(item.summary, 'Echt verhaal');
    expect(item.year, 2024);

    // Server progress higher than local → merged up; lower → never lowered.
    await client.applyServerWatchState(videoFile.path, viewOffsetMs: 90000);
    item = (await client.scanAllItems()).firstWhere((i) => i.id == videoFile.path);
    expect(item.viewOffsetMs, 90000);
    await client.applyServerWatchState(videoFile.path, viewOffsetMs: 5000);
    item = (await client.scanAllItems()).firstWhere((i) => i.id == videoFile.path);
    expect(item.viewOffsetMs, 90000, reason: 'server sync must never lower local progress');
    await client.applyServerWatchState(videoFile.path, watched: true);
    item = (await client.scanAllItems()).firstWhere((i) => i.id == videoFile.path);
    expect(item.viewCount, 1);
  });

  test('scan cache: repeated library/stream requests do not rescan folders', () async {
    final channel = await pairGuest('cache-guest');
    await channel.request('GET', '/library');
    final scansAfterFirst = scanCount;
    expect(scansAfterFirst, greaterThan(0));

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    for (var i = 0; i < 3; i++) {
      await channel.request('GET', '/library');
      final resp = await (await http.getUrl(Uri.parse(channel.streamUrl(videoFile.path)))).close();
      await resp.drain<void>();
    }
    expect(scanCount, scansAfterFirst, reason: 'requests within the TTL must reuse the scan cache');

    host.invalidateScanCache();
    await channel.request('GET', '/library');
    expect(scanCount, greaterThan(scansAfterFirst));
  });
}

class _CountingLocalFolderClient extends LocalFolderClient {
  final void Function() onScan;

  _CountingLocalFolderClient({required super.connection, required super.cache, required this.onScan});

  @override
  Future<List<MediaItem>> scanAllItems() {
    onScan();
    return super.scanAllItems();
  }
}
