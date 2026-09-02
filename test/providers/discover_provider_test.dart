import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/recommendations/personalized_rows_builder.dart';
import 'package:pleya/services/recommendations/recommendation_service.dart';
import 'package:pleya/services/recommendations/tautulli_history_importer.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

import '../test_helpers/prefs.dart';

MediaItem _item(String id, {String? parentId, String serverId = 'server_1', MediaKind kind = MediaKind.episode}) =>
    MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: kind,
      title: id,
      serverId: serverId,
      serverName: 'Server',
      parentId: parentId,
    );

MediaHub _hub(
  String id, {
  String? identifier,
  String? libraryId,
  List<MediaItem>? items,
  String serverId = 'server_1',
}) => MediaHub(
  id: id,
  title: id,
  type: 'movie',
  identifier: identifier,
  items: items ?? [_item('$id-item', serverId: serverId)],
  size: 1,
  libraryId: libraryId,
  serverId: serverId,
);

/// Counting fake — the provider's fetch-cost policy is the contract under
/// test: a watch event must cost exactly one on-deck call and zero hub
/// refetches, an order change zero calls, a hidden-set change one full pass.
class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  int onDeckCalls = 0;
  int hubCalls = 0;
  Set<String>? lastOnDeckServerIds;
  Set<String>? lastHubsServerIds;
  Set<String>? onDeckSucceededServerIds;
  Set<String>? hubSucceededServerIds;
  List<MediaItem> Function() onDeckResult = () => const [];
  List<MediaHub> Function() hubsResult = () => const [];

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async {
    onDeckCalls++;
    lastOnDeckServerIds = serverIds;
    final items = onDeckResult();
    return (
      items: limit != null && items.length > limit ? items.sublist(0, limit) : items,
      succeededServerIds: onDeckSucceededServerIds ?? serverIds ?? const {'server_1'},
    );
  }

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async {
    hubCalls++;
    lastHubsServerIds = serverIds;
    return (hubs: hubsResult(), succeededServerIds: hubSucceededServerIds ?? serverIds ?? const {'server_1'});
  }
}

/// Counts how often the feed asks for personalized rows and what the imported
/// history sync answered, so the "no new data, no extra work" contract is
/// measured rather than assumed.
class _FakeRecommendationService implements RecommendationService {
  _FakeRecommendationService({this.syncResult = false});

  bool syncResult;
  int buildCalls = 0;
  int syncCalls = 0;

  @override
  String get profileId => 'p1';

  @override
  Future<List<MediaHub>> buildRows(
    List<MediaServerClient> clients, {
    List<MediaItem> hubItems = const [],
    Set<String> excludeKeys = const {},
    int? nowMs,
  }) async {
    buildCalls++;
    return const [];
  }

  @override
  Future<bool> syncImportedHistory() async {
    syncCalls++;
    return syncResult;
  }

  @override
  void invalidateCandidates() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The real service, with only the row build counted. Used where the point is
/// the service's own hydration logic rather than the feed's arithmetic.
class _CountingRecommendationService extends RecommendationService {
  _CountingRecommendationService({
    required AppDatabase database,
    required Set<String> Function() enabledImportServerIds,
    required Future<void> Function() importSourcesReady,
    required TautulliImporterFactory importerFactory,
  }) : super(
         profileId: 'p1',
         database: database,
         titles: PersonalizedRowTitles(
           topPicks: 'Top Picks',
           becauseYouLike: (g) => 'Because you like $g',
           hiddenGems: 'Hidden Gems',
         ),
         enabledImportServerIds: enabledImportServerIds,
         importSourcesReady: importSourcesReady,
         importerFactory: importerFactory,
       );

  int buildCalls = 0;

  @override
  Future<List<MediaHub>> buildRows(
    List<MediaServerClient> clients, {
    List<MediaItem> hubItems = const [],
    Set<String> excludeKeys = const {},
    int? nowMs,
  }) {
    buildCalls++;
    return super.buildRows(clients, hubItems: hubItems, excludeKeys: excludeKeys, nowMs: nowMs);
  }
}

class _CountingImporter implements TautulliHistoryImporter {
  int syncs = 0;

