import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../mixins/event_aware.dart';
import '../services/settings_service.dart';
import '../services/data_aggregation_service.dart';
import '../services/discover_snapshot.dart';
import '../services/local_folder_client.dart';
import '../services/recommendations/recommendation_service.dart';
import '../utils/app_logger.dart';
import '../utils/error_message_utils.dart';
import '../utils/global_key_utils.dart';
import '../utils/watch_state_notifier.dart';
import 'discover/continue_watching_row.dart';
import 'discover/discover_hubs.dart';
import 'discover/recommendation_rows.dart';
import 'discover_refresh_policy.dart';
import 'hidden_libraries_provider.dart';
import 'libraries_provider.dart';
import 'multi_server_provider.dart';

enum DiscoverLoadState { initial, loading, loaded, error }

/// Owns the Discover tab's data: the Continue Watching row and the home hub
/// list, including the refresh policy that used to live in the screen —
/// watch events refresh only Continue Watching (one on-deck call, zero hub
/// refetches), hidden-library changes trigger a full reload, library-order
/// changes re-sort hubs in place without refetching, and the platform
/// launcher shelf syncs from every on-deck update.
///
/// Lives inside the profile-keyed provider subtree, so a profile switch
/// resets it by construction. The screen is a consumer: it renders this
/// state and keeps only UI concerns (hero carousel, focus, spotlight).
class DiscoverProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  /// Continue Watching preview cap; see [ContinueWatchingRow.previewLimit].
  static const int continueWatchingPreviewLimit = ContinueWatchingRow.previewLimit;

  DiscoverProvider(
    this._multiServer,
    this._hiddenLibraries,
    this._libraries, {
    required this.isProfileBinding,
    this.recommendations,
    DateTime Function()? now,
  }) : _refreshPolicy = DiscoverRefreshPolicy(now: now) {
    // Late server connects (reconnect after outage, slow wave) refresh
    // discover the same way they refresh libraries. Removed in [dispose] so a
    // profile switch can't leave a stale listener on the app-global provider.
    _multiServer.addOnlineServersListener(syncToOnlineServers);
    _hiddenLibraries.addListener(_onHiddenLibrariesChanged);
    _lastSeenLibraryOrderKeys = _libraryOrderKeys();
    _libraries.addListener(_onLibrariesChanged);
    _watchStateSubscription = subscribeToHierarchicalEvents<WatchStateEvent>(
      notifier: WatchStateNotifier(),
      mounted: () => !isDisposed,
      serverId: () => null,
      globalKeys: () => _continueWatching.watchedGlobalKeys,
      itemIds: () => _continueWatching.watchedIds,
      onEvent: _continueWatching.onWatchStateChanged,
    );
  }

  final MultiServerProvider _multiServer;
  final HiddenLibrariesProvider _hiddenLibraries;
  final LibrariesProvider _libraries;

  /// Whether the profile binder is still wiring servers — a no-servers load
  /// during binding stays in the loading state instead of flashing an error
  /// (main_screen primes another load once binding settles).
  final bool Function() isProfileBinding;

  /// Optional on-device personalization. Null in tests and when no profile is
  /// bound; when present it supplies "Top Picks"/"Because you like…" rows,
  /// built off the counted aggregation paths so the fetch contract holds.
  final RecommendationService? recommendations;

  late final ContinueWatchingRow _continueWatching = ContinueWatchingRow(
    multiServer: _multiServer,
    hiddenLibraries: _hiddenLibraries,
    isDisposed: () => isDisposed,
    notify: safeNotifyListeners,
  );

  /// Seed and personalized rows. Kept outside [_hubs] so library-order
  /// sorting, delta merges, and hub filtering can't touch them.
  late final RecommendationRows _recommendationRows = RecommendationRows(
    recommendations: recommendations,
    multiServer: _multiServer,
    feed: () => (onDeck: _onDeck, latestShowsHub: _latestShowsHub, hubs: _hubs),
    generation: () => _loadGeneration,
    isDisposed: () => isDisposed,
    notify: safeNotifyListeners,
  );

  StreamSubscription<WatchStateEvent>? _watchStateSubscription;
  final DiscoverRefreshPolicy _refreshPolicy;

  List<MediaHub> _hubs = [];

  /// Newest *released* movies for the home hero — release-date ordered, never
  /// watch-progress or added-date ordered. Refreshed only by a full [load]
  /// (it's a global "newest films" list; delta merges skip it).
  List<MediaItem> _latestMovies = [];

  /// "Recently Added Shows" row, synthesised as a hub so the home-layout
  /// screen can hide/reorder it like any other row. Held outside [_hubs] for
  /// the same reason as the recommendation rows.
  MediaHub? _latestShowsHub;

  DiscoverLoadState _onDeckState = DiscoverLoadState.initial;
  DiscoverLoadState _hubsState = DiscoverLoadState.initial;
  String? _errorMessage;
  int _loadGeneration = 0;

  Set<String> _lastSeenHiddenKeys = {};
  List<String> _lastSeenLibraryOrderKeys = const [];

  /// Online servers whose home-hub fetch succeeded in the current hub list.
  Set<String> _loadedHubServerIds = {};

  Set<String> get _fullyLoadedServerIds => _continueWatching.loadedServerIds.intersection(_loadedHubServerIds);

  Future<void>? _inFlightLoad;
  bool _hasPendingLoad = false;

  /// The pass in flight came from [refreshIfStale]: no refresh indicator and
  /// no hero reset. A [load] arriving mid-pass clears it.
  bool _silentPass = false;

  /// What [loadGeneration] reports; not bumped by silent passes.
  int _visibleLoadGeneration = 0;

  /// Newly-online servers queued for a delta pass — fetched and merged
  /// without repeating the full multi-server fan-out.
  final Set<String> _pendingDeltaServerIds = {};

  List<MediaItem> get _onDeck => _continueWatching.items;

  List<MediaItem> get onDeck => _onDeck;
  List<MediaItem> get latestMovies => _latestMovies;
  List<MediaHub> get hubs {
    final seedHubs = _recommendationRows.seedHubs;
    final personalizedHubs = _recommendationRows.personalizedHubs;
    return (seedHubs.isEmpty && personalizedHubs.isEmpty && _latestShowsHub == null)
        ? _hubs
        : [?_latestShowsHub, ...seedHubs, ...personalizedHubs, ..._hubs];
  }

  bool get hasMoreContinueWatching => _continueWatching.hasMore;

  /// Online servers whose hub or Continue Watching fetch has not succeeded in
  /// the current load — the `failedServerIds` the fase-6 discovery projection
  /// needs (hoofdstuk 21.4 and 41 of docs/tvos-unified-experience.md).
  ///
  /// It has to be published rather than derived by the projection, because a
  /// server that failed contributed no hub at all: it left no trace in [hubs]
  /// for anything downstream to notice it was ever expected. This provider is
  /// the only place that knows both halves — who was asked, and who answered.
  Set<String> get unansweredServerIds => _multiServer.onlineServerIds.toSet().difference(_fullyLoadedServerIds);

  /// Localized, display-ready load failure — already run through
  /// [friendlyError], never the raw exception. The screen shows it as-is.
  String? get errorMessage => _errorMessage;

  /// True until the first on-deck result (or error) of a [load] pass lands.
  bool get isLoading => _onDeckState == DiscoverLoadState.initial || _onDeckState == DiscoverLoadState.loading;

  bool get areHubsLoading => _hubsState == DiscoverLoadState.initial || _hubsState == DiscoverLoadState.loading;

  /// True while a load pass is in flight. Unlike [isLoading] this also covers
  /// the refresh-with-content-on-screen case, where the states deliberately
  /// stay `loaded` so the rows aren't swapped for a skeleton — leaving the
  /// header's refresh action as the only place that can show progress.
  bool get isRefreshing => _inFlightLoad != null && !_silentPass;

  /// Bumped each time a [load] pass replaces the on-deck list. The screen
  /// uses this to distinguish "full reload — reset the hero carousel" from
  /// a background Continue Watching refresh (clamp only). A silent
  /// [refreshIfStale] pass counts as background.
  int get loadGeneration => _visibleLoadGeneration;

  /// Refresh when a server comes online *mid-session* (reconnect, late wave) —
  /// its hubs and continue-watching rows are otherwise missing until a manual
  /// refresh. During profile binding this is a no-op: servers bind in waves
  /// and main_screen primes one [load] when binding settles, so reacting to
  /// each wave would multiply the (expensive) hub fan-out at startup.
  ///
  /// Once a full pass has loaded, only the genuinely new servers are fetched
  /// and merged in; already-loaded servers are not refetched.
  Future<void> syncToOnlineServers(Set<String> onlineServerIds) {
    if (onlineServerIds.isEmpty || isProfileBinding()) return Future<void>.value();
    if (_onDeckState == DiscoverLoadState.loaded &&
        _hubsState == DiscoverLoadState.loaded &&
        _fullyLoadedServerIds.containsAll(onlineServerIds)) {
      return Future<void>.value();
    }
    // Nothing (or a failed pass) to merge into yet — run the full load.
    if (_onDeckState != DiscoverLoadState.loaded || _hubsState != DiscoverLoadState.loaded) return load();
    _pendingDeltaServerIds.addAll(onlineServerIds.difference(_fullyLoadedServerIds));
    return _ensureLoadLoop();
  }

  /// Full load of Continue Watching + hubs. Concurrent calls coalesce into
  /// the in-flight pass plus at most one trailing pass (so a request that
  /// arrives mid-load still observes its own fresh fetch).
  Future<void> load() {
    _silentPass = false;
    _hasPendingLoad = true;
    return _ensureLoadLoop();
  }

  Future<void> _ensureLoadLoop() {
    final inFlight = _inFlightLoad;
    if (inFlight != null) return inFlight;
    // Both edges of [isRefreshing] notify explicitly. The clear runs in
    // whenComplete, i.e. after the pass's own final notify, so without this a
    // finished refresh would keep listeners showing it as still running until
    // something else happened to rebuild them.
    final load = _runLoadLoop().whenComplete(() {
      _inFlightLoad = null;
      _silentPass = false;
      _notifyRefreshingChanged();
    });
    _inFlightLoad = load;
    _notifyRefreshingChanged();
    return load;
  }

  /// Deferred by a microtask: [load] is called from the screen's `initState`,
  /// and notifying there would mark listening widgets dirty mid-build.
  void _notifyRefreshingChanged() => scheduleMicrotask(safeNotifyListeners);

  Future<void> _runLoadLoop() async {
    while ((_hasPendingLoad || _pendingDeltaServerIds.isNotEmpty) && !isDisposed) {
      if (_hasPendingLoad) {
        _hasPendingLoad = false;
        _pendingDeltaServerIds.clear(); // a full pass covers every server
        await _loadOnce();
      } else {
        final ids = Set<String>.of(_pendingDeltaServerIds);
        _pendingDeltaServerIds.clear();
        await _loadDeltaOnce(ids);
      }
    }
  }

  Future<void> _loadOnce() async {
    // Yield to the microtask queue before the first notify so a load()
    // kicked off during build (the screen's initState) doesn't mark
    // listening widgets dirty mid-build.
    await null;
    appLogger.d('DiscoverProvider: loading content from all servers');
    await _tryApplySnapshot();
    // With a snapshot on screen, stay in the loaded state during the network
    // refresh — flipping to loading would swap the rows for a skeleton. A
    // silent pass never flips, even over an empty Home, and leaves an error
    // message up until it succeeds.
    final audit = DiscoverPassAudit(silent: _silentPass, asked: _askedServerIds);
    final showingSnapshot = audit.silent || _onDeck.isNotEmpty || _hubs.isNotEmpty;
    if (!showingSnapshot) {
      _onDeckState = DiscoverLoadState.loading;
      _hubsState = DiscoverLoadState.loading;
    }
    if (!audit.silent) _errorMessage = null;
    safeNotifyListeners();

    try {
      if (!_multiServer.hasConnectedServers) {
        if (isProfileBinding()) return;
        throw Exception('No servers available');
      }

      await _hiddenLibraries.ensureInitialized();
      if (isDisposed) return;
      _lastSeenHiddenKeys = Set.of(_hiddenLibraries.hiddenLibraryKeys);

      final settings = await SettingsService.getInstance();
      final useGlobalHubs = settings.read(SettingsService.useGlobalHubs);
      final aggregation = _multiServer.aggregationService;

      // On-deck and hubs fetch in parallel; on-deck is published as soon as
      // it lands so the hero renders while hubs are still loading.
      final onDeckFuture = _continueWatching.fetch();
      final hubsFuture = aggregation.getHubsFromAllServers(
        hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
        useGlobalHubs: useGlobalHubs,
        includePlaybackHubs: false,
      );
      // Newest released films for the hero — fetched in parallel, awaited
      // separately so the hero renders as soon as it lands.
      final latestMoviesFuture = aggregation.getLatestMoviesFromAllServers(
        limit: 12,
        hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      );

      final latestShowsFuture = aggregation.getLatestShowsFromAllServers(
        limit: 12,
        hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      );

      final fetchedOnDeck = await onDeckFuture;
      if (isDisposed) return;
      if (!audit.keepOld(fetchedOnDeck.succeededServerIds, 'continue watching')) {
        _continueWatching.apply(fetchedOnDeck.items);
        _continueWatching.loadedServerIds = fetchedOnDeck.succeededServerIds;
      }
      _onDeckState = DiscoverLoadState.loaded;
      _loadGeneration++;
      if (!_silentPass) _visibleLoadGeneration++;
      safeNotifyListeners();
      unawaited(_continueWatching.syncShelf());

      final fetchedLatestMovies = await latestMoviesFuture;
      if (isDisposed) return;
      if (!audit.keepOld(fetchedLatestMovies.succeededServerIds, 'latest movies')) {
        _latestMovies = fetchedLatestMovies.items;
      }
      safeNotifyListeners();

      final fetchedLatestShows = await latestShowsFuture;
      if (isDisposed) return;
      if (!audit.keepOld(fetchedLatestShows.succeededServerIds, 'latest shows')) {
        _latestShowsHub = buildLatestShowsHub(fetchedLatestShows.items);
      }
      safeNotifyListeners();

      final fetchedHubs = await hubsFuture;
      if (isDisposed) return;
      if (audit.keepOld(fetchedHubs.succeededServerIds, 'hubs')) return;

      final filteredHubs = filterDiscoverHubs(fetchedHubs.hubs);
      orderDiscoverHubs(filteredHubs, _libraries.libraries);

      appLogger.d('DiscoverProvider: ${_onDeck.length} on-deck items, ${filteredHubs.length} hubs');
      _hubs = dedupeDiscoverHubs(filteredHubs, _onDeck);
      _hubsState = DiscoverLoadState.loaded;
      _errorMessage = null;
      _loadedHubServerIds = fetchedHubs.succeededServerIds;
      if (audit.complete) _refreshPolicy.markFullLoad();
      safeNotifyListeners();
      // Refreshed on silent passes too: the rows keep what they showed on a
      // failure and never refetch a hub, and new titles and watch history are
      // exactly what they are built from.
      unawaited(_recommendationRows.load());
      unawaited(
        DiscoverSnapshot(
          onDeck: _onDeck,
          hubs: _hubs,
          latestMovies: _latestMovies,
        ).save().catchError((Object e) => appLogger.w('DiscoverProvider: snapshot save failed', error: e)),
      );
    } catch (e) {
      appLogger.e('Failed to load discover content', error: e);
      if (isDisposed) return;
      if (showingSnapshot) return; // Stale snapshot rows beat an error flash.
      _errorMessage = friendlyError(e, context: t.discover.title);
      _onDeckState = DiscoverLoadState.error;
      _hubsState = DiscoverLoadState.error;
      safeNotifyListeners();
    }
  }

  bool _snapshotChecked = false;

  /// Cold-start path: publish the previous session's persisted home payload
  /// before any network fetch so rows and posters (already in the image disk
  /// cache) render instantly. Runs at most once, and only while nothing has
  /// loaded yet.
  Future<void> _tryApplySnapshot() async {
    if (_snapshotChecked) return;
    _snapshotChecked = true;
    if (_onDeckState != DiscoverLoadState.initial || _onDeck.isNotEmpty || _hubs.isNotEmpty) return;
    final snapshot = await DiscoverSnapshot.load();
    if (snapshot == null || isDisposed) return;
    if (snapshot.onDeck.isEmpty && snapshot.hubs.isEmpty) return;
    appLogger.d('DiscoverProvider: showing snapshot (${snapshot.onDeck.length} on-deck, ${snapshot.hubs.length} hubs)');
    _continueWatching.apply(snapshot.onDeck);
    _hubs = snapshot.hubs;
    _latestMovies = snapshot.latestMovies;
    _onDeckState = DiscoverLoadState.loaded;
    _hubsState = DiscoverLoadState.loaded;
    _loadGeneration++;
    _visibleLoadGeneration++;
    safeNotifyListeners();
  }

  /// Fetch Continue Watching + hubs from [serverIds] only (servers that came
  /// online after the last full pass) and merge them into the loaded state.
  /// Failures keep the loaded state and leave the ids un-loaded, so the next
  /// status emission retries them.
  Future<void> _loadDeltaOnce(Set<String> serverIds) async {
    // A full pass may have covered these ids while they sat in the queue.
    final ids = serverIds.difference(_fullyLoadedServerIds);
    final onDeckIds = ids.difference(_continueWatching.loadedServerIds);
    final hubIds = ids.difference(_loadedHubServerIds);
    if (onDeckIds.isEmpty && hubIds.isEmpty) return;
    appLogger.d('DiscoverProvider: merging content from newly-online servers $ids (onDeck=$onDeckIds, hubs=$hubIds)');

    try {
      await _hiddenLibraries.ensureInitialized();
      if (isDisposed) return;

      final settings = await SettingsService.getInstance();
      final useGlobalHubs = settings.read(SettingsService.useGlobalHubs);

      final Future<OnDeckAggregationResult?> onDeckFuture = onDeckIds.isEmpty
          ? Future<OnDeckAggregationResult?>.value()
          : _continueWatching.fetch(serverIds: onDeckIds);
      final Future<HubAggregationResult?> hubsFuture = hubIds.isEmpty
          ? Future<HubAggregationResult?>.value()
          : _multiServer.aggregationService.getHubsFromAllServers(
              hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
              useGlobalHubs: useGlobalHubs,
              includePlaybackHubs: false,
              serverIds: hubIds,
            );

      final freshOnDeck = await onDeckFuture;
      final freshHubs = await hubsFuture;
      if (isDisposed) return;

      // No _loadGeneration bump: a delta behaves like the background Continue
      // Watching refresh (the hero clamps instead of resetting).
      if (freshOnDeck != null && !await _continueWatching.merge(freshOnDeck)) return;

      if (freshHubs != null) {
        final succeededHubIds = freshHubs.succeededServerIds;
        _hubs = mergeServerHubs(
          _hubs,
          freshHubs.hubs,
          succeededHubIds,
          libraries: _libraries.libraries,
          onDeck: _onDeck,
        );
        _loadedHubServerIds = {..._loadedHubServerIds, ...succeededHubIds};
      }

      appLogger.d('DiscoverProvider: ${_onDeck.length} on-deck items, ${_hubs.length} hubs after merging $ids');
      safeNotifyListeners();
      unawaited(_continueWatching.syncShelf());
      // A reconnected server can add items that now duplicate (or should feed)
      // the recommendation rows; rebuild them against the merged state.
      unawaited(_recommendationRows.load());
    } catch (e) {
      // Keep the loaded state — stale rows beat an error flash.
      appLogger.w('DiscoverProvider: delta load failed for $ids', error: e);
    }
  }

  /// Background refresh of Continue Watching only — never flips load states
  /// or surfaces errors (a stale row beats an error flash), never refetches
  /// hubs.
  Future<void> refreshContinueWatching() => _continueWatching.refresh();

  /// Home's return/resume/timer refresh: a silent full reload when the rows
  /// are older than [maxAge], otherwise only Continue Watching. Silent means
  /// the states stay `loaded`, [isRefreshing] stays false and a server that
  /// does not answer leaves its rows on screen. A pass already in flight is
  /// joined, never doubled. [rescanLocalFolders] also invalidates the
  /// local-folder scans; it costs a full listing, so only the return and
  /// resume paths ask for it.
  Future<void> refreshIfStale({Duration maxAge = kHomeRefreshInterval, bool rescanLocalFolders = false}) {
    final inFlight = _inFlightLoad;
    if (inFlight != null) return inFlight;
    if (!_refreshPolicy.isStale(maxAge, hasContent: _hubsState == DiscoverLoadState.loaded)) {
      return refreshContinueWatching();
    }
    if (rescanLocalFolders) LocalFolderClient.invalidateAllScans(_multiServer.serverManager.onlineClients.values);
    _silentPass = true;
    _hasPendingLoad = true;
    return _ensureLoadLoop();
  }

  /// The servers a full pass asks: the aggregation's own set.
  Set<String> _askedServerIds() {
    final manager = _multiServer.serverManager;
    return {
      for (final id in manager.onlineClients.keys)
        if (manager.isServerVisible(ServerId(id))) id,
    };
  }

  /// The full unlimited Continue Watching list for the hub's load-more path.
  Future<List<MediaItem>> loadAllContinueWatching() => _continueWatching.loadAll();

  /// Refetch a single item (post-edit refresh, or a return from the player)
  /// and swap it into whichever lists hold it.
  ///
  /// [serverId] is what makes this safe on more than one server. A backend
  /// item id is only unique *within* its server — two Plex servers both
  /// number their rating keys from 1 — so resolving the owner by scanning
  /// for a bare id match picks whichever list happens to hold that id first.
  /// On a single server that is always the right one; on two it silently
  /// refetches an unrelated title from the wrong server and swaps it into
  /// the row. Every surface that fans over servers therefore passes the
  /// owner, and the match is on [MediaItem.globalKey] — the same
  /// server-qualified key the unified catalog uses throughout.
  ///
  /// Without [serverId] the old bare-id behaviour remains, for the
  /// single-source callers that have no server to give.
  Future<void> updateItem(String itemId, {String? serverId}) async {
    try {
      final ownerId = serverId ?? serverIdForItem(itemId, _onDeck, _hubs);
      if (ownerId == null) return;
      final key = buildGlobalKey(ServerId(ownerId), itemId);
      final updated = await _multiServer.getClientForServer(ServerId(ownerId))?.fetchItem(itemId);
      if (updated == null || isDisposed) return;
      _updateItemInLists(itemId, updated, globalKey: serverId == null ? null : key);
      safeNotifyListeners();
    } catch (_) {
      // Silently fail — the item will refresh on the next full reload.
    }
  }

  void _updateItemInLists(String itemId, MediaItem updatedItem, {String? globalKey}) {
    bool matches(MediaItem item) => globalKey == null ? item.id == itemId : item.globalKey == globalKey;

    _continueWatching.replaceWhere(matches, updatedItem);
    _hubs = replaceItemInHubs(_hubs, matches, updatedItem);
  }

  // --- Event reactions -----------------------------------------------------

  void _onHiddenLibrariesChanged() {
    final currentKeys = _hiddenLibraries.hiddenLibraryKeys;
    if (currentKeys.length == _lastSeenHiddenKeys.length && currentKeys.containsAll(_lastSeenHiddenKeys)) {
      return;
    }
    _lastSeenHiddenKeys = Set.of(currentKeys);
    unawaited(load());
  }

  void _onLibrariesChanged() {
    final currentKeys = _libraryOrderKeys();
    if (listEquals(currentKeys, _lastSeenLibraryOrderKeys)) return;
    _lastSeenLibraryOrderKeys = currentKeys;
    if (_hubs.isEmpty) return;

    final sortedHubs = reorderDiscoverHubs(_hubs, _libraries.libraries);
    if (sortedHubs == null) return;
    _hubs = sortedHubs;
    safeNotifyListeners();
  }

  List<String> _libraryOrderKeys() => [for (final library in _libraries.libraries) library.globalKey];

  /// The Home hero's films, in slide order, for the Top Shelf carousel.
  /// `TvHomeProjectionProvider` pushes them after each projection, so the
  /// shelf shows exactly what the billboard rotates over. Resyncs on change.
  void setTopShelfHero(List<MediaItem> hero) => _continueWatching.setTopShelfHero(hero);

  @override
  void dispose() {
    _multiServer.removeOnlineServersListener(syncToOnlineServers);
    _hiddenLibraries.removeListener(_onHiddenLibrariesChanged);
    _libraries.removeListener(_onLibrariesChanged);
    _watchStateSubscription?.cancel();
    _watchStateSubscription = null;
    _continueWatching.dispose();
    super.dispose();
  }
}
