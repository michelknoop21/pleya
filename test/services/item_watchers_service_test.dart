import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/item_watchers_service.dart';
import 'package:pleya/services/tautulli/tautulli_client.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_session.dart';

String fixture(String name) => File('test/fixtures/tautulli/$name').readAsStringSync();

String envelope(Object? data) => json.encode({
  'response': {'result': 'success', 'message': null, 'data': data},
});

/// A Tautulli client whose transport answers each command from a fixture.
TautulliClient tautulliFor(Map<String, String> byCommand, {List<String>? log}) => TautulliClient(
  const TautulliSession(
    baseUrl: 'https://tautulli.example.test',
    authMode: TautulliAuthMode.device,
    token: 'TESTTOKEN',
  ),
  httpClient: MockClient((request) async {
    final cmd = request.url.queryParameters['cmd']!;
    log?.add(cmd);
    final body = byCommand[cmd];
    if (body == null) return http.Response('{"response":{"result":"error","message":"no fixture"}}', 200);
    return http.Response(body, 200, headers: {'content-type': 'application/json'});
  }),
);

/// A Tautulli client that always fails, to exercise the fallback.
TautulliClient failingTautulli() => TautulliClient(
  const TautulliSession(
    baseUrl: 'https://tautulli.example.test',
    authMode: TautulliAuthMode.device,
    token: 'TESTTOKEN',
  ),
  httpClient: MockClient((_) async => http.Response('{"response":{"result":"error","message":"boom"}}', 200)),
);

MediaItem movie() => MediaItem(id: '2', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 's1');

MediaItem show() => MediaItem(id: '46473', backend: MediaBackend.plex, kind: MediaKind.show, serverId: 's1');

void main() {
  const service = ItemWatchersService();

  group('Tautulli is preferred', () {
    test('a movie is answered from history, so only finished plays count', () async {
      final log = <String>[];
      final client = tautulliFor({'get_history': envelope(json.decode(fixture('history_movie.json')))}, log: log);
      addTearDown(client.dispose);

      final result = await service.resolve(movie(), tautulli: client);

      expect(log, contains('get_history'));
      expect(result.scope, ItemWatchersScope.watched);
      expect(result.watchers, isNotEmpty);
      // The capture holds a play that stopped at 10 percent by the same user;
      // it must not add a second entry, and it must not be the reason they show.
      expect(result.watchers.map((w) => w.id).toSet(), hasLength(result.watchers.length));
    });

    test('a series is answered from the per-user aggregate, and says so', () async {
      final log = <String>[];
      final client = tautulliFor({
        'get_item_user_stats': envelope(json.decode(fixture('item_user_stats_show.json'))),
      }, log: log);
      addTearDown(client.dispose);

      final result = await service.resolve(show(), tautulli: client);

      expect(log, contains('get_item_user_stats'));
      // A series has no single completion, so the claim is weaker on purpose.
      expect(result.scope, ItemWatchersScope.watchingSeries);
      expect(result.watchers, hasLength(2));
      expect(result.watchers.first.plays, greaterThan(result.watchers.last.plays));
    });

    test('avatars survive the mapping', () async {
      final client = tautulliFor({'get_history': envelope(json.decode(fixture('history_movie.json')))});
      addTearDown(client.dispose);

      final result = await service.resolve(movie(), tautulli: client);
      expect(result.watchers.every((w) => (w.thumbUrl ?? '').isNotEmpty), isTrue);
    });
  });

  group('self detection', () {
    // The trap this guards: the same person is account 1 on the Plex Media
    // Server and 4725462 in Tautulli, so a single hardcoded id points at the
    // wrong human depending on which source answered.
    test('matches on the plex.tv id that Tautulli reports', () async {
      final client = tautulliFor({'get_history': envelope(json.decode(fixture('history_movie.json')))});
      addTearDown(client.dispose);

      final result = await service.resolve(movie(), tautulli: client, selfPlexAccountId: 4725462);
      expect(result.watchers.where((w) => w.isSelf), hasLength(1));
      expect(result.watchers.firstWhere((w) => w.isSelf).id, '4725462');
    });

    test('the Plex Media Server id marks nobody in Tautulli output', () async {
      final client = tautulliFor({'get_history': envelope(json.decode(fixture('history_movie.json')))});
      addTearDown(client.dispose);

      // 1 is the owner on the PMS. Passing it here must not accidentally match.
      final result = await service.resolve(movie(), tautulli: client, selfPlexAccountId: 1);
      expect(result.watchers.any((w) => w.isSelf), isFalse);
    });

    test('nobody is marked when the id could not be resolved', () async {
      final client = tautulliFor({'get_history': envelope(json.decode(fixture('history_movie.json')))});
      addTearDown(client.dispose);

      final result = await service.resolve(movie(), tautulli: client);
      expect(result.watchers.any((w) => w.isSelf), isFalse);
    });
  });

  group('fallback', () {
    test('with no Tautulli and no Plex client the list is simply empty', () async {
      final result = await service.resolve(movie());
      expect(result.watchers, isEmpty);
      expect(result.scope, ItemWatchersScope.watched);
    });

    test('a failing Tautulli does not throw', () async {
      final client = failingTautulli();
      addTearDown(client.dispose);

      final result = await service.resolve(movie(), tautulli: client);
      expect(result.watchers, isEmpty);
    });
  });

  group('ordering', () {
    test('most recent first when timestamps are known', () {
      final list = [
        const ItemWatcher(id: 'a', displayName: 'A', viewedAt: 100),
        const ItemWatcher(id: 'b', displayName: 'B', viewedAt: 300),
        const ItemWatcher(id: 'c', displayName: 'C', viewedAt: 200),
      ]..sort(ItemWatcher.compare);
      expect(list.map((w) => w.id), ['b', 'c', 'a']);
    });

    test('most plays first when they are not', () {
      final list = [
        const ItemWatcher(id: 'a', displayName: 'A', plays: 3),
        const ItemWatcher(id: 'b', displayName: 'B', plays: 153),
      ]..sort(ItemWatcher.compare);
      expect(list.map((w) => w.id), ['b', 'a']);
    });
  });
}
