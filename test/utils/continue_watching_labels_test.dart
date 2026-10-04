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
        'S3 E4 · 18min left',
      );
    });
    test('volgende aflevering: place and the explicit state, no bar text', () {
      expect(continueWatchingStatusLine(episode(episode: 5)), 'S3 E5 · Next episode');
    });
    test('a film says only what is left', () {
      expect(continueWatchingStatusLine(film(durationMs: 100 * minute, viewOffsetMs: 58 * minute)), '42min left');
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
    test('hours and minutes for a long remainder', () {
      expect(continueWatchingStatusLine(film(durationMs: 180 * minute, viewOffsetMs: 70 * minute)), '1h 50min left');
    });
  });
}
