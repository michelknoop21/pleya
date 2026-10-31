/// What a mirrored play may and may not do to a copy: it stays with the profile
/// that watched, only moves a copy forward, and leaves when it is not the
/// newest word on that copy (hoofdstuk 13.2 of docs/tvos-unified-experience.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/unified_progress_mirror.dart';
import 'package:pleya/services/unified_catalog/unified_title_discovery.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/services/unified_catalog/watch_mark_order.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/mirror_server.dart';
import '../../test_helpers/prefs.dart';

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late OfflineWatchSyncService queue;
  const stop = Duration(minutes: 50);
  const length = Duration(hours: 2);

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    manager = MultiServerManager();
    for (final server in const ['playing', 'other', 'third']) {
      manager.debugMarkAdministeredForTesting(ServerId(server));
    }
    queue = OfflineWatchSyncService(database: db, serverManager: manager);
  });

  tearDown(() async {
    queue.dispose();
    manager.dispose();
    await db.close();
  });

  UnifiedTitlePlayback titleOf(
    List<MediaItem> copies, {
    Set<String> someoneElses = const {},
    ExternalIds ids = const ExternalIds(tmdb: 1),
  }) {
    final sources = [for (final copy in copies) UnifiedMediaSource.fromItem(copy, externalIds: ids)];
    return UnifiedTitlePlayback(
      routeContext: UnifiedMediaRouteContext(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
        sourceKey: sources.first.sourceKey,
        titleSources: sources,
        availableSourceKeys: [for (final s in sources) s.sourceKey],
        coverage: SourceCoverageState.none,
        intent: UnifiedActivationIntent.play,
      ),
      sources: sources,
      gate: UnifiedSourceGate(
        clientFor: manager.getClient,
        isOnline: manager.isServerOnline,
        isAuthRejected: (_) => false,
        isVisible: (_) => true,
        isOwn: (id) => !someoneElses.contains(id.value),
        hiddenLibraryKeys: () => const {},
        isRestrictedProfile: () async => false,
      ),
    );
  }

  UnifiedProgressMirror mirrorOf(MediaItem copy, {Set<String> someoneElses = const {}}) => UnifiedProgressMirror(
    queue: queue,
    playing: mirrorFilm('playing'),
    known: titleOf([mirrorFilm('playing'), copy], someoneElses: someoneElses),
  );

  group('the profile of a mirrored play', () {
    test('a switch before the stop writes nothing as the next profile', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      queue.setActiveProfileId('adult');
      final mirror = mirrorOf(mirrorFilm('other'));

      queue.setActiveProfileId('kid');
      await mirror.write(stop, length, watched: false);

      expect(other.positions, isEmpty);
      expect(await db.getLatestWatchAction('other:film'), isNull);
    });

    test('the sync stops where the profile changed: the next rows are not this client\'s', () async {
      final gate = Completer<void>();
      final other = MirrorServer('other', holdUntil: gate.future);
      manager.debugRegisterClientForTesting(other);
      queue.setActiveProfileId('adult');
      for (final item in const ['first', 'second']) {
        await queue.queueMirroredProgress(
          serverId: ServerId('other'),
          itemId: item,
          viewOffset: 1000,
          duration: mirrorHour,
          watched: false,
          profileId: 'adult',
        );
      }

      final running = queue.syncPendingItems();
      await pumpEventQueue();
      queue.setActiveProfileId('kid');
      gate.complete();
      await running;

      expect(other.positions, hasLength(1));
      expect(await db.getLatestWatchAction('other:second'), isNotNull);
    });

    test('a mark held for a profile that left stays out of the queue', () async {
      queue.setActiveProfileId('kid');

      final queued = await queue.queueCopyMark(
        serverId: ServerId('other'),
        itemId: 'film',
        watched: true,
        profileId: 'adult',
      );

      expect(queued.held, isFalse);
      expect(await db.getLatestWatchAction('other:film'), isNull);
    });
  });

  group('a play only moves a copy forward', () {
    test('eight seconds elsewhere leave an hour on the copy alone', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      await mirrorOf(
        mirrorFilm('other').copyWith(viewOffsetMs: 72 * 60000),
      ).write(const Duration(seconds: 8), length, watched: false);

      expect(other.positions, isEmpty);
      expect(await db.getLatestWatchAction('other:film'), isNull);
    });

    test('nothing to gain at the same position', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      await mirrorOf(
        mirrorFilm('other').copyWith(viewOffsetMs: stop.inMilliseconds),
      ).write(stop, length, watched: false);

      expect(other.positions, isEmpty);
    });

    test('a further play goes through', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      await mirrorOf(mirrorFilm('other').copyWith(viewOffsetMs: 60000)).write(stop, length, watched: false);

      expect(other.positions, [stop.inMilliseconds]);
    });

    test('finishing it is the one thing that does lower a copy', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      await mirrorOf(mirrorFilm('other').copyWith(viewOffsetMs: 72 * 60000)).write(stop, length, watched: true);

      expect(other.watched, ['film']);
    });

    test('a copy that moved since the row was written stays where it is', () async {
      final other = MirrorServer('other', item: mirrorFilm('other').copyWith(viewOffsetMs: 80 * 60000));
      manager.debugRegisterClientForTesting(other);
      await queue.queueMirroredProgress(
        serverId: ServerId('other'),
        itemId: 'film',
        viewOffset: stop.inMilliseconds,
        duration: length.inMilliseconds,
        watched: false,
        profileId: queue.activeProfileId,
      );

      await queue.syncPendingItems();

      expect(other.positions, isEmpty);
      expect(await queue.getPendingSyncCount(), 0, reason: 'the row is done: it has nothing to add');
    });

    test('a copy that cannot be read keeps the row: blind, the position could go back', () async {
      final other = MirrorServer('other', onRead: () => throw StateError('hiccup'));
      manager.debugRegisterClientForTesting(other);
      await queue.queueMirroredProgress(
        serverId: ServerId('other'),
        itemId: 'film',
        viewOffset: stop.inMilliseconds,
        duration: length.inMilliseconds,
        watched: false,
        profileId: queue.activeProfileId,
      );

      await queue.syncPendingItems();

      expect(other.positions, isEmpty);
      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 1);
    });

    test('a waiting row keeps its furthest position and a finished play', () async {
      manager.debugRegisterClientForTesting(MirrorServer('other'), online: false);
      Future<void> held(int offset, {required bool watched}) => queue.queueMirroredProgress(
        serverId: ServerId('other'),
        itemId: 'film',
        viewOffset: offset,
        duration: length.inMilliseconds,
        watched: watched,
        profileId: queue.activeProfileId,
      );

      await held(100 * 60000, watched: true);
      await held(5 * 60000, watched: false);

      final row = await db.getLatestWatchAction('other:film');
      expect(row?.shouldMarkWatched, isTrue, reason: 'B still has to hear it was finished');
      expect(row?.viewOffset, 100 * 60000);
    });

    test('the row of the source that played may still go back', () async {
      await db.upsertProgressAction(
        profileId: null,
        serverId: ServerId('own'),
        clientScopeId: null,
        ratingKey: 'film',
        viewOffset: 100 * 60000,
        duration: length.inMilliseconds,
        shouldMarkWatched: true,
      );
      await db.upsertProgressAction(
        profileId: null,
        serverId: ServerId('own'),
        clientScopeId: null,
        ratingKey: 'film',
        viewOffset: 5 * 60000,
        duration: length.inMilliseconds,
        shouldMarkWatched: false,
      );

      final row = await db.getLatestWatchAction('own:film');
      expect(row?.shouldMarkWatched, isFalse);
      expect(row?.viewOffset, 5 * 60000);
    });
  });

  test('a copy that does not know its length gets the position of the play', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other, online: false);

    await mirrorOf(mirrorFilm('other', durationMs: 0)).write(stop, length, watched: false);

    final row = await db.getLatestWatchAction('other:film');
    expect(row?.viewOffset, stop.inMilliseconds);
    expect(row?.duration, length.inMilliseconds);
  });

  group('a mark made in the meantime', () {
    test('a finished play whose lookup lands after a manual unmark stays away', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      final playing = mirrorFilm('playing');
      final lookup = Completer<UnifiedTitlePlayback?>();

      final written = UnifiedProgressMirror(
        find: () => lookup.future,
        playing: playing,
        queue: queue,
      ).write(length, length, watched: true);
      await pumpEventQueue();
      WatchMarkOrder.next(playing.globalKey);
      lookup.complete(titleOf([playing, mirrorFilm('other')]));
      await written;

      expect(other.watched, isEmpty);
      expect(await db.getLatestWatchAction('other:film'), isNull);
    });

    test('a mark on the copy itself counts too', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      final copy = mirrorFilm('other');
      final lookup = Completer<UnifiedTitlePlayback?>();

      final written = UnifiedProgressMirror(
        find: () => lookup.future,
        playing: mirrorFilm('playing'),
        queue: queue,
      ).write(stop, length, watched: false);
      await pumpEventQueue();
      WatchMarkOrder.next(copy.globalKey);
      lookup.complete(titleOf([mirrorFilm('playing'), copy]));
      await written;

      expect(other.positions, isEmpty);
    });
  });

  group('a row that keeps failing', () {
    Future<void> row() => queue.queueMirroredProgress(
      serverId: ServerId('other'),
      itemId: 'film',
      viewOffset: 1000,
      duration: mirrorHour,
      watched: false,
      profileId: queue.activeProfileId,
    );

    for (final (name, failure) in <(String, Object)>[
      ('a removed item', MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 404)),
      ('a refused write', MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 403)),
    ]) {
      test('$name ends the row of a copy: nobody waits on it', () async {
        manager.debugRegisterClientForTesting(MirrorServer('other', failure: failure));
        await row();

        await queue.syncPendingItems();

        expect(await queue.getPendingSyncCount(), 0);
      });
    }

    test('a server error keeps its row', () async {
      manager.debugRegisterClientForTesting(
        MirrorServer(
          'other',
          failure: MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 503),
        ),
      );
      await row();

      await queue.syncPendingItems();

      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 1);
    });

    test('a row out of attempts gets a new round after a while, no reconnect needed', () async {
      var now = DateTime(2026, 10, 31);
      final clocked = OfflineWatchSyncService(database: db, serverManager: manager, now: () => now);
      addTearDown(clocked.dispose);
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await clocked.syncPendingItems();
      await row();
      final id = (await db.getLatestWatchAction('other:film'))!.id;
      for (var i = 0; i < OfflineWatchSyncService.maxSyncAttempts; i++) {
        await db.updateSyncAttempt(id, 'server error');
      }

      now = now.add(OfflineWatchSyncService.exhaustedRetryInterval - const Duration(minutes: 1));
      await clocked.syncPendingItems();
      expect(other.positions, isEmpty, reason: 'too soon');

      now = now.add(const Duration(minutes: 2));
      await clocked.syncPendingItems();
      expect(other.positions, hasLength(1));
    });

    test('a restart does not start the wait over', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await row();
      final id = (await db.getLatestWatchAction('other:film'))!.id;
      for (var i = 0; i < OfflineWatchSyncService.maxSyncAttempts; i++) {
        await db.updateSyncAttempt(id, 'server error');
      }

      await queue.syncPendingItems();

      expect(other.positions, hasLength(1));
    });

    test('a position written during the replay is not lost with the old row', () async {
      final gate = Completer<void>();
      final other = MirrorServer('other', holdUntil: gate.future);
      manager.debugRegisterClientForTesting(other);
      await row();

      final running = queue.syncPendingItems();
      await pumpEventQueue();
      // The clock of the row has to move for this to be a new write.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.queueMirroredProgress(
        serverId: ServerId('other'),
        itemId: 'film',
        viewOffset: 9000,
        duration: mirrorHour,
        watched: false,
        profileId: queue.activeProfileId,
      );
      gate.complete();
      await running;

      expect((await db.getLatestWatchAction('other:film'))?.viewOffset, 9000);
    });
  });

  group('a play that finished offline', () {
    Future<void> ownRow({required bool finished}) => db.upsertProgressAction(
      profileId: null,
      serverId: ServerId('other'),
      clientScopeId: null,
      ratingKey: 'film',
      viewOffset: finished ? length.inMilliseconds : stop.inMilliseconds,
      duration: length.inMilliseconds,
      shouldMarkWatched: finished,
    );

    test('tells the copies once its own server took it', () async {
      manager.debugRegisterClientForTesting(MirrorServer('other', item: mirrorFilm('other')));
      final heard = Completer<(MediaItem, Duration, Duration, bool)>();
      queue.onOwnPlayReplayed = (item, position, duration, {required watched}) =>
          heard.complete((item, position, duration, watched));
      await ownRow(finished: true);

      await queue.syncPendingItems();
      final (item, position, duration, watched) = await heard.future;

      expect(item.globalKey, 'other:film');
      expect(position, length);
      expect(duration, length);
      expect(watched, isTrue);
    });

    test('a part of it reaches them too, as a position', () async {
      manager.debugRegisterClientForTesting(MirrorServer('other', item: mirrorFilm('other')));
      final heard = Completer<(Duration, bool)>();
      queue.onOwnPlayReplayed = (_, position, _, {required watched}) => heard.complete((position, watched));
      await ownRow(finished: false);

      await queue.syncPendingItems();

      expect(await heard.future, (stop, false));
    });

    test('a row its own server had moved past tells nobody', () async {
      final newer = mirrorFilm('other').copyWith(lastViewedAt: DateTime(2100).millisecondsSinceEpoch ~/ 1000);
      manager.debugRegisterClientForTesting(MirrorServer('other', item: newer));
      var heard = false;
      queue.onOwnPlayReplayed = (_, _, _, {required watched}) => heard = true;
      await ownRow(finished: false);

      await queue.syncPendingItems();
      await pumpEventQueue();

      expect(heard, isFalse);
    });

    test('a profile that took over while the item came in hears nothing', () async {
      final answer = Completer<MediaItem?>();
      manager.debugRegisterClientForTesting(_AnswersLater('other', mirrorFilm('other'), answer.future));
      var heard = false;
      queue.onOwnPlayReplayed = (_, _, _, {required watched}) => heard = true;
      queue.setActiveProfileId('adult');
      await db.upsertProgressAction(
        profileId: 'adult',
        serverId: ServerId('other'),
        clientScopeId: null,
        ratingKey: 'film',
        viewOffset: length.inMilliseconds,
        duration: length.inMilliseconds,
        shouldMarkWatched: true,
      );

      await queue.syncPendingItems();
      queue.setActiveProfileId('kid');
      answer.complete(mirrorFilm('other'));
      await pumpEventQueue();

      expect(heard, isFalse);
    });
  });

  test('two films that only share a title and a year keep their own state', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other);

    await UnifiedProgressMirror(
      queue: queue,
      playing: mirrorFilm('playing'),
      known: titleOf([mirrorFilm('playing'), mirrorFilm('other')], ids: const ExternalIds()),
    ).write(stop, length, watched: true);

    expect(other.positions, isEmpty);
    expect(await db.getLatestWatchAction('other:film'), isNull);
  });

  group('only the viewer\'s own servers', () {
    test('a friend\'s server gets no session and no row', () async {
      final friend = MirrorServer('friend');
      manager.debugRegisterClientForTesting(friend);

      await UnifiedProgressMirror(
        queue: queue,
        playing: mirrorFilm('playing'),
        known: titleOf([mirrorFilm('playing'), mirrorFilm('friend')], someoneElses: {'friend'}),
      ).write(stop, length, watched: true);

      expect(friend.positions, isEmpty);
      expect(friend.watched, isEmpty);
      expect(await db.getLatestWatchAction('friend:film'), isNull);
    });
  });

  group('a server that is down at the moment', () {
    UnifiedTitlePlayback titleWithRealOwners(List<MediaItem> copies) {
      final sources = [
        for (final copy in copies) UnifiedMediaSource.fromItem(copy, externalIds: const ExternalIds(tmdb: 1)),
      ];
      return UnifiedTitlePlayback(
        routeContext: UnifiedMediaRouteContext(
          groupId: 'g',
          identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
          sourceKey: sources.first.sourceKey,
          titleSources: sources,
          availableSourceKeys: [for (final s in sources) s.sourceKey],
          coverage: SourceCoverageState.none,
          intent: UnifiedActivationIntent.play,
        ),
        sources: sources,
        gate: UnifiedSourceGate(
          clientFor: manager.getClient,
          isOnline: manager.isServerOnline,
          isAuthRejected: (_) => false,
          isVisible: (_) => true,
          isOwn: (id) => !manager.isSomeoneElsesServer(id),
          hiddenLibraryKeys: () => const {},
          isRestrictedProfile: () async => false,
        ),
      );
    }

    test(
      'without a client it counts as the viewer\'s until it proves otherwise, and the queue holds the write',
      () async {
        await UnifiedProgressMirror(
          queue: queue,
          playing: mirrorFilm('playing'),
          known: titleWithRealOwners([mirrorFilm('playing'), mirrorFilm('nas')]),
        ).write(stop, length, watched: false);

        expect((await db.getLatestWatchAction('nas:film'))?.actionType, 'mirroredProgress');
      },
    );

    test('a server with a client that is not the viewer\'s stays out', () async {
      manager.debugRegisterClientForTesting(MirrorServer('friend'));

      await UnifiedProgressMirror(
        queue: queue,
        playing: mirrorFilm('playing'),
        known: titleWithRealOwners([mirrorFilm('playing'), mirrorFilm('friend')]),
      ).write(stop, length, watched: false);

      expect(await db.getLatestWatchAction('friend:film'), isNull);
    });
  });

  group('what the session wires up', () {
    testWidgets('a play that ran offline leaves out a library this profile hides', (tester) async {
      manager
        ..debugMarkAdministeredForTesting(ServerId('hidden'))
        ..debugRegisterClientForTesting(_Answers('playing', const []))
        ..debugRegisterClientForTesting(
          _Answers('hidden', [mirrorFilm('hidden').copyWith(libraryId: 'kids', libraryTitle: 'Kids')]),
        )
        ..debugRegisterClientForTesting(_Answers('other', [mirrorFilm('other')]));
      final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(multiServer.dispose);
      late BuildContext inside;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: _Hidden(const {'hidden:kids'})),
          ],
          child: Builder(
            builder: (context) {
              inside = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final unbind = bindOwnPlayMirror(inside, queue);
      addTearDown(unbind);

      await tester.runAsync(() async {
        queue.onOwnPlayReplayed!(mirrorFilm('playing'), stop, length, watched: false);
        final other = manager.getClient(ServerId('other'))! as _Answers;
        await other.positionsFor(1);
      });

      expect((manager.getClient(ServerId('hidden'))! as _Answers).positions, isEmpty);
    });

    test('the wiring lives inside the profile session, where this profile\'s hidden libraries are', () {
      final session = File('lib/navigation/profile_session_screen.dart').readAsStringSync();
      final root = File('lib/main.dart').readAsStringSync();

      expect(session, contains('bindOwnPlayMirror(context, queue)'));
      expect(root, isNot(contains('onOwnPlayReplayed')));
    });

    test('a session that ended leaves nothing behind', () {
      final unbind = bindOwnPlayMirror(_Mounted(), queue);

      unbind();

      expect(queue.onOwnPlayReplayed, isNull);
    });
  });

  group('who a tracker reports to', () {
    UnifiedTitlePlayback title() => titleOf([mirrorFilm('playing'), mirrorFilm('other')]);
    UnifiedTitleDiscovery discovery() =>
        UnifiedTitleDiscovery(findSources: (_, _) async => const [], gate: title().gate);

    test('held: what the play came with', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      unifiedSettledCallback(metadata: mirrorFilm('playing'), queue: queue, title: title(), discovery: null)!(
        stop,
        length,
        watched: false,
      );

      await other.positionsFor(1);
      expect(other.positions, [stop.inMilliseconds]);
    });

    test('not held: the title of another item stays out of it', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      final callback = unifiedSettledCallback(
        metadata: mirrorFilm('elsewhere'),
        queue: queue,
        title: title(),
        discovery: discovery(),
      );
      callback!(stop, length, watched: false);
      await pumpEventQueue();

      expect(other.positions, isEmpty);
    });

    test('no title and no discovery: nothing to reach', () {
      expect(
        unifiedSettledCallback(metadata: mirrorFilm('playing'), queue: queue, title: null, discovery: null),
        isNull,
      );
    });

    test('a title it does not hold and no discovery: nothing to reach either', () {
      expect(
        unifiedSettledCallback(metadata: mirrorFilm('elsewhere'), queue: queue, title: title(), discovery: null),
        isNull,
      );
    });

    test('no queue: nowhere to write', () {
      expect(
        unifiedSettledCallback(metadata: mirrorFilm('playing'), queue: null, title: title(), discovery: discovery()),
        isNull,
      );
    });
  });
}

/// The replay reads the item once; what the copies hear reads it again.
class _Answers extends MirrorServer {
  _Answers(super.id, this.matches) : super();

  final List<MediaItem> matches;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds(tmdb: 1);

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async => matches;
}

class _Hidden extends ChangeNotifier implements HiddenLibrariesProvider {
  _Hidden(this.hiddenLibraryKeys);

  @override
  final Set<String> hiddenLibraryKeys;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mounted extends Fake implements BuildContext {
  @override
  bool get mounted => true;
}

class _AnswersLater extends MirrorServer {
  _AnswersLater(super.id, this.first, this.later);

  final MediaItem first;
  final Future<MediaItem?> later;
  var _reads = 0;

  @override
  Future<MediaItem?> fetchItem(String id) async => ++_reads <= 1 ? first : later;
}