  @override
  Future<TautulliImportOutcome?> sync() async {
    syncs++;
    // A warm profile: everything is already stored, so nothing is new. The
    // rebuild has to happen anyway, because the rows were scored without it.
    return const TautulliImportOutcome(fetched: 3, deduplicated: 3);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements MediaServerClient {
  _FakeClient({this.id = 'server_1'});

  final String id;
  MediaItem? itemResult;
  final List<String> fetchedIds = [];

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async {
    fetchedIds.add(id);
    return itemResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeClient client;
  late _FakeAggregationService aggregation;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider provider;
  bool isBinding = false;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    isBinding = false;

    client = _FakeClient();
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider();
    provider = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => isBinding);
  });

  test('updateItem refetches from the server that owns the item, not the first id match', () async {
    // A backend item id is unique per server: two Plex servers both number
    // their rating keys from 1. Resolving the owner by scanning for a bare id
    // match picks whichever list holds that id first, so finishing a film on
    // one server refetched an unrelated title from the other and swapped it
    // into the row — wrong title, wrong artwork, wrong route on the next
    // Select.
    final other = _FakeClient(id: 'server_2');
    multiServer.serverManager.debugRegisterClientForTesting(other);
    client.itemResult = _item('12345', serverId: 'server_1').copyWith(title: 'the right film, refreshed');
    other.itemResult = _item('12345', serverId: 'server_2').copyWith(title: 'an unrelated film');

    // server_2's copy is listed first, so a bare-id scan resolves to it.
    aggregation.onDeckResult = () => [
      _item('12345', serverId: 'server_2').copyWith(title: 'an unrelated film'),
      _item('12345', serverId: 'server_1').copyWith(title: 'the right film'),
    ];
    await provider.load();

    await provider.updateItem('12345', serverId: 'server_1');

    expect(client.fetchedIds, ['12345'], reason: 'the owning server is the one asked');
    expect(other.fetchedIds, isEmpty, reason: 'the other server holds a different title under the same id');
    expect(provider.onDeck.map((i) => (i.serverId, i.title)), [
      ('server_2', 'an unrelated film'),
      ('server_1', 'the right film, refreshed'),
    ]);
  });

