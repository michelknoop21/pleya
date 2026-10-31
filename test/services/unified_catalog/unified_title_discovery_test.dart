/// A play or a mark that came without its other sources finds them afterwards,
/// and only on proof: a write must never land on a same-named title (besluit 3
/// of DEC-XXX "Eén titel over servers heen").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/unified_progress_mirror.dart';
import 'package:pleya/services/unified_catalog/unified_title_discovery.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _Client implements MediaServerClient {
  _Client(
    this._id, {
    this.ids = const {},
    this.episodes = const [],
    this.matches = const [],
    this.failsIds = false,
    this.idsDelay = Duration.zero,
    this.hangsLookup = false,
  });

  final String _id;
  final Map<String, ExternalIds> ids;
  final List<MediaItem> episodes;
  final List<MediaItem> matches;
  final bool failsIds;
  final Duration idsDelay;
  final bool hangsLookup;
  final stopped = <String>[];

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  double get watchedThreshold => 0.9;

  @override
  bool get marksWatchedOnPlaybackStopped => false;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    if (failsIds) throw StateError('server down');
    await Future<void>.delayed(idsDelay);
    return ids[itemId] ?? const ExternalIds();
  }

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) =>
      hangsLookup ? Completer<List<MediaItem>>().future : Future.value(matches);

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async => episodes;

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

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
  }) async => stopped.add(itemId);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _film(String server, String id) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel', year: 2010, serverId: server);

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

  UnifiedSourceGate gate() => UnifiedSourceGate(
    clientFor: manager.getClient,
    isOnline: manager.isServerOnline,
    isAuthRejected: (_) => false,
    isVisible: (_) => true,
    hiddenLibraryKeys: () => const {},
    isRestrictedProfile: () async => false,
  );

  UnifiedTitleDiscovery discoveryOf(
    List<MediaItem> answers, {
    Duration timeout = const Duration(seconds: 1),
    void Function(MediaIdentity identity)? onAsk,
  }) => UnifiedTitleDiscovery(
    gate: gate(),
    timeout: timeout,
    findSources: (identity, except) async {
      onAsk?.call(identity);
      return answers;
    },
  );

  const shared = ExternalIds(tmdb: 45745);

  UnifiedTitlePlayback _titleOf(List<MediaItem> copies) {
    final sources = [for (final copy in copies) UnifiedMediaSource.fromItem(copy)];
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
      gate: gate(),
    );
  }

  test('a film the row showed on one server still reaches the other', () async {
    final other = _Client('other', ids: {'film-b': shared});
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(other);
    final playing = _film('playing', 'film-a').copyWith(durationMs: 7200000);
    final discovery = discoveryOf([_film('other', 'film-b').copyWith(durationMs: 7200000)]);

    await UnifiedProgressMirror(
      find: () => discovery.titleOf(playing),
      playing: playing,
      queue: queue,
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.stopped, ['film-b']);
  });

  test('the proof of every candidate comes in side by side, inside the overall limit', () async {
    const wait = Duration(milliseconds: 100);
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}, idsDelay: wait))
      ..debugRegisterClientForTesting(_Client('b', ids: {'film-b': shared}, idsDelay: wait))
      ..debugRegisterClientForTesting(_Client('c', ids: {'film-c': shared}, idsDelay: wait));
    final discovery = discoveryOf([
      _film('b', 'film-b'),
      _film('c', 'film-c'),
    ], timeout: const Duration(milliseconds: 260));

    final title = await discovery.titleOf(_film('playing', 'film-a'));

    expect(title?.sources.map((s) => s.serverId.value), containsAll(['b', 'c']));
  });

  test('a same-named title without a shared number is not a copy', () async {
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(_Client('other', ids: {'film-b': const ExternalIds(tmdb: 1)}));

    final title = await discoveryOf([_film('other', 'film-b')]).titleOf(_film('playing', 'film-a'));

    expect(title, isNull);
  });

  test('nothing to prove with: the servers are not even asked', () async {
    manager
      ..debugRegisterClientForTesting(_Client('playing'))
      ..debugRegisterClientForTesting(_Client('other'));
    var asked = false;

    final title = await discoveryOf([], onAsk: (_) => asked = true).titleOf(_film('playing', 'film-a'));

    expect(title, isNull);
    expect(asked, isFalse);
  });

  test('a server that does not answer leaves it on the source that plays', () async {
    manager.debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}));
    final never = UnifiedTitleDiscovery(
      gate: gate(),
      timeout: Duration.zero,
      findSources: (_, _) => Completer<List<MediaItem>>().future,
    );

    expect(await never.titleOf(_film('playing', 'film-a')), isNull);
  });

  test('a lookup that fails stays inside', () async {
    manager.debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}));
    final failing = UnifiedTitleDiscovery(gate: gate(), findSources: (_, _) async => throw StateError('down'));

    expect(await failing.titleOf(_film('playing', 'film-a')), isNull);
  });

  test('every server with the title counts: a guid on one does not end the search by number on another', () async {
    const plexGuid = 'plex://movie/abc';
    manager
      ..debugRegisterClientForTesting(_Client('plex-a', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(_Client('plex-b', ids: {'film-b': shared}))
      ..debugRegisterClientForTesting(_Client('pleya', ids: {'film-c': shared}));
    final film = _film('plex-a', 'film-a').copyWith(guid: plexGuid);

    final title = await discoveryOf([
      _film('plex-b', 'film-b').copyWith(guid: plexGuid),
      _film('pleya', 'film-c'),
    ]).titleOf(film);
    final copies = await title?.copiesOf(film);

    expect(copies?.map((c) => c.globalKey), unorderedEquals(['plex-b:film-b', 'pleya:film-c']));
  });

  test('a children\'s profile looks nothing up: it writes to the sources it already sees', () async {
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(_Client('other', ids: {'film-b': shared}));
    var asked = false;
    final restricted = UnifiedTitleDiscovery(
      gate: UnifiedSourceGate(
        clientFor: manager.getClient,
        isOnline: manager.isServerOnline,
        isAuthRejected: (_) => false,
        isVisible: (_) => true,
        hiddenLibraryKeys: () => const {},
        isRestrictedProfile: () async => true,
      ),
      findSources: (_, _) async {
        asked = true;
        return [_film('other', 'film-b')];
      },
    );

    expect(await restricted.titleOf(_film('playing', 'film-a')), isNull);
    expect(asked, isFalse);
  });

  test('a playing server that stopped answering still finds the others by guid', () async {
    const plexGuid = 'plex://movie/abc';
    manager
      ..debugRegisterClientForTesting(_Client('playing', failsIds: true))
      ..debugRegisterClientForTesting(_Client('other'));
    final film = _film('playing', 'film-a').copyWith(guid: plexGuid);

    final title = await discoveryOf([_film('other', 'film-b').copyWith(guid: plexGuid)]).titleOf(film);

    expect((await title?.copiesOf(film))?.map((c) => c.globalKey), ['other:film-b']);
  });

  testWidgets('a slow server costs the others nothing', (tester) async {
    final slow = _Client('slow', hangsLookup: true);
    final fast = _Client('fast', ids: {'film-b': shared}, matches: [_film('fast', 'film-b')]);
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(slow)
      ..debugRegisterClientForTesting(fast);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: Builder(
          builder: (host) {
            context = host;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final film = _film('playing', 'film-a');

    final title = await tester.runAsync(
      () => UnifiedTitleDiscovery.of(context, serverWait: const Duration(milliseconds: 50))!.titleOf(film),
    );

    expect((await tester.runAsync(() => title!.copiesOf(film)))?.map((c) => c.globalKey), ['fast:film-b']);
  });

  test('what the play already knows goes first, and the lookup adds only the rest', () async {
    final known = _Client('known');
    final found = _Client('found', ids: {'film-c': shared});
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(known)
      ..debugRegisterClientForTesting(found);
    final playing = _film('playing', 'film-a');
    final group = _titleOf([playing, _film('known', 'film-b')]);
    final discovery = discoveryOf([_film('known', 'film-b'), _film('found', 'film-c')]);
    final lookup = Completer<UnifiedTitlePlayback?>();

    final written = UnifiedProgressMirror(
      known: group,
      find: () => lookup.future,
      playing: playing,
      queue: queue,
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);
    await pumpEventQueue();
    for (var i = 0; i < 40 && known.stopped.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(known.stopped, ['film-b'], reason: 'the group does not wait for the lookup');
    lookup.complete(discovery.titleOf(playing));
    await written;

    expect(found.stopped, ['film-c']);
    expect(known.stopped, ['film-b'], reason: 'once');
  });

  test('an episode finds its series and reaches its copy', () async {
    final copy = MediaItem(
      id: 'ep-b',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      grandparentId: 'show-b',
      parentIndex: 1,
      index: 2,
      serverId: 'other',
    );
    final other = _Client('other', ids: {'show-b': shared}, episodes: [copy]);
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'show-a': shared}))
      ..debugRegisterClientForTesting(other);
    final episode = MediaItem(
      id: 'ep-a',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      grandparentId: 'show-a',
      grandparentTitle: 'Severance',
      parentIndex: 1,
      index: 2,
      serverId: 'playing',
    );
    MediaIdentity? asked;
    final show = MediaItem(id: 'show-b', backend: MediaBackend.plex, kind: MediaKind.show, serverId: 'other');

    final title = await discoveryOf([show], onAsk: (i) => asked = i).titleOf(episode);
    final copies = await title?.copiesOf(episode);

    expect(asked?.kind, MediaKind.show);
    expect(asked?.title, 'Severance');
    expect(copies?.map((c) => c.globalKey), ['other:ep-b']);
  });
}
