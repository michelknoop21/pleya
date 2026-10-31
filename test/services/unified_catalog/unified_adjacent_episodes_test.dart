/// What the player gets as next and previous on a title with more sources: the
/// real queue provider and the real navigation service, in the order
/// `_loadAdjacentEpisodes` runs them, walking a series the way a viewer does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/models/plex/play_queue_response.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/episode_navigation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/unified_adjacent_episodes.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:provider/provider.dart';

class _Client implements MediaServerClient {
  _Client(this._id, this.episodes, {this.keepsQueueOnServer = false});

  final String _id;
  final List<MediaItem> episodes;
  final bool keepsQueueOnServer;

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => keepsQueueOnServer ? MediaBackend.plex : MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async => episodes;

  @override
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) async => keepsQueueOnServer ? null : episodes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _show(String server) => MediaItem(
  id: 'show-$server',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.show,
  title: 'Severance',
  serverId: server,
);

MediaItem _episode(String server, int number) => MediaItem(
  id: '$server-e$number',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: 'E$number',
  grandparentId: 'show-$server',
  parentIndex: 1,
  index: number,
  serverId: server,
);

PlexMediaItem _queued(String server, int number) => PlexMediaItem(
  id: '$server-e$number',
  kind: MediaKind.episode,
  title: 'E$number',
  grandparentId: 'show-$server',
  parentIndex: 1,
  index: number,
  serverId: server,
  playQueueItemId: 1000 + number,
);

UnifiedTitlePlayback _title(MultiServerManager manager) {
  final sources = [UnifiedMediaSource.fromItem(_show('chosen')), UnifiedMediaSource.fromItem(_show('other'))];
  return UnifiedTitlePlayback(
    routeContext: UnifiedMediaRouteContext(
      groupId: 'g',
      identity: CanonicalMediaIdentity.show(title: 'Severance'),
      sourceKey: 'chosen:show-chosen',
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
      isOwn: (_) => true,
      hiddenLibraryKeys: () => const {},
      isRestrictedProfile: () async => false,
    ),
  );
}

