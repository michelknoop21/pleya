import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/widgets/hub_activation.dart';

/// The rule that decides which title a row opens.
///
/// It is a pure function for the same reason `resolveOverlaySheetGeometry` is:
/// the question "which item did the user just activate" should be answerable
/// without a focus system, a navigator or a frame. The bug it exists to stop is
/// a row that refreshes between the frame the user looked at and the moment
/// they press, after which an index points at somebody else's title.
void main() {
  MediaItem item(String id, {String server = 's1'}) =>
      MediaItem.plex(id: id, kind: MediaKind.movie, serverId: server, title: 'Title $id');

  group('identity', () {
    test('is scoped to the server, not just the item id', () {
      // Two servers can hand out the same Plex ratingKey. If identity were the
      // bare id, a row spanning two servers would treat them as one item.
      expect(hubItemIdentity(item('57881', server: 'a')), isNot(hubItemIdentity(item('57881', server: 'b'))));
      expect(hubItemIdentity(item('57881', server: 'a')), hubItemIdentity(item('57881', server: 'a')));
    });

    test('is the same string a Jellyfin item produces for the same server and id', () {
      // The rule lives on the base MediaItem, so it carries no backend-specific
      // assumption. A hub can mix backends and the comparison still holds.
      final plex = MediaItem.plex(id: 'x1', kind: MediaKind.movie, serverId: 's1', title: 'X');
      final jellyfin = MediaItem.jellyfin(id: 'x1', kind: MediaKind.movie, serverId: 's1', title: 'X');
      expect(hubItemIdentity(plex), hubItemIdentity(jellyfin));
    });
  });

  group('resolveHubActivation', () {
    final items = [item('a'), item('b'), item('c'), item('d')];

    test('follows the identity when the row reorders under the cursor', () {
      final moved = [item('d'), item('a'), item('b'), item('c')];
      final result = resolveHubActivation(
        items: moved,
        hasMore: false,
        focusedIndex: 3, // where 'd' used to be; 'c' sits there now
        target: HubFocusItem(hubItemIdentity(item('d'))),
      );

      expect(result.strategy, HubActivationStrategy.identity);
      expect(result.item?.id, 'd');
      expect(result.index, 0, reason: 'it reports where the item ended up');
    });

    test('drops the activation when the focused item is gone', () {
      // The reported failure: press on one title, get the one that slid into
      // its slot. The row keeps its length, so a length check sees nothing.
      final replaced = [item('a'), item('b'), item('c'), item('zz')];
      final result = resolveHubActivation(
        items: replaced,
        hasMore: false,
        focusedIndex: 3,
        target: HubFocusItem(hubItemIdentity(item('d'))),
      );

      expect(result.strategy, HubActivationStrategy.staleDropped);
      expect(result.item, isNull, reason: 'opening the replacement is exactly the bug');
      expect(result.opensItem, isFalse);
    });

    test('uses the index only while nothing has been chosen yet', () {
      final result = resolveHubActivation(items: items, hasMore: false, focusedIndex: 2, target: const HubFocusNone());

      expect(result.strategy, HubActivationStrategy.initialIndex);
      expect(result.item?.id, 'c');
    });

    test('opens the hub from the trailing card, and only while there is more', () {
      expect(
        resolveHubActivation(items: items, hasMore: true, focusedIndex: 4, target: const HubFocusViewAll()).strategy,
        HubActivationStrategy.viewAll,
      );
      // "View All" without a "more" flag is not a card at all.
      expect(
        resolveHubActivation(items: items, hasMore: false, focusedIndex: 4, target: const HubFocusViewAll()).strategy,
        HubActivationStrategy.none,
      );
    });

    test('reaches the trailing card from a bare index too', () {
      final result = resolveHubActivation(items: items, hasMore: true, focusedIndex: 4, target: const HubFocusNone());
      expect(result.strategy, HubActivationStrategy.viewAll);
    });

    test('has nothing to open on an empty row', () {
      final result = resolveHubActivation(
        items: const [],
        hasMore: false,
        focusedIndex: 0,
        target: const HubFocusNone(),
      );
      expect(result.strategy, HubActivationStrategy.none);
      expect(result.item, isNull);
    });

    test('the three cursor states stay distinguishable', () {
      // A single nullable key cannot tell "the trailing card" from "nothing
      // chosen yet", and that ambiguity is what let an activation fall through
      // to the old index.
      const none = HubFocusNone();
      const viewAll = HubFocusViewAll();
      final onItem = HubFocusItem(hubItemIdentity(item('a')));

      expect(none, isNot(equals(viewAll)));
      expect(onItem, isNot(equals(viewAll)));
      expect(onItem, equals(HubFocusItem(hubItemIdentity(item('a')))));
      expect(onItem, isNot(equals(HubFocusItem(hubItemIdentity(item('b'))))));
    });
  });
}
