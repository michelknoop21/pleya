/// A play or a mark that came without its other sources finds them afterwards,
/// and only on proof: a write must never land on a same-named title (besluit 3
/// of DEC-XXX "Eén titel over servers heen").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
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

class _Client implements MediaServerClient, CopyStateClient {
  _Client(
    this._id, {
    this.ids = const {},
    this.episodes = const [],
    this.matches = const [],
    this.failsIds = false,
    this.idsGate,
    this.hangsLookup = false,
  });

  final String _id;
  final Map<String, ExternalIds> ids;
  final List<MediaItem> episodes;
  final List<MediaItem> matches;
  final bool failsIds;
  final Future<void>? idsGate;
  final bool hangsLookup;
  final stopped = <String>[];
  final asked = <MediaIdentity>[];
  final reported = Completer<void>();
  var idsAsked = 0;

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
    idsAsked++;
    await idsGate;
    return ids[itemId] ?? const ExternalIds();
  }

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) {
    asked.add(identity);
    return hangsLookup ? Completer<List<MediaItem>>().future : Future.value(matches);
  }

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async => episodes;

  @override
  Future<MediaItem?> fetchItem(String id) async =>
      MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, serverId: _id);

  @override
  Future<MediaItem?> readCopyState(String id) => fetchItem(id);

  @override
  bool get movesCopyWithoutViewing => true;

  @override
  Future<bool> writeCopyState(
    MediaItem item, {
    required Duration position,
    Duration? duration,
    required bool watched,
  }) async {
    stopped.add(item.id);
    if (!reported.isCompleted) reported.complete();
    return true;
  }

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
    for (final server in const ['playing', 'other', 'known', 'found', 'plex-a', 'plex-b', 'pleya', 'fast', 'slow']) {
      manager.debugMarkAdministeredForTesting(ServerId(server));
    }
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
    isOwn: (_) => true,
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
    final sources = [for (final copy in copies) UnifiedMediaSource.fromItem(copy, externalIds: shared)];
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

  test('the proof of every candidate comes in side by side', () async {
    final proof = Completer<void>();
    final b = _Client('b', ids: {'film-b': shared}, idsGate: proof.future);
    final c = _Client('c', ids: {'film-c': shared}, idsGate: proof.future);
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(b)
      ..debugRegisterClientForTesting(c);

    final found = discoveryOf([_film('b', 'film-b'), _film('c', 'film-c')]).titleOf(_film('playing', 'film-a'));
    await pumpEventQueue();

    expect((b.idsAsked, c.idsAsked), (1, 1), reason: 'the second is asked while the first still has to answer');
    proof.complete();
    expect((await found)?.sources.map((s) => s.serverId.value), containsAll(['b', 'c']));
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

  test('a server that does not answer leaves it on the source that plays, once the limit is up', () {
    manager.debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}));
    final never = UnifiedTitleDiscovery(
      gate: gate(),
      timeout: const Duration(seconds: 20),
      findSources: (_, _) => Completer<List<MediaItem>>().future,
    );

    fakeAsync((clock) {
      UnifiedTitlePlayback? title;
      var answered = false;
      never.titleOf(_film('playing', 'film-a')).then((found) {
        title = found;
        answered = true;
      });

      clock.elapse(const Duration(seconds: 19));
      expect(answered, isFalse, reason: 'it really waits');

      clock.elapse(const Duration(seconds: 2));
      expect(answered, isTrue);
      expect(title, isNull);
    });
  });

  group('a guid that says nothing proves nothing', () {
    for (final guid in const ['local://1234', 'LOCAL://1234', 'com.plexapp.agents.none://1234?lang=xn']) {
      test('$guid is no identity', () async {
        manager
          ..debugRegisterClientForTesting(_Client('playing'))
          ..debugRegisterClientForTesting(_Client('other'));
        var asked = false;

        final title = await discoveryOf([
          _film('other', 'film-b').copyWith(guid: guid),
        ], onAsk: (_) => asked = true).titleOf(_film('playing', 'film-a').copyWith(guid: guid));

        expect(title, isNull);
        expect(asked, isFalse);
      });

      test('$guid stays out of the question when the numbers can do it', () async {
        manager
          ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
          ..debugRegisterClientForTesting(_Client('other', ids: {'film-b': shared}));
        MediaIdentity? asked;

        await discoveryOf([
          _film('other', 'film-b'),
        ], onAsk: (i) => asked = i).titleOf(_film('playing', 'film-a').copyWith(guid: guid));

        expect(asked?.guid, isNull);
        expect(asked?.externalIds.tmdb, 45745);
      });
    }

    test('a real guid goes out as the server stored it', () async {
      manager
        ..debugRegisterClientForTesting(_Client('playing'))
        ..debugRegisterClientForTesting(_Client('other'));
      MediaIdentity? asked;

      await discoveryOf(
        [],
        onAsk: (i) => asked = i,
      ).titleOf(_film('playing', 'film-a').copyWith(guid: 'plex://Movie/AbC'));

      expect(asked?.guid, 'plex://Movie/AbC');
    });
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
        isOwn: (_) => true,
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

  group('looked up on the servers of this viewer', () {
    Future<BuildContext> pumped(WidgetTester tester) async {
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
      return context;
    }

    void own(String server) => manager.debugMarkAdministeredForTesting(ServerId(server));

    testWidgets('a slow server costs the others nothing', (tester) async {
      manager
        ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
        ..debugRegisterClientForTesting(_Client('slow', hangsLookup: true))
        ..debugRegisterClientForTesting(_Client('fast', ids: {'film-b': shared}, matches: [_film('fast', 'film-b')]));
      ['playing', 'slow', 'fast'].forEach(own);
      final context = await pumped(tester);
      final film = _film('playing', 'film-a');

      final title = await tester.runAsync(
        () => UnifiedTitleDiscovery.of(context, serverWait: const Duration(milliseconds: 1))!.titleOf(film),
      );

      expect((await tester.runAsync(() => title!.copiesOf(film)))?.map((c) => c.globalKey), ['fast:film-b']);
    });

    testWidgets('a match without a server is stamped with the one that answered', (tester) async {
      final unstamped = MediaItem(id: 'film-b', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel');
      manager
        ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
        ..debugRegisterClientForTesting(_Client('other', ids: {'film-b': shared}, matches: [unstamped]));
      ['playing', 'other'].forEach(own);
      final context = await pumped(tester);
      final film = _film('playing', 'film-a');

      final title = await tester.runAsync(() => UnifiedTitleDiscovery.of(context)!.titleOf(film));

      expect((await tester.runAsync(() => title!.copiesOf(film)))?.map((c) => c.globalKey), ['other:film-b']);
    });

    testWidgets('one server: nothing to look up', (tester) async {
      manager.debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}));
      own('playing');

      expect(UnifiedTitleDiscovery.of(await pumped(tester)), isNull);
    });

    testWidgets('the server that plays is not asked for its own copy', (tester) async {
      final playing = _Client('playing', ids: {'film-a': shared});
      final other = _Client('other', ids: {'film-b': shared}, matches: [_film('other', 'film-b')]);
      manager
        ..debugRegisterClientForTesting(playing)
        ..debugRegisterClientForTesting(other);
      ['playing', 'other'].forEach(own);
      final context = await pumped(tester);

      await tester.runAsync(() => UnifiedTitleDiscovery.of(context)!.titleOf(_film('playing', 'film-a')));

      expect(playing.asked, isEmpty);
      expect(other.asked, hasLength(1));
    });

    testWidgets('a server someone else runs is not asked', (tester) async {
      final friend = _Client('friend', ids: {'film-b': shared}, matches: [_film('friend', 'film-b')]);
      final mine = _Client('mine', ids: {'film-c': shared}, matches: [_film('mine', 'film-c')]);
      manager
        ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
        ..debugRegisterClientForTesting(friend)
        ..debugRegisterClientForTesting(mine);
      ['playing', 'mine'].forEach(own);
      final context = await pumped(tester);

      await tester.runAsync(() => UnifiedTitleDiscovery.of(context)!.titleOf(_film('playing', 'film-a')));

      expect(friend.asked, isEmpty);
      expect(mine.asked, hasLength(1));
    });

    testWidgets('only someone else\'s servers: no lookup at all', (tester) async {
      manager
        ..debugRegisterClientForTesting(_Client('neighbour'))
        ..debugRegisterClientForTesting(_Client('friend'));

      expect(UnifiedTitleDiscovery.of(await pumped(tester)), isNull);
    });
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
    await known.reported.future;

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
