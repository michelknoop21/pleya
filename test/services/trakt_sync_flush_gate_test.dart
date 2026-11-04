import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/models/trakt/trakt_ids.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/trackers/tracker_session.dart';
import 'package:pleya/services/trakt/trakt_constants.dart';
import 'package:pleya/services/trakt/trakt_sync_queue.dart';
import 'package:pleya/services/trakt/trakt_sync_service.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

import '../test_helpers/prefs.dart';

TrackerSession _session() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return TrackerSession(
    accessToken: 'at',
    refreshToken: 'rt',
    expiresAt: now + 3600,
    scope: 'public',
    createdAt: now,
    username: 'alice',
  );
}

void main() {
  setUp(resetSharedPreferencesForTest);

  test('a queued watched mark leaves only when sync is allowed, also right after linking', () async {
    final requests = <String>[];
    final queue = TraktSyncQueue();
    await queue.add(
      'u1',
      TraktSyncQueueItem(
        op: TraktSyncOp.add,
        ratingKey: 'm1',
        serverId: 'jf',
        kind: TraktMediaKind.movie,
        ids: const TraktIds(imdb: 'tt1160419'),
        watchedAtIso: '2026-10-01T00:00:00.000Z',
      ),
    );
    final service = TraktSyncService.instance;
    await service.setEnabled(false);

    // Linking triggers a flush by itself; it must not send anything.
    service.rebindToProfile(
      'u1',
      _session(),
      onSessionInvalidated: () {},
      httpClient: MockClient((r) async {
        requests.add(r.url.path);
        return http.Response(json.encode({}), 200);
      }),
    );
    await service.flushQueue();
    await pumpEventQueue();
    expect(requests, isEmpty);
    expect(await queue.load('u1'), hasLength(1), reason: 'kept for when the user allows it');

    await service.setEnabled(true);
    await service.flushQueue();
    await pumpEventQueue();
    expect(requests, ['/sync/history']);
    expect(await queue.load('u1'), isEmpty);

    service.rebindToProfile('u1', null, onSessionInvalidated: () {});
    await service.setEnabled(false);
  });

  test('one mark is one play on Trakt, however many copies the title has', () async {
    final requests = <String>[];
    final sent = Completer<String>();
    final manager = MultiServerManager()..debugRegisterClientForTesting(_ImdbClient());
    addTearDown(manager.dispose);
    final service = TraktSyncService.instance;
    await service.initialize(serverManager: manager);
    await service.setEnabled(true);
    service.rebindToProfile(
      'u1',
      _session(),
      onSessionInvalidated: () {},
      httpClient: MockClient((r) async {
        requests.add(r.url.path);
        if (!sent.isCompleted) sent.complete(r.body);
        return http.Response(json.encode({}), 200);
      }),
    );
    MediaItem film(String id) => MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 'srv');

    // In this order: a copy that did go out would be the first thing sent.
    WatchStateNotifier().notifyWatched(item: film('111'), isCopy: true);
    WatchStateNotifier().notifyWatched(item: film('222'));
    final body = await sent.future;

    expect(body, contains('tt222'));
    expect(body, isNot(contains('tt111')), reason: 'a copy says nothing about a viewing');
    expect(requests, ['/sync/history']);

    service.rebindToProfile('u1', null, onSessionInvalidated: () {});
    await service.setEnabled(false);
  });
}

class _ImdbClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('srv');

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ExternalIds(imdb: 'tt$itemId');

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
