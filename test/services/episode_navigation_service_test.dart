/// D11 — "Next Episode alleen op andere bron" (hoofdstuk 15).
///
/// The binding sentence is the prohibition, not the offer: *"Een gekozen
/// seriesource blijft sticky voor de afspeelsessie. Next Episode komt van
/// dezelfde server en queue. Pleya springt niet stil naar een andere
/// server."* The optional half — an explicit "de volgende aflevering staat op
/// NAS, overschakelen?" — is granted with *kan* and is deliberately not built;
/// there is no i18n key for it anywhere.
///
/// So what is provable today is that the queue is bound to the server of the
/// item being played, and that a next episode existing only somewhere else
/// produces *no* next rather than a silent hop. That is structural:
/// [EpisodeNavigationService] resolves exactly one client, from
/// `metadata.serverId`, and the queue it builds can only hold what that one
/// fetch returned.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/episode_navigation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:provider/provider.dart';

/// A client that answers only [fetchClientSideEpisodeQueue] — the Jellyfin
/// shape. Plex returns null there and keeps its queue server-side, which is
/// why the rule is asserted on this path and only cited for Plex.
class _QueueClient implements MediaServerClient {
  _QueueClient(this._id, {this.episodes = const []});

  final String _id;
  final List<MediaItem> episodes;
  final List<String> queueFetches = [];

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) async {
    queueFetches.add(seriesId);
    return episodes;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _episode(String serverId, {required String id, required int index, String seriesId = 'show-1'}) => MediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: 'E$index',
  serverId: serverId,
  serverName: serverId,
  grandparentId: seriesId,
  index: index,
  parentIndex: 1,
);

void main() {
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late PlaybackStateProvider playback;

  setUp(() {
    manager = MultiServerManager();
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    playback = PlaybackStateProvider();
  });

  tearDown(() {
    multiServer.dispose();
    manager.dispose();
    playback.dispose();
  });

  /// Runs [body] with a real `BuildContext` under the two providers
  /// [EpisodeNavigationService.loadAdjacentEpisodes] reads.
  Future<void> withContext(WidgetTester tester, Future<void> Function(BuildContext context) body) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<PlaybackStateProvider>.value(value: playback),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await body(captured);
  }

  testWidgets('D11: a next episode that exists only on another source is no next episode at all', (tester) async {
    // server_1 holds the episode being watched and nothing after it.
    final onlyE1 = _QueueClient('server_1', episodes: [_episode('server_1', id: 's1e1', index: 1)]);
    // server_2 holds the same show, one episode further along.
    final alsoE2 = _QueueClient(
      'server_2',
      episodes: [
        _episode('server_2', id: 's2e1', index: 1),
        _episode('server_2', id: 's2e2', index: 2),
      ],
    );
    manager
      ..debugRegisterClientForTesting(onlyE1)
      ..debugRegisterClientForTesting(alsoE2);

    await withContext(tester, (context) async {
      final adjacent = await EpisodeNavigationService().loadAdjacentEpisodes(
        context: context,
        metadata: _episode('server_1', id: 's1e1', index: 1),
      );

      expect(
        adjacent.next,
        isNull,
        reason: 'the chosen source has no next episode; the copy on server_2 is not Pleya\'s to jump to',
      );
      expect(
        alsoE2.queueFetches,
        isEmpty,
        reason: 'the other server was never even asked — the queue is built from one client',
      );
      expect(onlyE1.queueFetches, ['show-1']);
    });
  });

  testWidgets('D11: the same playback on the source that does have the next episode gets it', (tester) async {
    // The negative control for the test above: without it, a queue that
    // returned null for everything would look like correct stickiness.
    final alsoE2 = _QueueClient(
      'server_2',
      episodes: [
        _episode('server_2', id: 's2e1', index: 1),
        _episode('server_2', id: 's2e2', index: 2),
      ],
    );
    manager.debugRegisterClientForTesting(alsoE2);

    await withContext(tester, (context) async {
      final adjacent = await EpisodeNavigationService().loadAdjacentEpisodes(
        context: context,
        metadata: _episode('server_2', id: 's2e1', index: 1),
      );

      expect(adjacent.next, isNotNull);
      expect(adjacent.next!.id, 's2e2');
      expect(adjacent.next!.serverId, 'server_2', reason: 'and it came from the source being watched');
    });
  });

  testWidgets('D11: two servers using the same series id never serve each other\'s episodes', (tester) async {
    // `grandparentId` is server-local — two servers can both call their show
    // `show-1`. The per-session series cache is keyed on that id, so this is
    // the one way a single player session could serve one server's episode
    // list for another server's playback.
    final serverOne = _QueueClient('server_1', episodes: [_episode('server_1', id: 's1e1', index: 1)]);
    final serverTwo = _QueueClient(
      'server_2',
      episodes: [
        _episode('server_2', id: 's2e1', index: 1),
        _episode('server_2', id: 's2e2', index: 2),
      ],
    );
    manager
      ..debugRegisterClientForTesting(serverOne)
      ..debugRegisterClientForTesting(serverTwo);

    await withContext(tester, (context) async {
      final navigation = EpisodeNavigationService();

      await navigation.loadAdjacentEpisodes(
        context: context,
        metadata: _episode('server_1', id: 's1e1', index: 1),
      );
      final second = await navigation.loadAdjacentEpisodes(
        context: context,
        metadata: _episode('server_2', id: 's2e1', index: 1),
      );

      expect(
        second.next?.serverId,
        'server_2',
        reason: 'server_2 playback must not inherit server_1\'s episode list through a shared series id',
      );
      expect(second.next?.id, 's2e2');
    });
  });
}
