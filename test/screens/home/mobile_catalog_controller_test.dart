/// The catalogue screen's view-settings layer: stored preferences, backend
/// capabilities, and the order in which the two become a query. iOS Unified
/// 2026 fase 3.
///
/// Runs against a real `UnifiedCatalogProvider` over fake clients rather than
/// a stubbed one, because the thing worth pinning here is the *interaction*:
/// a source restriction changes which backends take part, which changes which
/// filters may be applied. A stub would let that ordering pass whether or not
/// it holds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_filter_result.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_filter.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/screens/home/mobile_catalog_controller.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

import '../../test_helpers/prefs.dart';

class _FakeClient implements MediaServerClient {
  _FakeClient(this.id, {required this.backend, this.itemsByLibrary = const {}});

  final String id;
  @override
  final MediaBackend backend;
  final Map<String, List<MediaItem>> itemsByLibrary;

  /// Every query this client was asked to run, so a test can assert that a
  /// filter the backends cannot execute never reached the wire.
  final List<LibraryQuery> queries = [];

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  ServerCapabilities get capabilities =>
      backend == MediaBackend.plex ? ServerCapabilities.plex : ServerCapabilities.jellyfin;

  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    queries.add(query);
    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  /// Jellyfin's shape: categories and their values in one answer, which is the
  /// branch `loadUnifiedFilterOptions` takes when `cachedValues` is populated.
  List<String> genres = const [];

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult(
    filters: const [],
    cachedValues: {
      'genre': [for (final genre in genres) MediaFilterValue(key: genre, title: genre)],
    },
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title, required String serverId}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: serverId);

