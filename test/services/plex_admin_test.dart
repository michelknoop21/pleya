import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/server_administration.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

PlexClient _client(List<http.Request> seen, {required bool admin, String activities = '{}'}) {
  final client = PlexClient.forTesting(
    config: PlexConfig(
      baseUrl: 'https://plex.example',
      token: 'token',
      clientIdentifier: 'client-id',
      product: 'Pleya',
      version: '1.0.0',
    ),
    serverId: ServerId('server-1'),
    serverName: 'Plex',
    httpClient: MockClient((request) async {
      seen.add(request);
      final body = request.url.path == '/activities' ? activities : '{}';
      return http.Response(body, 200, headers: {'content-type': 'application/json'});
    }),
  );
  client.canAdministerServer = () => admin;
  client.canManageServerMetadata = () => admin;
  return client;
}

void main() {
  setUpAll(() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
  });

  test('PlexClient exposes scan, item refresh and jobs, not retry', () {
    final client = _client([], admin: true);
    expect(client, isA<LibraryScanClient>());
    expect(client, isA<ItemMetadataRefreshClient>());
    expect(client, isA<ServerJobsClient>());
    expect(client, isNot(isA<RetryableJobsClient>()));
    expect(client.supportsServerAdministration, isTrue);
  });

  test('refreshItemMetadata is PUT /library/metadata/{id}/refresh', () async {
    final seen = <http.Request>[];
    await _client(seen, admin: true).refreshItemMetadata('42');
    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '/library/metadata/42/refresh');
  });

  test('listJobs maps activities to running jobs', () async {
    final seen = <http.Request>[];
    final client = _client(
      seen,
      admin: true,
      activities:
          '{"MediaContainer":{"Activity":[{"uuid":"a-1","type":"library.update.section","title":"Scanning",'
          '"subtitle":"Films","progress":40,"cancellable":true}]}}',
    );
    final jobs = await client.listJobs();
    expect(jobs, hasLength(1));
    final job = jobs.single;
    expect(job.id, 'a-1');
    expect(job.title, 'Scanning: Films');
    expect(job.state, ServerJobState.running);
    expect(job.progress, closeTo(0.4, 1e-9));
    expect(job.cancellable, isTrue);
    expect(job.retryable, isFalse);
  });

  test('cancelJob is DELETE /activities/{uuid}', () async {
    final seen = <http.Request>[];
    await _client(seen, admin: true).cancelJob('a-1');
    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/activities/a-1');
  });

  test('an id that would change the route is refused before the network', () async {
    final seen = <http.Request>[];
    final client = _client(seen, admin: true);
    // `/activities/../library/metadata/1` normalises to a media delete.
    for (final id in ['..', '.', '']) {
      await expectLater(client.cancelJob(id), throwsArgumentError);
      await expectLater(client.refreshItemMetadata(id), throwsArgumentError);
    }
    await client.cancelJob('../library/metadata/1').catchError((_) {});
    expect(seen.map((r) => r.url.path), isNot(contains('/library/metadata/1')));
    expect(seen.every((r) => r.url.path.startsWith('/activities/')), isTrue);
  });

  test('without authority nothing is sent', () async {
    final seen = <http.Request>[];
    final client = _client(seen, admin: false);
    final forbidden = isA<MediaServerAuthException>().having((e) => e.statusCode, 'statusCode', 403);
    await expectLater(client.refreshItemMetadata('42'), throwsA(forbidden));
    await expectLater(client.listJobs(), throwsA(forbidden));
    await expectLater(client.cancelJob('a-1'), throwsA(forbidden));
    await expectLater(client.scanLibrary('1'), throwsA(forbidden));
    expect(seen, isEmpty);
  });
}
