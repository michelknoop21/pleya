import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/continue_watching_labels.dart';

/// The two card types of mockup 38 A / 22: `S3 E4 · 18 min left` with a bar,
/// `S3 E5 · Next episode` without one. Base locale is English in tests.
void main() {
  const minute = 60 * 1000;

  MediaItem episode({int? season = 3, int? episode = 4, int? durationMs, int? viewOffsetMs}) => MediaItem(
    id: 'ep',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    title: 'Violet',
    grandparentTitle: 'The Bear',
    parentIndex: season,
    index: episode,
    durationMs: durationMs,
    viewOffsetMs: viewOffsetMs,
  );

  MediaItem film({int? durationMs, int? viewOffsetMs}) => MediaItem(
    id: 'film',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Everything Everywhere All at Once',
    durationMs: durationMs,
    viewOffsetMs: viewOffsetMs,
  );

  group('state', () {
    test('an episode with progress is in progress', () {
      expect(
        continueWatchingStateFor(episode(durationMs: 48 * minute, viewOffsetMs: 30 * minute)),
        ContinueWatchingState.inProgress,
      );
    });
    test('an episode without progress is the next episode', () {
      expect(continueWatchingStateFor(episode(durationMs: 48 * minute)), ContinueWatchingState.nextEpisode);
      expect(continueWatchingStateFor(episode()), ContinueWatchingState.nextEpisode);
    });
    test('an offset that reached the end is not progress', () {
      expect(
        continueWatchingStateFor(episode(durationMs: 48 * minute, viewOffsetMs: 48 * minute)),
        ContinueWatchingState.nextEpisode,
      );
    });
    test('a film without progress is unstarted, never a next episode', () {
      expect(continueWatchingStateFor(film(durationMs: 100 * minute)), ContinueWatchingState.unstarted);
    });
  });

  group('status line', () {
    test('begonnen: place and what is left', () {
      expect(
        continueWatchingStatusLine(episode(durationMs: 48 * minute, viewOffsetMs: 30 * minute)),
        'S3 E4 · 18 min left',
      );
    });
    test('volgende aflevering: place and the explicit state, no bar text', () {
      expect(continueWatchingStatusLine(episode(episode: 5)), 'S3 E5 · Next episode');
    });
    test('a film says only what is left', () {
      expect(continueWatchingStatusLine(film(durationMs: 100 * minute, viewOffsetMs: 58 * minute)), '42 min left');
    });
    test('an unstarted film falls back to its runtime', () {
      expect(continueWatchingStatusLine(film(durationMs: 166 * minute)), '2h 46min');
    });
    test('episode number setting off keeps only the season', () {
      expect(continueWatchingStatusLine(episode(episode: 5), showEpisodeNumber: false), 'S3 · Next episode');
    });
    test('no duration, no time: the line never invents a number', () {
      expect(continueWatchingStatusLine(episode(viewOffsetMs: 5 * minute)), 'S3 E4 · Next episode');
      expect(continueWatchingStatusLine(film()), '');
    });
    group('new episode and new season', () {
      final now = DateTime(2026, 10, 16, 12);
      int secondsAgo(int days) => now.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;

      MediaItem next({required int season, required int number, int? added, int? watched}) => MediaItem(
        id: 'next',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.episode,
        title: 'Next',
        grandparentTitle: 'The Bear',
        parentIndex: season,
        index: number,
        addedAt: added == null ? null : secondsAgo(added),
        lastViewedAt: watched == null ? null : secondsAgo(watched),
        continueWatchingKind: ContinueWatchingKind.nextUp,
      );

      test('an episode added after the last watch says New episode', () {
        expect(
          continueWatchingStatusLine(next(season: 2, number: 5, added: 3, watched: 40), now: now),
          'S2 E5 · New episode',
        );
      });
      test('the first episode of a later season says New season', () {
        expect(
          continueWatchingStatusLine(next(season: 3, number: 1, added: 3, watched: 40), now: now),
          'S3 E1 · New season',
        );
      });
      test('without proof it stays Next episode', () {
        expect(continueWatchingStatusLine(next(season: 2, number: 5, added: 3), now: now), 'S2 E5 · Next episode');
        expect(
          continueWatchingStatusLine(next(season: 2, number: 5, added: 30, watched: 60), now: now),
          'S2 E5 · Next episode',
        );
      });
    });
    test('hours and minutes for a long remainder', () {
      expect(continueWatchingStatusLine(film(durationMs: 180 * minute, viewOffsetMs: 70 * minute)), '1h 50 min left');
    });
  });
}