void main() {
  late PlaybackStateProvider playback;
  late MultiServerManager manager;
  late UnifiedTitlePlayback title;
  late BuildContext context;
  late EpisodeNavigationService navigation;

  // Fresh per test: it keeps episode lists per series.
  setUp(() => navigation = EpisodeNavigationService());

  Future<void> pumpHost(
    WidgetTester tester, {
    required List<int> chosen,
    required List<int> other,
    bool plex = false,
  }) async {
    manager = MultiServerManager()
      ..debugRegisterClientForTesting(
        _Client('chosen', [for (final e in chosen) _episode('chosen', e)], keepsQueueOnServer: plex),
      )
      ..debugRegisterClientForTesting(_Client('other', [for (final e in other) _episode('other', e)]));
    playback = PlaybackStateProvider();
    title = _title(manager);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<PlaybackStateProvider>.value(value: playback),
        ],
        child: Builder(
          builder: (host) {
            context = host;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  /// The steps `_loadAdjacentEpisodes` takes for the item that plays now.
  Future<AdjacentEpisodes> adjacentOf(WidgetTester tester, MediaItem current) async {
    final queued = (await tester.runAsync(() => navigation.loadAdjacentEpisodes(context: context, metadata: current)))!;
    return (await tester.runAsync(
      () => adjacentAcrossSources(
        title: title,
        current: current,
        queued: queued,
        queue: playback,
        inWatchTogether: false,
      ),
    ))!;
  }

  /// Follows Next from [start] the way the player does, and answers where it
  /// went: `_reloadMediaInPlace` tells the queue the item that now plays.
  Future<List<String>> walk(WidgetTester tester, MediaItem start) async {
    final seen = <String>[];
    var current = start;
    for (var i = 0; i < 12; i++) {
      final next = (await adjacentOf(tester, current)).next;
      if (next == null) break;
      seen.add('${next.serverId}:${next.index}');
      playback.setCurrentItem(next);
      current = next;
    }
    return seen;
  }

  group('a queue on the client, Jellyfin and Emby', () {
    testWidgets('the series goes on past the end of the chosen server', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3, 4], other: [1, 2, 3, 4, 5, 6, 7, 8]);

      expect(await walk(tester, _episode('chosen', 3)), ['chosen:4', 'other:5', 'other:6', 'other:7', 'other:8']);
    });

    testWidgets('two missing episodes in a row are both played', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3, 4, 7, 8], other: [1, 2, 3, 4, 5, 6, 7, 8]);

      expect(await walk(tester, _episode('chosen', 4)), ['other:5', 'other:6', 'chosen:7', 'chosen:8']);
    });

    testWidgets('Previous on a borrowed episode is the one before it', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3, 4, 6], other: [1, 2, 3, 4, 5, 6]);
      await adjacentOf(tester, _episode('chosen', 4));

      final adjacent = await adjacentOf(tester, _episode('other', 5));

      expect(adjacent.previous?.globalKey, 'chosen:chosen-e4');
      expect(adjacent.next?.globalKey, 'chosen:chosen-e6');
    });
  });

  group('a queue on the server, Plex', () {
    Future<void> seedQueue(List<int> numbers, int selected, {String? context, bool shuffled = false}) =>
        playback.setPlaybackFromPlayQueue(
          PlayQueueResponse(
            playQueueID: 1,
            playQueueSelectedItemID: 1000 + selected,
            playQueueShuffled: shuffled,
            playQueueTotalCount: numbers.length,
            playQueueVersion: 1,
            size: numbers.length,
            items: [for (final e in numbers) _queued('chosen', e)],
          ),
          context ?? 'show-chosen',
        );

    testWidgets('the series goes on past the end of the queue', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3, 4], other: [1, 2, 3, 4, 5, 6, 7, 8], plex: true);
      await seedQueue([1, 2, 3, 4], 4);

      expect(await walk(tester, _queued('chosen', 4)), ['other:5', 'other:6', 'other:7', 'other:8']);
    });

    testWidgets('two missing episodes in a row are both played, and the queue takes over again', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3, 4, 7, 8], other: [1, 2, 3, 4, 5, 6, 7, 8], plex: true);
      await seedQueue([1, 2, 3, 4, 7, 8], 4);

      expect(await walk(tester, _queued('chosen', 4)), ['other:5', 'other:6', 'chosen:7', 'chosen:8']);
    });

    testWidgets('Previous on a borrowed episode is the one before it, not the one before the queue stopped', (
      tester,
    ) async {
      await pumpHost(tester, chosen: [1, 2, 3, 4], other: [1, 2, 3, 4, 5], plex: true);
      await seedQueue([1, 2, 3, 4], 4);

      final adjacent = await adjacentOf(tester, _episode('other', 5));

      expect(adjacent.previous?.globalKey, 'chosen:chosen-e4');
    });

    testWidgets('a playlist keeps its own order', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3], other: [1, 2, 3], plex: true);
      await seedQueue([1, 3], 1, context: 'playlist-7');

      final adjacent = await adjacentOf(tester, _queued('chosen', 1));

      expect(adjacent.next?.index, 3, reason: 'E2 is not on the list');
    });

    testWidgets('a shuffle keeps its own order', (tester) async {
      await pumpHost(tester, chosen: [1, 2, 3], other: [1, 2, 3], plex: true);
      await seedQueue([3, 1], 3, shuffled: true);

      final adjacent = await adjacentOf(tester, _queued('chosen', 3));

      expect(adjacent.next?.index, 1);
    });
  });

  testWidgets('a Watch Together party stays on the queue it agreed on', (tester) async {
    await pumpHost(tester, chosen: [1], other: [1, 2]);
    final queued = AdjacentEpisodes();

    final adjacent = await adjacentAcrossSources(
      title: title,
      current: _episode('chosen', 1),
      queued: queued,
      queue: playback,
      inWatchTogether: true,
    );

    expect(adjacent, same(queued));
  });
}
