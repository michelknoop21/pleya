/// The long-press menu of the iPhone library look (A-06, Michel 30 October 2026,
/// reference 8c2d7495): the rows of `media_context_menu.dart` in the reference's
/// order, on the floating sheet, with nothing lost.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/app_menu.dart';
import 'package:pleya/widgets/media_menu_action.dart';
import 'package:pleya/widgets/mobile/library_phone_look.dart';
import 'package:pleya/widgets/mobile/library_phone_menu.dart';
import 'package:pleya/widgets/mobile/library_phone_sheet.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:share_plus_platform_interface/method_channel/method_channel_share.dart';

import '../../test_helpers/media_menu_harness.dart';
import '../../test_helpers/prefs.dart';

MediaMenuAction _action(String value) => MediaMenuAction(value: value, icon: Symbols.circle_rounded, label: value);

/// Every value `media_context_menu.dart` can put in a menu.
const _everyRow = [
  'play_from_beginning',
  'play_trailer',
  'share',
  'request',
  'watch',
  'unwatch',
  'remove_from_continue_watching',
  'details',
  'rate',
  'watchlist_toggle',
  'edit_metadata',
  'match',
  'unmatch',
  'remove_from_collection',
  'series',
  'shuffle_play',
  'play_version',
  'fileinfo',
  'play_external',
  'manage_sync',
  'remove_sync',
  'delete_download',
  'download',
  'add_to',
  'delete_media',
  'play_item',
  'play',
  'shuffle',
  'download_playlist',
  'download_collection',
  'delete',
];

List<String> _values(List<LibraryPhoneMenuRow> rows) => [
  for (final row in rows)
    if (row.children.isEmpty) row.value! else ..._values(row.children),
];

