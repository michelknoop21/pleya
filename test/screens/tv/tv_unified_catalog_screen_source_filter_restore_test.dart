/// CAT20: a source filter that names a server which merely has not finished
/// connecting yet must survive the screen's own `_restorePreferences` prune.
///
/// The cold start from log ijqxp showed G-Plexflix answering after the
/// catalog had already opened: only the faster server ('nas') had a bound
/// library at the moment the stored filter was first read. `withKnownSources`
/// only sees bound libraries, so without the registry-widened known-server
/// set the late server was pruned out of the selection and the write-back
/// made that permanent. See [pruneStoredSourceFilter].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/screens/tv/tv_unified_catalog_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
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

  testWidgets('CAT20: a server that has not bound yet is not pruned out of the stored filter', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    const stored = UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(serverIds: {'plexflix', 'nas'}));
    await UnifiedCatalogQueryStore.write(MediaKind.movie, stored);

    // Only 'nas' has a bound client/library at this point; 'plexflix'
    // answers its endpoint race later, same as log ijqxp. The profile is
    // registered for both, which is what a real cold start's
    // ActiveProfileBinder.setExpectedVisibleServerIds already records before
    // either server has finished connecting.
    final client = _FakeLibraryClient([_movie('m1', title: 'Alpha')]);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    multiServer.setExpectedVisibleServerIds({'plexflix', 'nas'});
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
    await catalog.ensureStarted();
    addTearDown(catalog.dispose);
    addTearDown(multiServer.dispose);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: _shell(TvUnifiedCatalogScreen(catalog: catalog, title: t.unifiedCatalog.moviesTitle)),
      ),
    );
    await tester.pumpAndSettle();

    final storedAfterOpen = await UnifiedCatalogQueryStore.read(MediaKind.movie);
    expect(
      storedAfterOpen.filters.serverIds,
      contains('plexflix'),
      reason: 'a server that is merely late is not a server that was removed',
    );
  });
}
