/// Real providers for the "Home aanpassen" tests (HOME-R1): the layout, the own
/// rows, the Home projection and discover, with only the network edge faked
/// (aggregation, the own-row loader). Same shape as the harness in
/// `tv_home_row_order_test.dart`, for widget tests.
library;

import 'package:flutter/material.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/models/livetv_hub_result.dart';
import 'package:pleya/providers/continue_watching_hidden_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_extra_rows_provider.dart';
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
import 'package:pleya/services/unified_catalog/home_row_editing.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import 'prefs.dart';

MediaItem homeFilm(String id, String title, {String server = 'nas'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: 2024,
  serverId: server,
  serverName: server.toUpperCase(),
);

/// A Plex section hub: the identifier is the same for every library, the hub
/// key (`id`) is not.
MediaHub sectionHub(String section, String title, List<MediaItem> items) => MediaHub(
  id: '/hubs/sections/$section/recentlyAdded',
  identifier: 'movie.recentlyadded',
  title: title,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

MediaHub plainHub(String identifier, String title, List<MediaItem> items, {String type = 'movie'}) => MediaHub(
  id: identifier,
  identifier: identifier,
  title: title,
  type: type,
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

UnifiedMediaGroup homeGroup(String id) {
  final source = UnifiedMediaSource.fromItem(homeFilm(id, id));
  return UnifiedMediaGroup(
    groupId: id,
    identity: CanonicalMediaIdentity.movie(title: id, year: 2021),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

/// Answers every own row with the same content.
class FixedRowLoader implements HomeCustomRowLoader {
  FixedRowLoader(this.content);
  HomeCustomRowContent content;

  @override
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit}) async => content;
}

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

class HomeRowsHarness {
  HomeRowsHarness._();

  late final HomeLayoutProvider layout;
  late final HomeCustomRowsProvider customRows;
  late final TvHomeProjectionProvider projection;
  late final DiscoverProvider discover;
  late final MultiServerProvider multiServer;
  late final HiddenLibrariesProvider hiddenLibraries;
  late final LibrariesProvider libraries;
  late final ContinueWatchingHiddenProvider hidden;
  HomeExtraRowsProvider? extraRows;

  /// Boots every provider over [hubs]. Call inside `tester.runAsync`, because
  /// storage reads never complete under the fake clock of a widget test.
  static Future<HomeRowsHarness> boot({
    required List<MediaHub> hubs,
    List<HomeCustomRow> own = const [],
    HomeCustomRowLoader? loader,
    String? profileId,
    bool liveTv = false,
  }) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final h = HomeRowsHarness._();

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    final aggregation = _FakeAggregation(manager)..hubs = hubs;
    h.multiServer = MultiServerProvider(manager, aggregation);
    h.hiddenLibraries = HiddenLibrariesProvider();
    h.libraries = LibrariesProvider();
    h.discover = DiscoverProvider(h.multiServer, h.hiddenLibraries, h.libraries, isProfileBinding: () => false);
    await h.discover.load();
    h.projection = TvHomeProjectionProvider(
      discover: h.discover,
      multiServer: h.multiServer,
      continueWatchingTitle: 'Verder kijken',
      latestMoviesTitle: 'Recent uitgebracht',
    );
    for (var i = 0; i < 200 && h.projection.isProjecting; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    h.layout = HomeLayoutProvider(profileId: profileId);
    await h.layout.ensureInitialized();
    h.customRows = HomeCustomRowsProvider(
      layout: h.layout,
      multiServer: h.multiServer,
      libraries: h.libraries,
      hiddenLibraries: h.hiddenLibraries,
      loader: loader ?? FixedRowLoader(HomeCustomRowContent.empty),
    );
    for (final row in own) {
      await h.layout.saveCustomRow(row);
      await h.customRows.refreshRow(row.id);
    }
    if (liveTv) {
      // The Nu op tv row exists as soon as a Live TV source does; it is an
      // opt-in row, hidden until the viewer turns it on.
      h.extraRows = HomeExtraRowsProvider(
        layout: h.layout,
        multiServer: h.multiServer,
        watchlistTitle: 'Kijklijst',
        liveTvTitle: 'Nu op tv',
        discover: h.discover,
        loadLiveTv: () async => (entries: <LiveTvHubEntry>[], channels: <LiveTvChannel>[]),
      );
    }
    h.hidden = ContinueWatchingHiddenProvider();
    await h.hidden.ensureInitialized();
    return h;
  }

  /// Wraps [home] in the providers and a themed app.
  Widget app(Widget home, {TargetPlatform? platform}) => TranslationProvider(
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
        ChangeNotifierProvider<HomeCustomRowsProvider>.value(value: customRows),
        ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
        ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
        if (extraRows != null) ChangeNotifierProvider<HomeExtraRowsProvider>.value(value: extraRows!),
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
        ChangeNotifierProvider<ContinueWatchingHiddenProvider>.value(value: hidden),
      ],
      child: MaterialApp(
        theme: monoTheme(dark: true).copyWith(platform: platform),
        home: home,
      ),
    ),
  );

  void dispose() {
    extraRows?.dispose();
    projection.dispose();
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
    customRows.dispose();
    layout.dispose();
    hidden.dispose();
  }
}

/// Makes the wizard's libraries and preview the test's own, instead of reading
/// the app's providers. Undo with [uninstallHomeRowEditingStub] in `tearDown`.
void installHomeRowEditingStub({Future<HomeCustomRowContent> Function(HomeCustomRow draft)? preview}) {
  homeRowEditingOverride = (_) => HomeRowEditing(
    librariesFor: (_) => const [],
    preview: preview ?? (_) async => HomeCustomRowContent.empty,
    clientFor: (_) => null,
  );
}

void uninstallHomeRowEditingStub() => homeRowEditingOverride = null;

/// Screen sizes the customise screen is tested at.
enum HomeTestDevice {
  /// iPhone 15: 393x852 points at 3x, which `PlatformDetector.isPhone` reads as
  /// a phone.
  phone(Size(1179, 2556), 3, TargetPlatform.iOS),

  /// A small iPhone (SE): 375x667 points.
  phoneSmall(Size(1125, 2001), 3, TargetPlatform.iOS),

  /// iPad landscape, 1180x820 points.
  tablet(Size(2360, 1640), 2, TargetPlatform.iOS),

  /// A Mac window, 1440x900 points.
  mac(Size(2880, 1800), 2, TargetPlatform.macOS);

  const HomeTestDevice(this.size, this.pixelRatio, this.platform);
  final Size size;
  final double pixelRatio;
  final TargetPlatform platform;
}
