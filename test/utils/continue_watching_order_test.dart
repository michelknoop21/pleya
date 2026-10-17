import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/continue_watching_order.dart';

/// The order of Verder kijken: last watched first, then at most two new
/// episodes or seasons, then the active titles, then Eerder begonnen.
void main() {
  final now = DateTime(2026, 10, 16, 12);
  int secondsAgo(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;
  const day = Duration(days: 1);

  MediaItem film(String id, {Duration? watched}) => MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: id,
    viewOffsetMs: 1000,
    lastViewedAt: watched == null ? null : secondsAgo(watched),
    continueWatchingKind: ContinueWatchingKind.resume,
  );

  /// The next episode of a series. [seriesWatched] is when the series was last
  /// watched, [added] when this episode appeared on the server.
  MediaItem next(
    String id, {
    Duration? seriesWatched,
    Duration? added,
    int season = 1,
    int episode = 4,
    ContinueWatchingKind? kind = ContinueWatchingKind.nextUp,
  }) => MediaItem(
    id: id,
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    title: id,
    grandparentTitle: 'Show $id',
    parentIndex: season,
    index: episode,
    lastViewedAt: seriesWatched == null ? null : secondsAgo(seriesWatched),
    addedAt: added == null ? null : secondsAgo(added),
    continueWatchingKind: kind,
  );

  List<String> order(List<MediaItem> items) => [
    for (final i in orderContinueWatching(items, itemOf: (i) => i, now: now)) i.id,
  ];

  group('continueWatchingFreshness', () {
    ContinueWatchingFreshness of(MediaItem item) => continueWatchingFreshness(item, now: now);

    test('an episode added after the series was last watched, within two weeks, is new', () {
      expect(of(next('a', seriesWatched: day * 40, added: day * 3)), ContinueWatchingFreshness.newEpisode);
    });

    test('the first episode of a later season is a new season', () {
      expect(
        of(next('a', seriesWatched: day * 40, added: day * 3, season: 3, episode: 1)),
        ContinueWatchingFreshness.newSeason,
      );
    });

    test('episode 1 of season 1 is never a new season', () {
      expect(
        of(next('a', seriesWatched: day * 40, added: day * 3, season: 1, episode: 1)),
        ContinueWatchingFreshness.newEpisode,
      );
    });

    test('an episode that was already there when the series was watched is not new', () {
      expect(of(next('a', seriesWatched: day * 2, added: day * 60)), ContinueWatchingFreshness.none);
    });

    test('an episode added on the day of the last watch is not new', () {
      expect(
        of(next('a', seriesWatched: day * 3, added: day * 3 - const Duration(hours: 2))),
        ContinueWatchingFreshness.none,
      );
    });

    test('after two weeks the priority is over', () {
      expect(of(next('a', seriesWatched: day * 60, added: day * 15)), ContinueWatchingFreshness.none);
    });

    test('without both dates nothing is suggested', () {
      expect(of(next('no-added', seriesWatched: day * 40)), ContinueWatchingFreshness.none);
      expect(of(next('no-watched', added: day * 3)), ContinueWatchingFreshness.none);
    });

    test('only a next-up item can be new, never a resume item or an item with no origin', () {
      expect(
        of(next('resume', seriesWatched: day * 40, added: day * 3, kind: ContinueWatchingKind.resume)),
        ContinueWatchingFreshness.none,
      );
      expect(of(next('none', seriesWatched: day * 40, added: day * 3, kind: null)), ContinueWatchingFreshness.none);
    });

    test('an added date in the future is not trusted', () {
      expect(of(next('a', seriesWatched: day * 40, added: -day * 5)), ContinueWatchingFreshness.none);
    });
  });

  group('orderContinueWatching', () {
    test('the title watched last comes first', () {
      expect(
        order([
          film('old', watched: day * 9),
          film('last', watched: const Duration(hours: 1)),
          film('mid', watched: day * 3),
        ]),
        ['last', 'mid', 'old'],
      );
    });

    test('at most two new episodes follow the last watched one, even when that series was last watched months ago', () {
      final items = [
        film('last', watched: const Duration(hours: 2)),
        film('active', watched: day * 1),
        next('new-1', seriesWatched: day * 200, added: day * 6),
        next('new-2', seriesWatched: day * 120, added: day * 2),
        next('new-3', seriesWatched: day * 150, added: day * 4),
      ];
      expect(order(items), ['last', 'new-2', 'new-3', 'active', 'new-1']);
    });

    test('a third new episode is not lost, it falls back to the order of its own activity', () {
      final items = [
        film('last', watched: const Duration(hours: 2)),
        next('new-1', seriesWatched: day * 20, added: day * 6),
        next('new-2', seriesWatched: day * 20, added: day * 2),
        next('new-3', seriesWatched: day * 20, added: day * 4),
      ];
      expect(order(items), ['last', 'new-2', 'new-3', 'new-1']);
    });

    test('when the new episode is also the series watched last it takes the first place, not a second one', () {
      final items = [
        film('earlier', watched: day * 9),
        next('both', seriesWatched: day * 5, added: const Duration(hours: 2)),
        next('new-b', seriesWatched: day * 90, added: day * 2),
      ];
      expect(order(items), ['both', 'new-b', 'earlier']);
    });

    test('active titles go on their last activity', () {
      expect(order([film('c', watched: day * 5), film('a', watched: day * 1), film('b', watched: day * 3)]), [
        'a',
        'b',
        'c',
      ]);
    });

    test('something left alone for over three months goes behind the active titles', () {
      final items = [
        film('last', watched: day * 1),
        film('stale-new', watched: day * 100),
        film('stale-old', watched: day * 300),
        film('active', watched: day * 20),
      ];
      expect(order(items), ['last', 'active', 'stale-new', 'stale-old']);
    });

    test('an ordinary next episode of a series left alone for months is Eerder begonnen', () {
      final items = [
        film('last', watched: day * 1),
        next('quiet-series', seriesWatched: day * 200, added: day * 400),
        film('active', watched: day * 20),
      ];
      expect(order(items), ['last', 'active', 'quiet-series']);
    });

    test('something without a date is never old and stays behind the dated active titles', () {
      final items = [
        film('last', watched: day * 1),
        film('undated'),
        film('stale', watched: day * 200),
        film('active', watched: day * 30),
      ];
      expect(order(items), ['last', 'active', 'undated', 'stale']);
    });

    test('a new episode that is two weeks old no longer jumps the queue', () {
      final items = [
        film('last', watched: day * 1),
        film('active', watched: day * 10),
        next('was-new', seriesWatched: day * 60, added: day * 15),
      ];
      expect(order(items), ['last', 'active', 'was-new']);
    });

    test('equal items keep their incoming order', () {
      expect(order([film('b'), film('a'), film('c')]), ['b', 'a', 'c']);
    });

    test('one item or none is returned as it is', () {
      expect(order([]), isEmpty);
      expect(order([film('only')]), ['only']);
    });
  });
}
