/// The collections and playlists grids in the iPhone library look (A-06): the
/// same three columns as Bladeren. Neither the Verify fixture nor the demo
/// server holds collections or playlists, so this is where that is proven.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/libraries/libraries_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/focusable_media_card.dart';
import 'package:pleya/widgets/media_card.dart';
import 'package:pleya/widgets/mobile/library_phone_look.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

final _films = MediaLibrary(
  id: '1',
  backend: MediaBackend.plex,
  title: 'Films',
  kind: MediaKind.movie,
  serverId: 's1',
  serverName: 'Pleya',
);

class _GridClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('s1');

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage(
    totalCount: 7,
    items: [
      for (var i = 0; i < 7; i++)
        MediaItem(
          id: 'c$i',
          backend: MediaBackend.plex,
          kind: MediaKind.collection,
          title: 'Collectie $i',
          serverId: 's1',
        ),
    ],
  );

  @override
  Future<LibraryPage<MediaPlaylist>> fetchPlaylistsPage({
    String playlistType = 'video',
    bool? smart,
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage(
    totalCount: 7,
    items: [
      for (var i = 0; i < 7; i++)
        MediaPlaylist(id: 'p$i', backend: MediaBackend.plex, title: 'Lijst $i', playlistType: 'video'),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpTab(WidgetTester tester, String tab, {required bool phoneLook}) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await SettingsService.getInstance();
      final storage = await StorageService.getInstance();
      await storage.saveSelectedLibraryKey(_films.globalKey);
      await storage.saveLibraryTab(_films.globalKey, tab);
    });

    final manager = MultiServerManager()..debugRegisterClientForTesting(_GridClient());
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);
    final libraries = LibrariesProvider()..debugSetLibraries([_films]);
    final hidden = HiddenLibrariesProvider();
    await tester.runAsync(() => hidden.ensureInitialized());

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: libraries),
            ChangeNotifierProvider.value(value: hidden),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: LibrariesScreen(phoneLook: phoneLook),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        for (var j = 0; j < 4; j++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump();
    }
  }

  List<Rect> cards(WidgetTester tester) =>
      tester.widgetList(find.byType(FocusableMediaCard)).map((w) => tester.getRect(find.byWidget(w))).toList();

  for (final tab in const ['collections', 'playlists']) {
    testWidgets('$tab: three columns, flush with the insets', (tester) async {
      await pumpTab(tester, tab, phoneLook: true);

      final rects = cards(tester);
      expect(rects.length, greaterThanOrEqualTo(4));
      expect(rects[0].top, rects[2].top);
      expect(rects[3].top, greaterThan(rects[0].top));
      expect(rects[0].left, LibraryPhoneMetrics.gridInsetStart);
      expect(rects[2].right, closeTo(402 - LibraryPhoneMetrics.gridInsetEnd, 0.5));
      expect(rects[0].width, closeTo((402 - 37 - 10) / 3, 0.5));
    });

    testWidgets('$tab: the cards sit under the look, and nothing overflows', (tester) async {
      await pumpTab(tester, tab, phoneLook: true);
      final card = find.byType(MediaCard).first;
      expect(find.ancestor(of: card, matching: find.byType(LibraryPhoneLook)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('without the flag the column count still follows the density', (tester) async {
    await pumpTab(tester, 'collections', phoneLook: false);
    expect(cards(tester).first.left, isNot(LibraryPhoneMetrics.gridInsetStart));
  });
}
