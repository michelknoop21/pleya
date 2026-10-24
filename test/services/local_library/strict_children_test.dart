import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Plex strict child enumeration rejects malformed emptiness and accepts confirmed empty', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    var body = <String, Object?>{};
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.invalid',
        token: 'fixture',
        clientIdentifier: 'fixture',
        product: 'Pleya',
        version: '1',
      ),
      serverId: ServerId('one'),
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}),
      ),
    );
    await expectLater(client.fetchChildrenPage('show', requireTotalCount: true), throwsStateError);
    body = {
      'MediaContainer': {'Metadata': [], 'totalSize': 0, 'offset': 0},
    };
    expect((await client.fetchChildrenPage('show', requireTotalCount: true)).totalCount, 0);
    client.close();
    await db.close();
  });
}
