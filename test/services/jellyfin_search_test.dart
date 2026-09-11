import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/jellyfin_client.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

JellyfinConnection _conn() => JellyfinConnection(
  id: 'srv-1/user-1',
  baseUrl: 'https://jf.example.com',
  serverName: 'Home',
  serverMachineId: 'srv-1',
  userId: 'user-1',
  userName: 'edde',
  accessToken: 'tok-abc',
  deviceId: 'dev-xyz',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  JellyfinClient makeClient(Future<http.Response> Function(http.Request request) handler) =>
      JellyfinClient.forTesting(connection: _conn(), httpClient: MockClient(handler));

  group('searchPeople (SRCH-2)', () {
    test('maps /Persons Items into id/title/thumbPath', () async {
      final captured = <Uri>[];
      final client = makeClient((request) async {
        captured.add(request.url);
        if (request.url.path == '/Persons') {
          return _json({
            'Items': [
              {'Id': 'person-1', 'Name': 'Denzel Washington', 'PrimaryImageTag': 'abc123'},
              {'Id': 'person-2', 'Name': 'No Image Actor'},
            ],
          });
        }
        return http.Response('unexpected request', 500);
      });
      addTearDown(client.close);

      final results = await client.searchPeople('denzel');

      expect(captured.single.path, '/Persons');
      expect(captured.single.queryParameters['searchTerm'], 'denzel');
      expect(results.map((item) => item.id), ['person-1', 'person-2']);
      expect(results.first.title, 'Denzel Washington');
      expect(results.first.thumbPath, contains('/Items/person-1/Images/Primary'));
      expect(results.first.thumbPath, contains('tag=abc123'));
      expect(results.first.kind, MediaKind.unknown);
      expect(results.last.thumbPath, isNull);
    });

    test('a person with no Id or Name is dropped rather than crashing the mapping', () async {
      final client = makeClient((request) async {
        return _json({
          'Items': [
            {'Name': 'No Id'},
            {'Id': 'no-name'},
          ],
        });
      });
      addTearDown(client.close);

      expect(await client.searchPeople('x'), isEmpty);
    });

    test('a failing /Persons call degrades to no people rather than throwing', () async {
      final client = makeClient((request) async => http.Response('server error', 500));
      addTearDown(client.close);

      expect(await client.searchPeople('anything'), isEmpty);
    });
  });
}
