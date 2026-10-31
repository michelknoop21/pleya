/// A settled play reaches the other sources of its title through the existing
/// watch queue, and nothing that goes wrong there reaches the play (besluit 3
/// of DEC-XXX "Eén titel over servers heen").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/unified_progress_mirror.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

import '../../test_helpers/prefs.dart';

class _Server implements MediaServerClient {
  _Server(this._id, {this.refuses = false, this.item});

  final String _id;
  final bool refuses;
  final MediaItem? item;
  final stopped = <int>[];
  final watched = <String>[];

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  double get watchedThreshold => 0.9;

  @override
  bool get marksWatchedOnPlaybackStopped => false;

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async => item;

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    if (refuses) throw StateError('server refused');
    stopped.add(position.inMilliseconds);
  }

  @override
  Future<void> markWatched(MediaItem item) async {
    if (refuses) throw StateError('server refused');
    watched.add(item.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _hour = 60 * 60 * 1000;

MediaItem _film(String server, {int durationMs = 2 * _hour}) => MediaItem(
  id: 'film',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Sintel',
  serverId: server,
  serverName: server,
  durationMs: durationMs,
);

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late OfflineWatchSyncService queue;

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    manager = MultiServerManager();
    queue = OfflineWatchSyncService(database: db, serverManager: manager);
  });

  tearDown(() async {
    queue.dispose();
    manager.dispose();
    await db.close();
  });

  UnifiedProgressMirror mirror(List<MediaItem> copies, {required String playing, Set<String> rejected = const {}}) {
    final sources = [for (final copy in copies) UnifiedMediaSource.fromItem(copy)];
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
      title: UnifiedTitlePlayback(
        routeContext: route,
        sources: sources,
        gate: UnifiedSourceGate(
          clientFor: manager.getClient,
          isOnline: manager.isServerOnline,
          isAuthRejected: (id) => rejected.contains(id.value),
          isVisible: (_) => true,
          hiddenLibraryKeys: () => const {},
          isRestrictedProfile: () async => false,
        ),
      ),
    );
  }

  test('the position lands on the other source', () async {
    final other = _Server('other');
    manager.debugRegisterClientForTesting(other);

    await mirror([
      _film('playing'),
      _film('other'),
    ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.stopped, [50 * 60000]);
    expect(await queue.getPendingSyncCount(), 0, reason: 'a write that landed leaves no row');
  });

  test('a source that is not reachable keeps the write for when it is back', () async {
    final other = _Server('other');
    manager.debugRegisterClientForTesting(other, online: false);

    await mirror([
      _film('playing'),
      _film('other'),
    ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.stopped, isEmpty);
    expect(await queue.getPendingSyncCount(), 1);
    final row = await db.getLatestWatchAction('other:film');
    expect(row?.actionType, 'mirroredProgress');
    expect(row?.viewOffset, 50 * 60000);
  });

  test('a source that refuses keeps the row for a retry and reaches nobody else', () async {
    final refusing = _Server('other', refuses: true);
    final fine = _Server('third');
    manager
      ..debugRegisterClientForTesting(refusing)
      ..debugRegisterClientForTesting(fine);

    await expectLater(
      mirror([
        _film('playing'),
        _film('other'),
        _film('third'),
      ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false),
      completes,
    );

    expect(fine.stopped, [50 * 60000]);
    final row = await db.getLatestWatchAction('other:film');
    expect(row?.syncAttempts, 1);
  });

  test('a failure in the mirror never comes out of report', () async {
    final throwing = UnifiedProgressMirror(queue: queue, playing: _film('playing'), title: _ThrowingTitle());

    await runZonedGuarded(() async {
      throwing.report(const Duration(minutes: 1), const Duration(hours: 2), watched: false);
      await pumpEventQueue();
    }, (error, _) => fail('reached the zone: $error'));
  });

  test('a cut of a very different length keeps its own state (G7)', () async {
    final other = _Server('other');
    manager.debugRegisterClientForTesting(other);

    await mirror([
      _film('playing'),
      _film('other', durationMs: 3 * _hour),
    ], playing: 'playing').write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.stopped, isEmpty);
    expect(await queue.getPendingSyncCount(), 0);
  });

  test('a rejected token gets no write and no row: a reconnect does not fix it', () async {
    final other = _Server('other');
    manager.debugRegisterClientForTesting(other);

    await mirror(
      [_film('playing'), _film('other')],
      playing: 'playing',
      rejected: {'other'},
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.stopped, isEmpty);
    expect(await queue.getPendingSyncCount(), 0);
  });

  test('watched on the source that plays is watched everywhere, without a second watched event', () async {
    final other = _Server('other', item: _film('other'));
    manager.debugRegisterClientForTesting(other);
    final events = <WatchStateEvent>[];
    final subscription = WatchStateNotifier().stream.listen(events.add);
    addTearDown(subscription.cancel);

    await mirror([
      _film('playing'),
      _film('other'),
    ], playing: 'playing').write(const Duration(minutes: 100), const Duration(hours: 2), watched: true);
    await pumpEventQueue();

    expect(other.watched, ['film']);
    expect(events.where((e) => e.changeType == WatchStateChangeType.watched), isEmpty);
    final copy = events.singleWhere((e) => e.globalKey == 'other:film');
    expect(copy.changeType, WatchStateChangeType.progressUpdate);
    expect(copy.isNowWatched, isTrue, reason: 'the page and the rails still see the copy finish');
  });

  test('a position past the end of a slightly shorter copy stops at its end', () async {
    final other = _Server('other');
    manager.debugRegisterClientForTesting(other, online: false);

    await mirror([
      _film('playing'),
      _film('other', durationMs: 2 * _hour - 60000),
    ], playing: 'playing').write(const Duration(hours: 2), const Duration(hours: 2), watched: false);

    expect((await db.getLatestWatchAction('other:film'))?.viewOffset, 2 * _hour - 60000);
  });

  test('a row written during a running sync does not wait for the next reconnect', () async {
    final other = _Server('other');
    manager.debugRegisterClientForTesting(other);
    await queue.queueMirroredProgress(
      serverId: ServerId('other'),
      itemId: 'film',
      viewOffset: 1000,
      duration: _hour,
      watched: false,
    );
    final running = queue.syncPendingItems();
    await queue.syncPendingItems(queueIfBusy: true);
    await running;
    await pumpEventQueue();
    await untilCalled(() async => await queue.getPendingSyncCount() == 0);

    expect(await queue.getPendingSyncCount(), 0);
  });
}

Future<void> untilCalled(Future<bool> Function() done) async {
  for (var i = 0; i < 20; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _ThrowingTitle implements UnifiedTitlePlayback {
  @override
  Future<List<MediaItem>> copiesOf(MediaItem item) async => throw StateError('no lists');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
