import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/index_order.dart';

MediaItem _episode(String id, {int? index, String? title, String? titleSort}) => MediaItem(
  id: id,
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.episode,
  title: title ?? id,
  titleSort: titleSort,
  index: index,
);

List<String> _ids(Iterable<MediaItem> items) => [for (final i in items) i.id];

void main() {
  group('compareByIndexNullsLast', () {
    test('numbered items come first on their number, unnumbered ones after on title', () {
      final items = [
        _episode('zebra', title: 'Zebra'),
        _episode('e10', index: 10, title: 'Zzz'),
        _episode('bumba', title: 'Bumba'),
        _episode('e2', index: 2, title: 'Aaa'),
        _episode('e0', index: 0, title: 'Special'),
      ]..sort(compareByIndexNullsLast);

      expect(_ids(items), ['e0', 'e2', 'e10', 'bumba', 'zebra']);
    });

    test('an unnumbered item is not read as episode zero', () {
      // The old `(a.index ?? 0)` put a loose clip in front of episode 1.
      final items = [_episode('clip', title: 'Aaa'), _episode('e1', index: 1, title: 'Zzz')]
        ..sort(compareByIndexNullsLast);

      expect(_ids(items), ['e1', 'clip']);
    });

    test('titleSort wins over the title, and case does not matter', () {
      final items = [
        _episode('b', title: 'De Aap', titleSort: 'Aap, De'),
        _episode('a', title: 'bumba'),
        _episode('c', title: 'Zebra'),
      ]..sort(compareByIndexNullsLast);

      expect(_ids(items), ['b', 'a', 'c']);
    });

    test('the result does not depend on the input order', () {
      final base = [
        _episode('x1', title: 'Same'),
        _episode('x2', title: 'Same'),
        _episode('x3', title: 'Same'),
        _episode('n1', index: 1),
        _episode('n2', index: 1),
      ];
      final first = _ids([...base]..sort(compareByIndexNullsLast));
      for (final shuffled in [
        base.reversed.toList(),
        [base[2], base[4], base[0], base[3], base[1]],
      ]) {
        expect(_ids(shuffled..sort(compareByIndexNullsLast)), first);
      }
    });
  });

  group('playEpisodeLabel', () {
    test('shows season and episode when both are known', () {
      expect(playEpisodeLabel(season: 1, episode: 4), t.discover.playEpisode(season: '1', episode: '4'));
      expect(playEpisodeLabel(season: 1, episode: 4), 'S1E4');
    });

    test('says plain Play, not S1E0, for an episode without a number', () {
      expect(playEpisodeLabel(season: 1, episode: null), t.common.play);
      expect(playEpisodeLabel(season: null, episode: 4), t.common.play);
      expect(playEpisodeLabel(season: 1, episode: null), isNot(contains('0')));
    });
  });

  test('media_detail_screen no longer sorts a missing number as zero', () {
    // Six places sorted with `(a.index ?? 0)`. The comparator above replaced them;
    // this keeps a seventh from coming back, which no widget test here would notice.
    final source = File('lib/screens/media_detail_screen.dart').readAsStringSync();
    expect(RegExp(r'\(a\.index \?\? 0\)').hasMatch(source), isFalse);
    expect('compareByIndexNullsLast'.allMatches(source).length, 6);
  });
}
