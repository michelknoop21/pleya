/// CAT20 on the mobile variant: `MobileCatalogScreen._restorePreferences`
/// carries the identical line `tv_unified_catalog_screen.dart` had, and
/// therefore the identical defect: a server that has merely not finished
/// connecting yet is pruned out of the stored source filter, and the
/// write-back makes that permanent. See
/// `tv_unified_catalog_screen_source_filter_restore_test.dart` for the full
/// reasoning and `pruneStoredSourceFilter` for the shared fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/home/mobile_catalog_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/unified_catalog/unified_artwork_prefetcher.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id);

  final String id;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => const LibraryPage<MediaItem>(items: [], totalCount: 0, offset: 0);

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CAT20: a server that has not bound yet is not pruned out of the mobile stored filter', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
    UnifiedCatalogQueryStore.resetForTesting();

    const stored = UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(serverIds: {'s2', 's1'}));
    await UnifiedCatalogQueryStore.write(MediaKind.movie, stored);

    // Only 's1' has a bound client/library at this point; 's2' answers its
    // endpoint race later. The profile is registered for both.
    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeLibraryClient('s1'));
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    multiServer.setExpectedVisibleServerIds({'s2', 's1'});
    final hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: 'A',
          backend: MediaBackend.plex,
          title: 'A',
          kind: MediaKind.movie,
          serverId: 's1',
          serverName: 's1',
        ),
      ]);
    final catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);
    addTearDown(catalogs.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          Provider<UnifiedCatalogs>.value(value: catalogs),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: MobileCatalogScreen(
              kind: MobileCatalogKind.movies,
              debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final storedAfterOpen = await UnifiedCatalogQueryStore.read(MediaKind.movie);
    expect(
      storedAfterOpen.filters.serverIds,
      contains('s2'),
      reason: 'a server that is merely late is not a server that was removed',
    );
  });
}
