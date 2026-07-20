import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../mixins/event_aware.dart';
import '../services/settings_service.dart';
import '../services/data_aggregation_service.dart';
import '../services/discover_snapshot.dart';
import '../services/recommendations/hub_dedup.dart';
import '../services/recommendations/recommendation_service.dart';
import '../services/system_shelf_service.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import '../utils/media_hub_ordering.dart';
import '../utils/watch_state_notifier.dart';
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
  /// Preview row caps at 20; one extra item is fetched as a probe so
  /// [hasMoreContinueWatching] can show the "more" affordance without a
  /// second request.
  static const int continueWatchingPreviewLimit = 20;
  static const int _continueWatchingProbeLimit = continueWatchingPreviewLimit + 1;

  DiscoverProvider(
    this._multiServer,
    this._hiddenLibraries,
    this._libraries, {
    required this.isProfileBinding,
    this.recommendations,
  }) {
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
      globalKeys: () => _watchedGlobalKeys,
      itemIds: () => _watchedIds,
      onEvent: _onWatchStateChanged,
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

  StreamSubscription<WatchStateEvent>? _watchStateSubscription;

  List<MediaItem> _onDeck = [];
  List<MediaHub> _hubs = [];

  /// Newest *released* movies for the home hero — release-date ordered, never
  /// watch-progress or added-date ordered. Refreshed only by a full [load]
  /// (it's a global "newest films" list; delta merges skip it).
  List<MediaItem> _latestMovies = [];

  /// Global keys of watched movies filtered out of every on-deck apply until
  /// the server stops returning them — beats the scrobble race
  /// deterministically (see [_onWatchStateChanged] / [_applyOnDeck]).
  final Set<String> _suppressedOnDeckKeys = {};

  /// "Because you watched X" recommendation rows (up to 3, one per recent
  /// seed). Kept outside [_hubs] so library-order sorting, delta merges, and
  /// hub filtering can't touch them.
  List<MediaHub> _seedHubs = [];

  /// On-device personalized rows (Top Picks, Because you like…, Hidden Gems).
  /// Like [_seedHubs], held outside [_hubs] and recomputed only on full loads.
  List<MediaHub> _personalizedHubs = [];
  bool _hasMoreContinueWatching = false;
  DiscoverLoadState _onDeckState = DiscoverLoadState.initial;
  DiscoverLoadState _hubsState = DiscoverLoadState.initial;
  String? _errorMessage;
  int _loadGeneration = 0;

  Set<String> _lastSeenHiddenKeys = {};
  List<String> _lastSeenLibraryOrderKeys = const [];

  /// Online servers whose Continue Watching fetch succeeded in the current
  /// on-deck list. Tracked separately from hubs so a transient failure in one
  /// surface does not cache the other as loaded forever or force unnecessary
  /// refetches.
  Set<String> _loadedOnDeckServerIds = {};

  /// Online servers whose home-hub fetch succeeded in the current hub list.
  Set<String> _loadedHubServerIds = {};

  Set<String> get _fullyLoadedServerIds => _loadedOnDeckServerIds.intersection(_loadedHubServerIds);

  Future<void>? _inFlightLoad;
  bool _hasPendingLoad = false;

  /// Newly-online servers queued for a delta pass — fetched and merged
  /// without repeating the full multi-server fan-out.
  final Set<String> _pendingDeltaServerIds = {};

  Future<void>? _systemShelfSyncFuture;
  List<MediaItem>? _pendingSystemShelfItems;

  List<MediaItem> get onDeck => _onDeck;
  List<MediaItem> get latestMovies => _latestMovies;
  List<MediaHub> get hubs =>
      (_seedHubs.isEmpty && _personalizedHubs.isEmpty) ? _hubs : [..._seedHubs, ..._personalizedHubs, ..._hubs];
  bool get hasMoreContinueWatching => _hasMoreContinueWatching;

  /// Raw load failure (unlocalized); the screen wraps it for display.
  String? get errorMessage => _errorMessage;

  /// True until the first on-deck result (or error) of a [load] pass lands.
  bool get isLoading => _onDeckState == DiscoverLoadState.initial || _onDeckState == DiscoverLoadState.loading;

  bool get areHubsLoading => _hubsState == DiscoverLoadState.initial || _hubsState == DiscoverLoadState.loading;

  /// Bumped each time a [load] pass replaces the on-deck list. The screen
  /// uses this to distinguish "full reload — reset the hero carousel" from
  /// a background Continue Watching refresh (clamp only).
  int get loadGeneration => _loadGeneration;

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
    _hasPendingLoad = true;
    return _ensureLoadLoop();
  }

  Future<void> _ensureLoadLoop() => _inFlightLoad ??= _runLoadLoop().whenComplete(() => _inFlightLoad = null);

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
    // refresh — flipping to loading would swap the rows for a skeleton.
    final showingSnapshot = _onDeck.isNotEmpty || _hubs.isNotEmpty;
    if (!showingSnapshot) {
      _onDeckState = DiscoverLoadState.loading;
      _hubsState = DiscoverLoadState.loading;
    }
    _errorMessage = null;
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
      final onDeckFuture = aggregation.getOnDeckFromAllServers(
        limit: _continueWatchingProbeLimit,
        hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      );
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

      final fetchedOnDeck = await onDeckFuture;
      if (isDisposed) return;
      _applyOnDeck(fetchedOnDeck.items);
      _onDeckState = DiscoverLoadState.loaded;
      _loadedOnDeckServerIds = fetchedOnDeck.succeededServerIds;
      _loadGeneration++;
      safeNotifyListeners();
      unawaited(_syncSystemShelf(_onDeck));

      final fetchedLatestMovies = await latestMoviesFuture;
      if (isDisposed) return;
      _latestMovies = fetchedLatestMovies.items;
      safeNotifyListeners();

      final fetchedHubs = await hubsFuture;
      if (isDisposed) return;

      final filteredHubs = _filterDiscoverHubs(fetchedHubs.hubs);
      _orderDiscoverHubs(filteredHubs);

      appLogger.d('DiscoverProvider: ${_onDeck.length} on-deck items, ${filteredHubs.length} hubs');
      _hubs = _dedupeDiscoverHubs(filteredHubs);
      _hubsState = DiscoverLoadState.loaded;
      _loadedHubServerIds = fetchedHubs.succeededServerIds;
      safeNotifyListeners();
      unawaited(_loadRecommendationRows());
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
      _errorMessage = e.toString();
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
    _applyOnDeck(snapshot.onDeck);
    _hubs = snapshot.hubs;
    _latestMovies = snapshot.latestMovies;
    _onDeckState = DiscoverLoadState.loaded;
    _hubsState = DiscoverLoadState.loaded;
    _loadGeneration++;
    safeNotifyListeners();
  }

  /// Fetch Continue Watching + hubs from [serverIds] only (servers that came
  /// online after the last full pass) and merge them into the loaded state.
  /// Failures keep the loaded state and leave the ids un-loaded, so the next
  /// status emission retries them.
  Future<void> _loadDeltaOnce(Set<String> serverIds) async {
    // A full pass may have covered these ids while they sat in the queue.
    final ids = serverIds.difference(_fullyLoadedServerIds);
    final onDeckIds = ids.difference(_loadedOnDeckServerIds);
    final hubIds = ids.difference(_loadedHubServerIds);
    if (onDeckIds.isEmpty && hubIds.isEmpty) return;
    appLogger.d('DiscoverProvider: merging content from newly-online servers $ids (onDeck=$onDeckIds, hubs=$hubIds)');

    try {
      await _hiddenLibraries.ensureInitialized();
      if (isDisposed) return;

      final settings = await SettingsService.getInstance();
      final useGlobalHubs = settings.read(SettingsService.useGlobalHubs);
      final aggregation = _multiServer.aggregationService;

      final Future<OnDeckAggregationResult?> onDeckFuture = onDeckIds.isEmpty
          ? Future<OnDeckAggregationResult?>.value()
          : aggregation.getOnDeckFromAllServers(
              limit: _continueWatchingProbeLimit,
              hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
              serverIds: onDeckIds,
            );
      final Future<HubAggregationResult?> hubsFuture = hubIds.isEmpty
          ? Future<HubAggregationResult?>.value()
          : aggregation.getHubsFromAllServers(
              hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
              useGlobalHubs: useGlobalHubs,
              includePlaybackHubs: false,
              serverIds: hubIds,
            );

      final freshOnDeck = await onDeckFuture;
      final freshHubs = await hubsFuture;
      if (isDisposed) return;

      if (freshOnDeck != null) {
        final hadMore = _hasMoreContinueWatching;
        final mergedOnDeck = await aggregation.mergeContinueWatching(
          _onDeck,
          freshOnDeck.items,
          limit: _continueWatchingProbeLimit,
        );
        if (isDisposed) return;
        _applyOnDeck(mergedOnDeck);
        // The stored list is already trimmed, so the merge can't see old items
        // past the cap — a previously-true "more" affordance stays true.
        if (hadMore) _hasMoreContinueWatching = true;
        _loadedOnDeckServerIds = {..._loadedOnDeckServerIds, ...freshOnDeck.succeededServerIds};
        // No _loadGeneration bump: a delta behaves like the background Continue
        // Watching refresh (the hero clamps instead of resetting).
      }

      if (freshHubs != null) {
        final succeededHubIds = freshHubs.succeededServerIds;
        final mergedHubs = [
          ..._hubs.where((hub) => hub.serverId == null || !succeededHubIds.contains(hub.serverId)),
          ..._filterDiscoverHubs(freshHubs.hubs),
        ];
        _orderDiscoverHubs(mergedHubs);
        _hubs = _dedupeDiscoverHubs(mergedHubs);
        _loadedHubServerIds = {..._loadedHubServerIds, ...succeededHubIds};
      }

      appLogger.d('DiscoverProvider: ${_onDeck.length} on-deck items, ${_hubs.length} hubs after merging $ids');
      safeNotifyListeners();
      unawaited(_syncSystemShelf(_onDeck));
      // A reconnected server can add items that now duplicate (or should feed)
      // the recommendation rows; rebuild them against the merged state.
      unawaited(_loadRecommendationRows());
    } catch (e) {
      // Keep the loaded state — stale rows beat an error flash.
      appLogger.w('DiscoverProvider: delta load failed for $ids', error: e);
    }
  }

  /// Build up to three "Because you watched X" rows from the most recently
  /// watched, distinct titles across all online servers, each paired with its
  /// related hub on the owning server. Fully fault-tolerant: any failure or
  /// empty step simply leaves rows out (or keeps the previous set). Recomputed
  /// on full loads only, entirely off the counted aggregation paths.
  /// Runs the two post-load recommendation surfaces in order: seed rows first
  /// so the personalized rows below them can exclude the seed items (both read
  /// `_seedHubs`/`_hubs`), avoiding the same title appearing in adjacent rows.
  Future<void> _loadRecommendationRows() async {
    try {
      await _loadBecauseYouWatched();
    } catch (e) {
      appLogger.w('DiscoverProvider: seed rows failed', error: e);
    }
    await _loadPersonalizedRows();
  }

  Future<void> _loadBecauseYouWatched() async {
    try {
      final clients = _multiServer.serverManager.onlineClients.values.toList();
      if (clients.isEmpty) return;
      final generation = _loadGeneration;
      // Don't re-surface items already shown in Continue Watching or the hubs.
      final alreadyShown = <String>{
        for (final item in _onDeck) item.globalKey,
        for (final hub in _hubs)
          for (final item in hub.items) item.globalKey,
      };
      final recents = await Future.wait([
        for (final client in clients)
          client.fetchRecentlyWatched(limit: 5).catchError((Object _) => const <MediaItem>[]),
      ]);

      // Most-recent-first, then keep up to 3 distinct show/movie seeds so the
      // rows don't all come from the same binge.
      final merged = recents.expand((items) => items).toList()
        ..sort((a, b) => b.recencySortKey.compareTo(a.recencySortKey));
      final seeds = <MediaItem>[];
      final usedIdentities = <String>{};
      for (final item in merged) {
        if (item.serverId == null || item.title == null) continue;
        final identity = (item.grandparentTitle ?? item.title ?? item.id).toLowerCase();
        if (!usedIdentities.add(identity)) continue;
        seeds.add(item);
        if (seeds.length >= 3) break;
      }
      final rows = seeds.isEmpty
          ? const <MediaHub?>[]
          : await Future.wait([
              for (final seed in seeds) _relatedRowForSeed(seed, alreadyShown).catchError((Object _) => null),
            ]);
      if (isDisposed || generation != _loadGeneration) return;

      final newSeedHubs = [for (final row in rows) ?row];
      // Assign even when empty so cleared history / changed watch state drops
      // stale "Because you watched…" rows instead of stranding them.
      if (_seedHubs.isEmpty && newSeedHubs.isEmpty) return;
      _seedHubs = newSeedHubs;
      safeNotifyListeners();
    } catch (e) {
      // Transient failure: keep whatever rows were already shown.
      appLogger.w('DiscoverProvider: because-you-watched rows failed (keeping previous)', error: e);
    }
  }

  /// Resolves a single "Because you watched X" row for [seed] from the owning
  /// server's related hub, or null when nothing usable comes back.
  Future<MediaHub?> _relatedRowForSeed(MediaItem seed, Set<String> alreadyShown) async {
    final serverId = seed.serverId;
    final seedTitle = seed.title;
    if (serverId == null || seedTitle == null) return null;
    final client = _multiServer.getClientForServer(ServerId(serverId));
    if (client == null) return null;
    final relatedHubs = await client.fetchRelatedHubs(seed.id);
    for (final hub in relatedHubs) {
      final items = hub.items
          .where((item) => item.globalKey != seed.globalKey && !alreadyShown.contains(item.globalKey))
          .toList();
      if (items.isEmpty) continue;
      return hub.copyWith(
        identifier: 'home.becauseyouwatched',
        title: t.discover.becauseYouWatched(title: seedTitle),
        items: items,
      );
    }
    return null;
  }

  /// Build the on-device personalized rows (Top Picks, Because you like…,
  /// Hidden Gems). No-op when personalization is unavailable/disabled. Runs
  /// post-load off the counted aggregation paths, guarded on [_loadGeneration].
  Future<void> _loadPersonalizedRows() async {
    final service = recommendations;
    if (service == null) return;
    final generation = _loadGeneration;
    try {
      final clients = _multiServer.serverManager.onlineClients.values.toList();

      // Items already on screen (Continue Watching + loaded hubs + seed rows)
      // are free candidates and, via [excludeKeys], must not be echoed by the
      // personalized rows below them.
      final onScreen = <MediaItem>[
        ..._onDeck,
        for (final hub in _hubs) ...hub.items,
        for (final hub in _seedHubs) ...hub.items,
      ];
      final excludeKeys = {for (final item in onScreen) item.globalKey};

      final rows = clients.isEmpty
          ? const <MediaHub>[]
          : await service.buildRows(clients, hubItems: onScreen, excludeKeys: excludeKeys);
      if (isDisposed || generation != _loadGeneration) return;
      // Assign even when empty so disabling personalization or losing history
      // clears any previously-shown rows instead of stranding them.
      if (_personalizedHubs.isEmpty && rows.isEmpty) return;
      _personalizedHubs = rows;
      safeNotifyListeners();
    } catch (e) {
      // Transient failure: keep whatever rows were already shown.
      appLogger.w('DiscoverProvider: personalized rows failed (keeping previous)', error: e);
    }
  }

  /// Playback-progress hubs duplicate the top Continue Watching row.
  List<MediaHub> _filterDiscoverHubs(List<MediaHub> hubs) {
    return hubs.where((hub) {
      final hubId = hub.identifier?.toLowerCase() ?? '';
      final title = hub.title.toLowerCase();
      return !hubId.contains('ondeck') &&
          !hubId.contains('continue') &&
          !hubId.contains('nextup') &&
          !title.contains('continue watching') &&
          !title.contains('on deck') &&
          !title.contains('next up');
    }).toList();
  }

  /// Background refresh of Continue Watching only — never flips load states
  /// or surfaces errors (a stale row beats an error flash), never refetches
  /// hubs.
  Future<void> refreshContinueWatching() async {
    try {
      if (!_multiServer.hasConnectedServers) return;
      final fetched = await _multiServer.aggregationService.getOnDeckFromAllServers(
        limit: _continueWatchingProbeLimit,
        hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
      );
      if (isDisposed) return;
      _applyOnDeck(fetched.items);
      _loadedOnDeckServerIds = fetched.succeededServerIds;
      safeNotifyListeners();
      unawaited(_syncSystemShelf(_onDeck));
    } catch (e) {
      appLogger.w('Failed to refresh Continue Watching', error: e);
    }
  }

  /// The full unlimited Continue Watching list for the hub's load-more path.
  Future<List<MediaItem>> loadAllContinueWatching() async {
    if (!_multiServer.hasConnectedServers) return const [];
    await _hiddenLibraries.ensureInitialized();
    if (isDisposed) return const [];
    final fetched = await _multiServer.aggregationService.getOnDeckFromAllServers(
      hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
    );
    return fetched.items;
  }

  /// Refetch a single item (post-edit refresh from a hub row) and swap it
  /// into whichever lists contain it. Items can come from any registered
  /// server, so the owning server is resolved by scanning the visible lists.
  Future<void> updateItem(String itemId) async {
    try {
      final serverId = _serverIdForItem(itemId);
      if (serverId == null) return;
      final updated = await _multiServer.getClientForServer(ServerId(serverId))?.fetchItem(itemId);
      if (updated == null || isDisposed) return;
      _updateItemInLists(itemId, updated);
      safeNotifyListeners();
    } catch (_) {
      // Silently fail — the item will refresh on the next full reload.
    }
  }

  String? _serverIdForItem(String itemId) {
    for (final item in _onDeck) {
      if (item.id == itemId) return item.serverId;
    }
    for (final hub in _hubs) {
      for (final item in hub.items) {
        if (item.id == itemId) return item.serverId;
      }
    }
    return null;
  }

  void _updateItemInLists(String itemId, MediaItem updatedItem) {
    final onDeckIndex = _onDeck.indexWhere((item) => item.id == itemId);
    if (onDeckIndex != -1) {
      _onDeck = List.of(_onDeck)..[onDeckIndex] = updatedItem;
    }

    for (var i = 0; i < _hubs.length; i++) {
      final hub = _hubs[i];
      final itemIndex = hub.items.indexWhere((item) => item.id == itemId);
      if (itemIndex != -1) {
        final newItems = List<MediaItem>.from(hub.items);
        newItems[itemIndex] = updatedItem;
        _hubs = List.of(_hubs)..[i] = hub.copyWith(items: newItems);
      }
    }
  }

  void _applyOnDeck(List<MediaItem> fetched) {
    if (_suppressedOnDeckKeys.isNotEmpty) {
      // Self-cleaning: once the server stops returning a suppressed item, its
      // scrobble has landed and the suppression is no longer needed.
      _suppressedOnDeckKeys.retainAll({for (final item in fetched) item.globalKey});
      if (_suppressedOnDeckKeys.isNotEmpty) {
        fetched = fetched.where((item) => !_suppressedOnDeckKeys.contains(item.globalKey)).toList();
      }
    }
    final hasMore = fetched.length > continueWatchingPreviewLimit;
    _onDeck = hasMore ? fetched.take(continueWatchingPreviewLimit).toList() : fetched;
    _hasMoreContinueWatching = hasMore;
  }

  // --- Event reactions -----------------------------------------------------

  /// Watch on-deck items and their parent shows/seasons (an episode's watch
  /// flip changes what Continue Watching should show for its series).
  Set<String>? get _watchedIds {
    final keys = <String>{};
    for (final item in _onDeck) {
      keys.add(item.id);
      if (item.parentId != null) keys.add(item.parentId!);
      if (item.grandparentId != null) keys.add(item.grandparentId!);
    }
    return keys;
  }

  Set<String>? get _watchedGlobalKeys {
    // Suppressed movies are no longer in _onDeck but must keep receiving
    // events: a rewatch (unwatched/progress) has to lift the suppression.
    final keys = <String>{..._suppressedOnDeckKeys};
    for (final item in _onDeck) {
      final serverId = item.serverId;
      if (serverId == null) return null;

      keys.add(buildGlobalKey(ServerId(serverId), item.id));
      if (item.parentId != null) keys.add(buildGlobalKey(ServerId(serverId), item.parentId!));
      if (item.grandparentId != null) keys.add(buildGlobalKey(ServerId(serverId), item.grandparentId!));
    }
    return keys;
  }

  void _onWatchStateChanged(WatchStateEvent event) {
    switch (event.changeType) {
      case WatchStateChangeType.removedFromContinueWatching:
        _removeFromOnDeck(event.globalKey);
      case WatchStateChangeType.watched when event.mediaType == MediaKind.movie.id && event.isNowWatched != false:
        // A finished movie leaves the row for good; suppress its key so the
        // background refetch can't race the server's scrobble processing and
        // bring it back with stale in-progress metadata. Episodes are left to
        // the refetch: the server swaps in the next episode of the series.
        _suppressedOnDeckKeys.add(event.globalKey);
        _removeFromOnDeck(event.globalKey);
      case WatchStateChangeType.unwatched:
        _suppressedOnDeckKeys.remove(event.globalKey);
      case WatchStateChangeType.progressUpdate:
        // A rewatch must resurface immediately, but a trailing near-complete
        // progress event (isNowWatched) must not undo the watched suppression.
        if (event.isNowWatched != true) _suppressedOnDeckKeys.remove(event.globalKey);
      default:
        break;
    }
    unawaited(refreshContinueWatching());
  }

  void _removeFromOnDeck(String globalKey) {
    final remaining = _onDeck.where((item) => item.globalKey != globalKey).toList();
    if (remaining.length != _onDeck.length) {
      _onDeck = remaining;
      safeNotifyListeners();
    }
  }

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

    final sortedHubs = List<MediaHub>.from(_hubs);
    // Re-order only (items are already de-duplicated); a reorder introduces no
    // new cross-row duplicates so we skip the dedup pass here.
    final byLibrary = sortMediaHubsByLibraryOrder(sortedHubs, _libraries.libraries);
    final byPriority = sortMediaHubsByPriority(sortedHubs);
    if (!byLibrary && !byPriority) return;
    _hubs = sortedHubs;
    safeNotifyListeners();
  }

  List<String> _libraryOrderKeys() => [for (final library in _libraries.libraries) library.globalKey];

  /// Orders discover hubs by library order, then lifts personalized/next-up/
  /// fresh rows toward the top via [hubPriorityClass]. Mutates in place.
  void _orderDiscoverHubs(List<MediaHub> hubs) {
    sortMediaHubsByLibraryOrder(hubs, _libraries.libraries);
    sortMediaHubsByPriority(hubs);
  }

  /// Removes cross-row duplicate items (an item shown in too many hubs), seeded
  /// with the Continue Watching keys so those aren't echoed throughout the feed.
  List<MediaHub> _dedupeDiscoverHubs(List<MediaHub> hubs) {
    final continueWatchingKeys = {for (final item in _onDeck) item.globalKey};
    return dedupeAcrossHubs(hubs, alreadyShownKeys: continueWatchingKeys);
  }

  // --- Platform launcher shelf ----------------------------------------------

  /// Sync Continue Watching to the platform launcher shelf. Rapid updates
  /// coalesce: a sync that arrives while one is in flight queues exactly one
  /// follow-up pass with the latest items.
  Future<void> _syncSystemShelf(List<MediaItem> onDeck) async {
    _pendingSystemShelfItems = List<MediaItem>.unmodifiable(onDeck);
    if (_systemShelfSyncFuture != null) {
      await _systemShelfSyncFuture;
      return;
    }

    final syncFuture = _drainSystemShelfSyncQueue();
    _systemShelfSyncFuture = syncFuture;
    await syncFuture;
  }

  Future<void> _drainSystemShelfSyncQueue() async {
    try {
      while (_pendingSystemShelfItems != null) {
        final onDeck = _pendingSystemShelfItems!;
        _pendingSystemShelfItems = null;
        if (isDisposed) return;

        try {
          final settings = await SettingsService.getInstance();
          final syncableOnDeck = onDeck
              .where((item) {
                final serverId = item.serverId;
                return serverId != null && _multiServer.getClientForServer(ServerId(serverId)) != null;
              })
              .toList(growable: false);
          await SystemShelfService().syncFromContinueWatching(
            syncableOnDeck,
            _clientForShelfItem,
            hideSpoilers: settings.read(SettingsService.hideSpoilers),
          );
        } catch (e) {
          appLogger.w('Failed to sync system shelf', error: e);
        }
      }
    } finally {
      _systemShelfSyncFuture = null;
    }
  }

  MediaServerClient _clientForShelfItem(ServerId serverId) {
    final direct = _multiServer.getClientForServer(serverId);
    if (direct != null) return direct;
    throw Exception('No owning client available for $serverId');
  }

  @override
  void dispose() {
    _multiServer.removeOnlineServersListener(syncToOnlineServers);
    _hiddenLibraries.removeListener(_onHiddenLibrariesChanged);
    _libraries.removeListener(_onLibrariesChanged);
    _watchStateSubscription?.cancel();
    _watchStateSubscription = null;
    _pendingSystemShelfItems = null;
    super.dispose();
  }
}
