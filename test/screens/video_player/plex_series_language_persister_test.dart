import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/pleya_profile_language_preference_store.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

import '../../test_helpers/prefs.dart';

/// "Mirror to Plex" writes the series' item prefs, which every user of the
/// server shares. Only the owner mirrors; for anyone else it is a silent skip,
/// not a refused write.
void main() {
  late List<http.Request> requests;
  late PlexClient client;

  setUp(() {
    resetSharedPreferencesForTest();
    PleyaProfileLanguagePreferenceStore.resetForTesting();
    requests = [];
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('server-1'),
      serverName: 'Plex',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.close);
  });

  Future<void> mirror() => plexSeriesLanguagePersister(() => client)(seriesRatingKey: '42', audioLanguage: 'nl');

  test('a non-owner skips the mirror without sending or throwing', () async {
    client.canManageServerMetadata = () => false;
    await mirror();
    expect(requests, isEmpty);
  });

  test('an unwired client skips too', () async {
    client.canManageServerMetadata = null;
    await mirror();
    expect(requests, isEmpty);
  });

  test('the owner mirrors onto the series prefs', () async {
    client.canManageServerMetadata = () => true;
    await mirror();
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/library/metadata/42/prefs');
  });
}