MediaItem _movie({bool watched = false}) => MediaItem(
  id: 'movie-1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: '22 Jump Street',
  year: 2014,
  serverId: 'server-1',
  viewCount: watched ? 1 : 0,
  mediaVersions: const [
    MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'h264', container: 'mkv'),
    MediaVersion(id: 'b', videoResolution: '480', videoCodec: 'h264', container: 'mp4'),
  ],
);

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

  group('libraryPhoneMenuRows', () {
    test('follows the reference from top to bottom', () {
      final rows = libraryPhoneMenuRows([for (final value in _everyRow) _action(value)]);
      final top = [for (final row in rows) row.value ?? row.label];
      final inOrder = [
        'play_item',
        'watchlist_toggle',
        'add_to',
        'rate',
        'watch',
        'download',
        t.mediaMenu.manage,
        'fileinfo',
        t.mediaMenu.moreWaysToWatch,
        'share',
      ];
      final positions = [for (final row in inOrder) top.indexOf(row)];
      expect(positions, isNot(contains(-1)));
      expect(positions, [...positions]..sort());
      expect(top.last, 'share');
    });

    test('nothing the menu offers goes missing, and nothing appears twice', () {
      final rows = libraryPhoneMenuRows([for (final value in _everyRow) _action(value)]);
      expect(_values(rows)..sort(), [..._everyRow]..sort());
    });

    test('a row this file has never heard of lands above Delen, not nowhere', () {
      final rows = libraryPhoneMenuRows([_action('share'), _action('brand_new'), _action('rate')]);
      expect([for (final row in rows) row.value], ['rate', 'brand_new', 'share']);
    });

    test('Beheren and Meer manieren hold their rows and only exist with something in them', () {
      final rows = libraryPhoneMenuRows([_action('delete_media'), _action('edit_metadata'), _action('share')]);
      final manage = rows.singleWhere((row) => row.label == t.mediaMenu.manage);
      expect([for (final row in manage.children) row.value], ['edit_metadata', 'delete_media']);
      expect(rows.where((row) => row.label == t.mediaMenu.moreWaysToWatch), isEmpty);
    });

    test('NEGATIVE CONTROL: no rows, no groups', () {
      expect(libraryPhoneMenuRows(const []), isEmpty);
    });

    test('the icon says which way the state stands', () {
      LibraryPhoneMenuRow only(MediaMenuAction action) => libraryPhoneMenuRows([action]).single;
      expect(only(_action('unwatch')).filledIcon, isTrue);
      expect(only(_action('watch')).filledIcon, isFalse);
      const onList = MediaMenuAction(
        value: 'watchlist_toggle',
        icon: Symbols.bookmark_remove_rounded,
        label: 'x',
        active: true,
      );
      expect(only(onList).filledIcon, isTrue);
      expect(only(_action('watchlist_toggle')).filledIcon, isFalse);
    });
  });

  group('on a card in the look', () {
    Finder inSheet(Finder finder) => find.descendant(of: find.byType(LibraryPhoneMenuSheet), matching: finder);

    testWidgets('floats 8 pt off the edges with the title as heading', (tester) async {
      await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true, canManage: true);
      final surface = find.ancestor(of: find.byType(LibraryPhoneMenuSheet), matching: find.byType(Material)).first;
      final rect = tester.getRect(surface);
      expect((rect.left, rect.right, rect.bottom), (8.0, 394.0, 866.0));
      expect(tester.widget<Material>(surface).borderRadius, BorderRadius.circular(37));

      final title = find.text('22 Jump Street').last;
      expect(tester.getCenter(title).dx, closeTo(rect.center.dx, 0.5));
      expect(tester.widget<Text>(title).style!.fontWeight, FontWeight.w700);
    });

    testWidgets('rows are icon and label, 46 pt apart, on the reference\'s edges', (tester) async {
      await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true);
      final rows = inSheet(find.byType(LibraryPhoneSheetActionRow));
      expect(rows, findsWidgets);
      final first = tester.getRect(rows.at(0));
      final second = tester.getRect(rows.at(1));
      expect(second.top - first.top, LibraryPhoneMetrics.sheetRowHeight);

      final label = tester.getRect(find.text(t.mediaMenu.watch));
      expect(label.left - first.left, closeTo(54, 1), reason: 'text 54 pt from the sheet edge');
      expect(label.center.dy, closeTo(first.center.dy, 0.5));
    });

    testWidgets('a 48 pt Android navigation bar leaves the last row clear', (tester) async {
      await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true, bottomInset: 48);
      final rows = inSheet(find.byType(LibraryPhoneSheetActionRow));
      expect(tester.getRect(rows.last).bottom, lessThanOrEqualTo(874 - 48));
    });

    testWidgets('a film as the owner reads as in the reference, with the rows that exist', (tester) async {
      await MenuHarness.open(
        tester,
        item: _movie(watched: true),
        client: MenuFakeClient(),
        phoneLook: true,
        canManage: true,
      );
      final labels = [
        for (final row in tester.widgetList<LibraryPhoneSheetActionRow>(
          inSheet(find.byType(LibraryPhoneSheetActionRow)),
        ))
          row.label,
      ];
      expect(labels, [
        t.mediaMenu.watch,
        t.common.addTo,
        t.mediaMenu.rate,
        t.mediaMenu.markAsUnwatched,
        t.downloads.downloadNow,
        t.mediaMenu.manage,
        t.mediaMenu.fileInfo,
        t.mediaMenu.moreWaysToWatch,
        t.common.share,
      ]);
    });

    testWidgets('Beheren opens its rows in the same sheet, and back returns', (tester) async {
      await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true, canManage: true);
      await tester.tap(find.text(t.mediaMenu.manage));
      await tester.pumpAndSettle();

      expect(find.text(t.mediaMenu.deleteFromServer), findsOneWidget);
      expect(find.text(t.mediaMenu.watch), findsNothing);
      expect(find.text(t.mediaMenu.manage), findsOneWidget, reason: 'the group is the heading now');

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text(t.mediaMenu.watch), findsOneWidget);
    });

    testWidgets('Meer manieren holds the ways to start, a row in it runs like any other', (tester) async {
      final menu = await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true);
      await tester.tap(find.text(t.mediaMenu.moreWaysToWatch));
      await tester.pumpAndSettle();
      expect(find.text(t.mediaMenu.playVersion), findsOneWidget);
      expect(find.text(t.externalPlayer.playInExternalPlayer), findsOneWidget);

      await tester.tap(find.text(t.mediaMenu.playVersion));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPhoneMenuSheet), findsNothing);
      expect(
        find.text(MediaVersion(id: 'a', videoResolution: '1080', videoCodec: 'h264', container: 'mkv').displayLabel),
        findsOneWidget,
      );
      expect(menu.spy.playerRoutes, isEmpty);
    });

    testWidgets('Kijken closes the sheet and starts the player', (tester) async {
      final menu = await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true);
      await tester.tap(find.text(t.mediaMenu.watch));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPhoneMenuSheet), findsNothing);
      expect(menu.spy.playerRoutes, hasLength(1));
    });

    testWidgets('Delen stays anchored to the card, also after the sheet is gone', (tester) async {
      final shared = <Map<Object?, Object?>>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(MethodChannelShare.channel, (call) async {
        shared.add(call.arguments as Map<Object?, Object?>);
        return 'success';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(MethodChannelShare.channel, null));

      await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), phoneLook: true);
      await tester.tap(find.text(t.common.share));
      await tester.pumpAndSettle();
      expect(shared.single['text'], '22 Jump Street (2014)');
      expect(shared.single['originWidth'], 120);
    });

    testWidgets('a playlist keeps its own rows, with Verwijderen under Beheren', (tester) async {
      const playlist = MediaPlaylist(
        id: 'pl-1',
        backend: MediaBackend.plex,
        title: 'Mine',
        playlistType: 'video',
        serverId: 'server-1',
      );
      await MenuHarness.open(
        tester,
        item: playlist,
        client: MenuFakeClient(capabilities: ServerCapabilities.plex),
        phoneLook: true,
      );
      expect(find.text(t.common.play), findsOneWidget);
      await tester.tap(find.text(t.mediaMenu.manage));
      await tester.pumpAndSettle();
      expect(find.text(t.common.delete), findsOneWidget);
    });
  });

  testWidgets('NEGATIVE CONTROL: outside the look the menu keeps its flat rows', (tester) async {
    await MenuHarness.open(tester, item: _movie(), client: MenuFakeClient(), canManage: true);
    expect(find.byType(LibraryPhoneMenuSheet), findsNothing);
    expect(find.byType(AppMenuItemTile<String>), findsWidgets);
    expect(find.text(t.mediaMenu.manage), findsNothing);
    expect(find.text(t.mediaMenu.deleteFromServer), findsOneWidget);
  });
}