  tearDown(() {
    provider.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  test('load publishes on-deck and hubs; concurrent calls coalesce', () async {
    aggregation.onDeckResult = () => [_item('a')];
    aggregation.hubsResult = () => [_hub('hub-1')];

    // Three synchronous calls: one in-flight pass plus at most one trailing
    // pass (a request arriving mid-load must observe its own fresh fetch).
    await Future.wait([provider.load(), provider.load(), provider.load()]);

    expect(provider.onDeck.map((i) => i.id), ['a']);
    expect(provider.hubs.map((h) => h.id), ['hub-1']);
    expect(provider.isLoading, isFalse);
    expect(provider.areHubsLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(aggregation.onDeckCalls, 2);
    expect(aggregation.hubCalls, 2);
  });

  test('isRefreshing brackets a pass and notifies on both edges', () async {
    // The clear happens in a whenComplete, i.e. after the pass's own last
    // notify — miss the trailing notify and a finished refresh keeps showing
    // as running until something unrelated rebuilds.
    final transitions = <bool>[];
    provider.addListener(() {
      if (transitions.isEmpty || transitions.last != provider.isRefreshing) transitions.add(provider.isRefreshing);
    });

    expect(provider.isRefreshing, isFalse);
    final pass = provider.load();
    expect(provider.isRefreshing, isTrue);

    await pass;
    expect(provider.isRefreshing, isFalse);

    await pumpEventQueue();
    expect(transitions, [true, false]);
  });

  test('a refresh with content on screen is refreshing but not loading', () async {
    aggregation.onDeckResult = () => [_item('a')];
    aggregation.hubsResult = () => [_hub('hub-1')];
    await provider.load();

    final second = provider.load();
    expect(provider.isRefreshing, isTrue);
    // Deliberate: the rows stay put instead of flipping to a skeleton, which
    // is exactly why the refresh action needs its own signal.
    expect(provider.isLoading, isFalse);
    expect(provider.areHubsLoading, isFalse);

    await second;
    expect(provider.isRefreshing, isFalse);
  });

  test('limits the preview row and probes for more', () async {
    aggregation.onDeckResult = () => [for (var i = 0; i < 30; i++) _item('item-$i')];

    await provider.load();

    expect(provider.onDeck, hasLength(DiscoverProvider.continueWatchingPreviewLimit));
    expect(provider.hasMoreContinueWatching, isTrue);
  });

  test('filters playback-progress hubs that duplicate the continue watching row', () async {
    aggregation.hubsResult = () => [
      _hub('keep'),
      _hub('cw', identifier: 'home.continue'),
      _hub('od', identifier: 'home.ondeck'),
      _hub('nu', identifier: 'home.nextup'),
    ];

    await provider.load();

    expect(provider.hubs.map((h) => h.id), ['keep']);
  });

  test('watch event refreshes continue watching with one call and zero hub refetches', () async {
    aggregation.onDeckResult = () => [_item('ep-1', parentId: 'season-1')];
    aggregation.hubsResult = () => [_hub('hub-1')];
    await provider.load();
    final onDeckCallsBefore = aggregation.onDeckCalls;
    final hubCallsBefore = aggregation.hubCalls;

    WatchStateNotifier().notifyWatched(item: _item('ep-1', parentId: 'season-1'));
    await pumpEventQueue();

    expect(aggregation.onDeckCalls, onDeckCallsBefore + 1);
    expect(aggregation.hubCalls, hubCallsBefore);
  });

  test('removal event drops the row immediately, then refreshes in background', () async {
    aggregation.onDeckResult = () => [_item('ep-1'), _item('ep-2')];
    await provider.load();

    var sawImmediateRemoval = false;
    provider.addListener(() {
      if (provider.onDeck.length == 1 && provider.onDeck.single.id == 'ep-2') {
        sawImmediateRemoval = true;
      }
    });
    aggregation.onDeckResult = () => [_item('ep-2')];

    WatchStateNotifier().notifyRemovedFromContinueWatching(item: _item('ep-1'));
    await pumpEventQueue();

    expect(sawImmediateRemoval, isTrue);
    expect(provider.onDeck.map((i) => i.id), ['ep-2']);
  });

  test('G10: a removed row does not come back while the server still lists it', () async {
    // Hoofdstuk 13.4 point 6, and the case the queue exists for: a membership
    // whose removal is still queued keeps being listed by its server until
    // the replay lands. Dropping the row without suppressing it would put the
    // card back on the very next refresh.
    aggregation.onDeckResult = () => [_item('ep-1'), _item('ep-2')];
    await provider.load();

    WatchStateNotifier().notifyRemovedFromContinueWatching(item: _item('ep-1'));
    await pumpEventQueue();
    expect(provider.onDeck.map((i) => i.id), ['ep-2']);

    // The server has not processed the removal yet and still returns it.
    await provider.refreshContinueWatching();
    await pumpEventQueue();

    expect(provider.onDeck.map((i) => i.id), ['ep-2']);
  });

  test('G10: the suppression lifts once the server stops listing the row', () async {
    aggregation.onDeckResult = () => [_item('ep-1'), _item('ep-2')];
    await provider.load();

    WatchStateNotifier().notifyRemovedFromContinueWatching(item: _item('ep-1'));
    await pumpEventQueue();

    // The removal landed server-side, so the row is gone from the answer …
    aggregation.onDeckResult = () => [_item('ep-2')];
    await provider.refreshContinueWatching();

    // … and a genuine rewatch afterwards must be able to bring it back.
    aggregation.onDeckResult = () => [_item('ep-1'), _item('ep-2')];
    await provider.refreshContinueWatching();

    expect(provider.onDeck.map((i) => i.id), ['ep-1', 'ep-2']);
  });

  test('watched movie leaves the row immediately and a stale refetch cannot bring it back', () async {
    final movie = _item('movie-1', kind: MediaKind.movie);
    // The refetch keeps returning the movie (scrobble race on the server).
    aggregation.onDeckResult = () => [movie, _item('ep-1')];
    await provider.load();

    WatchStateNotifier().notifyWatched(item: movie);
    await pumpEventQueue();

    expect(provider.onDeck.map((i) => i.id), ['ep-1']);
  });

  test('watched episode keeps the series row for the refetch to advance', () async {
    aggregation.onDeckResult = () => [_item('ep-1')];
    await provider.load();

    WatchStateNotifier().notifyWatched(item: _item('ep-1'));
    await pumpEventQueue();

    expect(provider.onDeck.map((i) => i.id), ['ep-1']);
  });

  test('restarting a watched movie lifts the suppression', () async {
    final movie = _item('movie-1', kind: MediaKind.movie);
    aggregation.onDeckResult = () => [movie];
    await provider.load();

    WatchStateNotifier().notifyWatched(item: movie);
    await pumpEventQueue();
    expect(provider.onDeck, isEmpty);

    WatchStateNotifier().notifyProgress(item: movie, viewOffset: 60000, duration: 7200000);
    await pumpEventQueue();

    expect(provider.onDeck.map((i) => i.id), ['movie-1']);
  });

  test('library order change re-sorts hubs without any refetch', () async {
    aggregation.hubsResult = () => [_hub('hub-lib2', libraryId: 'lib-2'), _hub('hub-lib1', libraryId: 'lib-1')];
    await provider.load();
    expect(provider.hubs.map((h) => h.id), ['hub-lib2', 'hub-lib1']);
    final hubCallsBefore = aggregation.hubCalls;

    MediaLibrary lib(String id) => MediaLibrary(id: id, backend: MediaBackend.plex, title: id, serverId: 'server_1');
    await libraries.updateLibraryOrder([lib('lib-1'), lib('lib-2')]);
    await pumpEventQueue();

    expect(provider.hubs.map((h) => h.id), ['hub-lib1', 'hub-lib2']);
    expect(aggregation.hubCalls, hubCallsBefore);
  });

  test('hidden-library change triggers exactly one full reload', () async {
    await provider.load();
    final onDeckCallsBefore = aggregation.onDeckCalls;
    final hubCallsBefore = aggregation.hubCalls;

    await hiddenLibraries.hideLibrary('server_1:lib-1');
    await pumpEventQueue();

    expect(aggregation.onDeckCalls, onDeckCallsBefore + 1);
    expect(aggregation.hubCalls, hubCallsBefore + 1);
  });

  test('refreshContinueWatching never flips states or surfaces errors', () async {
    aggregation.onDeckResult = () => [_item('a')];
    await provider.load();

    aggregation.onDeckResult = () => throw Exception('server down');
    await provider.refreshContinueWatching();

    expect(provider.onDeck.map((i) => i.id), ['a']);
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);
  });

  test('load failure surfaces a friendly error (not the raw exception) and ends both loading states', () async {
    aggregation.onDeckResult = () => throw Exception('boom');

    await provider.load();

    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('boom')));
    expect(provider.errorMessage, isNot(contains('Exception')));
    expect(provider.isLoading, isFalse);
    expect(provider.areHubsLoading, isFalse);
  });

