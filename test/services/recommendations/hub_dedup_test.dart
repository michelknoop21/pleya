import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/recommendations/hub_dedup.dart';
import 'package:plezy/utils/media_hub_ordering.dart';

MediaItem _item(String id) => MediaItem.plex(id: id, kind: MediaKind.movie, serverId: 's1', title: 'Movie $id');

MediaHub _hub(String id, List<String> itemIds, {String? identifier, String title = 'Hub'}) => MediaHub(
      id: id,
      identifier: identifier,
      title: title,
      type: 'movie',
      items: [for (final i in itemIds) _item(i)],
    );

void main() {
  group('dedupeAcrossHubs', () {
    test('caps an item to maxAppearances across hubs, first wins', () {
      final hubs = [
        _hub('h1', ['a', 'b', 'c']),
        _hub('h2', ['a', 'd', 'e']),
        _hub('h3', ['a', 'f', 'g']), // third 'a' should be dropped
      ];
      final out = dedupeAcrossHubs(hubs, maxAppearances: 2, minHubItems: 1);
      final third = out.firstWhere((h) => h.id == 'h3');
      expect(third.items.map((i) => i.id), isNot(contains('a')));
      final firstTwoWithA = out.where((h) => h.items.any((i) => i.id == 'a')).length;
      expect(firstTwoWithA, 2);
    });

    test('drops a hub left with fewer than minHubItems', () {
      final hubs = [
        _hub('h1', ['a', 'b', 'c']),
        _hub('h2', ['a', 'b', 'x']), // only 'x' survives -> dropped at minHubItems 3
      ];
      final out = dedupeAcrossHubs(hubs, maxAppearances: 1, minHubItems: 3);
      expect(out.map((h) => h.id), ['h1']);
    });

    test('keeps original instance when nothing removed', () {
      final hubs = [_hub('h1', ['a', 'b', 'c'])];
      final out = dedupeAcrossHubs(hubs, minHubItems: 3);
      expect(identical(out.first, hubs.first), isTrue);
    });

    test('alreadyShownKeys pre-seeds so continue-watching items are limited', () {
      final hubs = [
        _hub('h1', ['a', 'b', 'c']),
      ];
      final out = dedupeAcrossHubs(
        hubs,
        alreadyShownKeys: {hubItemDedupKey(_item('a'))},
        maxAppearances: 2,
        minHubItems: 1,
      );
      // 'a' already counted once; still allowed once more here.
      expect(out.first.items.map((i) => i.id), contains('a'));
    });
  });

  group('hubPriorityClass', () {
    test('classifies personalized, next-up, recent, top-rated, other', () {
      expect(hubPriorityClass(_hub('x', [], identifier: 'home.becauseyouwatched')), 0);
      expect(hubPriorityClass(_hub('x', [], identifier: 'home.nextup')), 1);
      expect(hubPriorityClass(_hub('x', [], identifier: 'lib.recentlyadded')), 2);
      expect(hubPriorityClass(_hub('x', [], title: 'Top Rated')), 3);
      expect(hubPriorityClass(_hub('x', [], title: 'Documentaries')), 4);
    });

    test('sortMediaHubsByPriority is stable within a class', () {
      final hubs = [
        _hub('recent2', ['a'], identifier: 'lib.recentlyadded', title: 'Recently Added B'),
        _hub('picks', ['b'], identifier: 'home.foryou', title: 'Top Picks'),
        _hub('recent1', ['c'], identifier: 'lib.recentlyadded', title: 'Recently Added A'),
      ];
      final changed = sortMediaHubsByPriority(hubs);
      expect(changed, isTrue);
      expect(hubs.map((h) => h.id), ['picks', 'recent2', 'recent1']); // picks first; recents keep input order
    });
  });
}
