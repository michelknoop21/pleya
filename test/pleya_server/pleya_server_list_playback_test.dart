import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/playback_state_provider.dart';
import 'package:pleya/services/jellyfin_sequential_launcher.dart';
import 'package:pleya/services/media_list_playback_launcher.dart';
import 'package:pleya/services/play_queue_launcher.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart' show FakeList;
import 'package:provider/provider.dart';

import 'pleya_fake_server.dart';

class _StubPlexClient implements PlexClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlexOnlyProvider extends ChangeNotifier implements MultiServerProvider {
  @override
  PlexClient? getPlexClientForServer(ServerId serverId) => _StubPlexClient();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A list on Pleya Server has no server-side queue: the app builds one. Without this
/// route the press on Play reached the Plex launcher, which found no Plex client,
/// or found the wrong server.
void main() {
  late BuildContext context;

  Future<void> pump(WidgetTester tester, {MultiServerProvider? provider}) async {
    final app = MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      provider == null ? app : ChangeNotifierProvider<MultiServerProvider>.value(value: provider, child: app),
    );
  }

  MediaItem list(MediaBackend backend) =>
      MediaItem(id: 'l', backend: backend, kind: MediaKind.collection, serverId: 's');

  group('forItem', () {
    testWidgets('Pleya Server gets the local queue, for a collection, a playlist and a show', (tester) async {
      await pump(tester);
      final playlist = MediaPlaylist(id: 'p', backend: MediaBackend.pleyaServer, title: 'p', playlistType: 'video');
      final show = MediaItem(id: 's', backend: MediaBackend.pleyaServer, kind: MediaKind.show);
      for (final item in [list(MediaBackend.pleyaServer), playlist, show]) {
        expect(MediaListPlaybackLauncher.forItem(context, item), isA<JellyfinSequentialLauncher>());
      }
    });

    testWidgets('Jellyfin keeps the local queue', (tester) async {
      await pump(tester);
      expect(
        MediaListPlaybackLauncher.forItem(context, list(MediaBackend.jellyfin)),
        isA<JellyfinSequentialLauncher>(),
      );
    });

    testWidgets('Plex keeps its server-side queue', (tester) async {
      final provider = _PlexOnlyProvider();
      await pump(tester, provider: provider);
      expect(MediaListPlaybackLauncher.forItem(context, list(MediaBackend.plex)), isA<PlexPlayQueueLauncher>());
    });
  });

  group('playing a list', () {
    late PleyaServerClient client;
    late PlaybackStateProvider playback;
    late List<MediaItem> started;
    late PleyaFakeServer server;

    Future<void> connect(WidgetTester tester) async {
      await tester.runAsync(() async {
        server = PleyaFakeServer()..listsCapability = true;
        for (final id in ['m1', 'm2', 'm3']) {
          server.addItem(id: id, kind: 'movie', title: id);
        }
        server
          ..addItem(id: 'show', kind: 'show', title: 'Show', libraryId: 'lib-series')
          ..addItem(id: 'season', kind: 'season', title: 'S1', parentId: 'show', index: 1);
        for (final n in [1, 2]) {
          server.addItem(id: 'e$n', kind: 'episode', title: 'e$n', parentId: 'season', index: n);
        }
        client = server.client();
        await client.refreshCapabilities();
      });
      addTearDown(client.close);
      playback = PlaybackStateProvider();
      started = [];
      await pump(tester);
    }

    JellyfinSequentialLauncher launcher() => JellyfinSequentialLauncher(
      context: context,
      clientForTesting: client,
      playbackStateForTesting: playback,
      navigateForTesting: (item) async => started.add(item),
    );

    MediaPlaylist playlist(String id) => MediaPlaylist(
      id: id,
      backend: MediaBackend.pleyaServer,
      title: id,
      playlistType: 'video',
      serverId: client.serverId.toString(),
    );
    MediaItem collection(String id) => MediaItem(
      id: id,
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.collection,
      serverId: client.serverId.toString(),
    );

    testWidgets('a playlist plays in its own order, and the tapped row starts it', (tester) async {
      await connect(tester);
      server.lists.playlists['p'] = FakeList(id: 'p', title: 'p', itemIds: ['m3', 'm1', 'm2']);
      final tapped = MediaItem(id: 'm1', backend: MediaBackend.pleyaServer, kind: MediaKind.movie);

      final result = await tester.runAsync(
        () => launcher().launchFromCollectionOrPlaylist(
          item: playlist('p'),
          shuffle: false,
          startItem: tapped,
          showLoadingIndicator: false,
        ),
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(playback.loadedItems.map((item) => item.id), ['m3', 'm1', 'm2']);
      expect(started.single.id, 'm1');
      expect(started.single.backend, MediaBackend.pleyaServer);
      expect(started.single.serverId, client.serverId.toString());
      expect(await tester.runAsync(() => playback.getNextEpisode('m1', loopQueue: false)), isNotNull);
    });

    testWidgets('a collection plays from its rows, with a show as its episodes', (tester) async {
      await connect(tester);
      server.lists.collections['c'] = FakeList(id: 'c', title: 'c', itemIds: ['m2', 'show', 'm1']);

      final result = await tester.runAsync(
        () => launcher().launchFromCollectionOrPlaylist(
          item: collection('c'),
          shuffle: false,
          showLoadingIndicator: false,
        ),
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(playback.loadedItems.map((item) => item.id), ['m2', 'e1', 'e2', 'm1']);
      expect(started.single.id, 'm2');
    });

    testWidgets('shuffle keeps every row', (tester) async {
      await connect(tester);
      server.lists.collections['c'] = FakeList(id: 'c', title: 'c', itemIds: ['m1', 'm2', 'm3']);

      final result = await tester.runAsync(
        () => launcher().launchFromCollectionOrPlaylist(
          item: collection('c'),
          shuffle: true,
          showLoadingIndicator: false,
        ),
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(playback.loadedItems.map((item) => item.id), unorderedEquals(['m1', 'm2', 'm3']));
      expect(playback.isShuffleActive, isTrue);
    });

    testWidgets('an empty list is empty, not an error', (tester) async {
      await connect(tester);
      server.lists.playlists['p'] = FakeList(id: 'p', title: 'p');

      final result = await tester.runAsync(
        () =>
            launcher().launchFromCollectionOrPlaylist(item: playlist('p'), shuffle: false, showLoadingIndicator: false),
      );

      expect(result, isA<PlayQueueEmpty>());
      expect(started, isEmpty);
    });

    testWidgets('shuffling a show uses its episodes, because the backend has no queue of its own', (tester) async {
      await connect(tester);
      final show = MediaItem(
        id: 'show',
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.show,
        serverId: client.serverId.toString(),
      );

      final result = await tester.runAsync(
        () => launcher().launchShuffledShow(metadata: show, showLoadingIndicator: false),
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(playback.loadedItems.map((item) => item.id), unorderedEquals(['e1', 'e2']));
    });
  });
}
