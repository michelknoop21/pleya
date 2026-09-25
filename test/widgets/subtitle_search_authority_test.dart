import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/widgets/video_controls/video_controls.dart';

import '../test_helpers/prefs.dart';

/// "Search subtitles" downloads onto the shared server item, so the player
/// only offers it to the server's owner. Choosing existing tracks is not
/// affected (see server_authority_guard_test for selectStreams).
void main() {
  setUp(resetSharedPreferencesForTest);

  Future<MultiServerManager> plexManager({required bool owned}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    final m = MultiServerManager();
    addTearDown(m.dispose);
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('server-1'),
      serverName: 'Plex',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    m.debugRegisterClientForTesting(client);
    await m.refreshTokensForProfile(
      PlexAccountConnection(
        id: 'account-1',
        accountToken: 'account-token',
        clientIdentifier: 'account-client',
        accountLabel: 'Account',
        servers: [
          PlexServer(
            name: 'Plex',
            clientIdentifier: 'server-1',
            accessToken: 'token',
            connections: const [],
            owned: owned,
          ),
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    return m;
  }

  test('the Plex owner gets subtitle search', () async {
    expect(canOfferSubtitleSearch(await plexManager(owned: true), 'server-1'), isTrue);
  });

  test('a shared (not owned) Plex server hides subtitle search', () async {
    expect(canOfferSubtitleSearch(await plexManager(owned: false), 'server-1'), isFalse);
  });

  test('a borrowed or non-admin Home profile on an owned server hides subtitle search', () async {
    final m = await plexManager(owned: true);
    m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
    expect(canOfferSubtitleSearch(m, 'server-1'), isFalse);
  });

  test('Jellyfin has no external subtitle search, even for an administrator', () {
    final m = MultiServerManager();
    addTearDown(m.dispose);
    m.debugRegisterJellyfinClientForTesting(
      JellyfinClient.forTesting(
        connection: JellyfinConnection(
          id: 'jf-machine/user-a',
          baseUrl: 'https://jf.example.com',
          serverName: 'JF',
          serverMachineId: 'jf-machine',
          userId: 'user-a',
          userName: 'user-a',
          accessToken: 'token',
          deviceId: 'device',
          isAdministrator: true,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
    );
    expect(canOfferSubtitleSearch(m, 'jf-machine'), isFalse);
  });

  test('no server id means no search', () {
    final m = MultiServerManager();
    addTearDown(m.dispose);
    expect(canOfferSubtitleSearch(m, null), isFalse);
  });
}
