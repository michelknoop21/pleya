/// What Watch in the long-press menu starts. A show or season has no file of its
/// own, so a wrong answer here starts the wrong episode without a word.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/watch_target.dart';

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

  test('NEGATIVE CONTROL: a show without episodes has no target', () async {
    expect(await resolveWatchTarget(MenuFakeClient(), show), isNull);
  });
}
