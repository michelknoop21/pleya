/// "Alle films" / "Alle series" as a surface — mockup `03-alle-films.png`,
/// iOS Unified 2026 fase 3.
///
/// Every pump goes through `tester.runAsync`. The screen's controller reads
/// stored preferences through `SettingsService`/`StorageService`, and a
/// shared-preferences read does not complete inside `testWidgets`' fake async
/// zone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/mobile_shell_scope.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/home/mobile_catalog_screen.dart';
import 'package:pleya/screens/home/mobile_landing_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_grid.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_header.dart';
import 'package:pleya/widgets/mobile/mobile_media_card.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeClient implements MediaServerClient {
  _FakeClient(this.id, {this.itemsByLibrary = const {}, this.fails = false});

  final String id;
  final Map<String, List<MediaItem>> itemsByLibrary;
  final bool fails;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    if (fails) throw StateError('server down');
    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, year: 2024, serverId: 'nas');

MediaLibrary _library(String id) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: id,
  kind: MediaKind.movie,
  serverId: 'nas',
  serverName: 'NAS',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late UnifiedCatalogs catalogs;

  Future<void> setup({List<MediaItem>? items, bool fails = false, List<MediaLibrary>? eligible}) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    manager = MultiServerManager()
      ..debugRegisterClientForTesting(_FakeClient('nas', itemsByLibrary: {'films': items ?? const []}, fails: fails));
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider()..debugSetLibraries(eligible ?? [_library('films')]);
    catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);
  }

  tearDown(() {
    catalogs.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  Future<void> pumpCatalog(
    WidgetTester tester, {
    MobileLandingKind kind = MobileLandingKind.movies,
    void Function(NavigationTabId tab)? onOpenTab,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget screen = MobileCatalogScreen(kind: kind);
    if (onOpenTab != null) screen = MobileShellScope(openTab: onOpenTab, child: screen);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            Provider<UnifiedCatalogs>.value(value: catalogs),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: OverlaySheetHost(child: screen),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    });
    await tester.pump();
  }

  testWidgets('carries mockup 03\'s header, controls and status line', (tester) async {
    await setup(
      items: [
        _movie('m1', title: 'Alien'),
        _movie('m2', title: 'Dune'),
      ],
    );
    await pumpCatalog(tester);

    expect(find.text('All movies'), findsOneWidget);
    expect(find.byType(MobileCatalogHeader), findsOneWidget);
    // The three quiet controls, in mockup 03's order.
    expect(find.text('All sources'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Title A–Z'), findsOneWidget);
    // Loaded, never a total (10.7).
    expect(find.text('2 titles loaded'), findsOneWidget);
  });

  testWidgets('the Series catalogue is the same screen with the other title', (tester) async {
    await setup();
    await pumpCatalog(tester, kind: MobileLandingKind.series);

    expect(find.text('All series'), findsOneWidget);
    expect(find.text('All movies'), findsNothing);
  });

  testWidgets('draws the merged groups in a grid', (tester) async {
    await setup(
      items: [
        _movie('m1', title: 'Alien'),
        _movie('m2', title: 'Dune'),
      ],
    );
    await pumpCatalog(tester);

    expect(find.byType(MobileCatalogGrid), findsOneWidget);
    expect(find.byType(MobileMediaCard), findsNWidgets(2));
    expect(find.text('Alien'), findsOneWidget);
  });

  testWidgets('the search glyph opens the global Search destination, not a catalogue search', (tester) async {
    final opened = <NavigationTabId>[];
    await setup(items: [_movie('m1', title: 'Alien')]);
    await pumpCatalog(tester, onOpenTab: opened.add);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();

    // One glyph, one place, one meaning (DEC-094). It does not fill
    // UnifiedCatalogQuery.search.
    expect(opened, [NavigationTabId.search]);
  });

  testWidgets('the sources control opens the filter panel on its Servers section', (tester) async {
    await setup(items: [_movie('m1', title: 'Alien')]);
    await pumpCatalog(tester);

    await tester.tap(find.text('All sources'));
    await tester.pumpAndSettle();

    // The panel, opened where the control points — one filter model, two
    // entrances, no separate source sheet.
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);
  });

  testWidgets('the filters control opens the same panel on its first section', (tester) async {
    await setup(items: [_movie('m1', title: 'Alien')]);
    await pumpCatalog(tester);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Unwatched'), findsOneWidget);
  });

  testWidgets('the sort control opens the sort picker', (tester) async {
    await setup(items: [_movie('m1', title: 'Alien')]);
    await pumpCatalog(tester);

    // Scrolled into reach first: the control row is horizontally scrollable
    // on purpose, and under the test font (every glyph one em wide) the third
    // chip sits past the right edge. On a device with Inter it does not.
    await tester.scrollUntilVisible(find.text('Title A–Z'), 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Title A–Z'));
    await tester.pumpAndSettle();

    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Sort'), findsOneWidget);
  });

  testWidgets('an empty catalogue says it is empty, without offering a filter to clear', (tester) async {
    await setup();
    await pumpCatalog(tester);

    expect(find.text('This catalog is empty'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('every library failing is a full-page error, not an empty grid', (tester) async {
    await setup(fails: true);
    await pumpCatalog(tester);

    expect(find.text('No server answered. Check your connection and try again.'), findsOneWidget);
    expect(find.text('This catalog is empty'), findsNothing);
  });

  testWidgets('the control row scrolls rather than overflowing when the labels grow', (tester) async {
    await setup(items: [_movie('m1', title: 'Alien')]);
    await pumpCatalog(tester);

    // Three controls plus a long sort label plus a large text scale is more
    // than 393pt can hold, and a RenderFlex overflow there would be a red bar
    // across the northstar's own header.
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileCatalogControls), findsOneWidget);
  });

  testWidgets('brings its own OverlaySheetHost, because it is pushed above the shell\'s', (tester) async {
    await setup(items: [_movie('m1', title: 'Alien')]);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Deliberately no host around it, unlike `pumpCatalog`. The shell mounts
    // one in `main_screen.dart`, but this route is pushed *above* the shell,
    // so a screen that borrowed that host would find nothing at runtime and
    // both sheets would fail to open. A simulator probe caught this after
    // every other test in this file had mounted a host of its own and hidden
    // it.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            Provider<UnifiedCatalogs>.value(value: catalogs),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: const MobileCatalogScreen(kind: MobileLandingKind.movies),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    });
    await tester.pump();

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('the screen registers itself for Pleya Verify', (tester) async {
    await setup(items: [_movie('m1', title: 'Alien')]);
    await pumpCatalog(tester);

    // The ids the fase-3 scenario addresses. They are their own family
    // rather than a reuse of the landing's, so an assertion on the catalogue
    // fails rather than silently matching a rail.
    expect(
      AutomationIds.catalog().map((entry) => entry['id']),
      containsAll(<String>[
        AutomationIds.screenCatalog,
        AutomationIds.catalogHeader,
        AutomationIds.catalogControls,
        AutomationIds.catalogGrid,
        AutomationIds.catalogGridItem,
      ]),
    );
  });
}
