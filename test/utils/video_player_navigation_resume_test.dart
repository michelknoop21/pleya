import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/video_player_navigation.dart';

// `shouldRefetchForFreshResume` replaces the old inline condition in
// `navigateToVideoPlayer`, which read:
//
//   resolveWatchState && !isOffline && mediaClient != null &&
//   metadata.viewOffsetMs == null && (movie || episode)
//
// The `viewOffsetMs == null` clause is what these tests remove: an item that
// already carries a view offset is exactly the case where that offset can be
// stale, so it is the case that most needs the refetch.

void main() {
  group('shouldRefetchForFreshResume', () {
    test('refetches an episode that already carries a view offset', () {
      // Demonstrably red before the change: the old condition required
      // viewOffsetMs == null, so an item with a stale offset was never
      // refetched and resumed from that stale value.
      expect(
        shouldRefetchForFreshResume(
          resolveWatchState: true,
          isOffline: false,
          hasClient: true,
          kind: MediaKind.episode,
        ),
        isTrue,
      );
    });

    test('refetches a movie', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: true, isOffline: false, hasClient: true, kind: MediaKind.movie),
        isTrue,
      );
    });

    test('does not refetch for an explicit intent that opted out of watch-state resolution', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: false, isOffline: false, hasClient: true, kind: MediaKind.movie),
        isFalse,
      );
    });

    test('does not refetch during offline playback', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: true, isOffline: true, hasClient: true, kind: MediaKind.movie),
        isFalse,
      );
    });

    test('does not refetch without a reachable client', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: true, isOffline: false, hasClient: false, kind: MediaKind.movie),
        isFalse,
      );
    });

    test('does not refetch kinds that do not resume', () {
      for (final kind in [MediaKind.show, MediaKind.season, MediaKind.collection, MediaKind.playlist]) {
        expect(
          shouldRefetchForFreshResume(resolveWatchState: true, isOffline: false, hasClient: true, kind: kind),
          isFalse,
          reason: 'kind $kind should not trigger a resume refetch',
        );
      }
    });
  });
}
