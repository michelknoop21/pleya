/// The rows of the long-press menu follow what the server can really do, on
/// iPad and desktop as well as on the phone (Michel, 30 October 2026: no button
/// without a function). Pleya Server has no playlist or collection endpoints,
/// a local folder keeps no rating, and a TV has no share sheet.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:share_plus_platform_interface/method_channel/method_channel_share.dart';

import '../test_helpers/media_menu_harness.dart';
import '../test_helpers/prefs.dart';

MediaItem _item(MediaKind kind, {MediaBackend backend = MediaBackend.jellyfin, String? serverId = 'server-1'}) =>
    MediaItem(id: 'id-1', backend: backend, kind: kind, title: 'Sintel', year: 2010, serverId: serverId);

MenuFakeClient _jellyfin({MediaItem? onDeck}) =>
    MenuFakeClient(backend: MediaBackend.jellyfin, capabilities: ServerCapabilities.jellyfin, onDeck: onDeck);

/// What `PleyaServerCapabilityResolver` answers: no playlists, no collections.
MenuFakeClient _pleyaServer() =>
    MenuFakeClient(backend: MediaBackend.pleyaServer, capabilities: const ServerCapabilities(userRating: true));

MenuFakeClient _localFolder() => MenuFakeClient(backend: MediaBackend.local, capabilities: ServerCapabilities.local);

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(false);
    noticeController.debugReset();
  });
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    noticeController.debugReset();
  });

  group('Add to', () {
    testWidgets('Jellyfin offers it: a non-owner goes straight to the playlists', (tester) async {
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin());
      await tester.tap(find.text(t.common.addTo));
      await tester.pumpAndSettle();
      expect(find.text(t.collections.collection), findsNothing);
    });

    testWidgets('a Jellyfin owner chooses between playlist and collection', (tester) async {
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin(), canManage: true);
      await tester.tap(find.text(t.common.addTo));
      await tester.pumpAndSettle();
      expect(find.text(t.collections.collection), findsOneWidget);
      expect(find.text(t.playlists.playlist), findsOneWidget);
    });

    // Besluit Michel, "op alle apps": the TV menu is this menu, and the client can.
    testWidgets('a TV offers Add to on Jellyfin too', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin(), size: const Size(1920, 1080));
      expect(find.text(t.common.addTo), findsOneWidget);
    });

    testWidgets('and to an owner Remove from collection', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await MenuHarness.open(
        tester,
        item: _item(MediaKind.movie),
        client: _jellyfin(),
        canManage: true,
        collectionId: 'col-1',
        size: const Size(1920, 1080),
      );
      expect(find.text(t.collections.removeFromCollection), findsOneWidget);
    });

    testWidgets('NEGATIVE CONTROL: a backend without playlists has no row', (tester) async {
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _pleyaServer(), canManage: true);
      expect(find.text(t.common.addTo), findsNothing);
    });

    testWidgets('an owner on Jellyfin can take an item out of a collection', (tester) async {
      await MenuHarness.open(
        tester,
        item: _item(MediaKind.movie),
        client: _jellyfin(),
        canManage: true,
        collectionId: 'col-1',
      );
      expect(find.text(t.collections.removeFromCollection), findsOneWidget);
    });

    testWidgets('NEGATIVE CONTROL: not on a backend without collections', (tester) async {
      await MenuHarness.open(
        tester,
        item: _item(MediaKind.movie),
        client: _pleyaServer(),
        canManage: true,
        collectionId: 'col-1',
      );
      expect(find.text(t.collections.removeFromCollection), findsNothing);
    });
  });

  group('Rate', () {
    testWidgets('where the backend keeps a rating', (tester) async {
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin());
      expect(find.text(t.mediaMenu.rate), findsOneWidget);
    });

    testWidgets('NEGATIVE CONTROL: a local folder keeps none', (tester) async {
      await MenuHarness.open(
        tester,
        item: _item(MediaKind.movie, backend: MediaBackend.local),
        client: _localFolder(),
      );
      expect(find.text(t.mediaMenu.rate), findsNothing);
    });
  });

  group('Share', () {
    late List<Map<Object?, Object?>> shared;

    setUp(() {
      shared = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelShare.channel,
        (call) async {
          shared.add(call.arguments as Map<Object?, Object?>);
          return 'success';
        },
      );
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannelShare.channel,
        null,
      ),
    );

    for (final client in [_jellyfin(), _pleyaServer(), _localFolder()]) {
      testWidgets('title and year, anchored to the card, on ${client.backend.name}', (tester) async {
        await MenuHarness.open(
          tester,
          item: _item(MediaKind.movie, backend: client.backend),
          client: client,
        );
        await tester.tap(find.text(t.common.share));
        await tester.pumpAndSettle();

        expect(shared, hasLength(1));
        expect(shared.single['text'], 'Sintel (2010)');
        final card = tester.getRect(find.text('target'));
        expect(shared.single['originWidth'], card.width, reason: 'the iPad popover needs a real rectangle');
        expect(shared.single['originX'], card.left);
      });
    }

    testWidgets('NEGATIVE CONTROL: a TV has no share sheet', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin());
      expect(find.text(t.common.share), findsNothing);
    });

    testWidgets('NEGATIVE CONTROL: not on a collection or a playlist', (tester) async {
      await MenuHarness.open(tester, item: _item(MediaKind.collection), client: _jellyfin());
      expect(find.text(t.common.share), findsNothing);
    });

    testWidgets('a playlist has no row either', (tester) async {
      const playlist = MediaPlaylist(
        id: 'pl-1',
        backend: MediaBackend.jellyfin,
        title: 'Mine',
        playlistType: 'video',
        serverId: 'server-1',
      );
      await MenuHarness.open(tester, item: playlist, client: _jellyfin());
      expect(find.text(t.common.share), findsNothing);
    });
  });

  group('Watch', () {
    testWidgets('starts a movie', (tester) async {
      final menu = await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin());
      await tester.tap(find.text(t.mediaMenu.watch));
      await tester.pumpAndSettle();
      expect(menu.spy.playerRoutes, hasLength(1));
    });

    testWidgets('starts the next episode of a show', (tester) async {
      final next = _item(MediaKind.episode);
      final menu = await MenuHarness.open(
        tester,
        item: _item(MediaKind.show),
        client: _jellyfin(onDeck: next),
      );
      await tester.tap(find.text(t.mediaMenu.watch));
      await tester.pumpAndSettle();
      expect(menu.spy.playerRoutes, hasLength(1));
    });

    testWidgets('NEGATIVE CONTROL: a show without episodes says so and starts nothing', (tester) async {
      final menu = await MenuHarness.open(tester, item: _item(MediaKind.show), client: _jellyfin());
      await tester.tap(find.text(t.mediaMenu.watch));
      await tester.pumpAndSettle();
      expect(menu.spy.playerRoutes, isEmpty);
      expect(noticeController.visible, isNotEmpty, reason: 'no NoticeHost here, so the model holds it');
    });

    testWidgets('NEGATIVE CONTROL: no row on a TV, where Select already plays', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await MenuHarness.open(tester, item: _item(MediaKind.movie), client: _jellyfin());
      expect(find.text(t.mediaMenu.watch), findsNothing);
    });

    testWidgets('NEGATIVE CONTROL: no row for an item whose server is gone', (tester) async {
      await MenuHarness.open(
        tester,
        item: _item(MediaKind.movie, serverId: 'elsewhere'),
        client: _jellyfin(),
      );
      expect(find.text(t.mediaMenu.watch), findsNothing);
    });
  });
}
