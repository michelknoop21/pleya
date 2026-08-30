import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/screens/tv/tv_unified_activation.dart';
import 'package:pleya/screens/tv/tv_unified_catalog_screen.dart';
import 'package:pleya/screens/tv/tv_media_source_picker_route.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/library_header_bar.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
import 'package:pleya/widgets/tv/tv_media_source_picker.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/tv_catalog_artwork.dart';
import '../test_helpers/tv_catalog_fixtures.dart';
import '../test_helpers/prefs.dart';

/// Visual acceptance for the Films page's **non-default** states
/// (docs/tvos-unified-experience.md hoofdstuk 10.7, 28, 29, plus fase 4's
/// hoofdstuk 14 seen from the catalog).
///
/// `tv_unified_catalog_golden_test.dart` next door pictures a page that has
/// content: the grid, the focus ring, the header, the panels. It never shows
/// the four moments where the page has *nothing to draw yet* — the first frame,
/// the page fetching a second page underneath the user, a filter that matched
/// nothing, and a catalog no server answered — nor the fase-4 picker arriving
/// over that page. Those are the frames a user actually meets on a cold Apple
/// TV in a house with one server switched off, and they are exactly the frames
/// that rot unseen, because nothing else in the suite renders them.
///
/// ## Why three of these pump the real screen
///
/// The loading, filter-empty and error states are drawn by
/// `TvUnifiedCatalogScreen`'s own private `_EmptyState` and its
/// `CircularProgressIndicator`, chosen by a five-branch method in `_buildBody`.
/// A hand-built stand-in would render a spinner and a centred paragraph that
/// look right and prove nothing — least of all which branch a real provider
/// state lands in. So they are driven the long way: real providers, real
/// preference store, and a fake [MediaServerClient] that hangs, answers empty
/// or throws. What the picture then shows is genuinely the branch the screen
/// picked.
///
/// The two states that *do* have content — a grid paging, and the picker over a
/// grid — are composed the way the neighbouring file composes [_page], because
/// there the composition is entirely in the header and the grid, and pumping a
/// live merge would only add a network fake to the picture.
///
/// Artwork is absent for the same reason as next door: `OptimizedMediaImage`
/// needs a live client to sign a URL, and a golden that depended on a network
/// image would be a golden about the network.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_unified_catalog_states_golden_test.dart`

// ---------------------------------------------------------------------------
// Fixtures — private to this file on purpose; shared catalog fixtures are Main's
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// A server that behaves the way one state needs it to
// ---------------------------------------------------------------------------

/// How the one fake library answers a page request.
enum _ServerBehaviour {
  /// Never completes — the honest shape of a first load in flight, and the only
  /// way to hold `isInitialLoading` still long enough to photograph it.
  hang,

  /// Answers immediately with nothing, which is what a filter that matched
  /// nothing looks like from the merge's side.
  empty,

  /// Throws, so every cursor carries a `lastError` and the snapshot reports
  /// `initialLoadFailed` — the only input that reaches `_buildBody`'s
  /// full-error branch.
  fail,
}

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, this.behaviour);

  final String id;
  final _ServerBehaviour behaviour;

  /// Every page request left hanging, so [drain] can end them.
  final List<Completer<LibraryPage<MediaItem>>> pending = [];

  /// Answers everything still outstanding.
  ///
  /// Not optional politeness: `UnifiedCatalogService` wraps each page fetch in
  /// `.timeout(...)`, which arms a real `Timer`. Leave the fetch hanging past
  /// the end of the test and the binding fails the test with "A Timer is still
  /// pending" — a harness fault reported as a widget fault. Completing the
  /// source future cancels the timeout timer, so the loading golden is captured
  /// first and the fetch is let go afterwards.
  void drain() {
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.complete(const LibraryPage<MediaItem>(items: [], totalCount: 0, offset: 0));
      }
    }
    pending.clear();
  }

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) {
    switch (behaviour) {
      case _ServerBehaviour.hang:
        // A Completer rather than a long Duration: the point is a frame with
        // the fetch genuinely outstanding, not a slow one. See [drain] for the
        // other half of this.
        final completer = Completer<LibraryPage<MediaItem>>();
        pending.add(completer);
        return completer.future;
      case _ServerBehaviour.empty:
        return Future.value(const LibraryPage<MediaItem>(items: [], totalCount: 0, offset: 0));
      case _ServerBehaviour.fail:
        return Future.error(StateError('server unreachable'));
    }
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Everything the real screen needs behind it, torn down together.
class _ScreenHarness {
  _ScreenHarness(_ServerBehaviour behaviour) : client = _FakeLibraryClient('nas', behaviour) {
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films 4K',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'NAS',
        ),
      ]);
    hiddenLibraries = HiddenLibrariesProvider();
    catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
  }

  final _FakeLibraryClient client;
  late final MultiServerManager manager;
  late final MultiServerProvider multiServer;
  late final LibrariesProvider libraries;
  late final HiddenLibrariesProvider hiddenLibraries;
  late final UnifiedCatalogProvider catalog;

  void dispose() {
    client.drain();
    catalog.dispose();
    hiddenLibraries.dispose();
    libraries.dispose();
    multiServer.dispose();
  }
}

