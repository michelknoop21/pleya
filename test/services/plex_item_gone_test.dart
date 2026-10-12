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
