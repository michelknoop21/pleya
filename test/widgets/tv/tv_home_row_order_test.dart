/// HOME-R1: the order "Home aanpassen" writes must be the order Home draws.
///
/// The panel moves a row by writing every row's layout ids into
/// `HomeLayoutProvider.order`, and Home ranks each row by its earliest id in
/// that list. That only round-trips when every id belongs to exactly one
/// panel row. Two backend hubs from one server that carry the same
/// `hubIdentifier` (Plex's per-library hubs: every movie library has its own
/// `movie.recentlyadded`) project to two separate rows with one and the same
/// layout id, and then the write and the read disagree.
///
/// Real providers throughout; only the network edge (aggregation, custom-row
/// loader) is faked.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_custom_rows_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/widgets/tv/tv_home_customize_controller.dart';
import 'package:pleya/widgets/tv/tv_home_row_assembly.dart';

import '../../test_helpers/prefs.dart';

MediaItem _film(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: 2024,
  serverId: 'nas',
  serverName: 'NAS',
);

/// A Plex section hub: the identifier is the same for every library, the hub
/// key (`id`) is not.
MediaHub _sectionHub(String section, String title, List<MediaItem> items) => MediaHub(
  id: '/hubs/sections/$section/recentlyAdded',
  identifier: 'movie.recentlyadded',
  title: title,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

MediaHub _hub(String identifier, String title, List<MediaItem> items) => MediaHub(
  id: identifier,
  identifier: identifier,
  title: title,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

class _FakeAggregation extends DataAggregationService {
  _FakeAggregation(super.serverManager);

  List<MediaHub> hubs = const [];

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: const {'nas'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubs, succeededServerIds: const {'nas'});

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: const {'nas'});
}

class _FakeClient implements MediaServerClient {
  @override
  final ServerId serverId = ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyLoader implements HomeCustomRowLoader {
  @override
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit}) async => HomeCustomRowContent.empty;
}

const _ownRow = HomeCustomRow(
  id: 'r1',
  kind: MediaKind.movie,
  name: 'Mijn rij',
  preferences: UnifiedCatalogPreferences.defaults,
);

void main() {
  late TvHomeCustomizeController controller;
  late HomeLayoutProvider layout;

  Future<void> boot(List<MediaHub> hubs) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    final aggregation = _FakeAggregation(manager)..hubs = hubs;
    final multiServer = MultiServerProvider(manager, aggregation);
    final hiddenLibraries = HiddenLibrariesProvider();
    final libraries = LibrariesProvider();
    final discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
    addTearDown(discover.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);
    await discover.load();

    final projection = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
      latestMoviesTitle: 'Recently Released',
    );
    addTearDown(projection.dispose);
    for (var i = 0; i < 200 && projection.isProjecting; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    layout = HomeLayoutProvider();
    addTearDown(layout.dispose);
    await layout.ensureInitialized();
    final customRows = HomeCustomRowsProvider(
      layout: layout,
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
      loader: _EmptyLoader(),
    );
    addTearDown(customRows.dispose);
    await layout.saveCustomRow(_ownRow);
    await customRows.refreshRow(_ownRow.id);

    controller = TvHomeCustomizeController(
      layout: layout,
      customRows: customRows,
      projection: projection,
      librariesFor: (_) => const [],
      preview: (_) async => HomeCustomRowContent.empty,
    );
  }

  List<String> panelTitles() => [for (final row in controller.orderedRows()) row.title];

  // Two section hubs on one server, one own row, one ordinary hub.
  final duplicateHubs = [
    _sectionHub('1', 'Recently Added in Films', [_film('a1', 'Dune')]),
    _sectionHub('2', 'Recently Added in Kids', [_film('b1', 'Moana')]),
    _hub('movie.toprated', 'Top Rated', [_film('c1', 'Casablanca')]),
  ];

  group('rows that share a layout id', () {
    test('the fixture really gives two panel rows one layout id', () async {
      await boot(duplicateHubs);
      final entries = controller.entries();
      expect(
        [for (final e in entries) e.row.title],
        ['Mijn rij', 'Recently Added in Films', 'Recently Added in Kids', 'Top Rated'],
      );
      expect(entries[1].layoutIds, entries[2].layoutIds);
    });

    test('an own row moved down past the shared-id rows leaves its place on every press', () async {
      await boot(duplicateHubs);

      // Every press of "move down" must change where the own row sits.
      final positions = <int>[panelTitles().indexOf('Mijn rij')];
      for (var press = 0; press < 3; press++) {
        final index = panelTitles().indexOf('Mijn rij');
        await controller.move(index, 1);
        positions.add(panelTitles().indexOf('Mijn rij'));
        if (positions.last == panelTitles().length - 1) break;
      }
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThan(positions[i - 1]), reason: 'press $i did nothing: $positions');
      }
      expect(panelTitles().last, 'Mijn rij');
    });

    test('an own row moved up past the shared-id rows leaves its place on every press', () async {
      await boot(duplicateHubs);
      // Put the own row at the bottom first.
      await layout.setOrder(['nas:movie.recentlyadded', 'nas:movie.toprated', _ownRow.layoutRowId]);
      expect(panelTitles().last, 'Mijn rij');

      final positions = <int>[panelTitles().indexOf('Mijn rij')];
      for (var press = 0; press < 3; press++) {
        final index = panelTitles().indexOf('Mijn rij');
        await controller.move(index, -1);
        positions.add(panelTitles().indexOf('Mijn rij'));
        if (positions.last == 0) break;
      }
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], lessThan(positions[i - 1]), reason: 'press $i did nothing: $positions');
      }
      expect(panelTitles().first, 'Mijn rij');
    });

    test('moving a shared-id row moves it, and the order on Home is the order in the panel', () async {
      await boot(duplicateHubs);
      final before = panelTitles();
      // "Recently Added in Films" one down.
      await controller.move(1, 1);
      final after = panelTitles();
      expect(after, isNot(before), reason: 'the press did nothing');
      // Home draws what the panel lists (minus empty/hidden rows).
      final home = [
        for (final row in tvHomeOrderableRows(
          projection: controller.projection,
          layout: layout,
          customRows: controller.customRows,
        ))
          row.title,
      ];
      expect(home, [
        for (final t in after)
          if (t != 'Mijn rij') t,
      ]);
    });
  });

  group('rows the panel could not see when the order was written', () {
    test('a row missing at move time keeps its place among the rows it was saved between', () async {
      await boot(duplicateHubs);
      await layout.setOrder(['nas:movie.toprated', _ownRow.layoutRowId, 'nas:movie.recentlyadded', 'nas:offline-row']);
      // 'nas:offline-row' is not on screen (its server is offline). Moving Top
      // Rated below the own row must not drop it from the stored order.
      await controller.move(0, 1);
      expect(layout.order, [_ownRow.layoutRowId, 'nas:movie.toprated', 'nas:movie.recentlyadded', 'nas:offline-row']);
    });

    test('a missing row in the middle stays behind the row it followed', () async {
      await boot(duplicateHubs);
      await layout.setOrder(['nas:movie.toprated', 'nas:offline-row', _ownRow.layoutRowId, 'nas:movie.recentlyadded']);
      expect(panelTitles(), ['Top Rated', 'Mijn rij', 'Recently Added in Films', 'Recently Added in Kids']);
      await controller.move(1, -1);
      expect(layout.order, [_ownRow.layoutRowId, 'nas:movie.toprated', 'nas:offline-row', 'nas:movie.recentlyadded']);
    });
  });
}