  test('no servers while the profile binder runs stays loading instead of erroring', () async {
    final emptyManager = MultiServerManager();
    final emptyAggregation = _FakeAggregationService(emptyManager);
    final emptyMultiServer = MultiServerProvider(emptyManager, emptyAggregation);
    addTearDown(emptyMultiServer.dispose);
    final binderProvider = DiscoverProvider(
      emptyMultiServer,
      hiddenLibraries,
      libraries,
      isProfileBinding: () => isBinding,
    );
    addTearDown(binderProvider.dispose);

    isBinding = true;
    await binderProvider.load();
    expect(binderProvider.isLoading, isTrue);
    expect(binderProvider.errorMessage, isNull);

    isBinding = false;
    await binderProvider.load();
    expect(binderProvider.isLoading, isFalse);
    expect(binderProvider.errorMessage, isNotNull);
  });

  test('updateItem refetches one item and swaps it in place', () async {
    aggregation.onDeckResult = () => [_item('ep-1')];
    aggregation.hubsResult = () => [
      _hub('hub-1', items: [_item('movie-1')]),
    ];
    await provider.load();

    client.itemResult = _item('movie-1').copyWith(title: 'Updated Title');
    await provider.updateItem('movie-1');

    expect(provider.hubs.single.items.single.title, 'Updated Title');
    expect(provider.onDeck.single.id, 'ep-1');
  });

  test('syncToOnlineServers reloads for mid-session connects only', () async {
    aggregation.onDeckResult = () => [_item('a')];
    await provider.load();
    final onDeckCallsBefore = aggregation.onDeckCalls;

    // Same server set → already covered, no fetch.
    await provider.syncToOnlineServers({'server_1'});
    expect(aggregation.onDeckCalls, onDeckCallsBefore);

    // New server mid-session → one delta fetch scoped to it.
    await provider.syncToOnlineServers({'server_1', 'server_2'});
    expect(aggregation.onDeckCalls, onDeckCallsBefore + 1);

    // During profile binding the startup priming owns loading — waves are
    // ignored so the hub fan-out doesn't run once per wave.
    isBinding = true;
    await provider.syncToOnlineServers({'server_1', 'server_2', 'server_3'});
    expect(aggregation.onDeckCalls, onDeckCallsBefore + 1);
  });

