import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/search_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_expandable_media_tile.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

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
    // TV renders unified discovery rails now (fase 6, hoofdstuk 16.1/16.2):
    // "the first result" is the first tile of the first rail, not a
    // source-concrete card, so its debug label carries the rail's own
    // per-group prefix instead of the non-TV list's fixed 'SearchFirstResult'.
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('tvDiscoveryTile_'));
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
    // TV renders unified discovery rails now (fase 6, hoofdstuk 16.1/16.2):
    // "the first result" is the first tile of the first rail, not a
    // source-concrete card, so its debug label carries the rail's own
    // per-group prefix instead of the non-TV list's fixed 'SearchFirstResult'.
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('tvDiscoveryTile_'));
  });

  testWidgets('TV history chips are focusable and run their query on select', (tester) async {
    SettingsService.instance.write(SettingsService.searchHistory, ['star wars']);
    final (client, _) = await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();

    // The default TV landing state (history exists, nothing searched yet).
    expect(find.text('star wars'), findsOneWidget);

    // D-pad down from the keyboard panel until the history chip has focus.
    var reachedChip = false;
    for (var i = 0; i < 12 && !reachedChip; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      reachedChip = FocusManager.instance.primaryFocus?.debugLabel == 'filter_chip_star wars';
    }
    expect(reachedChip, isTrue, reason: 'history chip must be reachable by D-pad');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(client.queries, ['star wars']);
    expect(find.text('Movie 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV clear-history keeps focus alive by returning it to the input', (tester) async {
    SettingsService.instance.write(SettingsService.searchHistory, ['star wars']);
    final (_, key) = await _pumpTvSearchScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.search.clearHistory).last);
    await tester.pumpAndSettle();

    expect(find.text('star wars'), findsNothing);
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
    // TV renders unified discovery rails now (fase 6, hoofdstuk 16.1/16.2):
    // "the first result" is the first tile of the first rail, not a
    // source-concrete card, so its debug label carries the rail's own
    // per-group prefix instead of the non-TV list's fixed 'SearchFirstResult'.
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('tvDiscoveryTile_'));

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

    // One rail (Films), one tile, carrying both sources — not two rows for
    // one title.
    expect(find.byType(TvDiscoveryRail), findsOneWidget);
    expect(find.byType(TvSourceCountBadge), findsOneWidget);
    expect(find.descendant(of: find.byType(TvSourceCountBadge), matching: find.text('2')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('LAND4: TV Search stacks rails, so a vertical step keeps its column', () {
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

    String? focusedTile() {
      final label = FocusManager.instance.primaryFocus?.debugLabel;
      const prefix = 'tvDiscoveryTile_';
      return label != null && label.startsWith(prefix) ? label.substring(prefix.length) : null;
    }

    Future<List<TvDiscoveryRailState>> pumpResults(WidgetTester tester) async {
      TvDetectionService.debugSetAppleTVOverride(null);
      await TvDetectionService.getInstance(forceTv: true);
      TvDetectionService.setForceTVSync(true);
      tester.view.devicePixelRatio = 1.0;
      // Taller than the usual TV fixture on purpose: two result rails have to
      // be laid out at once for a step between them to mean anything, and a
      // sliver below the viewport is never built.
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
      return tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).toList();
    }

    testWidgets('DOWN from the Films rail lands on the same column of the Series rail', (tester) async {
      final rails = await pumpResults(tester);
      expect(rails, hasLength(2), reason: 'sanity: a Films rail and a Series rail');
      final films = rails.first.widget.groups;
      final series = rails.last.widget.groups;

      // The lower rail is parked far right, so geometry would answer with the
      // tile it remembers rather than the column the step came from.
      expect(rails.last.focusGroup(series.first.groupId), isTrue);
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(focusedTile(), series[6].groupId, reason: 'sanity: the Series rail is parked far right');

      expect(rails.first.focusGroup(films[2].groupId), isTrue);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedTile(), series[2].groupId);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focusedTile(), films[2].groupId, reason: 'and the round trip ends where it started');
    });

    testWidgets('Search keeps naming its results, which LAND4 does not touch', (tester) async {
      // Deliberate and load-bearing: on TV Search the caption under a rail is
      // the only place a result's title appears, so it is a label rather than a
      // projection of where the remote is. Gating it on focus would hand the
      // viewer a page of unnamed artwork. LAND4 changes who decides a vertical
      // step, and nothing about who may describe a tile — see
      // [TvDiscoveryRail.alwaysDescribesCurrent] and the SEARCH1 row in
      // docs/tvos-fysieke-correctieronde.md.
      final rails = await pumpResults(tester);

      expect(
        rails.map((rail) => rail.widget.alwaysDescribesCurrent),
        everyElement(isTrue),
        reason: 'every result rail names its current result, focus or no focus',
      );
      // And it is really on screen with the focus nowhere near it.
      expect(rails.first.focusGroup(rails.first.widget.groups.first.groupId), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Serie 0'), findsWidgets, reason: 'the Series rail is named while the focus is in Films');
    });
  });

  testWidgets('non-TV search stays source-concrete for the same multi-server match', (tester) async {
    // Same fixture as the TV dedup test above, pumped through the ordinary
    // (non-TV) SearchScreen: mobile/desktop must keep showing one card per
    // server, unchanged by the TV projection this fase adds.
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

    expect(find.byType(TvDiscoveryRail), findsNothing);
    expect(find.text('Dune'), findsNWidgets(2));
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

class _FakeMediaServerClient implements MediaServerClient {
  final List<MediaItem> items;
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
  Future<ExternalIds> fetchExternalIds(String itemId) async => externalIdsByItemId[itemId] ?? const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
