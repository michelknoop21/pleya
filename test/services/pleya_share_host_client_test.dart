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
import 'package:pleya/services/pleya_share/pleya_share_host_service.dart';
import 'package:pleya/services/pleya_share/pleya_share_pairing.dart';
import 'package:pleya/services/pleya_share/pleya_share_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real in-app Pleya Share host on an ephemeral port and drives the
/// full guest flow with a raw HttpClient: pair with the 6-digit code, fetch the
/// library, Range-stream a real file (206 + 416), and round-trip guest watch
/// state. Mirrors what PleyaShareClient does on device, without discovery.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  late File videoFile;
  late HttpClient http;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;

  setUp(() async {
    // flutter_test installs a mock HttpClient that rejects real requests;
    // disable it so this integration test can talk to the in-process host.
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    http = HttpClient();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);

    tmp = Directory.systemTemp.createTempSync('pleya-share-host-test');
    videoFile = File('${tmp.path}/clip.mp4')..writeAsBytesSync(List<int>.generate(1000, (i) => i % 256));

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
    // The host is a singleton and paired guests survive stop() by design;
    // clear them so each test starts from a clean roster.
    for (final guest in host.pairedGuests.toList()) {
      await host.revokeGuest(guest.pairId);
    }
  });

  tearDown(() async {
    await host.stop();
    http.close(force: true);
    HttpOverrides.global = savedOverrides;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${host.port}$path');

  Future<(int, Map<String, dynamic>)> postJson(String path, Map<String, Object?> body) async {
    final req = await http.postUrl(url(path));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
  }

  test('full guest flow: pair → library → Range stream (206/416) → watch round-trip', () async {
    final code = host.pairCode!;
    final clientNonce = PleyaSharePairing.randomBytes(32);

    // 1. /pair/start
    final (startCode, start) = await postJson('/pair/start', {'clientNonce': base64Encode(clientNonce)});
    expect(startCode, 200);
    final hostNonce = base64Decode(start['hostNonce'] as String);
    final salt = base64Decode(start['salt'] as String);

    // 2. /pair/complete with the correct code
    final pairingKey = await PleyaSharePairing.derivePairingKey(code, salt);
    final authTag = PleyaSharePairing.computeAuthTag(
      key: pairingKey,
      hostNonce: hostNonce,
      clientNonce: clientNonce,
      context: 'pair',
    );
    final (completeCode, complete) = await postJson('/pair/complete', {
      'clientNonce': base64Encode(clientNonce),
      'authTag': authTag,
      'deviceName': 'test-guest',
    });
    expect(completeCode, 200);
    final sessionKey = await PleyaSharePairing.deriveSessionKey(pairingKey, hostNonce, clientNonce);
    final creds = await PleyaSharePairing.decryptPayload(sessionKey, complete['payload'] as String);
    final token = creds['token'] as String;
    expect(token, isNotEmpty);
    expect(host.pairedGuests, hasLength(1));

    // 3. /library shows our item
    final libReq = await http.getUrl(url('/library?token=$token'));
    final libResp = await libReq.close();
    final lib = jsonDecode(await libResp.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final items = (lib['items'] as List).cast<Map<String, dynamic>>();
    expect(items.map((i) => i['id']), contains(videoFile.path));

    // 4. Range stream: 206 partial content for bytes=0-99
    final encoded = PleyaShareProtocol.encodeItemId(videoFile.path);
    final rangeReq = await http.getUrl(url('/stream/$encoded?token=$token'));
    rangeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-99');
    final rangeResp = await rangeReq.close();
    expect(rangeResp.statusCode, HttpStatus.partialContent);
    expect(rangeResp.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(rangeResp.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-99/1000');
    final bytes = await rangeResp.fold<int>(0, (n, chunk) => n + chunk.length);
    expect(bytes, 100);

    // 4b. Unsatisfiable range → 416
    final badReq = await http.getUrl(url('/stream/$encoded?token=$token'));
    badReq.headers.set(HttpHeaders.rangeHeader, 'bytes=5000-6000');
    final badResp = await badReq.close();
    await badResp.drain<void>();
    expect(badResp.statusCode, HttpStatus.requestedRangeNotSatisfiable);

    // 5. Watch state round-trips (host-side, namespaced per guest)
    final (watchCode, _) = await postJson('/watch?token=$token', {'itemId': videoFile.path, 'progressMs': 42000});
    expect(watchCode, 200);
    final lib2Req = await http.getUrl(url('/library?token=$token'));
    final lib2Resp = await lib2Req.close();
    final lib2 = jsonDecode(await lib2Resp.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final item = (lib2['items'] as List).cast<Map<String, dynamic>>().firstWhere((i) => i['id'] == videoFile.path);
    expect(item['viewOffsetMs'], 42000);
  });

  test('wrong pair code is rejected with 403', () async {
    final clientNonce = PleyaSharePairing.randomBytes(32);
    final (_, start) = await postJson('/pair/start', {'clientNonce': base64Encode(clientNonce)});
    final hostNonce = base64Decode(start['hostNonce'] as String);
    final salt = base64Decode(start['salt'] as String);

    final wrongKey = await PleyaSharePairing.derivePairingKey('000000', salt);
    final authTag = PleyaSharePairing.computeAuthTag(
      key: wrongKey,
      hostNonce: hostNonce,
      clientNonce: clientNonce,
      context: 'pair',
    );
    final (code, _) = await postJson('/pair/complete', {
      'clientNonce': base64Encode(clientNonce),
      'authTag': authTag,
      'deviceName': 'attacker',
    });
    expect(code, HttpStatus.forbidden);
    expect(host.pairedGuests, isEmpty);
  });
}
