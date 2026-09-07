/// E13: hoofdstuk 7.6's "filter- of sorteermutatie → grid naar boven, focus
/// blijft op de actie totdat nieuwe data gereed is" — proven over the real
/// screen, not just read off `_updatePreferences`'s source.
///
/// **Why this closes E13 rather than reproducing it.** The edge case asks
/// what happens when a filter/sort mutation removes the group that currently
/// holds the grid's focus. On this screen that state is unreachable by
/// construction: every path that can call `_updatePreferences` — the sort
/// panel's own choice, the filter panel's Apply, the "Wis filters" empty-state
/// action — starts from a header action or an empty-state button, never from
/// a grid card, so grid focus is never the thing a mutation is applied while
/// holding. What *is* real and worth a regression is the guarantee the
/// library doc names instead: the action that opened the panel gets focus
/// back, not the grid, and the scroll resets. That is what this test drives
/// end to end, through the real `TvUnifiedCatalogScreen`/`UnifiedCatalogProvider`
/// pair rather than the header+grid composition
/// `tv_unified_catalog_golden_test.dart` builds for its pictures.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/screens/tv/tv_unified_catalog_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.items);

  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'nas';

  @override
  MediaBackend get backend => MediaBackend.plex;

  /// Honours `sort`, `offset` and `limit`, which is the whole point of the
  /// fixture for E13: a fake that ignores the query returns the same page one
  /// whatever the viewer sorts by, and then nothing ever leaves the grid.
  /// On a real library a sort change re-pages, so page one holds different
  /// titles afterwards, which is the condition CAT17 lives in.
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final ordered = [...items];
    ordered.sort(switch (query.sort?.field) {
      'addedAt' => (a, b) => (a.addedAt ?? 0).compareTo(b.addedAt ?? 0),
      _ => (a, b) => (a.title ?? '').compareTo(b.title ?? ''),
    });
    if (query.sort?.direction == LibrarySortDirection.descending) {
      final reversed = ordered.reversed.toList();
      ordered
        ..clear()
        ..addAll(reversed);
    }
    return LibraryPage<MediaItem>(
      items: ordered.skip(query.offset).take(query.limit).toList(),
      totalCount: ordered.length,
      offset: query.offset,
    );
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title, int? addedAt}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  addedAt: addedAt,
  serverId: 'nas',
  serverName: 'nas',
);

/// One page worth of titles plus one, with the alphabet and the added-at order
/// deliberately opposite: sorted by title page one is T00..T49, sorted by
/// recently-added it is T50..T01. The card the viewer was standing on before
/// opening the rail is therefore off page one after the sort, which is what
/// makes the grid drop its node.
const int _catalogPageSize = 50;

List<MediaItem> _oppositelyOrderedMovies() => [
  for (var i = 0; i <= _catalogPageSize; i++) _movie('m$i', title: 'T${i.toString().padLeft(2, '0')}', addedAt: i),
];

Widget _shell(Widget child) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: InputModeTracker(
        child: OverlaySheetHost(
          child: Scaffold(backgroundColor: theme.extension<MonoTokens>()!.bg, body: child),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('E13: choosing a sort returns focus to the Sortering row of the rail, never to a grid card', (
    tester,
  ) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    SelectKeyUpSuppressor.clearSuppression();
    addTearDown(SelectKeyUpSuppressor.clearSuppression);

    final client = _FakeLibraryClient(_oppositelyOrderedMovies());
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'nas',
        ),
      ]);
    final hiddenLibraries = HiddenLibrariesProvider();
    final catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
    addTearDown(catalog.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    await catalog.ensureStarted();
    expect(
      catalog.snapshot.groups.length,
      lessThan(client.items.length),
      reason: 'page one is a subset of the library, so the sort below really changes which titles are on it',
    );
    final firstGroupId = catalog.snapshot.groups.first.groupId;

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: _shell(TvUnifiedCatalogScreen(catalog: catalog, title: t.unifiedCatalog.moviesTitle)),
      ),
    );
    await tester.pumpAndSettle();

    // Put focus on a grid card first, matching a viewer who has been
    // browsing — not the header — before ever touching a panel.
    final cardNode = tester
        .widgetList<Focus>(find.byType(Focus))
        .map((f) => f.focusNode)
        .whereType<FocusNode>()
        .firstWhere((n) => n.debugLabel == 'TvUnifiedCard($firstGroupId)');
    cardNode.requestFocus();
    await tester.pump();
    expect(cardNode.hasPrimaryFocus, isTrue);

    // LEFT off column 0 opens CAT5's rail, and two DOWNs reach Sortering,
    // the route a viewer actually takes, rather than a poked focus node.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCatalogRailSort');

    SelectKeyUpSuppressor.clearSuppression();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text(sortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget, reason: 'the sort panel is open');

    final optionFocus = Focus.maybeOf(
      tester.element(find.text(sortLabel(UnifiedCatalogSort.recentlyAdded))),
      scopeOk: true,
    )!;
    optionFocus.requestFocus();
    await tester.pump();
    SelectKeyUpSuppressor.clearSuppression();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(
      find.byType(TvCatalogSortPanel),
      findsNothing,
      reason: 'the panel itself is gone, so the rail may now legitimately show the new sort as its own value',
    );
    expect(
      catalog.snapshot.groups.map((g) => g.groupId),
      isNot(contains(firstGroupId)),
      reason: 'CAT17: the card the viewer stood on before opening the rail has left page one',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TvCatalogRailSort',
      reason: 'hoofdstuk 7.6: the row that opened the panel gets focus back, not the grid card focus was on before',
    );
  });

  testWidgets('CAT14: a catalog with nothing in it still has one thing the remote can stand on', (tester) async {
    // `TvCatalogEmptyState` draws only its button, so a state without an action
    // has no focusable widget at all. Alle films on a server with no films then
    // stood as a page that could neither be moved within nor left — and on
    // tvOS that is terminal, because the engine claims every press before
    // UIKit's responder chain sees it. The error state and the filtered-empty
    // state always carried an action; this third one did not.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final client = _FakeLibraryClient(const []);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'nas',
        ),
      ]);
    final hiddenLibraries = HiddenLibrariesProvider();
    final catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
    addTearDown(catalog.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    await catalog.ensureStarted();
    expect(catalog.snapshot.groups, isEmpty, reason: 'this is the plain-empty state, not the filtered one');
    expect(catalog.loadFailed, isFalse, reason: 'and not the error one either');

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: _shell(TvUnifiedCatalogScreen(catalog: catalog, title: t.unifiedCatalog.moviesTitle)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.unifiedCatalog.states.emptyTitle), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TvCatalogStateAction',
      reason: 'the one action autofocuses, so the page opens with something focused rather than with nothing',
    );

    // And it is the way into the rail, which is the only place a viewer can do
    // anything about an empty catalog — unhide a source, drop a filter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('TvCatalogRail'));
  });
}
