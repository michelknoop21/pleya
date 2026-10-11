import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/models/trakt/trakt_ids.dart';
import 'package:pleya/services/trackers/tracker_session.dart';
import 'package:pleya/services/trakt/trakt_constants.dart';
import 'package:pleya/services/trakt/trakt_sync_queue.dart';
import 'package:pleya/services/trakt/trakt_sync_service.dart';

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
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests, isEmpty);
    expect(await queue.load('u1'), hasLength(1), reason: 'kept for when the user allows it');

    await service.setEnabled(true);
    await service.flushQueue();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests, ['/sync/history']);
    expect(await queue.load('u1'), isEmpty);

    service.rebindToProfile('u1', null, onSessionInvalidated: () {});
    await service.setEnabled(false);
  });
}
