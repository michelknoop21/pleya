import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart' hide ProductionFilter;
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/utils/app_logger.dart';

void main() {
  late MemoryOutput log;
  late Logger previous;

  setUp(() {
    previous = appLogger;
    log = MemoryOutput();
    appLogger = Logger(output: log, printer: SimplePrinter(), filter: _AllowAll(), level: Level.trace);
  });
  tearDown(() => appLogger = previous);

  plexExternalIdsTests();

  PlexClient clientAnswering(int status, {required List<String> requested}) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('plex-1'),
      httpClient: MockClient((request) async {
        requested.add(request.url.path);
        return http.Response('<html>nope</html>', status, headers: {'content-type': 'text/html'});
      }),
    );
    addTearDown(client.close);
    return client;
  }

  test('a 502 or 401 is no answer about the item: it throws, so nobody concludes the item is gone', () async {
    for (final status in [401, 403, 500, 502, 503]) {
      final client = clientAnswering(status, requested: []);

      await expectLater(client.fetchItem('59533'), throwsA(isA<MediaServerHttpException>()), reason: 'HTTP $status');
    }
  });

  test('a 404 for an item is "gone": null, nothing cached, and no warning that blames the response type', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    final requested = <String>[];
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('plex-1'),
      httpClient: MockClient((request) async {
        requested.add(request.url.path);
        return http.Response('<html>Not Found</html>', 404, headers: {'content-type': 'text/html'});
      }),
    );
    addTearDown(client.close);

    final item = await client.fetchItem('59533');

    expect(item, isNull);
    expect(requested, ['/library/metadata/59533']);
    expect(
      log.buffer.where((e) => e.level.value >= Level.warning.value),
      isEmpty,
      reason: 'a deleted item is not a warning',
    );
    expect(await PlexApiCache.instance.get(ServerId('plex-1'), '/library/metadata/59533'), isNull);
  });
}

class _AllowAll extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

/// A failed Plex id lookup is not "this item has no ids": the catalog merge
/// caches the answer, so an empty list from a 502 would pin the item without
/// identity evidence until the next reset.
void plexExternalIdsTests() {
  PlexClient clientAnsweringIds(int status, String body) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('plex-1'),
      httpClient: MockClient(
        (request) async => http.Response(body, status, headers: {'content-type': 'application/json'}),
      ),
    );
    addTearDown(client.close);
    return client;
  }

  test('fetchExternalIds throws on a server failure instead of answering with no ids', () async {
    for (final status in [401, 500, 502, 503]) {
      final client = clientAnsweringIds(status, '{}');

      await expectLater(client.fetchExternalIds('1'), throwsA(isA<MediaServerHttpException>()), reason: 'HTTP $status');
    }
  });

  test('fetchExternalIds reads the guids, and a 404 is simply no ids', () async {
    final ok = clientAnsweringIds(
      200,
      '{"MediaContainer":{"Metadata":[{"Guid":[{"id":"tmdb://603"},{"id":"imdb://tt0133093"}]}]}}',
    );
    expect((await ok.fetchExternalIds('1')).tmdb, 603);

    final gone = clientAnsweringIds(404, '{}');
    expect((await gone.fetchExternalIds('1')).hasAny, isFalse);
  });

  test('the Trakt-facing fetchExternalGuids stays tolerant', () async {
    final client = clientAnsweringIds(502, '{}');

    expect(await client.fetchExternalGuids('1'), isEmpty);
  });
}
