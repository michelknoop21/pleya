/// What Watch in the long-press menu starts. A show or season has no file of its
/// own, so a wrong answer here starts the wrong episode without a word.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/watch_target.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../test_helpers/media_menu_harness.dart';

MediaItem _item(String id, MediaKind kind, {int? index, int? leaves, int? viewedLeaves, int viewCount = 0}) =>
    MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: kind,
      title: id,
      index: index,
      leafCount: leaves,
      viewedLeafCount: viewedLeaves,
      viewCount: viewCount,
    );

MediaItem _episode(String id, {bool watched = false}) => _item(id, MediaKind.episode, viewCount: watched ? 1 : 0);

/// What a Jellyfin season answers on its own route: no missing or virtual
/// episodes. `fetchChildren` lists those too, as files that do not exist.
class _PagingClient extends MenuFakeClient implements SeasonEpisodePagingClient {
  _PagingClient({required super.children, required this.episodes});

  final List<MediaItem> episodes;
  final seriesIds = <String>[];

  @override
  Future<LibraryPage<MediaItem>> fetchSeasonEpisodesPage(
    String seriesId,
    String seasonId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    seriesIds.add(seriesId);
    final from = start ?? 0;
    final end = (from + (size ?? episodes.length)).clamp(0, episodes.length);
    return LibraryPage(items: episodes.sublist(from.clamp(0, end), end), totalCount: episodes.length, offset: from);
  }
}

void main() {
  final show = MediaItem(
    id: 'show',
    backend: MediaBackend.plex,
    kind: MediaKind.show,
    title: 'Show',
    serverId: 'server-1',
    serverName: 'Nas',
    libraryId: 'lib',
  );

  test('a movie is its own target', () async {
    final movie = _item('m', MediaKind.movie);
    expect(identical(await resolveWatchTarget(MenuFakeClient(), movie), movie), isTrue);
  });

  test('a show follows the server, and the episode stays bound to the show\'s server', () async {
    final target = await resolveWatchTarget(MenuFakeClient(onDeck: _episode('deck')), show);
    expect(target?.id, 'deck');
    expect(target?.serverId, 'server-1');
    expect(target?.serverName, 'Nas');
    expect(target?.libraryId, 'lib');
  });

  test('without on deck: the first episode still to watch, past the seasons that are done', () async {
    final client = MenuFakeClient(
      children: {
        'show': [
          _item('s0', MediaKind.season, index: 0, leaves: 2),
          _item('s1', MediaKind.season, index: 1, leaves: 2, viewedLeaves: 2),
          _item('s2', MediaKind.season, index: 2, leaves: 2, viewedLeaves: 1),
        ],
        's2': [_episode('e1', watched: true), _episode('e2')],
      },
    );
    expect((await resolveWatchTarget(client, show))?.id, 'e2');
  });

  test('everything watched: the first episode of the first regular season, for a rewatch', () async {
    final client = MenuFakeClient(
      children: {
        'show': [
          _item('s0', MediaKind.season, index: 0, leaves: 1, viewedLeaves: 1),
          _item('s1', MediaKind.season, index: 1, leaves: 2, viewedLeaves: 2),
        ],
        's1': [_episode('e1', watched: true), _episode('e2', watched: true)],
      },
    );
    expect((await resolveWatchTarget(client, show))?.id, 'e1');
  });

  test('a season starts on its first episode still to watch', () async {
    final season = _item('s1', MediaKind.season, index: 1);
    final client = MenuFakeClient(
      children: {
        's1': [_episode('e1', watched: true), _episode('e2'), _episode('e3')],
      },
    );
    expect((await resolveWatchTarget(client, season))?.id, 'e2');
  });

  group('a client with its own season route', () {
    final placeholder = _episode('missing-placeholder');

    test('a season does not start a placeholder without a file', () async {
      final season = _item('s1', MediaKind.season, index: 1).copyWith(parentId: 'show');
      final client = _PagingClient(
        children: {
          's1': [placeholder, _episode('real')],
        },
        episodes: [_episode('real')],
      );
      expect((await resolveWatchTarget(client, season))?.id, 'real');
      expect(client.seriesIds, ['show']);
    });

    test('nor does a show that falls back to its seasons', () async {
      final client = _PagingClient(
        children: {
          'show': [_item('s1', MediaKind.season, index: 1, leaves: 1)],
          's1': [placeholder, _episode('real')],
        },
        episodes: [_episode('real')],
      );
      expect((await resolveWatchTarget(client, show))?.id, 'real');
      expect(client.seriesIds, ['show']);
    });

    test('a season longer than one page still reaches its first episode to watch', () async {
      final season = _item('s1', MediaKind.season, index: 1).copyWith(parentId: 'show');
      final client = _PagingClient(
        children: const {},
        episodes: [for (var i = 0; i < 150; i++) _episode('e$i', watched: true), _episode('next')],
      );
      expect((await resolveWatchTarget(client, season))?.id, 'next');
    });

    test('a season watched to the end starts again at its first episode', () async {
      final season = _item('s1', MediaKind.season, index: 1).copyWith(parentId: 'show');
      final client = _PagingClient(
        children: const {},
        episodes: [for (var i = 0; i < 150; i++) _episode('e$i', watched: true)],
      );
      expect((await resolveWatchTarget(client, season))?.id, 'e0');
    });

    test('NEGATIVE CONTROL: without a known series the season route cannot be asked', () async {
      final season = _item('s1', MediaKind.season, index: 1);
      final client = _PagingClient(
        children: {
          's1': [_episode('from-children')],
        },
        episodes: [_episode('paged')],
      );
      expect((await resolveWatchTarget(client, season))?.id, 'from-children');
      expect(client.seriesIds, isEmpty);
    });
  });

  test('NEGATIVE CONTROL: a show without episodes has no target', () async {
    expect(await resolveWatchTarget(MenuFakeClient(), show), isNull);
  });
}