// ---------------------------------------------------------------------------
// Shells
// ---------------------------------------------------------------------------

/// The production shell: `InputModeTracker` (which is what makes TV default to
/// keyboard mode, and therefore what makes the focus ring paint at all) and
/// `OverlaySheetHost` — the same host `MainScreen` mounts, so a panel's scrim,
/// centring and constraints in the image are the real ones.
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

/// The same shell with the one provider `TvUnifiedCatalogScreen` reads from the
/// tree, so the screen is pumped exactly as the profile subtree mounts it.
Widget _screenShell(_ScreenHarness harness) => ChangeNotifierProvider<MultiServerProvider>.value(
  value: harness.multiServer,
  child: _shell(TvUnifiedCatalogScreen(catalog: harness.catalog, title: t.unifiedCatalog.moviesTitle)),
);

/// Header plus grid, exactly as `TvUnifiedCatalogScreen` composes them, for the
/// two states whose picture is entirely about content.
Widget _page({
  required List<UnifiedMediaGroup> groups,
  required List<FocusNode> actionNodes,
  required ValueChanged<UnifiedMediaGroup> onActivate,
  bool isLoadingMore = false,
  ScrollController? controller,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    TvCatalogHeaderBar(
      title: t.unifiedCatalog.moviesTitle,
      actions: [
        TvCatalogHeaderAction(
          icon: Symbols.dns_rounded,
          action: LibraryHeaderAction(label: t.unifiedCatalog.allSources, focusNode: actionNodes[0], onPressed: () {}),
        ),
        TvCatalogHeaderAction(
          icon: Symbols.filter_list_rounded,
          action: LibraryHeaderAction(
            label: t.unifiedCatalog.filters.title,
            focusNode: actionNodes[1],
            onPressed: () {},
          ),
        ),
        TvCatalogHeaderAction(
          icon: Symbols.swap_vert_rounded,
          action: LibraryHeaderAction(
            label: t.unifiedCatalog.sort.title,
            value: sortLabel(UnifiedCatalogSort.titleAsc),
            focusNode: actionNodes[2],
            onPressed: () {},
          ),
        ),
      ],
    ),
    Expanded(
      child: TvUnifiedMediaGrid(
        controller: controller,
        groups: groups,
        onActivate: onActivate,
        hasMore: true,
        isLoadingMore: isLoadingMore,
        onLoadMore: () {},
        footer: TvUnifiedGridFooter(
          loadedCount: groups.length,
          isComplete: false,
          isLoadingMore: isLoadingMore,
          failedLibraryCount: 0,
        ),
      ),
    ),
  ],
);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
    TvGoldenArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvGoldenArtwork.remove();
  });

  setUp(() async {
    // The three store-backed screens all read `UnifiedCatalogQueryStore`
    // before their first fetch, and the picker reads two more stores. Leaving
    // them on whatever the previous test wrote would make the goldens depend on
    // execution order.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    // Both, and both awaited here in the real zone. `initializeInstance`
    // publishes the singleton *before* awaiting its cache, so a second call
    // that arrives while the first is still in flight gets an instance whose
    // `_cache` is not assigned yet and throws `LateInitializationError`. Inside
    // `testWidgets` the first call is exactly that: it starts under fake async
    // and cannot finish without a pump, so every store read the screen makes
    // during its first frames would race it. Warming both up front removes the
    // race rather than papering over the exception the stores swallow.
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  List<FocusNode> nodes(WidgetTester tester) {
    final list = [for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'action$i')];
    addTearDown(() {
      for (final node in list) {
        node.dispose();
      }
    });
    return list;
  }

  _ScreenHarness harnessFor(_ServerBehaviour behaviour) {
    final harness = _ScreenHarness(behaviour);
    addTearDown(harness.dispose);
    return harness;
  }

  // Hoofdstuk 29's first state, and the one nobody looks at twice: the cold
  // open, before any library has answered. The header is already there —
  // hoofdstuk 7.4's traversal exists from the first frame — and only the body
  // is waiting.
  testWidgets('films, initial load', (tester) async {
    setGoldenSurfaceSize(tester);
    final harness = harnessFor(_ServerBehaviour.hang);
    await tester.pumpWidget(_screenShell(harness));

    // A fixed pump schedule instead of `pumpAndSettle`: the indicator never
    // settles, and a golden of an animation needs the same elapsed time on
    // every run. Ten frames is comfortably past the preference read and the
    // merge start, both of which resolve on the microtask queue.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(harness.catalog.isInitialLoading, isTrue);
    expect(harness.catalog.snapshot.groups, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_state_loading');

    // The picture is taken; let the fetch go so its timeout timer is cancelled
    // before the binding checks for pending timers.
    harness.client.drain();
    await tester.pumpAndSettle();
  });

  // Hoofdstuk 28: paging must not reflow, and hoofdstuk 10.7 puts the state of
  // the fetch in the footer rather than over the grid.
  //
  // Scrolled to the bottom, which the state requires and no existing golden
  // does: paging is asked for by DOWN on the *last* row, so the top of the grid
  // is precisely where a user never is when this state exists — and the footer
  // that carries the whole state does not fit on a 584pt canvas from the top.
  testWidgets('films, fetching the next page', (tester) async {
    setGoldenSurfaceSize(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _shell(
        _page(
          groups: tvGoldenCatalog(),
          actionNodes: nodes(tester),
          onActivate: (_) {},
          isLoadingMore: true,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.text(t.unifiedCatalog.loadingMore), findsOneWidget);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_state_loading_more');
  });

  // Hoofdstuk 29 splits "no results" in two, and this is the half with a way
  // out: the filters are the user's own doing, so the state names them and
  // offers to clear them. The Filters badge in the header is the other half of
  // the same sentence, which is why the stored selection is real rather than
  // faked into the body.
  testWidgets('films, filters matched nothing', (tester) async {
    setGoldenSurfaceSize(tester);
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched)),
    );
    final harness = harnessFor(_ServerBehaviour.empty);
    await tester.pumpWidget(_screenShell(harness));
    await tester.pumpAndSettle();

    expect(harness.catalog.snapshot.groups, isEmpty);
    expect(find.text(t.unifiedCatalog.states.filterEmptyTitle), findsOneWidget);
    expect(find.text(t.unifiedCatalog.states.clearFilters), findsOneWidget);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_state_filter_empty');
  });

  // The other half of hoofdstuk 29: nothing loaded and the load failed. Not a
  // banner over content — there is no content — and the retry carries the focus
  // because it is the only thing on the page to operate.
  testWidgets('films, nothing answered', (tester) async {
    setGoldenSurfaceSize(tester);
    final harness = harnessFor(_ServerBehaviour.fail);
    await tester.pumpWidget(_screenShell(harness));
    await tester.pumpAndSettle();

    expect(harness.catalog.snapshot.initialLoadFailed, isTrue);
    expect(find.text(t.unifiedCatalog.states.errorTitle), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_state_error');
  });

  // Where fase 4 and fase 5 actually meet, and the one composition neither
  // file pictured: the picker of hoofdstuk 14 arriving over the grid of
  // hoofdstuk 10. The two surfaces were designed apart and are judged together
  // here — the scrim against a real poster grid rather than against flat black,
  // and the panel's proportion against the card rhythm behind it.
  //
  // Driven through the real `activateUnifiedMediaGroup` on a real Select press,
  // so the panel on screen is the one the coordinator decided to open (a
  // multi-source group, no preferred server, both sources online) rather than a
  // picker a test opened by hand.
  testWidgets('films, source picker over the grid', (tester) async {
    setGoldenSurfaceSize(tester);
    final groups = tvGoldenCatalog();
    // Two online sources on the focused title, and no preferred server stored,
    // which is precisely `ShowSourcePicker`'s territory (hoofdstuk 14.6: one
    // usable source is not a question, so it is not asked).
    final multiSource = groups.first;
    expect(multiSource.sources.length, greaterThan(1));

    await tester.pumpWidget(
      _shell(
        Builder(
          builder: (context) => _page(
            groups: groups,
            actionNodes: nodes(tester),
            onActivate: (group) => activateUnifiedMediaGroup(
              context,
              group: group,
              intent: UnifiedActivationIntent.details,
              environment: buildUnifiedActivationEnvironment(
                group: group,
                health: unifiedServerHealth(isOnline: (_) => true, authErrorServerIds: const {}),
                catalogServerIds: const {'nas', 'attic'},
                availabilityRevision: ValueNotifier<int>(0),
                // Left out deliberately: with a resolver the panel opens in its
                // "checking more sources" state, and that frame is already
                // pictured in tv_source_picker_resolving.png. This one is about
                // the settled panel over the grid.
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Focus.of(tester.element(find.text(multiSource.representativeSource.item.displayTitle))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byType(TvMediaSourcePicker), findsOneWidget);
    await expectMatchesGolden(find.byType(MaterialApp), 'tv_catalog_state_source_picker');
  });
}
