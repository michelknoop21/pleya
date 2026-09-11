import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/actor_media_screen.dart';
import 'package:pleya/screens/collection_detail_screen.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/screens/search_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/services/search_recents.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_rail.dart';
import 'package:pleya/widgets/tv/tv_section_header.dart';
import 'package:pleya/widgets/tv/tv_catalog_item_card.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    // `StorageService` first: `BaseSharedPreferencesService`'s shared cache
    // future is created by whichever subclass asks first, and a second
    // subclass's `onInit()` never actually completing when it asks second
    // is a real, if latent, ordering bug — invisible everywhere else because
    // nothing else awaits `HiddenLibrariesProvider`'s own storage-backed init
    // to completion, but the B17 tests below do exactly that.
    await StorageService.getInstance();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });

  testWidgets('stale callbacks are no-ops after SearchScreen is disposed', (tester) async {
    final key = GlobalKey<State<SearchScreen>>();

    final hiddenLibraries = HiddenLibrariesProvider();
    addTearDown(hiddenLibraries.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<HiddenLibrariesProvider>.value(
          value: hiddenLibraries,
          child: MaterialApp(home: SearchScreen(key: key)),
        ),
      ),
    );

    final state = key.currentState!;
    final searchInput = state as SearchInputFocusable;
    searchInput.setSearchQuery('movie');
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(() => (state as Refreshable).refresh(), returnsNormally);
    expect(() => (state as dynamic).updateItem('movie_1'), returnsNormally);
    expect(() => (state as FullRefreshable).fullRefresh(), returnsNormally);
    expect(() => searchInput.setSearchQuery('new movie'), returnsNormally);
    expect(() => (state as FocusableTab).focusActiveTabIfReady(), returnsNormally);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV OSK search key moves focus to the first result', (tester) async {
    final (client, key) = await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();
    // Inline keyboard: always visible on the TV search page, no modal to open.
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsOneWidget);

    final state = key.currentState!;
    (state as SearchInputFocusable).setSearchQuery('movie');
    // rate_limiter's Debounce compares DateTime.now() against the fake-clock
    // timer, so it never invokes under FakeAsync — run the search via
    // refresh() (same _performSearch path) to get results in place.
    (state as Refreshable).refresh();
    await tester.pumpAndSettle();
    expect(client.queries, ['movie']);
    expect(find.text('Movie 1'), findsOneWidget);

    await tester.tap(_keyboardDoneKey());
    await tester.pumpAndSettle();

    // The inline keyboard stays put; Done only jumps focus to the results.
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsOneWidget);
    // TV draws the results as catalog cards in bands since DEC-108 (mockup
    // 36 B): "the first result" is the first card of the first band, not a
    // source-concrete card, so its debug label carries the band's own prefix
    // instead of the non-TV list's fixed 'SearchFirstResult'.
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('TvSearchCard(movies)'));
    expect(find.text('Movie 1'), findsOneWidget);

    // Dispose the screen so its still-armed debounce timer is cancelled.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV OSK search key before the debounce fires searches immediately', (tester) async {
    final (client, key) = await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsOneWidget);

    (key.currentState! as SearchInputFocusable).setSearchQuery('movie');
    await tester.pump(const Duration(milliseconds: 100));
    expect(client.queries, isEmpty);

    await tester.tap(_keyboardDoneKey());
    await tester.pumpAndSettle();

    expect(client.queries, ['movie']);
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsOneWidget);
    // TV draws the results as catalog cards in bands since DEC-108 (mockup
    // 36 B): "the first result" is the first card of the first band, not a
    // source-concrete card, so its debug label carries the band's own prefix
    // instead of the non-TV list's fixed 'SearchFirstResult'.
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('TvSearchCard(movies)'));
  });

  testWidgets('the row at rest is the titles that were opened, not the queries that were typed (36 A)', (tester) async {
    // Mockup 36 A. `search_history` still holds the query strings, and desktop
    // and mobile still draw them as chips; TV draws what those queries were
    // *for*. A row of past query strings asks a viewer to remember what "dune"
    // got them; a row of posters is the thing itself, one press away.
    SettingsService.instance.write(SettingsService.searchHistory, ['star wars']);
    rememberSearchRecent(
      MediaItem(
        id: 'm1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Andor',
        year: 2022,
        serverId: 'server_1',
        serverName: 'Server',
      ),
    );

    await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Andor'), findsOneWidget);
    expect(find.text('star wars'), findsNothing, reason: 'the query chips are the desktop presentation, not this one');
    expect(find.byType(TvCatalogItemCard), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Wissen empties both recencies, and hands the focus back to the input', (tester) async {
    // 36 A draws no button beside the heading, and without one this row would
    // be the one list on TV a viewer cannot clear — the chips it replaces
    // always had a Wissen. It clears both halves, because on this page they
    // are one idea with two presentations.
    SettingsService.instance.write(SettingsService.searchHistory, ['star wars']);
    rememberSearchRecent(
      MediaItem(
        id: 'm1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Andor',
        serverId: 'server_1',
        serverName: 'Server',
      ),
    );

    final (_, key) = await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();

    // Through the remote rather than through a tap: this control only exists
    // on TV, and `FocusableWrapper` is what carries Select there.
    final action = Focus.maybeOf(tester.element(find.text(t.search.clearHistory).last), scopeOk: true)!;
    action.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.text('Andor'), findsNothing);
    expect(readSearchRecents(), isEmpty);
    expect(SettingsService.instance.read(SettingsService.searchHistory), isEmpty);
    // The row unmounts under the button that was just pressed; without a new
    // home primary focus dies with it and the D-pad goes dead.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'SearchInput');
    expect(key.currentState, isNotNull);
  });

  testWidgets('TV: a new search while a result is focused parks focus on the input', (tester) async {
    final (client, key) = await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();

    final state = key.currentState!;
    (state as SearchInputFocusable).setSearchQuery('movie');
    (state as Refreshable).refresh();
    await tester.pumpAndSettle();
    await tester.tap(_keyboardDoneKey());
    await tester.pumpAndSettle();
    // TV draws the results as catalog cards in bands since DEC-108 (mockup
    // 36 B): "the first result" is the first card of the first band, not a
    // source-concrete card, so its debug label carries the band's own prefix
    // instead of the non-TV list's fixed 'SearchFirstResult'.
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('TvSearchCard(movies)'));

    // A new search swaps the results sliver for skeletons (zero focusables) —
    // without the safety net, primary focus dies with the unmounted card.
    (state as SearchInputFocusable).submitSearchQuery('other movie');
    await tester.pumpAndSettle();

    expect(client.queries, ['movie', 'other movie']);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'SearchInput');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV search projects equivalent multi-server results onto one unified tile', (tester) async {
    // hoofdstuk 16.1/16.2: "Dune (2021) — 3 bronnen", never one row per
    // server. Two servers answer the same query with the same title and
    // matching external ids — production merge evidence — so the unified
    // rail must render exactly one tile carrying both sources, not two.
    TvDetectionService.debugSetAppleTVOverride(null);
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final clientA = _FakeMediaServerClient(
      items: [_dune('dune-a', 'server_a')],
      serverId: 'server_a',
      serverName: 'Server A',
      externalIdsByItemId: {'dune-a': const ExternalIds(tmdb: 438631)},
    );
    final clientB = _FakeMediaServerClient(
      items: [_dune('dune-b', 'server_b')],
      serverId: 'server_b',
      serverName: 'Server B',
      externalIdsByItemId: {'dune-b': const ExternalIds(tmdb: 438631)},
    );
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(clientA)
      ..debugRegisterClientForTesting(clientB);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    final hiddenLibraries = HiddenLibrariesProvider();
    addTearDown(hiddenLibraries.dispose);

    final key = GlobalKey<State<SearchScreen>>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: SearchScreen(key: key),
          ),
        ),
      ),
    );
    (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
    (key.currentState! as Refreshable).refresh();
    await tester.pumpAndSettle();

    // One band (Films), one card, carrying both sources — not two rows for
    // one title. Since DEC-108 the multiplicity is the catalog card's own
    // top-left marker (hoofdstuk 10.3) rather than the discovery rail's badge.
    expect(find.byType(TvCatalogCardRail), findsOneWidget);
    expect(find.byType(TvUnifiedMediaCard), findsOneWidget);
    expect(find.text(t.unifiedCatalog.sources(count: 2)), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('LAND4: TV Zoeken stacks bands, so a vertical step keeps its column', () {
    MediaItem film(String id, String title) => MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: title,
      serverId: 'server_1',
      serverName: 'Server',
    );

    MediaItem show(String id, String title) => MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.show,
      title: title,
      serverId: 'server_1',
      serverName: 'Server',
    );

    /// The column the focus stands on, read off the card's own debug label —
    /// `TvSearchCard(<band>)(<id>)`.
    String? focusedCardId() {
      final label = FocusManager.instance.primaryFocus?.debugLabel;
      final match = RegExp(r'^TvSearchCard\([a-z]+\)\((.+)\)$').firstMatch(label ?? '');
      return match?.group(1);
    }

    Future<List<TvCatalogCardRailState>> pumpResults(WidgetTester tester) async {
      TvDetectionService.debugSetAppleTVOverride(null);
      await TvDetectionService.getInstance(forceTv: true);
      TvDetectionService.setForceTVSync(true);
      tester.view.devicePixelRatio = 1.0;
      // Taller than the usual TV fixture on purpose: two bands have to be laid
      // out at once for a step between them to mean anything.
      tester.view.physicalSize = const Size(1280, 1600);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final client = _FakeMediaServerClient(
        items: [
          for (var i = 0; i < 8; i++) film('f$i', 'Film $i'),
          for (var i = 0; i < 8; i++) show('s$i', 'Serie $i'),
        ],
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);
      final hiddenLibraries = HiddenLibrariesProvider();
      addTearDown(hiddenLibraries.dispose);

      final key = GlobalKey<State<SearchScreen>>();
      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: SearchScreen(key: key),
            ),
          ),
        ),
      );
      (key.currentState! as SearchInputFocusable).setSearchQuery('e');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      return tester.stateList<TvCatalogCardRailState>(find.byType(TvCatalogCardRail)).toList();
    }

    testWidgets('DOWN from the Films band lands on the same column of the Series band', (tester) async {
      final bands = await pumpResults(tester);
      expect(bands, hasLength(2), reason: 'sanity: a Films band and a Series band');
      final films = bands.first.widget.itemIds;
      final series = bands.last.widget.itemIds;

      // The lower band is parked far right, so its own focus memory would
      // answer with the card it remembers rather than with the column the step
      // came from — which is precisely what LAND4 forbids.
      expect(bands.last.focusColumn(6), isTrue);
      await tester.pumpAndSettle();
      expect(focusedCardId(), series[6], reason: 'sanity: the Series band is parked far right');

      expect(bands.first.focusColumn(2), isTrue);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedCardId(), series[2]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focusedCardId(), films[2], reason: 'and the round trip ends where it started');
    });

    testWidgets('SEARCH1: the section is named by a heading, which the focus does not move', (tester) async {
      // The old build named a result through `TvDiscoveryRail`'s caption, with
      // `alwaysDescribesCurrent` set — one rail carrying an exception to the
      // rail contract, because on a feed that caption follows the focus and on
      // a result page it must not. Mockup 36 B settles it the other way: the
      // name is a heading above a band that owns no caption at all, so there
      // is nothing left to make an exception for.
      final bands = await pumpResults(tester);

      expect(find.text(t.unifiedCatalog.moviesTitle), findsOneWidget);
      expect(find.text(t.unifiedCatalog.seriesTitle), findsOneWidget);
      expect(
        find.descendant(of: find.byType(TvSectionHeader), matching: find.text('8')),
        findsNWidgets(2),
        reason: 'the heading states how many results the section has',
      );

      expect(bands.first.focusColumn(0), isTrue);
      await tester.pumpAndSettle();
      expect(
        find.text(t.unifiedCatalog.seriesTitle),
        findsOneWidget,
        reason: 'the Series heading stands while the focus is in Films — it names a section, not a position',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        find.text(t.unifiedCatalog.moviesTitle),
        findsOneWidget,
        reason: 'and moving within a band does not rewrite its heading',
      );
    });
  });

  testWidgets('desktop search stays source-concrete for the same multi-server match', (tester) async {
    // Same fixture as the TV dedup test above, pumped through the ordinary
    // desktop SearchScreen: desktop must keep showing one card per server,
    // unchanged by the unified projection I4 gives the phone build. A large,
    // non-phone viewport is forced explicitly (`PlatformDetector.isPhone`
    // has no debug override, unlike TV's `debugSetAppleTVOverride`) —
    // without it the default flutter_test surface reads as phone-sized and
    // this test would exercise the wrong build path.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final clientA = _FakeMediaServerClient(
      items: [_dune('dune-a', 'server_a')],
      serverId: 'server_a',
      serverName: 'Server A',
      externalIdsByItemId: {'dune-a': const ExternalIds(tmdb: 438631)},
    );
    final clientB = _FakeMediaServerClient(
      items: [_dune('dune-b', 'server_b')],
      serverId: 'server_b',
      serverName: 'Server B',
      externalIdsByItemId: {'dune-b': const ExternalIds(tmdb: 438631)},
    );
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(clientA)
      ..debugRegisterClientForTesting(clientB);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    final hiddenLibraries = HiddenLibrariesProvider();
    addTearDown(hiddenLibraries.dispose);

    final key = GlobalKey<State<SearchScreen>>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: SearchScreen(key: key),
          ),
        ),
      ),
    );
    await tester.pump();
    (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
    (key.currentState! as Refreshable).refresh();
    await tester.pumpAndSettle();

    expect(find.byType(TvCatalogCardRail), findsNothing, reason: 'off TV the source-concrete list is unchanged');
    expect(find.text('Dune'), findsNWidgets(2));
  });

  group('I4: phone unified search sections (05-zoeken.png)', () {
    Future<GlobalKey<State<SearchScreen>>> pumpPhoneSearchScreen(
      WidgetTester tester,
      MediaServerClient client, {
      List<NavigatorObserver> navigatorObservers = const [],
    }) async {
      // Phone-sized, unlike `_pumpSearchScreen`'s 1280×900: `PlatformDetector`
      // has no debug override for `isPhone`, so the branch under test is only
      // reached by an actual phone-shaped viewport. `physicalSize` is
      // physical, not logical, pixels, and `isTablet` divides the logical
      // diagonal by `devicePixelRatio * 160/2.54` — so getting a real iPhone
      // logical size of 393×852 needs a physical size of 393×852 *times* the
      // device pixel ratio, not 393×852 itself (`mobile_home_screen_test.dart`
      // pairs that literal 393×852 with DPR 1.0 instead, for its own
      // unrelated layout math, and a DPR of 1.0 here reads as a ~15" tablet).
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);
      final hiddenLibraries = HiddenLibrariesProvider();
      addTearDown(hiddenLibraries.dispose);

      final key = GlobalKey<State<SearchScreen>>();
      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              navigatorObservers: navigatorObservers,
              // MediaDetailScreen (a movie/show group's activation target)
              // requires ProfileNavigationScope above it in the tree — see
              // the `_navigateToActorMedia`/detail-route gotcha in the
              // project's own CLAUDE.md. It has to sit in `builder`, above
              // the Navigator itself, not wrapped around `home` directly:
              // `home` only wraps route 1's own page, a sibling Overlay
              // entry to whatever `Navigator.push` adds next, so a route
              // this test pushes would not inherit it either way.
              builder: (context, child) => withProfileNavigationScope(child: child!),
              home: SearchScreen(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      return key;
    }

    testWidgets('renders movies/shows unified with a source count, and collections/people alongside', (tester) async {
      final client = _FakeMediaServerClient(
        items: [
          _dune('dune-a', 'server_1'),
          MediaItem(
            id: 'silo-1',
            backend: MediaBackend.plex,
            kind: MediaKind.show,
            title: 'Silo',
            serverId: 'server_1',
            serverName: 'Server',
          ),
          MediaItem(
            id: 'coll-1',
            backend: MediaBackend.plex,
            kind: MediaKind.collection,
            title: 'Denis Villeneuve',
            serverId: 'server_1',
            serverName: 'Server',
          ),
        ],
        people: [
          MediaItem(
            id: 'person-1',
            backend: MediaBackend.plex,
            kind: MediaKind.unknown,
            title: 'Denzel Washington',
            serverId: 'server_1',
            serverName: 'Server',
          ),
        ],
      );
      final key = await pumpPhoneSearchScreen(tester, client);
      (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();

      expect(find.text('Dune'), findsOneWidget);
      // Both Dune (movie) and Silo (show) are single-source groups, so both
      // rows carry the label — `05-zoeken.png` shows "1 bron" even alone.
      expect(find.text(t.unifiedCatalog.oneSource), findsNWidgets(2));
      expect(find.text('Silo'), findsOneWidget);
      expect(find.text('Denis Villeneuve'), findsOneWidget, reason: 'collections render under their own section');
      expect(find.text('Denzel Washington'), findsOneWidget, reason: 'SRCH-2: people render as their own section');
      expect(find.byType(TvCatalogCardRail), findsNothing, reason: 'phone renders rows, not TV rails');
    });

    testWidgets('a unified group opens detail on its representative source', (tester) async {
      // MediaDetailScreen itself needs a DownloadProvider (and more) that no
      // test in this codebase stands up to mount it directly — the same
      // reason the collection case below inspects the pushed route rather
      // than letting it build.
      final observer = _RecordingNavigatorObserver();
      final client = _FakeMediaServerClient(items: [_dune('dune-a', 'server_1')]);
      final key = await pumpPhoneSearchScreen(tester, client, navigatorObservers: [observer]);
      (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dune'));

      final pushed = observer.lastPushedRoute;
      expect(pushed, isA<MaterialPageRoute>());
      final widget = (pushed! as MaterialPageRoute).builder(key.currentState!.context);
      expect(widget, isA<MediaDetailScreen>());
    });

    testWidgets('a collection opens through the same source-concrete route every other list uses', (tester) async {
      // CollectionDetailScreen itself needs a DownloadProvider and more that
      // no test in this codebase currently stands up (nothing here mounts it
      // directly) — out of scope to build for this workitem, since
      // `_openConcrete`'s collection branch is pre-existing, unmodified
      // `navigateToMediaItem` code already relied on by TV and desktop
      // search alike. What I4 actually adds is the phone *row* calling it at
      // all, which this proves by inspecting the pushed route's builder
      // directly — a plain function call, not an inflate — so nothing here
      // attempts the real screen's own construction.
      final observer = _RecordingNavigatorObserver();
      final client = _FakeMediaServerClient(
        items: [
          MediaItem(
            id: 'coll-1',
            backend: MediaBackend.plex,
            kind: MediaKind.collection,
            title: 'Denis Villeneuve',
            serverId: 'server_1',
            serverName: 'Server',
          ),
        ],
      );
      final key = await pumpPhoneSearchScreen(tester, client, navigatorObservers: [observer]);
      (key.currentState! as SearchInputFocusable).setSearchQuery('denis');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();

      // No `pump()` after the tap: `Navigator.push` and `didPush` both fire
      // synchronously from the tap's own pointer-event dispatch, before any
      // frame would actually build the pushed page and hit the missing
      // provider.
      await tester.tap(find.text('Denis Villeneuve'));

      final pushed = observer.lastPushedRoute;
      expect(pushed, isA<MaterialPageRoute>());
      final widget = (pushed! as MaterialPageRoute).builder(key.currentState!.context);
      expect(widget, isA<CollectionDetailScreen>());
    });

    testWidgets('a person opens ActorMediaScreen, never the generic media route (SRCH-2)', (tester) async {
      final client = _FakeMediaServerClient(
        items: const [],
        people: [
          MediaItem(
            id: 'person-1',
            backend: MediaBackend.plex,
            kind: MediaKind.unknown,
            title: 'Denzel Washington',
            serverId: 'server_1',
            serverName: 'Server',
          ),
        ],
      );
      final key = await pumpPhoneSearchScreen(tester, client);
      (key.currentState! as SearchInputFocusable).setSearchQuery('denzel');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Denzel Washington'));
      // Settle, not a single pump: mid-push-transition the incoming route is
      // still `Offstage`, which `find.byType`'s default `skipOffstage: true`
      // excludes even though the widget already exists in the tree.
      await tester.pumpAndSettle();

      expect(find.byType(ActorMediaScreen), findsOneWidget);
      expect(find.byType(MediaDetailScreen), findsNothing);
    });
  });

  testWidgets('a slow earlier search cannot overwrite a newer one', (tester) async {
    final client = _ProgrammableClient();
    final key = await _pumpSearchScreen(tester, client);
    final search = key.currentState! as SearchInputFocusable;

    // "bat" goes out first and hangs; "batman" is typed on top and answers.
    search.submitSearchQuery('bat');
    await tester.pump();
    search.submitSearchQuery('batman');
    await tester.pump();

    client.complete('batman', [_item('movie_batman', 'Batman')]);
    await tester.pumpAndSettle();
    expect(find.text('Batman'), findsOneWidget);

    // The stale "bat" response lands last and must be dropped entirely.
    client.complete('bat', [_item('movie_bat', 'Bat Documentary')]);
    await tester.pumpAndSettle();

    expect(find.text('Batman'), findsOneWidget);
    expect(find.text('Bat Documentary'), findsNothing);

    // ...and typing "batman" again must not be short-circuited by a
    // _lastSearchedQuery that the stale response corrupted.
    client.queries.clear();
    search.submitSearchQuery('batman');
    await tester.pump();
    expect(client.queries, ['batman']);

    // Settle the last request so its per-server timeout timer isn't left armed.
    client.complete('batman', const []);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failing search renders an error state with retry, not "no results"', (tester) async {
    final client = _ProgrammableClient();
    final key = await _pumpSearchScreen(tester, client);
    final search = key.currentState! as SearchInputFocusable;

    search.submitSearchQuery('movie');
    await tester.pump();
    client.fail('movie', Exception('connection refused'));
    await tester.pumpAndSettle();

    expect(find.text(t.search.errorTitle), findsOneWidget);
    expect(find.text(t.search.errorNetwork), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
    // The empty state would be actively misleading here.
    expect(find.text(t.search.tryDifferentTerm), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('backspacing below two characters clears the results', (tester) async {
    final client = _ProgrammableClient();
    final key = await _pumpSearchScreen(tester, client);
    final search = key.currentState! as SearchInputFocusable;

    search.submitSearchQuery('abc');
    await tester.pump();
    client.complete('abc', [_item('movie_abc', 'ABC Movie')]);
    await tester.pumpAndSettle();
    expect(find.text('ABC Movie'), findsOneWidget);

    // Backspace down to a single character: the old results no longer belong
    // to what is in the field.
    search.setSearchQuery('a');
    await tester.pumpAndSettle();
    expect(find.text('ABC Movie'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // B17: hidden libraries are a hard visibility boundary (hoofdstuk 22), and
  // TV search reads them synchronously off `HiddenLibrariesProvider` rather
  // than awaiting its own readiness (see the comment in `_performSearch`).
  // These prove the seam that actually closes the gap: a hide or unhide that
  // lands after a search already has results on screen reruns that same
  // query through `_onHiddenLibrariesChanged`, with a dedup guard so a
  // notification that left the effective set unchanged costs nothing. The
  // same listener is what corrects the narrower cold-start race this row
  // is actually about (a query submitted before persisted visibility has
  // loaded) — `_initialize()` ends with the same unconditional notify a
  // hide/unhide fires, so the mechanism is one and the same; that specific
  // timing window is not independently reproduced here; it collapses too
  // reliably under `flutter_test`'s own scheduling to assert on directly
  // without asserting a false negative.
  group('B17: hidden-library visibility and TV search', () {
    Future<GlobalKey<State<SearchScreen>>> pumpTvSearch(
      WidgetTester tester, {
      required MediaServerClient client,
      required HiddenLibrariesProvider hiddenLibraries,
    }) async {
      TvDetectionService.debugSetAppleTVOverride(null);
      await TvDetectionService.getInstance(forceTv: true);
      TvDetectionService.setForceTVSync(true);
      addTearDown(() => TvDetectionService.setForceTVSync(false));

      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      final key = GlobalKey<State<SearchScreen>>();
      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: SearchScreen(key: key),
            ),
          ),
        ),
      );
      return key;
    }

    testWidgets('a library hidden after a result is already on screen removes it', (tester) async {
      final client = _FakeMediaServerClient(items: [_dune('dune-visible', 'srv', libraryId: 'lib-visible')]);
      final hiddenLibraries = HiddenLibrariesProvider();
      addTearDown(hiddenLibraries.dispose);
      await hiddenLibraries.ensureInitialized();

      final key = await pumpTvSearch(tester, client: client, hiddenLibraries: hiddenLibraries);
      (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget, reason: 'the library is visible so far');

      await hiddenLibraries.hideLibrary('srv:lib-visible');
      await tester.pumpAndSettle();

      expect(
        find.text('Dune'),
        findsNothing,
        reason: 'a title from a library hidden mid-session must not linger as an activation candidate',
      );
    });

    testWidgets('unhiding a library brings its result back', (tester) async {
      final client = _FakeMediaServerClient(items: [_dune('dune-toggle', 'srv', libraryId: 'lib-toggle')]);
      final storage = await StorageService.getInstance();
      await storage.saveHiddenLibraries({'srv:lib-toggle'});
      final hiddenLibraries = HiddenLibrariesProvider();
      addTearDown(hiddenLibraries.dispose);
      await hiddenLibraries.ensureInitialized();

      final key = await pumpTvSearch(tester, client: client, hiddenLibraries: hiddenLibraries);
      (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing, reason: 'starts hidden');

      await hiddenLibraries.unhideLibrary('srv:lib-toggle');
      await tester.pumpAndSettle();

      expect(find.text('Dune'), findsOneWidget, reason: 'the source can come back once unhidden');
    });

    testWidgets('a hidden-library change that leaves the effective set unchanged reruns nothing', (tester) async {
      final client = _FakeMediaServerClient(items: [_dune('dune-plain', 'srv', libraryId: 'lib-plain')]);
      final hiddenLibraries = HiddenLibrariesProvider();
      addTearDown(hiddenLibraries.dispose);
      await hiddenLibraries.ensureInitialized();

      final key = await pumpTvSearch(tester, client: client, hiddenLibraries: hiddenLibraries);
      (key.currentState! as SearchInputFocusable).setSearchQuery('dune');
      (key.currentState! as Refreshable).refresh();
      await tester.pumpAndSettle();
      expect(client.queries, hasLength(1));

      // Provider-initiated notification with nothing actually changed — the
      // same shape as `_initialize()`'s own unconditional notify.
      await hiddenLibraries.refresh();
      await tester.pumpAndSettle();

      expect(
        client.queries,
        hasLength(1),
        reason: 'a notification that left the effective hidden set unchanged must not cost a second fan-out',
      );
    });
  });
}

MediaItem _item(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: 'server_1',
  serverName: 'Server',
);

// Same title, deliberately different serverId per call — the shape a real
// multi-server merge candidate takes. `_item` above always claims
// 'server_1', which is wrong for these fixtures' per-server fake clients.
MediaItem _dune(String id, String serverId, {String? libraryId}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  serverId: serverId,
  serverName: serverId,
  libraryId: libraryId,
);

Future<GlobalKey<State<SearchScreen>>> _pumpSearchScreen(WidgetTester tester, MediaServerClient client) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final provider = MultiServerProvider(manager, DataAggregationService(manager));
  addTearDown(provider.dispose);
  final hiddenLibraries = HiddenLibrariesProvider();
  addTearDown(hiddenLibraries.dispose);

  final key = GlobalKey<State<SearchScreen>>();
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: SearchScreen(key: key),
        ),
      ),
    ),
  );
  await tester.pump();
  return key;
}

