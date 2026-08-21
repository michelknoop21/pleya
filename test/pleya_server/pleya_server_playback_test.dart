import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/services/playback_initialization_types.dart';
import 'package:pleya/services/pleya_server_client.dart';

import 'pleya_fake_server.dart';

/// PS-4 on the client side: direct play and watch state.
///
/// The six ownership rules live on the server and are tested there against a
/// real database. What is tested here is the client's half of the same
/// conversation: which fields go on the wire, when they are held back because
/// the server does not advertise the capability, and what the client does with
/// the answer.
void main() {
  late PleyaFakeServer server;
  late PleyaServerClient client;

  Future<PleyaServerClient> connected(PleyaFakeServer fake) async {
    final c = fake.client();
    await c.refreshCapabilities();
    return c;
  }

  MediaItem movie(PleyaFakeServer fake) {
    fake.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    fake.addItem(id: 'movie-1', kind: 'movie', title: 'Grease', libraryId: 'lib-films', durationMs: 6720000);
    return MediaItem(
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      id: 'movie-1',
      title: 'Grease',
      durationMs: 6720000,
      mediaVersions: const [MediaVersion(id: 'version-1', container: 'mkv')],
    );
  }

  tearDown(() => client.close());

  group('direct play', () {
    test('resolves to a stream URL without a credential in it', () async {
      server = PleyaFakeServer(watchState: true);
      final item = movie(server);
      client = await connected(server);

      final result = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0),
      );

      expect(result.videoUrl, 'http://nas.lan:8832/pleya/v1/stream/version-1');
      expect(result.videoUrl, isNot(contains('token')));
      expect(result.isTranscoding, isFalse, reason: 'PS-4 is direct play; a transcode path here would be PS-8 early');
      expect(result.playMethod, 'DirectPlay');
      expect(result.selectedMediaIndex, 0);
    });

    test('the player authorises with a header, not with a query parameter', () async {
      server = PleyaFakeServer(watchState: true);
      final item = movie(server);
      client = await connected(server);

      // Before any request there is nothing to hand over, and claiming
      // otherwise would hand the player a token it cannot have.
      expect(client.streamHeaders, isEmpty);

      await client.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0));

      expect(client.streamHeaders['Authorization'], startsWith('Bearer '));
    });

    test('an item without versions cannot start playback, and says so', () async {
      server = PleyaFakeServer(watchState: true);
      client = await connected(server);

      final result = await client.getPlaybackInitialization(
        PlaybackInitializationOptions(
          metadata: MediaItem(backend: MediaBackend.pleyaServer, kind: MediaKind.movie, id: 'x', title: 'x'),
          selectedMediaIndex: 0,
        ),
      );
      expect(result.videoUrl, isNull);
      expect(result.availableVersions, isEmpty);
    });

    test('an external player gets a stream token in the URL, because it cannot set a header', () async {
      server = PleyaFakeServer(watchState: true);
      final item = movie(server);
      client = await connected(server);

      final url = await client.resolveExternalPlaybackUrl(item);
      expect(url, contains('/stream/version-1'));
      expect(url, contains('stream_token=st-for-version-1'));
    });
  });

  group('watch state on the wire', () {
    test('playback_started acquires, with a cause and a session', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );

      expect(server.watchEvents, hasLength(1));
      final event = server.watchEvents.single;
      expect(event['explicit_action'], 'playback_started');
      expect(event['cause'], 'user_started');
      expect(event['session_id'], isNotEmpty);
      expect(event['item_id'], 'movie-1');
      expect(event['occurred_at'], matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'));
    });

    test('a progress tick carries the revision the server last reported', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );
      await client.reportPlaybackProgress(
        itemId: item.id,
        position: const Duration(minutes: 30),
        duration: Duration(milliseconds: item.durationMs!),
      );

      final progress = server.watchEvents.last;
      expect(progress['explicit_action'], 'none');
      expect(progress['position_ms'], 1800000);
      expect(progress['base_revision'], 1, reason: 'the first answer carried revision 1');
      expect(progress['session_id'], server.watchEvents.first['session_id'], reason: 'one viewing, one session');
    });

    test('the first event of a viewing makes no causal claim it cannot back up', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );

      expect(
        server.watchEvents.single.containsKey('base_revision'),
        isFalse,
        reason: 'zero would claim "there is no state yet", which this client has not read',
      );
    });

    test('without the ownership capability the new fields stay off the wire', () async {
      server = PleyaFakeServer(watchState: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );

      final event = server.watchEvents.single;
      expect(event.containsKey('base_revision'), isFalse);
      expect(event.containsKey('cause'), isFalse);
      expect(event.containsKey('backlog'), isFalse);
      expect(
        event['explicit_action'],
        'none',
        reason: 'playback_started is not in the older ExplicitAction enum, and the schema is closed',
      );
    });

    test('a stopped report past the threshold marks the title watched', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStopped(
        itemId: item.id,
        position: const Duration(milliseconds: 6600000),
        duration: Duration(milliseconds: item.durationMs!),
      );

      expect(server.watchEvents.single['completed'], isTrue);
    });

    test('stopping halfway through is not completion', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStopped(
        itemId: item.id,
        position: const Duration(milliseconds: 3000000),
        duration: Duration(milliseconds: item.durationMs!),
      );

      expect(server.watchEvents.single['completed'], isFalse);
    });

    test('an offline replay is marked as a backlog', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStopped(
        itemId: item.id,
        position: const Duration(minutes: 40),
        duration: Duration(milliseconds: item.durationMs!),
        report: PlaybackReportMetadata.offlineReplay(recordedAt: DateTime.utc(2026, 8, 20)),
      );

      expect(
        server.watchEvents.single['backlog'],
        isTrue,
        reason: 'a replay that claims to be live would move a newer canonical state',
      );
    });

    test('the explicit actions map onto the three the contract names', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.markWatched(item);
      await client.markUnwatched(item);
      await client.removeFromContinueWatching(item);

      expect(server.watchEvents.map((e) => e['explicit_action']), [
        'mark_watched',
        'mark_unwatched',
        // No separate flag in the contract: position zero and not watched is
        // exactly the state that keeps a title out of the row.
        'mark_unwatched',
      ]);
    });

    test('a second viewing opens a new session', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );
      final first = server.watchEvents.last['session_id'];
      await client.reportPlaybackStopped(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );
      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );
      final second = server.watchEvents.last['session_id'];

      expect(second, isNot(first), reason: 'reusing the id would reuse a lease the server already granted');
    });

    test('losing the lease is not an error and does not stop reporting', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true)..ownedByThisSession = false;
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );
      await client.reportPlaybackProgress(
        itemId: item.id,
        position: const Duration(minutes: 5),
        duration: Duration(milliseconds: item.durationMs!),
      );

      expect(
        server.watchEvents,
        hasLength(2),
        reason: 'a device that lost the lease keeps reporting so it can reclaim',
      );
    });

    test('a server without watch state gets no events at all', () async {
      server = PleyaFakeServer();
      final item = movie(server);
      client = await connected(server);

      await client.reportPlaybackStarted(
        itemId: item.id,
        position: Duration.zero,
        duration: Duration(milliseconds: item.durationMs!),
      );
      await client.markWatched(item);

      expect(server.watchEvents, isEmpty);
      expect(server.requests.where((r) => r.contains('watch-state')), isEmpty);
    });
  });

  group('watch state on the way back', () {
    test('recently watched reads the list and keeps only the finished titles', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      server.addItem(id: 'movie-2', kind: 'movie', title: 'The Matrix', libraryId: 'lib-films');
      client = await connected(server);

      await client.markWatched(item);
      await client.reportPlaybackProgress(
        itemId: 'movie-2',
        position: const Duration(minutes: 5),
        duration: const Duration(hours: 2),
      );

      final watched = await client.fetchRecentlyWatched();
      expect(watched.map((i) => i.id), ['movie-1']);
    });

    test('an item answer carries the position the server holds', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      server.addItem(
        id: 'movie-1',
        kind: 'movie',
        title: 'Grease',
        libraryId: 'lib-films',
        durationMs: 6720000,
        userState: const {
          'position_ms': 1830000,
          'watched': false,
          'play_count': 0,
          'updated_at': '2026-08-21T20:12:44Z',
          'revision': 7,
        },
      );
      client = await connected(server);

      final item = await client.fetchItem('movie-1');
      expect(item?.viewOffsetMs, 1830000);
    });
  });
}
