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
    test('a position on a copy sends nothing: only a viewing moves a position here', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      final landed = await client.writeCopyState(
        item,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 90),
        watched: false,
      );

      expect(landed, isFalse);
      expect(server.watchEvents, isEmpty);
    });

    test('a position at 95 percent stays home too: the threshold would make it a viewing', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      final landed = await client.writeCopyState(
        item,
        position: const Duration(minutes: 95),
        duration: const Duration(minutes: 100),
        watched: false,
      );

      expect(landed, isFalse);
      expect(server.watchEvents, isEmpty);
    });

    test('a finished copy is one mark: mark_watched leaves no row in the history', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      final landed = await client.writeCopyState(
        item,
        position: const Duration(minutes: 90),
        duration: const Duration(minutes: 90),
        watched: true,
      );

      expect(landed, isTrue);
      final event = server.watchEvents.single;
      expect(event['explicit_action'], 'mark_watched');
      expect(event.containsKey('cause'), isFalse, reason: 'a reclaim would count as a viewing');
    });

    test('a finished copy lands on a server from before the ownership model too', () async {
      server = PleyaFakeServer(watchState: true);
      final item = movie(server);
      client = await connected(server);

      final landed = await client.writeCopyState(item, position: const Duration(minutes: 90), watched: true);

      expect(landed, isTrue);
      expect(server.watchEvents.single['explicit_action'], 'mark_watched');
    });

    test('a finished copy stays home just after a write: a session may hold the title', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final recent = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30;
      final item = movie(server).copyWith(lastViewedAt: recent);
      client = await connected(server);

      final landed = await client.writeCopyState(item, position: const Duration(minutes: 90), watched: true);

      expect(landed, isFalse);
      expect(server.watchEvents, isEmpty);
    });

    test('a finished copy goes out once the last write is older than two leases', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final old = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 200;
      final item = movie(server).copyWith(lastViewedAt: old);
      client = await connected(server);

      final landed = await client.writeCopyState(item, position: const Duration(minutes: 90), watched: true);

      expect(landed, isTrue);
      expect(server.watchEvents.single['explicit_action'], 'mark_watched');
    });

    test('a finished copy the server refuses throws, so the queue can decide', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);
      server.watchStateFailureStatus = 500;

      await expectLater(
        client.writeCopyState(item, position: const Duration(minutes: 90), watched: true),
        throwsA(isA<Exception>()),
      );
    });

    test('a viewing on this device keeps its session past a copy', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);
      await client.reportPlaybackStarted(itemId: item.id, position: Duration.zero);
      final viewing = server.watchEvents.single['session_id'];

      await client.writeCopyState(item, position: const Duration(minutes: 5), watched: false);
      await client.reportPlaybackProgress(
        itemId: item.id,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 90),
      );

      expect(server.watchEvents, hasLength(2));
      expect(server.watchEvents.last['session_id'], viewing);
    });

    group('with watch_state_copy', () {
      Future<MediaItem> copyServer() async {
        server = PleyaFakeServer(watchState: true, watchStateOwnership: true)..watchStateCopyCapability = true;
        final item = movie(server);
        client = await connected(server);
        return item;
      }

      test('a position is one event that says it is a copy, and no viewing', () async {
        final item = await copyServer();

        final landed = await client.writeCopyState(
          item,
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 90),
          watched: false,
        );

        expect(landed, isTrue, reason: 'owned_by_this_session is false on a copy, and that says nothing');
        final event = server.watchEvents.single;
        expect(event['copy'], isTrue);
        expect(event['explicit_action'], 'none');
        expect(event['completed'], isFalse);
        expect(event['position_ms'], 300000);
        expect(event['duration_ms'], 5400000);
        expect(event.containsKey('cause'), isFalse);
        expect(event.containsKey('backlog'), isFalse);
      });

      test('95 percent stays a position: only the flag says finished', () async {
        final item = await copyServer();

        final landed = await client.writeCopyState(
          item,
          position: const Duration(minutes: 95),
          duration: const Duration(minutes: 100),
          watched: false,
        );

        expect(landed, isTrue);
        expect(server.watchEvents.single['completed'], isFalse);
        expect(server.watchStates[item.id]?['watched'], isFalse);
      });

      test('a finished copy lands on the answer, at position zero', () async {
        final item = await copyServer();

        final landed = await client.writeCopyState(
          item,
          position: const Duration(minutes: 90),
          duration: const Duration(minutes: 90),
          watched: true,
        );

        expect(landed, isTrue);
        final event = server.watchEvents.single;
        expect(event['copy'], isTrue);
        expect(event['completed'], isTrue);
        expect(event['explicit_action'], 'none');
        expect(server.watchStates[item.id]?['play_count'], 1);
      });

      test('a session on the title holds it: a position and a finished copy do not land', () async {
        final item = await copyServer();
        server.watchLeases[item.id] = 'someone-watching';

        for (final watched in const [false, true]) {
          final landed = await client.writeCopyState(item, position: const Duration(minutes: 5), watched: watched);
          expect(landed, isFalse, reason: 'watched: $watched');
        }
        expect(server.watchStates, isEmpty);
      });

      test('a watched title refuses a position', () async {
        final item = await copyServer();
        await client.writeCopyState(item, position: Duration.zero, watched: true);

        final landed = await client.writeCopyState(item, position: const Duration(minutes: 5), watched: false);

        expect(landed, isFalse);
        expect(server.watchStates[item.id]?['position_ms'], 0);
      });

      test('every copy write is the same session, apart from a viewing', () async {
        final item = await copyServer();
        await client.reportPlaybackStarted(itemId: item.id, position: Duration.zero);
        final viewing = server.watchEvents.single['session_id'];
        server.watchLeases.remove(item.id);

        for (final minutes in const [5, 6]) {
          await client.writeCopyState(item, position: Duration(minutes: minutes), watched: false);
        }

        final copies = server.watchEvents.skip(1).map((e) => e['session_id']).toSet();
        expect(copies, hasLength(1));
        expect(copies, isNot(contains(viewing)));
      });

      test('a copy makes no claim on what this client last saw', () async {
        final item = await copyServer();
        await client.reportPlaybackStarted(itemId: item.id, position: Duration.zero);
        await client.reportPlaybackStopped(itemId: item.id, position: Duration.zero);
        server.watchLeases.remove(item.id);
        final before = server.watchEvents.length;

        await client.writeCopyState(item, position: const Duration(minutes: 5), watched: false);

        expect(server.watchEvents.skip(before).single.containsKey('base_revision'), isFalse);
      });

      test('an event that is no copy does not carry the field', () async {
        final item = await copyServer();

        await client.reportPlaybackStarted(itemId: item.id, position: Duration.zero);
        await client.markWatched(item);

        expect(server.watchEvents.map((e) => e.containsKey('copy')), everyElement(isFalse));
      });
    });

    test('a server without watch_state_copy refuses the field whole', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      client = await connected(server);

      await client.writeCopyState(item, position: const Duration(minutes: 5), watched: false);
      await client.writeCopyState(item, position: const Duration(minutes: 90), watched: true);

      expect(server.watchEvents.map((e) => e.containsKey('copy')), everyElement(isFalse));
    });

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

    test('a fresh read of the item hands its revision to the next playback_started', () async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      final item = movie(server);
      // Another device moved the item on, so the server is at revision 20.
      server.items[item.id] = {
        ...server.items[item.id]!,
        'user_state': {
          'position_ms': 2700000,
          'watched': false,
          'play_count': 0,
          'updated_at': '2026-10-18T10:00:00Z',
          'revision': 20,
        },
      };
      client = await connected(server);

      await client.fetchFreshItem(item.id);
      await client.reportPlaybackStarted(
        itemId: item.id,
        position: const Duration(minutes: 45),
        duration: Duration(milliseconds: item.durationMs!),
      );

      expect(
        server.watchEvents.single['base_revision'],
        20,
        reason: 'a stale base_revision gets playback_started refused, and then nothing owns the viewing',
      );
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
