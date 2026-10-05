import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/media/media_server_client.dart';

/// A connection saved before Pleya knew Emby (DEC-141) carries isEmby false.
/// The health check may migrate it, but only on proof from the same server.
void main() {
  final legacy = JellyfinConnection(
    id: 'srv-1/user-1',
    baseUrl: 'https://media.example.com',
    serverName: 'Home',
    serverMachineId: 'srv-1',
    userId: 'user-1',
    userName: 'edde',
    accessToken: 'tok-abc',
    deviceId: 'dev-xyz',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  tearDown(embyServerIds.clear);

  Future<({HealthStatus health, List<String> paths, List<JellyfinConnection> persisted, JellyfinClient client})> run(
    JellyfinConnection connection,
    Future<http.Response> Function(http.Request request) handler,
  ) async {
    final paths = <String>[];
    final persisted = <JellyfinConnection>[];
    final client = JellyfinClient.forTesting(
      connection: connection,
      httpClient: MockClient((request) {
        paths.add(request.url.path);
        return handler(request);
      }),
    );
    addTearDown(client.close);
    client.onConnectionUpdated = persisted.add;
    final health = await client.checkHealth();
    return (health: health, paths: paths, persisted: persisted, client: client);
  }

  test('legacy Emby connection migrates once and comes online', () async {
    final r = await run(legacy, (request) async {
      return switch (request.url.path) {
        '/Users/Me' => http.Response('', 500),
        '/System/Info/Public' => json({'Id': 'srv-1', 'ServerName': 'Home', 'Version': '4.9.3.0'}),
        '/Users/user-1' => json({'Id': 'user-1'}),
        _ => http.Response('', 404),
      };
    });

    expect(r.health, HealthStatus.online);
    expect(r.paths, ['/Users/Me', '/System/Info/Public', '/Users/user-1']);
    expect(r.persisted.single.isEmby, isTrue);
    expect(r.client.connection.isEmby, isTrue);
    expect(isEmbyServer('srv-1'), isTrue);
  });

  test('real Jellyfin with a failing /Users/Me is not migrated', () async {
    final r = await run(legacy, (request) async {
      return switch (request.url.path) {
        '/System/Info/Public' => json({
          'Id': 'srv-1',
          'ServerName': 'Home',
          'Version': '10.11.0',
          'ProductName': 'Jellyfin Server',
        }),
        _ => http.Response('', 500),
      };
    });

    expect(r.health, HealthStatus.offline);
    expect(r.persisted, isEmpty);
    expect(r.client.connection.isEmby, isFalse);
  });

  test('an Emby answer from a different server id is not trusted', () async {
    final r = await run(legacy, (request) async {
      return switch (request.url.path) {
        '/System/Info/Public' => json({'Id': 'other', 'ServerName': 'Other', 'Version': '4.9.3.0'}),
        _ => http.Response('', 500),
      };
    });

    expect(r.health, HealthStatus.offline);
    expect(r.persisted, isEmpty);
  });

  test('an unreachable server keeps offline behaviour and is not probed further', () async {
    final r = await run(legacy, (request) async => throw const SocketException('down'));

    expect(r.health, HealthStatus.offline);
    expect(r.paths, ['/Users/Me']);
    expect(r.persisted, isEmpty);
  });

  test('an already migrated Emby connection does no detection', () async {
    final r = await run(legacy.copyWith(isEmby: true), (request) async => http.Response('', 500));

    expect(r.health, HealthStatus.offline);
    expect(r.paths, ['/Users/user-1']);
    expect(r.persisted, isEmpty);
  });
}
