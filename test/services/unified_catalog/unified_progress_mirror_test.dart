/// A settled play reaches the other sources of its title through the existing
/// watch queue, and nothing that goes wrong there reaches the play (besluit 3
/// of DEC-XXX "Eén titel over servers heen").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/unified_progress_mirror.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

import '../../test_helpers/mirror_server.dart';
import '../../test_helpers/prefs.dart';

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late OfflineWatchSyncService queue;

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

  UnifiedProgressMirror mirror(List<MediaItem> copies, {required String playing, Set<String> rejected = const {}}) {
    final sources = [
      for (final copy in copies) UnifiedMediaSource.fromItem(copy, externalIds: const ExternalIds(tmdb: 1)),
    ];
    final key = '$playing:film';
    final route = UnifiedMediaRouteContext(
      groupId: 'g',
      identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
      sourceKey: key,
      titleSources: sources,
      availableSourceKeys: [for (final s in sources) s.sourceKey],
      coverage: SourceCoverageState.none,
      intent: UnifiedActivationIntent.play,
    );
    return UnifiedProgressMirror(
      queue: queue,
      playing: copies.firstWhere((c) => c.serverId == playing),
      known: UnifiedTitlePlayback(
        routeContext: route,
        sources: sources,
        gate: UnifiedSourceGate(
          clientFor: manager.getClient,
          isOnline: manager.isServerOnline,
          isAuthRejected: (id) => rejected.contains(id.value),
          isVisible: (_) => true,
          isOwn: (_) => true,
          hiddenLibraryKeys: () => const {},
          isRestrictedProfile: () async => false,
        ),
      ),
    );
  }

  test('the position lands on the other source', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other);

    await mirror([
      mirrorFilm('playing'),
      mirrorFilm('other'),
    ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.positions, [50 * 60000]);
    expect(await queue.getPendingSyncCount(), 0, reason: 'a write that landed leaves no row');
  });

  test('a source that is not reachable keeps the write for when it is back', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other, online: false);

    await mirror([
      mirrorFilm('playing'),
      mirrorFilm('other'),
    ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.positions, isEmpty);
    expect(await queue.getPendingSyncCount(), 1);
    final row = await db.getLatestWatchAction('other:film');
    expect(row?.actionType, 'mirroredProgress');
    expect(row?.viewOffset, 50 * 60000);
  });

  test('a source that refuses keeps the row for a retry and reaches nobody else', () async {
    final refusing = MirrorServer('other', refuses: true);
    final fine = MirrorServer('third');
    manager
      ..debugRegisterClientForTesting(refusing)
      ..debugRegisterClientForTesting(fine);

    await expectLater(
      mirror([
        mirrorFilm('playing'),
        mirrorFilm('other'),
        mirrorFilm('third'),
      ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false),
      completes,
    );

    expect(fine.positions, [50 * 60000]);
    final row = await db.getLatestWatchAction('other:film');
    expect(row?.syncAttempts, 1);
  });

  test('a failure in the mirror never comes out of report', () async {
    final throwing = UnifiedProgressMirror(queue: queue, playing: mirrorFilm('playing'), known: _ThrowingTitle());

    await runZonedGuarded(() async {
      throwing.report(const Duration(minutes: 1), const Duration(hours: 2), watched: false);
      await pumpEventQueue();
    }, (error, _) => fail('reached the zone: $error'));
  });

  test('a cut of a very different length keeps its own state (G7)', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other);

    await mirror([
      mirrorFilm('playing'),
      mirrorFilm('other', durationMs: 3 * mirrorHour),
    ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.positions, isEmpty);
    expect(await queue.getPendingSyncCount(), 0);
  });

  test('a rejected token gets no write and no row: a reconnect does not fix it', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other);

    await mirror(
      [mirrorFilm('playing'), mirrorFilm('other')],
      playing: 'playing',
      rejected: {'other'},
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.positions, isEmpty);
    expect(await queue.getPendingSyncCount(), 0);
  });

  test('watched on the source that plays is watched everywhere, without a second watched event', () async {
    final other = MirrorServer('other', item: mirrorFilm('other'));
    manager.debugRegisterClientForTesting(other);
    final events = <WatchStateEvent>[];
    final subscription = WatchStateNotifier().stream.listen(events.add);
    addTearDown(subscription.cancel);

    await mirror([
      mirrorFilm('playing'),
      mirrorFilm('other'),
    ], playing: 'playing').write(const Duration(minutes: 100), const Duration(hours: 2), watched: true);
    await pumpEventQueue();

    expect(other.watched, ['film']);
    expect(events.where((e) => e.changeType == WatchStateChangeType.watched && !e.isCopy), isEmpty);
    final copy = events.firstWhere((e) => e.changeType == WatchStateChangeType.progressUpdate);
    expect(copy.globalKey, 'other:film');
    expect(copy.isNowWatched, isTrue, reason: 'the page and the rails still see the copy finish');
  });

  test('a position past the end of a slightly shorter copy stops at its end', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other, online: false);

    await mirror([
      mirrorFilm('playing'),
      mirrorFilm('other', durationMs: 2 * mirrorHour - 60000),
    ], playing: 'playing').write(const Duration(hours: 2), const Duration(hours: 2), watched: false);

    expect((await db.getLatestWatchAction('other:film'))?.viewOffset, 2 * mirrorHour - 60000);
  });

  test('a profile that took over during the lookup does not get the row', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other, online: false);
    queue.setActiveProfileId('adult');
    final lookup = Completer<UnifiedTitlePlayback?>();
    final title = mirror([mirrorFilm('playing'), mirrorFilm('other')], playing: 'playing').known;

    final written = UnifiedProgressMirror(
      find: () => lookup.future,
      playing: mirrorFilm('playing'),
      queue: queue,
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);
    await pumpEventQueue();
    queue.setActiveProfileId('kid');
    lookup.complete(title);
    await written;

    expect(await db.getLatestWatchAction('other:film'), isNull, reason: 'that viewing was not this profile\'s');
  });

  test('the profile that watched gets the row', () async {
    manager.debugRegisterClientForTesting(MirrorServer('other'), online: false);
    queue.setActiveProfileId('adult');
    final title = mirror([mirrorFilm('playing'), mirrorFilm('other')], playing: 'playing').known;

    await UnifiedProgressMirror(
      find: () async => title,
      playing: mirrorFilm('playing'),
      queue: queue,
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect((await db.getLatestWatchAction('other:film'))?.profileId, 'adult');
  });

  test('a held copy mark lands on the server without telling anyone else', () async {
    final other = MirrorServer('other', item: mirrorFilm('other'));
    manager.debugRegisterClientForTesting(other);
    final events = <WatchStateEvent>[];
    final subscription = WatchStateNotifier().stream.listen(events.add);
    addTearDown(subscription.cancel);

    await queue.queueCopyMark(
      serverId: ServerId('other'),
      itemId: 'film',
      watched: true,
      profileId: queue.activeProfileId,
    );
    expect(await queue.getLocalWatchStatus('other:film'), isTrue, reason: 'waiting rows count as local state');

    await queue.syncPendingItems();
    await pumpEventQueue();

    expect(other.watched, ['film']);
    expect(await queue.getPendingSyncCount(), 0);
    final copy = events.single;
    expect(copy.isCopy, isTrue, reason: 'surfaces hear it; Trakt counted the viewing where it happened');
    expect(copy.globalKey, 'other:film');
  });

  test('a row written during a running sync does not wait for the next reconnect', () async {
    final gate = Completer<void>();
    final other = MirrorServer('other', holdUntil: gate.future);
    manager.debugRegisterClientForTesting(other);
    Future<void> queueFor(String itemId, int offset) => queue.queueMirroredProgress(
      serverId: ServerId('other'),
      itemId: itemId,
      viewOffset: offset,
      duration: mirrorHour,
      watched: false,
      profileId: queue.activeProfileId,
    );

    await queueFor('first', 1000);
    final running = queue.syncPendingItems();
    await pumpEventQueue();
    // The running sync has read its list by now, and stands in its first write.
    await queueFor('second', 2000);
    await queue.syncPendingItems(queueIfBusy: true);
    final drained = Completer<void>();
    queue.addListener(() {
      if (other.positions.length == 2 && !queue.isSyncing && !drained.isCompleted) drained.complete();
    });
    gate.complete();
    await running;
    await drained.future;

    expect(other.positions, hasLength(2));
  });
}

class _ThrowingTitle implements UnifiedTitlePlayback {
  @override
  Future<List<MediaItem>> copiesOf(MediaItem item) async => throw StateError('no lists');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
