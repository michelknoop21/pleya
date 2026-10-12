import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart' hide ProductionFilter;
import 'package:pleya/database/app_database.dart';
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