/// Client whose per-query futures the test completes by hand, so responses can
/// be made to arrive out of order.
class _ProgrammableClient implements MediaServerClient {
  final List<String> queries = [];
  final Map<String, Completer<List<MediaItem>>> _pending = {};

  void complete(String query, List<MediaItem> items) => _pending.remove(query)?.complete(items);

  void fail(String query, Object error) => _pending.remove(query)?.completeError(error);

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) {
    queries.add(query);
    return (_pending[query] ??= Completer<List<MediaItem>>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_FakeMediaServerClient, GlobalKey<State<SearchScreen>>)> _pumpTvSearchScreen(WidgetTester tester) async {
  TvDetectionService.debugSetAppleTVOverride(null);
  await TvDetectionService.getInstance(forceTv: true);
  TvDetectionService.setForceTVSync(true);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final client = _FakeMediaServerClient(
    items: [
      MediaItem(
        id: 'movie_1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Movie 1',
        serverId: 'server_1',
        serverName: 'Server',
      ),
    ],
  );
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final provider = MultiServerProvider(manager, DataAggregationService(manager));
  addTearDown(provider.dispose);
  final hiddenLibraries = HiddenLibrariesProvider();
  addTearDown(hiddenLibraries.dispose);

  final key = GlobalKey<State<SearchScreen>>();
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: SearchScreen(key: key),
        ),
      ),
    ),
  );
  return (client, key);
}

