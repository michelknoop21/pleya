/// Fase 6 (hoofdstuk 10.2a of docs/tvos-unified-experience.md, [DEC-064]):
/// `TvDiscoveryLandingProvider` re-projects whatever `DiscoverProvider`
/// already fetched, split by [MediaKind] so a Films landing never shows a show
/// hub and vice versa.
///
/// **No Continue Watching row, on either landing (DEC-086).** The landings used
/// to prepend one and this file used to prove it; the assertions now run the
/// other way round, and the Continue Watching *projection* contracts they
/// carried moved onto [TvHomeProjectionProvider], which owns that row and is
/// now the only thing that does.
///
/// Those contracts stayed in this file rather than moving to
/// `tv_home_projection_provider_test.dart` because they are built on this
/// file's on-deck fixtures — the fake aggregation service, the external-id
/// resolving clients, the episode builder — and re-homing them would have meant
/// either duplicating all of that or moving it, neither of which is a change
/// this round is making. What they assert is unchanged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_discovery_landing_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';

MediaItem _movie(String id, {String? title, int? year = 2024}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title ?? id,
  year: year,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _show(String id, {String? title, int? year = 2024}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: title ?? id,
  year: year,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _episode(
  String id, {
  required String showTitle,
  String serverId = 'server_1',
  String? showId,
  int season = 1,
  int episode = 1,
  int viewOffsetMs = 100,
  int? lastViewedAt,
  String? guid,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode',
  guid: guid,
  grandparentId: showId,
  grandparentTitle: showTitle,
  parentIndex: season,
  index: episode,
  durationMs: 1000,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
  serverId: serverId,
  serverName: serverId,
);

// `identifier` set, matching the shape a real backend hub carries (Plex's own
// `hubIdentifier`, Jellyfin's synthesized `home.recent` etc.) — without one,
// `UnifiedHubKey.forHub` treats the row as server-scoped rather than global
// (hoofdstuk 17.2), which is not what a "Recently Added" row is.
MediaHub _hub(String id, {required String type, required List<MediaItem> items, String serverId = 'server_1'}) =>
    MediaHub(
      id: id,
      identifier: id,
      title: id,
      type: type,
      items: items,
      size: items.length,
      serverId: serverId,
      serverName: 'Server',
    );

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaItem> Function() onDeckResult = () => const [];
  List<MediaHub> Function() hubsResult = () => const [];

  /// Overrides which servers "answered", independent of [serverIds] asked —
  /// how a server that stays online but never returns a hub/on-deck result is
  /// simulated here.
  Set<String>? succeededServerIds;

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: onDeckResult(), succeededServerIds: succeededServerIds ?? serverIds ?? const {'server_1'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubsResult(), succeededServerIds: succeededServerIds ?? serverIds ?? const {'server_1'});
}

class _FakeClient implements MediaServerClient {
  _FakeClient({String serverId = 'server_1', this.externalIds = const {}}) : serverId = ServerId(serverId);

  /// Keyed by the id the projection actually asks for — for Continue Watching
  /// that is the *show's* `grandparentId`, because a CW card is a series and
  /// the shared identity that merges two servers' copies is the show's.
  final Map<String, ExternalIds> externalIds;

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => externalIds[itemId] ?? const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Polls `isProjecting` down to settled, the way a widget test would `pump`
/// but for a plain `ChangeNotifier` with no widget tree to drive it.
///
/// A microtask-only yield (`Future.value()`), not `Future.delayed` — the
/// latter always schedules a real `Timer`, and under a `testWidgets` binding
/// (unlike this file's plain `test`) a `Timer` never fires without an
/// explicit `tester.pump()`, which would hang this loop forever.
Future<void> _settle(TvDiscoveryLandingProvider provider) async {
  for (var i = 0; i < 50 && provider.isProjecting; i++) {
    await Future<void>.value();
  }
}

/// The same poll for Home's projection.
Future<void> _settleHome(TvHomeProjectionProvider provider) async {
  for (var i = 0; i < 50 && provider.isProjecting; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAggregationService aggregation;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider discover;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider();
    discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
  });

  tearDown(() {
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  TvDiscoveryLandingProvider makeLanding() => TvDiscoveryLandingProvider(discover: discover, multiServer: multiServer);

  /// Home's projection — the only owner of Continue Watching after DEC-086.
  TvHomeProjectionProvider makeHome() {
    final home = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
      latestMoviesTitle: 'Recently Released',
    );
    addTearDown(home.dispose);
    return home;
  }

  test('splits backend hubs into movie and series rows by hub type, dropping mixed rows', () async {
    aggregation.hubsResult = () => [
      _hub(
        'recently-added-movies',
        type: 'movie',
        items: [_movie('m1', title: 'Harbourlight')],
      ),
      _hub(
        'recently-added-shows',
        type: 'show',
        items: [_show('s1', title: 'Kite Street')],
      ),
      _hub(
        'promoted-mixed',
        type: 'mixed',
        items: [_movie('m2', title: 'Blue Signal')],
      ),
    ];
    await discover.load();

    final landing = makeLanding();
    addTearDown(landing.dispose);
    await _settle(landing);

    expect(landing.movieRails, hasLength(1));
    expect(landing.movieRails.single.hubId, contains('recently-added-movies'));
    expect(landing.movieRails.single.groups.single.representativeSource.item.title, 'Harbourlight');

    expect(landing.seriesRails, hasLength(1));
    expect(landing.seriesRails.single.hubId, contains('recently-added-shows'));
    expect(landing.seriesRails.single.groups.single.representativeSource.item.title, 'Kite Street');
  });

  test('DEC-086: neither landing carries a Continue Watching row, however full on-deck is', () async {
    aggregation.onDeckResult = () => [
      _movie('cw-movie', title: 'The Long Harbour'),
      _episode('cw-ep', showTitle: 'Harbourlight'),
    ];
    aggregation.hubsResult = () => [
      _hub(
        'recently-added-movies',
        type: 'movie',
        items: [_movie('m1', title: 'Quarry Road')],
      ),
      _hub(
        'recently-added-shows',
        type: 'show',
        items: [_show('s1', title: 'Kite Street')],
      ),
    ];
    await discover.load();

    final landing = makeLanding();
    addTearDown(landing.dispose);
    await _settle(landing);

    // The first row of a landing is a recommendation row now, on both kinds.
    expect(landing.movieRails.map((r) => r.title), isNot(contains('Continue Watching')));
    expect(landing.seriesRails.map((r) => r.title), isNot(contains('Continue Watching')));
    expect(landing.movieRails, hasLength(1));
    expect(landing.movieRails.single.hubId, contains('recently-added-movies'));
    expect(landing.seriesRails, hasLength(1));
    expect(landing.seriesRails.single.hubId, contains('recently-added-shows'));
  });

  test('DEC-086: Home still has it, over the very same on-deck list', () async {
    // The half that makes the removal a relocation rather than a loss. If this
    // ever goes red the row has not moved to Home, it has disappeared.
    aggregation.onDeckResult = () => [
      _movie('cw-movie', title: 'The Long Harbour'),
      _episode('cw-ep', showTitle: 'Harbourlight'),
    ];
    await discover.load();

    final home = makeHome();
    await _settleHome(home);

    expect(home.continueWatching, isNotNull);
    expect(home.continueWatching!.groups, hasLength(2));
  });

  test('the landing never showed an episode on Films, which is why the row had to go', () async {
    // The defect found while removing it: the row was projected once over the
    // *whole* of `DiscoverProvider.onDeck` and prepended to both landings,
    // while the hubs beside it were kind-split. So the Films landing led with
    // half-watched episodes and the Series landing with films — the exact thing
    // this provider's own doc rules out.
    aggregation.onDeckResult = () => [_episode('cw-ep', showTitle: 'Harbourlight')];
    aggregation.hubsResult = () => [
      _hub(
        'recently-added-movies',
        type: 'movie',
        items: [_movie('m1', title: 'Quarry Road')],
      ),
    ];
    await discover.load();

    final landing = makeLanding();
    addTearDown(landing.dispose);
    await _settle(landing);

    final kinds = {
      for (final rail in landing.movieRails)
        for (final group in rail.groups) group.representativeSource.item.kind,
    };
    expect(kinds, isNot(contains(MediaKind.episode)), reason: 'a Films landing shows films');
  });

  test('a server that stayed online but never answered marks global rows partial', () async {
    // A second server the manager knows is online, but whose hub/on-deck
    // fetch this fixture never reports as succeeded — hoofdstuk 21.4's
    // "one bad server never empties a row", pictured from the failure side.
    multiServer.serverManager.debugRegisterClientForTesting(_FakeClient(serverId: 'server_2'));
    aggregation.hubsResult = () => [
      _hub(
        'recently-added-movies',
        type: 'movie',
        items: [_movie('m1', title: 'Quarry Road')],
      ),
    ];
    aggregation.succeededServerIds = {'server_1'};
    await discover.load();
    expect(discover.unansweredServerIds, {'server_2'});

    final landing = makeLanding();
    addTearDown(landing.dispose);
    await _settle(landing);

    expect(landing.movieRails.single.isPartial, isTrue);
    // Healthy content stays fully usable regardless (hoofdstuk 21.4): the
    // group from the server that did answer is still on the row.
    expect(landing.movieRails.single.groups, hasLength(1));
  });

  test('hubById finds a row across both landings', () async {
    aggregation.onDeckResult = () => [_movie('cw-movie', title: 'The Long Harbour')];
    aggregation.hubsResult = () => [
      _hub(
        'recently-added-movies',
        type: 'movie',
        items: [_movie('m1', title: 'Quarry Road')],
      ),
      _hub(
        'recently-added-shows',
        type: 'show',
        items: [_show('s1', title: 'Kite Street')],
      ),
    ];
    await discover.load();

    final landing = makeLanding();
    addTearDown(landing.dispose);
    await _settle(landing);

    final movieHub = landing.movieRails.last;
    final seriesHub = landing.seriesRails.last;

    expect(landing.hubById(movieHub.hubId), same(movieHub));
    expect(landing.hubById(seriesHub.hubId), same(seriesHub));
    expect(landing.hubById('hub:nonexistent'), isNull);
  });

  // Fase-6 Continue Watching proof (hoofdstuk 13.3, 21.4). The service-level
  // contracts live in `test/services/unified_catalog/home_projection_service_test.dart`;
  // these drive the production provider that owns the row — which after DEC-086
  // is `TvHomeProjectionProvider`, and only that.
  group('Continue Watching, through the provider that owns it', () {
    /// A second (or first) online server whose show ids resolve to real
    /// external ids — the evidence Continue Watching merges on.
    void registerServerWithShowIds(String serverId, Map<String, ExternalIds> showIds) {
      multiServer.serverManager.debugRegisterClientForTesting(_FakeClient(serverId: serverId, externalIds: showIds));
    }

    test('D1: the same episode of one series on two servers is one card carrying both sources', () async {
      // Hoofdstuk 11.8: Continue Watching groups on the exact episode. Two
      // servers holding the viewer at S02E04 of one series are one card, and
      // its sources stay the concrete resumable episodes each server has.
      // The shared *series* tmdb is what carries the merge across backends —
      // narrowed to `s2e4` before it becomes evidence, so it identifies this
      // episode and not the series.
      registerServerWithShowIds('server_1', {'show-1': const ExternalIds(tmdb: 95396)});
      registerServerWithShowIds('server_2', {'show-1': const ExternalIds(tmdb: 95396)});
      aggregation.onDeckResult = () => [
        _episode('ep-a', showTitle: 'Harbourlight', showId: 'show-1', serverId: 'server_1', season: 2, episode: 4),
        _episode('ep-b', showTitle: 'Harbourlight', showId: 'show-1', serverId: 'server_2', season: 2, episode: 4),
      ];
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      final cw = home.continueWatching!;
      expect(cw.title, 'Continue Watching');
      expect(cw.groups, hasLength(1), reason: 'one episode, one card');
      final sources = cw.groups.single.sources;
      expect(sources.map((s) => s.item.serverId).toSet(), {'server_1', 'server_2'});
      expect(sources.every((s) => s.item.kind == MediaKind.episode), isTrue);
      expect(sources.map((s) => (s.item.parentIndex, s.item.index)).toSet(), {(2, 4)});
    });

    test('D1: two episodes of one series on two servers stay two cards', () async {
      // The other half of D1, and the regression that catches the old
      // series-wide fold: both rows resolve the *same* series tmdb, and both
      // carry the same show title and show id. Only the episode ordinal
      // separates them, and it has to be enough.
      registerServerWithShowIds('server_1', {'show-1': const ExternalIds(tmdb: 95396)});
      registerServerWithShowIds('server_2', {'show-1': const ExternalIds(tmdb: 95396)});
      aggregation.onDeckResult = () => [
        _episode('ep-a', showTitle: 'Harbourlight', showId: 'show-1', serverId: 'server_1', season: 2, episode: 4),
        _episode('ep-b', showTitle: 'Harbourlight', showId: 'show-1', serverId: 'server_2', season: 2, episode: 5),
      ];
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      final cw = home.continueWatching!;
      expect(cw.groups, hasLength(2), reason: 'S02E04 and S02E05 are two Continue Watching entries');
      expect(
        {for (final g in cw.groups) (g.representativeSource.item.parentIndex, g.representativeSource.item.index)},
        {(2, 4), (2, 5)},
      );
    });

    test('two series with no shared identity stay two cards', () async {
      registerServerWithShowIds('server_1', {
        'show-1': const ExternalIds(tmdb: 95396),
        'show-2': const ExternalIds(tmdb: 71912),
      });
      aggregation.onDeckResult = () => [
        _episode('ep-1', showTitle: 'Harbourlight', showId: 'show-1'),
        _episode('ep-2', showTitle: 'Kite Street', showId: 'show-2'),
      ];
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      expect(home.continueWatching!.groups, hasLength(2));
    });

    test('every source keeps its own watch state — the card never averages them away', () async {
      // Hoofdstuk 13.1: bronstate blijft intact. The picker and the hoofdstuk
      // 13.4 group actions need the concrete per-source offsets, so a merged
      // card may present one progress but must not overwrite either source's.
      registerServerWithShowIds('server_1', {'show-1': const ExternalIds(tmdb: 95396)});
      registerServerWithShowIds('server_2', {'show-1': const ExternalIds(tmdb: 95396)});
      aggregation.onDeckResult = () => [
        _episode(
          'ep-a',
          showTitle: 'Harbourlight',
          showId: 'show-1',
          serverId: 'server_1',
          viewOffsetMs: 100,
          lastViewedAt: 1000,
        ),
        _episode(
          'ep-b',
          showTitle: 'Harbourlight',
          showId: 'show-1',
          serverId: 'server_2',
          viewOffsetMs: 800,
          lastViewedAt: 2000,
        ),
      ];
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      final group = home.continueWatching!.groups.single;
      final offsets = {for (final s in group.sources) s.item.serverId!: s.item.viewOffsetMs};
      expect(offsets, {'server_1': 100, 'server_2': 800});
    });

    test('one broken server does not remove the healthy Continue Watching content', () async {
      // Hoofdstuk 21.4. The row is flagged partial so the UI can say so, and
      // that is the *only* consequence: the answering server's cards stay.
      multiServer.serverManager.debugRegisterClientForTesting(_FakeClient(serverId: 'server_2'));
      aggregation.onDeckResult = () => [_episode('ep-a', showTitle: 'Harbourlight', serverId: 'server_1')];
      aggregation.succeededServerIds = {'server_1'};
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      final cw = home.continueWatching!;
      expect(cw.title, 'Continue Watching');
      expect(cw.groups, hasLength(1));
      expect(cw.isPartial, isTrue);
      expect(cw.groups.single.sources.single.item.serverId, 'server_1');
    });

    test('a card whose only source went unanswered still names that source, never a substitute', () async {
      // Hoofdstuk 4.4/15: no silent failover. A merged card must not quietly
      // re-point at the server that did answer — every source it lists is a
      // source it actually projected.
      multiServer.serverManager.debugRegisterClientForTesting(_FakeClient(serverId: 'server_2'));
      aggregation.onDeckResult = () => [
        _episode('ep-a', showTitle: 'Harbourlight', showId: 'show-1', serverId: 'server_1'),
        _episode('ep-b', showTitle: 'Kite Street', showId: 'show-2', serverId: 'server_2'),
      ];
      aggregation.succeededServerIds = {'server_1'};
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      final groups = home.continueWatching!.groups;
      expect(groups, hasLength(2));
      for (final group in groups) {
        for (final source in group.sources) {
          expect(
            source.item.serverId,
            isNotNull,
            reason: 'a source without its own server is exactly the substitution this forbids',
          );
        }
      }
      final kite = groups.firstWhere((g) => g.representativeSource.item.grandparentTitle == 'Kite Street');
      expect(kite.sources.single.item.serverId, 'server_2');
    });

    test('an online server that contributed nothing appears nowhere in Continue Watching', () async {
      // Not a profile-visibility test — this configures no visibility
      // restriction, and hoofdstuk 22's per-profile server visibility is
      // enforced upstream, in the aggregation this provider re-projects.
      // What it does prove is the half that lives here: the projection never
      // widens what it was handed, so a server that is online but returned no
      // on-deck item contributes no source.
      multiServer.serverManager.debugRegisterClientForTesting(_FakeClient(serverId: 'server_2'));
      aggregation.onDeckResult = () => [_episode('ep-a', showTitle: 'Harbourlight', serverId: 'server_1')];
      await discover.load();

      final home = makeHome();
      await _settleHome(home);

      final sources = [for (final group in home.continueWatching!.groups) ...group.sources.map((s) => s.item.serverId)];
      expect(sources, ['server_1'], reason: 'server_2 is online but contributed nothing, so it appears nowhere');
    });
  });
}
