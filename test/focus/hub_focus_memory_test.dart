import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/locked_hub_controller.dart';

/// A remembered slot is not a remembered place. Continue Watching moves the
/// title you just finished to the front, so restoring a bare index drops the
/// cursor on whatever slid into it — which is how "open another series"
/// replays the one you just watched.
void main() {
  setUp(HubFocusMemory.clear);
  tearDown(HubFocusMemory.clear);

  group('HubFocusMemory item identity', () {
    test('follows the item when the row reorders at equal length', () {
      HubFocusMemory.setForHub('home', 2, itemKey: 'plex:ted-lasso');

      // Same three items, watched one jumped to the front.
      final reordered = ['plex:ted-lasso', 'plex:severance', 'plex:andor'];

      expect(HubFocusMemory.rememberedItemIndex('home', reordered), 0);
    });

    test('returns null when the item dropped out of the row', () {
      HubFocusMemory.setForHub('home', 1, itemKey: 'plex:ted-lasso');

      expect(HubFocusMemory.rememberedItemIndex('home', ['plex:severance', 'plex:andor']), isNull);
    });

    test('returns null for a hub that only ever recorded a position', () {
      HubFocusMemory.setForHub('livetv', 3);

      expect(HubFocusMemory.rememberedItemIndex('livetv', ['a', 'b', 'c', 'd']), isNull);
      // The index memory itself is untouched, so those hubs keep working.
      expect(HubFocusMemory.getForHub('livetv', 4), 3);
    });

    test('a keyless write clears a previous identity instead of leaving it stale', () {
      HubFocusMemory.setForHub('home', 2, itemKey: 'plex:ted-lasso');
      HubFocusMemory.setForHub('home', 0);

      expect(HubFocusMemory.rememberedItemIndex('home', ['plex:ted-lasso']), isNull);
    });

    test('clear() drops identity as well as position', () {
      HubFocusMemory.setForHub('home', 1, itemKey: 'plex:ted-lasso');
      HubFocusMemory.clear();

      expect(HubFocusMemory.rememberedItemIndex('home', ['plex:ted-lasso']), isNull);
      expect(HubFocusMemory.getForHub('home', 3), 0);
    });

    test('index memory still wins for hubs whose contents are stable', () {
      HubFocusMemory.setForHub('library', 4, itemKey: 'plex:andor');

      // Nothing moved: identity resolves to the same slot the index would give.
      final unchanged = ['a', 'b', 'c', 'd', 'plex:andor'];
      expect(HubFocusMemory.rememberedItemIndex('library', unchanged), 4);
      expect(HubFocusMemory.getForHub('library', unchanged.length), 4);
    });
  });
}
