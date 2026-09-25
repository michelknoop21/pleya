import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
