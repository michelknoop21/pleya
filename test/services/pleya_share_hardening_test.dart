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
import 'package:pleya/services/pleya_share/pleya_share_client.dart';
import 'package:pleya/services/pleya_share/pleya_share_host_service.dart';
import 'package:pleya/services/pleya_share/pleya_share_pairing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase-3 hardening: challenge-eviction resistance and the guest watch-push
/// retry queue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  late File videoFile;
  late LocalFolderClient folderClient;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;

  setUp(() async {
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);

    tmp = Directory.systemTemp.createTempSync('pleya-share-hardening-test');
    videoFile = File('${tmp.path}/clip.mp4')..writeAsBytesSync(List<int>.generate(1000, (i) => i % 256));
    final connection = LocalFolderConnection(
      id: 'local-host',
      directoryUri: 'file://${tmp.path}',
      displayName: 'Host Folder',
      createdAt: DateTime(2026),
    );
    folderClient = LocalFolderClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
    folderClient.cacheItemForTest(
      MediaItem(
        id: videoFile.path,
        backend: MediaBackend.local,
        kind: MediaKind.movie,
        title: 'Clip',
        serverId: connection.id,
      ),
    );
    await host.start(clients: () => [folderClient], deviceName: 'test-host');
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

  test('a legit in-flight pairing survives 40 spammed /pair/start challenges', () async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    Future<(int, Map<String, dynamic>)> postJson(String path, Map<String, Object?> body) async {
      final req = await http.postUrl(Uri.parse('http://127.0.0.1:${host.port}$path'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      return (resp.statusCode, text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
    }

    // Legit guest opens its challenge…
    final clientNonce = PleyaSharePairing.randomBytes(32);
    final (_, start) = await postJson('/pair/start', {'clientNonce': base64Encode(clientNonce)});
    final hostNonce = base64Decode(start['hostNonce'] as String);
    final salt = base64Decode(start['salt'] as String);

    // …an attacker spams 40 fresh challenges…
    for (var i = 0; i < 40; i++) {
      await postJson('/pair/start', {'clientNonce': base64Encode(PleyaSharePairing.randomBytes(32))});
    }

    // …and the legit completion still works.
    final pairingKey = await PleyaSharePairing.derivePairingKey(host.pairCode!, salt);
    final authTag = PleyaSharePairing.computeAuthTag(
      key: pairingKey,
      hostNonce: hostNonce,
      clientNonce: clientNonce,
      context: 'pair',
    );
    final (code, _) = await postJson('/pair/complete', {
      'clientNonce': base64Encode(clientNonce),
      'authTag': authTag,
      'deviceName': 'legit-guest',
    });
    expect(code, 200);
    expect(host.pairedGuests, hasLength(1));
  });

  test('watch updates queue while host is down and flush on recovery', () async {
    final connection = await PleyaShareChannel.pairAny(
      ips: ['127.0.0.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'queue-guest',
    );
    final client = PleyaShareClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
    addTearDown(client.channel.close);
    final item = (await client.fetchRecentlyAdded()).firstWhere((i) => i.id == videoFile.path);

    // Host goes away — the update fails and is queued, not lost.
    await host.stop();
    await client.markWatched(item);

    // Host comes back (guests persist); health check flushes the queue.
    await host.start(clients: () => [folderClient], deviceName: 'test-host');
    await client.checkHealth();
    // flushPendingWatch is fired unawaited from checkHealth — settle it.
    await client.flushPendingWatch();

    final pairId = host.pairedGuests.single.pairId;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pleya_share_watch_$pairId');
    expect(raw, isNotNull);
    final state = jsonDecode(raw!) as Map<String, dynamic>;
    expect((state[videoFile.path] as Map)['w'], true);
  });
}
