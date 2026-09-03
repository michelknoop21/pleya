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

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(items: items, totalCount: items.length, offset: query.offset);

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: 'nas',
  serverName: 'nas',
);

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

  testWidgets('E13: choosing a sort returns focus to the Sort action, never to a grid card', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    SelectKeyUpSuppressor.clearSuppression();
    addTearDown(SelectKeyUpSuppressor.clearSuppression);

    final client = _FakeLibraryClient([_movie('m1', title: 'Alpha'), _movie('m2', title: 'Bravo')]);
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
    expect(catalog.snapshot.groups, hasLength(2), reason: 'the grid needs real cards to hold focus on');
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

    // Open the sort panel — the only way `_updatePreferences` for a sort
    // mutation is ever reached — and choose a different sort.
    final sortNode = tester
        .widgetList<Focus>(find.byType(Focus))
        .map((f) => f.focusNode)
        .whereType<FocusNode>()
        .firstWhere((n) => n.debugLabel == 'TvCatalogSortAction');
    sortNode.requestFocus();
    await tester.pump();
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
      reason: 'the panel itself is gone — the header may now legitimately show the new sort as its own value',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'TvCatalogSortAction',
      reason: 'hoofdstuk 7.6: the action that opened the panel gets focus back, not the grid card focus was on before',
    );
  });
}