MediaLibrary _library(String id, {required String serverId, MediaBackend backend = MediaBackend.plex}) =>
    MediaLibrary(id: id, backend: backend, title: id, kind: MediaKind.movie, serverId: serverId, serverName: serverId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeClient plex;
  late _FakeClient pleyaServer;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late UnifiedCatalogProvider catalog;
  late MobileCatalogController controller;

  /// Both servers eligible: a Plex one that executes every filter, and a Pleya
  /// Server one that executes none. That mix is the whole point — it is the
  /// case `unifiedFilterCapabilitiesFor` exists for.
  void buildWith({required List<MediaLibrary> eligible}) {
    libraries = LibrariesProvider()..debugSetLibraries(eligible);
    catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      kind: MediaKind.movie,
    );
    controller = MobileCatalogController(catalog: catalog, kind: MediaKind.movie, clientFor: manager.getClient);
  }

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    plex = _FakeClient(
      'plex',
      backend: MediaBackend.plex,
      itemsByLibrary: {
        'films': [_movie('p1', title: 'Alien', serverId: 'plex')],
      },
    );
    pleyaServer = _FakeClient(
      'pleya',
      backend: MediaBackend.pleyaServer,
      itemsByLibrary: {
        'films': [_movie('s1', title: 'Dune', serverId: 'pleya')],
      },
    );
    manager = MultiServerManager()
      ..debugRegisterClientForTesting(plex)
      ..debugRegisterClientForTesting(pleyaServer);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    hiddenLibraries = HiddenLibrariesProvider();
  });

  tearDown(() {
    controller.dispose();
    catalog.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  test('start reads the stored setup and hands the merge a query', () async {
    buildWith(eligible: [_library('films', serverId: 'plex')]);
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(
        sort: UnifiedCatalogSort.recentlyAdded,
        filters: UnifiedCatalogFilterSelection(genres: {'Drama'}),
      ),
    );

    expect(controller.isReady, isFalse);
    await controller.start();

    expect(controller.isReady, isTrue);
    expect(controller.sort, UnifiedCatalogSort.recentlyAdded);
    expect(controller.selection.genres, {'Drama'});
    expect(catalog.query.sortField, UnifiedCatalogSortField.addedAt);
    expect(catalog.query.genres, ['Drama']);
  });

  test('a Pleya Server library in the mix suppresses the genre filter without deleting the choice', () async {
    buildWith(
      eligible: [
        _library('films', serverId: 'plex'),
        _library('films', serverId: 'pleya', backend: .pleyaServer),
      ],
    );
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(genres: {'Drama'})),
    );
    await controller.start();

    // Not executable, so it never reaches the query — a genre filter with a
    // Pleya Server library in the mix would return that server's items
    // unfiltered and present them as matches.
    expect(controller.capabilities.supportsMetadataFilters, isFalse);
    expect(catalog.query.genres, isNull);
    expect(plex.queries.single.genres, isNull);
    // Kept, though: the panel still ticks it, and narrowing the sources is
    // what gets it back.
    expect(controller.selection.genres, {'Drama'});
    expect(controller.activeFilterCount, 0);
  });

  test('excluding the backend that cannot filter brings the filter back', () async {
    buildWith(
      eligible: [
        _library('films', serverId: 'plex'),
        _library('films', serverId: 'pleya', backend: .pleyaServer),
      ],
    );
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(genres: {'Drama'})),
    );
    await controller.start();
    expect(catalog.query.genres, isNull);

    // This is the ordering the controller's doc describes: the restriction
    // decides the participants, the participants decide the capabilities, and
    // only then is the query built. Reverse those and this stays null.
    await controller.setFilters(const UnifiedCatalogFilterSelection(genres: {'Drama'}, serverIds: {'plex'}));

    expect(controller.capabilities.supportsMetadataFilters, isTrue);
    expect(catalog.query.genres, ['Drama']);
    expect(controller.activeFilterCount, 2, reason: 'genre and the source restriction');
  });

  test('a stored server that no longer exists is pruned and written back', () async {
    buildWith(eligible: [_library('films', serverId: 'plex')]);
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(serverIds: {'plex', 'retired'})),
    );
    await controller.start();

    // A key naming a server that is gone has no row left in the panel to
    // untick it with, so it may not survive the open (hoofdstuk 10.6).
    expect(controller.selection.serverIds, {'plex'});
    await pumpEventQueue();
    expect((await UnifiedCatalogQueryStore.read(MediaKind.movie)).filters.serverIds, {'plex'});
  });

  test('an empty catalogue prunes nothing — a cold offline start keeps the selection', () async {
    buildWith(eligible: const []);
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(serverIds: {'plex'})),
    );
    await controller.start();

    expect(controller.selection.serverIds, {'plex'}, reason: 'no server has connected yet, that is not a choice');
  });

  test('the sources control counts libraries, and reads null while unrestricted', () async {
    buildWith(
      eligible: [
        _library('films', serverId: 'plex'),
        _library('kids', serverId: 'plex'),
      ],
    );
    await controller.start();
    expect(controller.restrictedSourceCount, isNull);

    await controller.setFilters(const UnifiedCatalogFilterSelection(libraryKeys: {'plex:films'}));
    expect(controller.restrictedSourceCount, 1);
  });

  test('setSort persists and restarts, and re-picking the same sort does neither', () async {
    buildWith(eligible: [_library('films', serverId: 'plex')]);
    await controller.start();
    final after = plex.queries.length;

    await controller.setSort(UnifiedCatalogSort.titleAsc);
    expect(plex.queries.length, after, reason: 'no restart, so the grid does not jump to the top');

    await controller.setSort(UnifiedCatalogSort.titleDesc);
    expect(plex.queries.length, greaterThan(after));
    await pumpEventQueue();
    expect((await UnifiedCatalogQueryStore.read(MediaKind.movie)).sort, UnifiedCatalogSort.titleDesc);
  });

  test('a source restriction leaves the excluded server unasked, rather than filtering after the fact', () async {
    buildWith(
      eligible: [
        _library('films', serverId: 'plex'),
        _library('films', serverId: 'pleya', backend: .pleyaServer),
      ],
    );
    await controller.start();
    expect(pleyaServer.queries, isNotEmpty);

    final before = pleyaServer.queries.length;
    await controller.setFilters(const UnifiedCatalogFilterSelection(serverIds: {'plex'}));

    expect(pleyaServer.queries.length, before, reason: 'an excluded server is never asked at all');
    expect(catalog.snapshot.groups.map((g) => g.representativeSource.item.title), ['Alien']);
  });

  test('clearFilters empties the selection and restarts', () async {
    buildWith(eligible: [_library('films', serverId: 'plex')]);
    await controller.start();
    await controller.setFilters(const UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched));
    expect(catalog.query.includeWatched, isFalse);

    await controller.clearFilters();
    expect(controller.selection, UnifiedCatalogFilterSelection.empty);
    expect(catalog.query.includeWatched, isTrue);
  });

  test('the filter values are the union of what the participating libraries report', () async {
    plex.genres = ['Drama', 'Thriller'];
    pleyaServer.genres = ['Comedy'];
    buildWith(
      eligible: [
        _library('films', serverId: 'plex'),
        _library('films', serverId: 'pleya', backend: .pleyaServer),
      ],
    );
    await controller.start();
    await pumpEventQueue();

    // Union, not intersection: a genre that exists on one server is a real
    // genre, and offering only what every server agrees on would hide most of
    // them the moment a second server appears.
    expect(controller.options.genres, ['Comedy', 'Drama', 'Thriller']);
  });

  test('narrowing the sources reloads the values, so a gone server\'s genres go with it', () async {
    plex.genres = ['Drama'];
    pleyaServer.genres = ['Comedy'];
    buildWith(
      eligible: [
        _library('films', serverId: 'plex'),
        _library('films', serverId: 'pleya', backend: .pleyaServer),
      ],
    );
    await controller.start();
    await pumpEventQueue();
    expect(controller.options.genres, ['Comedy', 'Drama']);

    await controller.setFilters(const UnifiedCatalogFilterSelection(serverIds: {'plex'}));
    await pumpEventQueue();
    expect(controller.options.genres, ['Drama']);
  });
}
