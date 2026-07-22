import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/settings/pleya_share_host_screen.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/local_folder_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/pleya_share/pleya_share_channel.dart';
import 'package:pleya/services/pleya_share/pleya_share_host_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// QR-scan pairing against a multi-IP candidate list: boots the real host and
/// verifies pairAny succeeds when only a later candidate is reachable — the
/// hotspot scenario where the QR's first IP is a Wi-Fi address the guest
/// can't route to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmp;
  final host = PleyaShareHostService.instance;
  HttpOverrides? savedOverrides;

  setUp(() async {
    PleyaShareChannel.discoveryDisabledForTest = true;
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);

    tmp = Directory.systemTemp.createTempSync('pleya-share-pairany-test');
    File('${tmp.path}/clip.mp4').writeAsBytesSync(List<int>.generate(100, (i) => i % 256));
    final connection = LocalFolderConnection(
      id: 'local-host',
      directoryUri: 'file://${tmp.path}',
      displayName: 'Host Folder',
      createdAt: DateTime(2026),
    );
    final client = LocalFolderClient(connection: connection, cache: ApiCache.forBackend(MediaBackend.local));
    client.cacheItemForTest(
      MediaItem(
        id: '${tmp.path}/clip.mp4',
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
  });

  tearDown(() async {
    await host.stop();
    HttpOverrides.global = savedOverrides;
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('pairAny pairs via a later candidate when the first IP is dead', () async {
    // 127.0.0.2 answers nothing on macOS loopback → probe fails fast; the
    // reachable 127.0.0.1 candidate must win.
    final connection = await PleyaShareChannel.pairAny(
      ips: ['127.0.0.2', '127.0.0.1'],
      port: host.port,
      code: host.pairCode!,
      deviceName: 'test-guest',
    );
    expect(connection.pairId, isNotEmpty);
    expect(host.pairedGuests, hasLength(1));
    // Winner first, other advertised IPs kept as reconnect candidates.
    expect(connection.lastKnownIps.first, '127.0.0.1');
    expect(connection.lastKnownIps, contains('127.0.0.2'));
  });

  test('pairAny aborts immediately on wrong code', () async {
    await expectLater(
      PleyaShareChannel.pairAny(ips: ['127.0.0.1'], port: host.port, code: '000000', deviceName: 'test-guest'),
      throwsA(isA<PleyaSharePairException>().having((e) => e.wrongCode, 'wrongCode', true)),
    );
    expect(host.pairedGuests, isEmpty);
  });

  test('orderIpsForPairing: hotspot first, link-local (direct cable) last', () {
    expect(PleyaShareHostScreen.orderIpsForPairing(['192.168.1.10', '172.20.10.1', '10.0.0.5']), [
      '172.20.10.1',
      '192.168.1.10',
      '10.0.0.5',
    ]);
    expect(PleyaShareHostScreen.orderIpsForPairing(['169.254.9.9', '192.168.1.10', '172.20.10.1']), [
      '172.20.10.1',
      '192.168.1.10',
      '169.254.9.9',
    ]);
  });

  test('gatewayCandidatesFrom skips link-local (no gateway on a direct cable)', () {
    expect(PleyaShareChannel.gatewayCandidatesFrom(['169.254.12.34']), isEmpty);
    expect(PleyaShareChannel.gatewayCandidatesFrom(['192.168.1.5', '169.254.12.34']), ['192.168.1.1']);
  });
}
