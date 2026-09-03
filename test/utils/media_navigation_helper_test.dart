import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/media_navigation_helper.dart';

void main() {
  test('episode detail target opens parent show and focuses season episode', () {
    final episode = MediaItem(
      id: 'episode-1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Episode 1',
      parentId: 'season-2',
      parentIndex: 2,
      grandparentId: 'show-1',
      grandparentTitle: 'The Show',
      serverId: 'server-1',
    );

    final target = mediaDetailNavigationTargetFor(episode);

    expect(target.metadata.id, 'show-1');
    expect(target.metadata.kind, MediaKind.show);
    expect(target.initialSeasonId, 'season-2');
    expect(target.initialSeasonIndex, 2);
    expect(target.initialEpisodeId, 'episode-1');
  });

  test('season detail target opens parent show and focuses season', () {
    final season = MediaItem(
      id: 'season-3',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 3',
      index: 3,
      parentId: 'show-1',
      parentTitle: 'The Show',
      serverId: 'server-1',
    );

    final target = mediaDetailNavigationTargetFor(season);

    expect(target.metadata.id, 'show-1');
    expect(target.metadata.kind, MediaKind.show);
    expect(target.initialSeasonId, 'season-3');
    expect(target.initialSeasonIndex, 3);
    expect(target.initialEpisodeId, isNull);
  });

  test('movie detail target keeps the movie itself', () {
    final movie = MediaItem(id: 'movie-1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie');

    final target = mediaDetailNavigationTargetFor(movie);

    expect(target.metadata, same(movie));
    expect(target.initialSeasonId, isNull);
    expect(target.initialEpisodeId, isNull);
  });

  group('episode activation details decision', () {
    test('normal activation uses the episode action setting', () {
      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: false,
          continueWatchingAction: ContinueWatchingAction.details,
          episodeAction: EpisodeAction.play,
        ),
        isFalse,
      );

      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: false,
          continueWatchingAction: ContinueWatchingAction.play,
          episodeAction: EpisodeAction.details,
        ),
        isTrue,
      );
    });

    test('play-direct activation uses only the continue watching action setting', () {
      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: true,
          continueWatchingAction: ContinueWatchingAction.play,
          episodeAction: EpisodeAction.details,
        ),
        isFalse,
      );

      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: true,
          continueWatchingAction: ContinueWatchingAction.details,
          episodeAction: EpisodeAction.play,
        ),
        isTrue,
      );
    });
  });

  group('post-playback return handling', () {
    // TvBrowseRail's episode activation goes through navigateToMediaItem's
    // direct-to-player branch, and VideoPlayerScreen only ever pops `true`
    // from its own _handleBack — every other exit (system back, a route
    // replaced under it) pops `false` or `null`. A caller relying on
    // onRefresh alone (gated on `result == true`) misses those. Without
    // onPlaybackReturned, this is exactly that old, narrower behavior.
    final episode = MediaItem(id: 'episode-1', backend: MediaBackend.plex, kind: MediaKind.episode, title: 'Episode 1');

    for (final result in [false, null]) {
      test('onRefresh alone does not fire when the player pops $result', () {
        var onRefreshCalls = 0;
        handlePlaybackReturn(
          episode,
          playerPopResult: result,
          onRefresh: (_) => onRefreshCalls++,
          onPlaybackReturned: null,
        );
        expect(onRefreshCalls, 0);
      });

      test('onPlaybackReturned fires when the player pops $result', () {
        MediaItem? returned;
        handlePlaybackReturn(
          episode,
          playerPopResult: result,
          onRefresh: (_) => fail('onRefresh should be superseded'),
          onPlaybackReturned: (item) => returned = item,
        );
        expect(returned, same(episode));
      });
    }

    test('onRefresh alone fires when the player pops true', () {
      String? refreshedId;
      handlePlaybackReturn(
        episode,
        playerPopResult: true,
        onRefresh: (id) => refreshedId = id,
        onPlaybackReturned: null,
      );
      expect(refreshedId, episode.id);
    });

    test('onPlaybackReturned supersedes onRefresh even when the player pops true', () {
      var onRefreshCalls = 0;
      MediaItem? returned;
      handlePlaybackReturn(
        episode,
        playerPopResult: true,
        onRefresh: (_) => onRefreshCalls++,
        onPlaybackReturned: (item) => returned = item,
      );
      expect(returned, same(episode));
      expect(onRefreshCalls, 0, reason: 'a caller supplying both should not pay for two refreshes of the same return');
    });
  });
}
