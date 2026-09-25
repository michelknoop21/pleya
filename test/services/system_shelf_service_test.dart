import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/system_shelf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShelfDeepLink.fromNative', () {
    test('a bare content id is a legacy link (Android, older tvOS builds)', () {
      final link = ShelfDeepLink.fromNative('pleya_srv_42')!;
      expect(link.contentId, 'pleya_srv_42');
      expect(link.action, ShelfLinkAction.legacy);
    });

    test('a map carries the action', () {
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1', 'action': 'play'})!.action, ShelfLinkAction.play);
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1', 'action': 'open'})!.action, ShelfLinkAction.open);
    });

    test('a map without or with an unknown action stays legacy', () {
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1'})!.action, ShelfLinkAction.legacy);
      expect(ShelfDeepLink.fromNative({'contentId': 'pleya_srv_1', 'action': 'x'})!.action, ShelfLinkAction.legacy);
    });

    test('rejects missing or empty ids', () {
      expect(ShelfDeepLink.fromNative(null), isNull);
      expect(ShelfDeepLink.fromNative(''), isNull);
      expect(ShelfDeepLink.fromNative({'action': 'play'}), isNull);
      expect(ShelfDeepLink.fromNative({'contentId': ''}), isNull);
    });
  });

  group('ShelfDeepLink.startsPlaybackFor', () {
    test('legacy keeps today\'s behaviour: always the player', () {
      const link = ShelfDeepLink('pleya_srv_1');
      expect(link.startsPlaybackFor(MediaKind.movie), isTrue);
      expect(link.startsPlaybackFor(MediaKind.episode), isTrue);
    });

    test('open always goes to the detail page', () {
      const link = ShelfDeepLink('pleya_srv_1', ShelfLinkAction.open);
      expect(link.startsPlaybackFor(MediaKind.movie), isFalse);
      expect(link.startsPlaybackFor(MediaKind.episode), isFalse);
    });

    test('play resumes playable items and falls back to detail otherwise', () {
      const link = ShelfDeepLink('pleya_srv_1', ShelfLinkAction.play);
      expect(link.startsPlaybackFor(MediaKind.movie), isTrue);
      expect(link.startsPlaybackFor(MediaKind.episode), isTrue);
      expect(link.startsPlaybackFor(MediaKind.clip), isTrue);
      expect(link.startsPlaybackFor(MediaKind.show), isFalse);
      expect(link.startsPlaybackFor(MediaKind.season), isFalse);
    });
  });

  test('warm start: a native onShelfItemTap reaches onShelfItemTap with its action', () async {
    final service = SystemShelfService();
    final received = <ShelfDeepLink>[];
    service.onShelfItemTap = received.add;
    addTearDown(() => service.onShelfItemTap = null);

    const codec = StandardMethodCodec();
    Future<void> send(String channel, String method, Object? args) {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel,
        codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    }

    await send('com.pleya/system_shelf', 'onShelfItemTap', {'contentId': 'pleya_srv_7', 'action': 'open'});
    await send('com.pleya/watch_next', 'onWatchNextTap', {'contentId': 'pleya_srv_8'});

    expect(received.map((l) => (l.contentId, l.action)), [
      ('pleya_srv_7', ShelfLinkAction.open),
      ('pleya_srv_8', ShelfLinkAction.legacy),
    ]);
  });

  group('SystemShelfService.recentlyAddedFor', () {
    MediaItem item(String id, MediaKind kind, int addedAt, {String? grandparentId}) => MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: kind,
      title: id,
      serverId: 'srv',
      addedAt: addedAt,
      grandparentId: grandparentId,
    );

    test('newest added first, capped', () {
      final candidates = [for (var i = 0; i < 15; i++) item('m$i', MediaKind.movie, i)];
      final result = SystemShelfService.recentlyAddedFor(candidates, const [], limit: 10);
      expect(result.map((i) => i.id), ['m14', 'm13', 'm12', 'm11', 'm10', 'm9', 'm8', 'm7', 'm6', 'm5']);
    });

    test('drops what Continue Watching already shows, including the show of an episode', () {
      final onDeck = [item('m1', MediaKind.movie, 0), item('e1', MediaKind.episode, 0, grandparentId: 'show1')];
      final candidates = [
        item('m1', MediaKind.movie, 9),
        item('show1', MediaKind.show, 8),
        item('show2', MediaKind.show, 7),
        item('show2', MediaKind.show, 7),
      ];
      final result = SystemShelfService.recentlyAddedFor(candidates, onDeck);
      expect(result.map((i) => i.id), ['show2']);
    });
  });
}
