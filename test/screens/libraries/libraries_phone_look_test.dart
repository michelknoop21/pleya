/// `LibrariesScreen` in the iPhone library look (A-06, Michel 30 October 2026).
///
/// The look is opt-in because this class also serves iPad, desktop and TV, so
/// the last test here pins that nothing changes without the flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/focus/focusable_action_bar.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/libraries/libraries_screen.dart';
import 'package:pleya/screens/libraries/mobile_library_header.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/focusable_tab_chip.dart';
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

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Widget? under,
    double topInset = 59,
    Size size = const Size(402, 874),
    List<MediaLibrary>? libraries,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: topInset);
    addTearDown(tester.view.reset);

    late StorageService storage;
    await tester.runAsync(() async {
      await SettingsService.getInstance();
      storage = await StorageService.getInstance();
      await storage.saveSelectedLibraryKey(_films.globalKey);
    });

    final manager = MultiServerManager();
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(multiServer.dispose);
    final provider = LibrariesProvider();
    final hidden = HiddenLibrariesProvider();
    await tester.runAsync(() => hidden.ensureInitialized());
    provider.debugSetLibraries(libraries ?? [_films]);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: hidden),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), home: under ?? screen),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pump();
    await tester.pump();
  }

  testWidgets('header: back, library with server line, then the actions; no pencil or refresh', (tester) async {
    await pump(tester, LibrariesScreen(phoneLook: true, onOpenSearch: () {}, onOpenWatchlist: () {}));

    expect(find.byType(MobileLibraryHeader), findsOneWidget);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Pleya'), findsOneWidget);
    expect(find.byIcon(Symbols.arrow_back_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.search_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.edit_rounded), findsNothing);
    expect(find.byIcon(Symbols.refresh_rounded), findsNothing);
    expect(find.byIcon(Symbols.tune_rounded), findsNothing);
    expect(find.byType(FocusableActionBar), findsNothing);

    final back = tester.getCenter(find.byIcon(Symbols.arrow_back_rounded));
    final title = tester.getCenter(find.text('Films'));
    final search = tester.getCenter(find.byIcon(Symbols.search_rounded));
    expect(back.dx, lessThan(title.dx));
    expect(title.dx, lessThan(search.dx));
  });

  testWidgets('the library name and the server line carry no tracking', (tester) async {
    await pump(tester, LibrariesScreen(phoneLook: true, onOpenSearch: () {}, onOpenWatchlist: () {}));

    expect(tester.widget<Text>(find.text('Films')).style!.letterSpacing, 0);
    expect(tester.widget<Text>(find.text('Pleya')).style!.letterSpacing, 0);
  });

  testWidgets('the title row stays clear of the status bar while its background runs under it', (tester) async {
    await pump(tester, const LibrariesScreen(phoneLook: true));

    expect(tester.getTopLeft(find.text('Films')).dy, greaterThanOrEqualTo(59));
    final background = find.descendant(of: find.byType(MobileLibraryHeader), matching: find.byType(BackdropFilter));
    expect(tester.getRect(background).top, 0);
  });

  testWidgets('all four tabs in the outlined style, under the title', (tester) async {
    await pump(tester, const LibrariesScreen(phoneLook: true));

    final chips = tester.widgetList<FocusableTabChip>(find.byType(FocusableTabChip)).toList();
    expect(chips.map((chip) => chip.label), [
      t.libraries.tabs.recommended,
      t.libraries.tabs.browse,
      t.libraries.tabs.collections,
      t.libraries.tabs.playlists,
    ]);
    expect(chips.every((chip) => chip.style == TabChipStyle.outlined), isTrue);
  });

  testWidgets('the tabs below sit inside the look', (tester) async {
    await pump(tester, const LibrariesScreen(phoneLook: true));
    expect(find.byType(LibraryPhoneLook), findsOneWidget);
  });

  testWidgets('the dots are there while no library is open', (tester) async {
    await pump(tester, const LibrariesScreen(phoneLook: true), libraries: const []);

    expect(find.byType(MobileLibraryHeader), findsOneWidget);
    expect(find.byIcon(Symbols.more_vert_rounded), findsOneWidget);
    expect(find.text(t.libraries.title), findsOneWidget);
  });

  testWidgets('search leaves this page and runs the main-screen route', (tester) async {
    var searches = 0;
    await pump(
      tester,
      const SizedBox(),
      under: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => LibrariesScreen(phoneLook: true, onOpenSearch: () => searches++)),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Symbols.search_rounded));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(searches, 1);
    expect(find.byType(LibrariesScreen), findsNothing);
  });

  testWidgets('avatar node is in the automation tree', (tester) async {
    await pump(tester, const LibrariesScreen(phoneLook: true));
    final ids = tester.widgetList<AutomationNode>(find.byType(AutomationNode)).map((node) => node.id).toSet();
    expect(ids, containsAll([AutomationIds.libraryHeaderAvatar, AutomationIds.libraryFilterMore]));
  });

  testWidgets('a 320 pt phone keeps the title and every action without overflow', (tester) async {
    await pump(
      tester,
      LibrariesScreen(phoneLook: true, onOpenSearch: () {}, onOpenWatchlist: () {}),
      size: const Size(320, 568),
      topInset: 20,
    );

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byIcon(Symbols.search_rounded)).right, lessThan(320));
    expect(
      tester.getRect(find.text('Films')).right,
      lessThan(tester.getRect(find.byIcon(Symbols.search_rounded)).left),
    );
  });

  testWidgets('without the flag the screen is what it was', (tester) async {
    await pump(tester, const LibrariesScreen());

    expect(find.byType(MobileLibraryHeader), findsNothing);
    expect(find.byType(LibraryPhoneLook), findsNothing);
    expect(find.byType(FocusableActionBar), findsOneWidget);
    expect(find.byIcon(Symbols.edit_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.refresh_rounded), findsOneWidget);
    final chips = tester.widgetList<FocusableTabChip>(find.byType(FocusableTabChip));
    expect(chips.every((chip) => chip.style == TabChipStyle.floating), isTrue);
  });
}