Finder _keyboardDoneKey() {
  return find.descendant(
    of: find.byKey(const Key('tv_virtual_keyboard_panel')),
    matching: find.byIcon(Icons.search_rounded),
  );
}

/// Captures the last pushed route without ever letting the test frame build
/// it — see the collection-activation test above for why.
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
  }
}

class _FakeMediaServerClient implements MediaServerClient, PersonSearchClient {
  final List<MediaItem> items;
  final List<MediaItem> people;
  final List<String> queries = [];
  final String _serverId;
  final String _serverName;
  // Keyed by item id. A missing entry degrades that item to guid-only
  // evidence (search_projection.dart's own documented failure mode) rather
  // than crashing the test — same contract `_fetchExternalIds` relies on in
  // production.
  final Map<String, ExternalIds> externalIdsByItemId;

  _FakeMediaServerClient({
    required this.items,
    this.people = const [],
    String serverId = 'server_1',
    String serverName = 'Server',
    this.externalIdsByItemId = const {},
  }) : _serverId = serverId,
       _serverName = serverName;

  @override
  ServerId get serverId => ServerId(_serverId);

  @override
  String? get serverName => _serverName;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async {
    queries.add(query);
    return items;
  }

  @override
  Future<List<MediaItem>> searchPeople(String query, {int limit = 100}) async => people;

  // ActorMediaScreen's own data need (I4/SRCH-2 activation coverage below):
  // an empty page is enough to mount without a real backend.
  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(items: const [], totalCount: 0, offset: 0);

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => externalIdsByItemId[itemId] ?? const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