  test('mid-session connect delta-fetches only the new server and merges', () async {
    aggregation.onDeckResult = () => [_item('a')];
    aggregation.hubsResult = () => [_hub('hub-1')];
    await provider.load();
    final generationBefore = provider.loadGeneration;

    aggregation.onDeckResult = () => [_item('b', serverId: 'server_2')];
    aggregation.hubsResult = () => [_hub('hub-2', serverId: 'server_2')];
    await provider.syncToOnlineServers({'server_1', 'server_2'});

    // The fetch fanned out to the new server only…
    expect(aggregation.lastOnDeckServerIds, {'server_2'});
    expect(aggregation.lastHubsServerIds, {'server_2'});
    // …and merged into the loaded state instead of replacing it.
    expect(provider.onDeck.map((i) => i.id), containsAll(['a', 'b']));
    expect(provider.hubs.map((h) => h.id), containsAll(['hub-1', 'hub-2']));
    // A delta behaves like a background refresh: no hero carousel reset.
    expect(provider.loadGeneration, generationBefore);

    // Already merged → the next emission with the same set is a no-op.
    final callsAfterDelta = aggregation.onDeckCalls;
    await provider.syncToOnlineServers({'server_1', 'server_2'});
    expect(aggregation.onDeckCalls, callsAfterDelta);
  });

  test('full load partial hub failure retries hubs without refetching continue watching', () async {
    aggregation.onDeckResult = () => [_item('a')];
    aggregation.hubsResult = () => const [];
    aggregation.hubSucceededServerIds = const {};
    await provider.load();
    final onDeckCallsBefore = aggregation.onDeckCalls;
    final hubCallsBefore = aggregation.hubCalls;

    aggregation.hubsResult = () => [_hub('hub-1')];
    aggregation.hubSucceededServerIds = const {'server_1'};
    await provider.syncToOnlineServers({'server_1'});

    expect(aggregation.onDeckCalls, onDeckCallsBefore);
    expect(aggregation.hubCalls, hubCallsBefore + 1);
    expect(aggregation.lastHubsServerIds, {'server_1'});
    expect(provider.hubs.map((h) => h.id), ['hub-1']);
  });

  test('delta partial hub failure retries only the missing surface', () async {
    aggregation.onDeckResult = () => [_item('a')];
    aggregation.hubsResult = () => [_hub('hub-1')];
    await provider.load();

    aggregation.onDeckResult = () => [_item('b', serverId: 'server_2')];
    aggregation.hubsResult = () => const [];
    aggregation.hubSucceededServerIds = const {};
    await provider.syncToOnlineServers({'server_1', 'server_2'});
    final onDeckCallsAfterPartial = aggregation.onDeckCalls;
    final hubCallsAfterPartial = aggregation.hubCalls;

    aggregation.hubsResult = () => [_hub('hub-2', serverId: 'server_2')];
    aggregation.hubSucceededServerIds = const {'server_2'};
    await provider.syncToOnlineServers({'server_1', 'server_2'});

    expect(aggregation.onDeckCalls, onDeckCallsAfterPartial);
    expect(aggregation.hubCalls, hubCallsAfterPartial + 1);
    expect(aggregation.lastHubsServerIds, {'server_2'});
    expect(provider.onDeck.map((i) => i.id), containsAll(['a', 'b']));
    expect(provider.hubs.map((h) => h.id), containsAll(['hub-1', 'hub-2']));
  });

  test('delta failure keeps the loaded state and retries on the next emission', () async {
    aggregation.onDeckResult = () => [_item('a')];
    aggregation.hubsResult = () => [_hub('hub-1')];
    await provider.load();
    final callsBefore = aggregation.onDeckCalls;

    aggregation.onDeckResult = () => throw Exception('flaky connect');
    await provider.syncToOnlineServers({'server_1', 'server_2'});
    expect(provider.onDeck.map((i) => i.id), ['a']);
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);

    // The failed id was not marked loaded, so the next emission retries it.
    aggregation.onDeckResult = () => [_item('b', serverId: 'server_2')];
    await provider.syncToOnlineServers({'server_1', 'server_2'});
    expect(aggregation.onDeckCalls, callsBefore + 2);
    expect(provider.onDeck.map((i) => i.id), containsAll(['a', 'b']));
  });

