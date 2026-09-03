import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/screens/media_detail_screen.dart';
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

  // The fase-4 plumbing of hoofdstuk 15: a route may now carry the group it was
  // reached through. Everything about it is additive, and the point of these is
  // that a caller that ignores it — which is every caller in the app today — is
  // handed exactly the route it was handed before.
  group('unified route context is additive', () {
    MediaItem movie() => MediaItem(
      id: 'i1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Dune',
      serverId: 'nas',
      serverName: 'NAS',
    );

    UnifiedMediaRouteContext context({List<String> keys = const ['nas:i1', 'attic:i2']}) => UnifiedMediaRouteContext(
      groupId: 'g1',
      identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
      sourceKey: 'nas:i1',
      availableSourceKeys: keys,
      coverage: SourceCoverageState.complete({'nas', 'attic'}),
      intent: UnifiedActivationIntent.play,
    );

    test('the route still builds without one, and still returns a bool route', () {
      expect(mediaDetailRoute(metadata: movie()), isA<PageRoute<bool>>());
      expect(mediaDetailRoute(metadata: movie(), unifiedRouteContext: context()), isA<PageRoute<bool>>());
    });

    test('the screen receives the context and the change callback it was given', () {
      Future<void> change(BuildContext _) async {}
      final screen = MediaDetailScreen(metadata: movie(), unifiedRouteContext: context(), onChangeSource: change);

      expect(screen.unifiedRouteContext?.sourceKey, 'nas:i1');
      expect(screen.onChangeSource, same(change));
    });

    test('omitting them leaves the screen in its pre-fase-4 shape', () {
      final screen = MediaDetailScreen(metadata: movie());

      expect(screen.unifiedRouteContext, isNull);
      expect(screen.onChangeSource, isNull);
    });

    // The override rule: once the user has explicitly changed source on an open
    // detail page, that page is bound to the concrete item — so Play, and the
    // episode queue behind it, cannot quietly jump back to the profile default.
    // Nothing enforces that at runtime; it is true because the route carries a
    // `MediaItem`, and these pin that it stays that way.
    test('the detail route is bound to the chosen concrete source, not to the group', () {
      final chosen = MediaItem(
        id: 'z1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Dune',
        serverId: 'attic',
        serverName: 'Zolder',
      );

      final target = mediaDetailNavigationTargetFor(chosen);

      expect(target.metadata.serverId, 'attic');
      expect(target.metadata.id, 'z1');
      final screen = MediaDetailScreen(
        metadata: target.metadata,
        unifiedRouteContext: context().withSourceKey('attic:i2'),
      );
      // Play on this page reads `metadata`; there is no second candidate on
      // the screen for it to prefer.
      expect(screen.metadata.serverId, 'attic');
      expect(screen.unifiedRouteContext?.sourceKey, 'attic:i2');
    });

    test('switching source changes the source key and nothing else about the context', () {
      final before = context();
      final after = before.withSourceKey('attic:i2');

      expect(after.sourceKey, 'attic:i2');
      expect(after.groupId, before.groupId);
      expect(after.availableSourceKeys, before.availableSourceKeys);
      expect(after.coverage, before.coverage);
      expect(after.intent, before.intent);
    });

    test('a single-source group renders no source line at all', () {
      // Hoofdstuk 15 only shows "Bron: … [ Wijzigen ]" when there is somewhere
      // else to go; the screen reads exactly this flag.
      expect(context(keys: const ['nas:i1']).hasAlternativeSources, isFalse);
      expect(context().hasAlternativeSources, isTrue);
    });
  });
}
