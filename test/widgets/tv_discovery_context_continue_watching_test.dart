import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';

import '../test_helpers/tv_discovery_fixtures.dart';

/// The focus line of the tvOS Verder kijken row (A-06, DEC-XXX Verder kijken):
/// the row says `Nieuwe aflevering` or `Nieuw seizoen` for the same provable
/// cases as the cards and Top Shelf, and `Volgende aflevering` otherwise.
void main() {
  int daysAgo(int d) => DateTime.now().subtract(Duration(days: d)).millisecondsSinceEpoch ~/ 1000;

  MediaItem nextUp({required int season, required int episode, int? addedAt, int? lastViewedAt}) => MediaItem(
    id: 's${season}e$episode',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    title: 'Violet',
    grandparentTitle: 'The Bear',
    parentIndex: season,
    index: episode,
    serverId: 'nas',
    serverName: 'NAS',
    continueWatchingKind: ContinueWatchingKind.nextUp,
    addedAt: addedAt,
    lastViewedAt: lastViewedAt,
  );

  String line(MediaItem item, {bool inContinueWatching = true}) =>
      discoveryContextFor(tvDiscoveryGroup('g-${item.id}', [item]), inContinueWatching: inContinueWatching).context;

  group('Verder kijken focus line', () {
    test('a provably new episode says Nieuwe aflevering', () {
      final item = nextUp(season: 2, episode: 5, addedAt: daysAgo(2), lastViewedAt: daysAgo(30));
      expect(line(item), endsWith(t.discover.newEpisodeStatus));
    });

    test('the first episode of a later season says Nieuw seizoen', () {
      final item = nextUp(season: 3, episode: 1, addedAt: daysAgo(2), lastViewedAt: daysAgo(30));
      expect(line(item), endsWith(t.discover.newSeasonStatus));
    });

    test('an ordinary next episode, or one without dates, stays Volgende aflevering', () {
      final old = nextUp(season: 2, episode: 6, addedAt: daysAgo(40), lastViewedAt: daysAgo(60));
      final undated = nextUp(season: 2, episode: 6);
      for (final item in [old, undated]) {
        expect(line(item), isNot(contains(t.discover.newEpisodeStatus)));
        expect(line(item), isNot(contains(t.discover.newSeasonStatus)));
      }
    });

    test('outside Verder kijken the label never appears', () {
      final item = nextUp(season: 2, episode: 5, addedAt: daysAgo(2), lastViewedAt: daysAgo(30));
      expect(line(item, inContinueWatching: false), isNot(contains(t.discover.newEpisodeStatus)));
    });
  });
}