  test('dispose unregisters the online-servers listener', () {
    final before = multiServer.onlineServersListenerCount;
    final extra = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => isBinding);
    expect(multiServer.onlineServersListenerCount, before + 1);

    extra.dispose();
    expect(multiServer.onlineServersListenerCount, before);
  });

  test('loadGeneration bumps on full loads only', () async {
    aggregation.onDeckResult = () => [_item('a')];
    final initial = provider.loadGeneration;

    await provider.load();
    expect(provider.loadGeneration, initial + 1);

    await provider.refreshContinueWatching();
    expect(provider.loadGeneration, initial + 1);
  });

  group('imported history refresh', () {
    Future<DiscoverProvider> loadWith(_FakeRecommendationService service) async {
      final p = DiscoverProvider(
        multiServer,
        hiddenLibraries,
        libraries,
        isProfileBinding: () => isBinding,
        recommendations: service,
      );
      aggregation.onDeckResult = () => [_item('a')];
      aggregation.hubsResult = () => [_hub('hub-1')];
      await p.load();
      // The recommendation pass runs unawaited off the load.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return p;
    }

    test('no new data means one personalized pass and no hub refetch', () async {
      final service = _FakeRecommendationService(syncResult: false);
      final p = await loadWith(service);
      addTearDown(p.dispose);

      expect(service.syncCalls, 1);
      expect(service.buildCalls, 1, reason: 'nothing new, so nothing to rebuild');
      expect(aggregation.hubCalls, 1, reason: 'the sync never triggers a hub refetch');
    });

    test('new data means exactly one extra personalized pass', () async {
      final service = _FakeRecommendationService(syncResult: true);
      final p = await loadWith(service);
      addTearDown(p.dispose);

      expect(service.syncCalls, 1);
      expect(service.buildCalls, 2, reason: 'once before the sync, once after');
      expect(aggregation.hubCalls, 1, reason: 'still no hub refetch');
    });

    test('a cold start imports once when the integration store answers late', () async {
      // The race this is about: Discover has servers and renders before
      // TautulliProvider has finished reading the device's integrations, so the
      // enabled set is empty at the moment the first rows are built.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hydration = Completer<void>();
      var enabled = <String>{};
      final importer = _CountingImporter();
      var factoryProfiles = <String>[];

      final service = _CountingRecommendationService(
        database: db,
        enabledImportServerIds: () => enabled,
        importSourcesReady: () => hydration.future,
        importerFactory: (profileId, _) {
          factoryProfiles.add(profileId);
          return importer;
        },
      );

      final p = DiscoverProvider(
        multiServer,
        hiddenLibraries,
        libraries,
        isProfileBinding: () => isBinding,
        recommendations: service,
      );
      addTearDown(p.dispose);
      aggregation.onDeckResult = () => [_item('a')];
      aggregation.hubsResult = () => [_hub('hub-1')];

      await p.load();
      await pumpEventQueue();

      // The feed is already on screen and the sync is still waiting.
      expect(p.hubs.map((h) => h.id), ['hub-1']);
      expect(service.buildCalls, 1, reason: 'existing rows are shown without waiting for the import');
      expect(importer.syncs, 0);

      // Hydration lands: a saved, enabled integration for a server this profile
      // has. Nothing else happens — no profile switch, no reload, no tap.
      enabled = {'server_1'};
      hydration.complete();
      await pumpEventQueue();

      expect(importer.syncs, 1, reason: 'exactly one import, unprompted');
      expect(factoryProfiles, ['p1'], reason: 'bound to this profile and no other');
      expect(service.buildCalls, 2, reason: 'the personalized rows are rebuilt once, with the server in scope');
      expect(aggregation.hubCalls, 1, reason: 'no hub refetch');
      expect(aggregation.onDeckCalls, 1, reason: 'no continue-watching refetch');

      // A second load does not re-import: the rows now match the enabled set.
      await p.load();
      await pumpEventQueue();
      expect(importer.syncs, 2, reason: 'one pass per load, never two');
      expect(service.buildCalls, 3, reason: 'nothing new and nothing out of date, so no extra rebuild');
    });

    test('without a recommendation service the feed behaves exactly as before', () async {
      aggregation.onDeckResult = () => [_item('a')];
      aggregation.hubsResult = () => [_hub('hub-1')];
      await provider.load();
      await Future<void>.delayed(Duration.zero);
      expect(provider.hubs.map((h) => h.id), ['hub-1']);
      expect(aggregation.hubCalls, 1);
    });
  });
}
