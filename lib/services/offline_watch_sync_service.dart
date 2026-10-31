import 'dart:async';
import '../media/ids.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../database/download_operations.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../media/watch_progress.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import 'offline_mode_source.dart';
import 'offline_watch_replay.dart';
import 'playback_resume_resolver.dart';
import '../utils/watch_state_notifier.dart';
import 'multi_server_manager.dart';
import 'plex_client.dart';
import 'settings_service.dart';
import 'watch_state_resolver.dart';

/// Service for managing offline watch progress and syncing it back to the
/// owning server. Backend-neutral over [MediaServerClient] — Plex actions
/// hit `/:/scrobble` and `/:/timeline`, Jellyfin actions hit
/// `/UserPlayedItems/{id}` and `/Sessions/Playing*` through the same queue.
///
/// Handles:
/// - Queuing progress updates when offline
/// - Queuing manual watch/unwatch actions
/// - Auto-marking items as watched at the server's threshold
/// - Syncing queued actions when connectivity is restored
class OfflineWatchSyncService extends ChangeNotifier {
  final AppDatabase _database;
  final MultiServerManager _serverManager;

  OfflineModeSource? _offlineModeSource;
  VoidCallback? _offlineModeListener;
  bool _isSyncing = false;
  bool _syncRequested = false;
  bool _isBidirectionalSyncing = false;
  bool _isShutDown = false;

  /// A pass ended while a bind ran. Nothing else starts the next one soon: the
  /// startup sync runs once, and a TV can stay in the app for days.
  bool _stoppedForBind = false;
  DateTime? _lastSyncTime;
  bool _hasPerformedStartupSync = false;
  String? _activeProfileId;
  int? _availableProfileCount;
  final Set<String> _legacyWatchActionsAdoptedForProfiles = <String>{};

  /// Callback to refresh download provider metadata after sync
  VoidCallback? onWatchStatesRefreshed;

  /// Get watched threshold for a server. Cascades:
  /// 1. Plex's fetched server prefs (`/:/prefs`)
  /// 2. Jellyfin's fixed [MediaServerClient.watchedThreshold] (0.9)
  /// 3. Cached value in SettingsService (mirrored by PlexClient.fetchServerPrefs)
  /// 4. Default 90%
  double getWatchedThreshold(ServerId serverId) {
    final client = _serverManager.getClient(serverId);
    if (client is PlexClient && client.serverPrefs.isNotEmpty) {
      return client.watchedThreshold;
    }
    if (client != null && client.backend != MediaBackend.plex) {
      // Jellyfin (and any future neutral backend) — the client exposes a
      // fixed threshold that mirrors the wire-protocol behaviour.
      return client.watchedThreshold;
    }
    // No client bound (offline) or Plex prefs not loaded yet — use the
    // mirror written on the last successful prefs fetch.
    final cached = SettingsService.instanceOrNull?.read(SettingsService.watchedThresholdPref(serverId)) ?? 90;
    return cached / 100.0;
  }

  /// Minimum interval between syncs.
  /// Mobile: no throttle (always sync on resume for cross-device updates)
  /// Desktop: 2 minutes (reduced from 10 min to handle tab-switching better)
  static Duration get minSyncInterval {
    if (Platform.isIOS || Platform.isAndroid) {
      return Duration.zero;
    }
    return const Duration(minutes: 2);
  }

  /// Maximum sync attempts before suppressing additional server-write retries.
  /// Queued actions are retained so a transient outage or server bug never
  /// silently drops local watch progress.
  static const int maxSyncAttempts = 5;

  /// How long a row that ran out of attempts waits for a new round.
  static const Duration exhaustedRetryInterval = Duration(hours: 6);

  /// Whether the active profile is being bound to its servers right now.
  bool Function()? isProfileBinding;

  /// What the viewer just marked on [item] says more than a copy waiting for it:
  /// the row would write the older state back. A season or a series speaks for
  /// its episodes, which are only looked up when one of them has a row.
  Future<void> forgetHeldCopy(
    MediaServerClient client,
    MediaItem item, {
    required ServerId serverId,
    required String? profileId,
  }) async {
    await _database.deleteCopyActions(buildGlobalKey(serverId, item.id), profileId: profileId);
    if (!item.isSeason && !item.isShow) return;
    final pending = await _database.getPendingWatchActions(profileId: profileId);
    final held = {
      for (final action in pending)
        if (action.serverId == serverId && _isCopyAction(action)) action.ratingKey,
    };
    if (held.isEmpty) return;
    try {
      for (final episode in await client.fetchPlayableDescendants(item.id)) {
        if (held.contains(episode.id)) {
          await _database.deleteCopyActions(buildGlobalKey(serverId, episode.id), profileId: profileId);
        }
      }
    } catch (e) {
      appLogger.d('Could not read the episodes of ${item.globalKey}', error: e);
    }
  }

  /// Hears a play that ran offline, once its own server took it: no player is
  /// left by then to tell its copies.
  void Function(MediaItem item, Duration position, Duration duration, {required bool watched})? onOwnPlayReplayed;

  OfflineWatchSyncService({required this._database, required this._serverManager, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _lastExhaustedReset;

  /// The profile queue rows are written for now. A write that waited on a
  /// server first reads this before the wait.
  String? get activeProfileId => _activeProfileId;

  /// Whether a sync is currently in progress
  bool get isSyncing => _isSyncing;

  void setActiveProfileId(String? profileId, {int? availableProfileCount}) {
    _activeProfileId = profileId;
    _availableProfileCount = availableProfileCount;
    if (profileId != null && profileId.isNotEmpty) {
      unawaited(_adoptLegacyWatchActionsForProfile(profileId, availableProfileCount: availableProfileCount));
    }
    // The provider tree calls this when a bind settles, and it does so while it
    // builds: a sync notifies at once, so it starts after this frame's work.
    if (_stoppedForBind && isProfileBinding?.call() != true) {
      _stoppedForBind = false;
      scheduleMicrotask(() {
        if (!_isShutDown) unawaited(syncPendingItems(queueIfBusy: true));
      });
    }
  }

  Future<void> _adoptLegacyWatchActionsForProfile(String profileId, {int? availableProfileCount}) async {
    if (profileId.isEmpty || !_legacyWatchActionsAdoptedForProfiles.add(profileId)) return;
    if (availableProfileCount != 1) {
      _legacyWatchActionsAdoptedForProfiles.remove(profileId);
      return;
    }
    try {
      await _database.adoptLegacyOfflineWatchActionsForProfile(profileId);
    } catch (e, st) {
      _legacyWatchActionsAdoptedForProfiles.remove(profileId);
      appLogger.w('Failed to adopt legacy offline watch actions for $profileId', error: e, stackTrace: st);
    }
  }

  Future<void> _adoptLegacyWatchActionsForActiveProfile() async {
    final profileId = _activeProfileId;
    if (profileId == null || profileId.isEmpty) return;
    await _adoptLegacyWatchActionsForProfile(profileId, availableProfileCount: _availableProfileCount);
  }

  void startConnectivityMonitoring(OfflineModeSource source) {
    if (_offlineModeSource != null && _offlineModeListener != null) {
      _offlineModeSource!.removeListener(_offlineModeListener!);
    }

    _offlineModeSource = source;
    _offlineModeListener = () {
      if (!source.isOffline) {
        // We just came online - trigger bidirectional sync. A fresh network is
        // a genuinely new environment, so actions that exhausted their retry
        // budget get a new one instead of being stranded forever.
        appLogger.i('Connectivity restored - starting bidirectional watch sync');
        unawaited(_database.resetExhaustedSyncAttempts(maxSyncAttempts).then((_) => _performBidirectionalSync()));
      }
    };

    source.addListener(_offlineModeListener!);

    // Don't sync on startup - servers aren't connected yet.
    // Sync will happen when:
    // - Connectivity is restored (listener triggers)
    // - App resumes from background (onAppResumed)
  }

  /// Perform bidirectional sync: push local changes, then pull server states.
  ///
  /// Push always happens immediately. Pull respects [minSyncInterval] unless [force] is true.
  Future<void> _performBidirectionalSync({bool force = false}) async {
    if (_isShutDown) return;

    // Prevent overlapping bidirectional syncs
    if (_isBidirectionalSyncing) {
      appLogger.d('Bidirectional sync already in progress, skipping');
      return;
    }

    if (_serverManager.onlineClients.isEmpty) {
      appLogger.d('Skipping watch sync - no connected servers available yet');
      return;
    }

    _isBidirectionalSyncing = true;
    try {
      // Always push local changes to server (never throttle outbound sync)
      await syncPendingItems();

      // Only throttle the pull from server
      if (!force && _lastSyncTime != null) {
        final elapsed = DateTime.now().difference(_lastSyncTime!);
        if (elapsed < minSyncInterval) {
          appLogger.d(
            'Skipping server pull - last sync was ${elapsed.inMinutes}m ago (min: ${minSyncInterval.inMinutes}m)',
          );
          return;
        }
      }

      // Pull latest states from server
      await syncWatchStatesFromServer();
      _lastSyncTime = DateTime.now();
    } finally {
      _isBidirectionalSyncing = false;
    }
  }

  /// Called when app becomes active - syncs for cross-device updates.
  /// On mobile, always syncs immediately (device-switching scenario).
  /// On desktop, respects the throttle interval.
  void onAppResumed() {
    if (_isShutDown) return;
    if (_offlineModeSource?.isOffline != true) {
      final isMobile = Platform.isIOS || Platform.isAndroid;
      appLogger.d('App resumed - ${isMobile ? "forcing" : "checking"} sync');
      _performBidirectionalSync(force: isMobile);
    }
  }

  /// Called when servers connect on app startup.
  ///
  /// Triggers the initial sync now that PlexClients are available.
  /// Only runs once per app session.
  void onServersConnected() {
    if (_isShutDown) return;
    if (_hasPerformedStartupSync) return;
    _hasPerformedStartupSync = true;

    if (_offlineModeSource?.isOffline != true) {
      appLogger.i('Servers connected - performing startup sync');
      _performBidirectionalSync();
    }
  }

  /// Queue a progress update for later sync.
  ///
  /// This is called during offline playback to track the watch position.
  /// If progress exceeds the server's threshold, shouldMarkWatched is set to true.
  ///
  /// The `ratingKey:` parameter on the underlying `_database` calls is
  /// preserved as the on-disk column name; the in-memory parameter renamed
  /// here is just the API-level identifier.
  Future<String?> queueProgressUpdate({
    required ServerId serverId,
    required String itemId,
    required int viewOffset,
    required int? duration,
  }) async {
    final shouldMarkWatched =
        duration != null && isWatchedByProgress(viewOffset, duration, serverId: ServerId(serverId));
    final clientScopeId = await _clientScopeIdForItem(ServerId(serverId), itemId);

    await _database.upsertProgressAction(
      profileId: _activeProfileId,
      serverId: serverId,
      clientScopeId: clientScopeId,
      ratingKey: itemId,
      viewOffset: viewOffset,
      duration: duration,
      shouldMarkWatched: shouldMarkWatched,
    );

    final durationLabel = duration == null ? 'unknown' : '${(duration / 1000).toStringAsFixed(0)}s';
    final percentLabel = duration == null || duration <= 0
        ? 'unknown'
        : '${((viewOffset / duration) * 100).toStringAsFixed(1)}%';
    appLogger.d(
      'Queued offline progress: $serverId:$itemId at ${(viewOffset / 1000).toStringAsFixed(0)}s / $durationLabel ($percentLabel)',
    );

    notifyListeners();
    return clientScopeId;
  }

  /// Holds a position that happened on another source of the same title, and
  /// a watched state with it when [watched] is set: the source that played
  /// decided that, whatever this server's own threshold says.
  ///
  /// Goes through this queue whether the server is up or not, so a server that
  /// answers late or refuses retries like any other queued write and can never
  /// reach the play. The replay keeps its last-writer guard: a position this
  /// server already moved past is dropped.
  Future<bool> queueMirroredProgress({
    required ServerId serverId,
    required String itemId,
    required int viewOffset,
    required int? duration,
    required bool watched,
    required String? profileId,
  }) async {
    final clientScopeId = await _clientScopeIdForItem(ServerId(serverId), itemId);
    // [profileId] is who watched. Another profile took over since: its row and
    // its token have nothing to do with this viewing.
    if (profileId != _activeProfileId) return false;
    await _database.upsertProgressAction(
      profileId: profileId,
      serverId: serverId,
      clientScopeId: clientScopeId,
      ratingKey: itemId,
      viewOffset: viewOffset,
      duration: duration,
      shouldMarkWatched: watched,
      actionType: OfflineActionType.mirroredProgress,
    );
    notifyListeners();
    return true;
  }

  /// Holds a watched or unwatched mark for another copy of a title whose mark
  /// already went out once. See [OfflineActionType.mirroredWatched].
  ///
  /// [profileId] is who marked it, read before anything waited. Answers whether
  /// the row landed, with the cache scope to announce it under.
  Future<({bool held, String? cacheServerId})> queueCopyMark({
    required ServerId serverId,
    required String itemId,
    required bool watched,
    required String? profileId,
  }) async {
    final clientScopeId = await _clientScopeIdForItem(ServerId(serverId), itemId);
    if (profileId != _activeProfileId) return (held: false, cacheServerId: null);
    await _database.insertWatchAction(
      profileId: profileId,
      serverId: serverId,
      clientScopeId: clientScopeId,
      ratingKey: itemId,
      actionType: (watched ? OfflineActionType.mirroredWatched : OfflineActionType.mirroredUnwatched).id,
    );
    notifyListeners();
    return (held: true, cacheServerId: clientScopeId);
  }

  Future<String?> queueMarkWatched({required ServerId serverId, required String itemId}) =>
      _queueWatchStatusAction(serverId: serverId, itemId: itemId, actionType: OfflineActionType.watched.id);

  Future<String?> queueMarkUnwatched({required ServerId serverId, required String itemId}) =>
      _queueWatchStatusAction(serverId: serverId, itemId: itemId, actionType: OfflineActionType.unwatched.id);

  /// Holds a Continue Watching removal for a membership that could not be
  /// reached (hoofdstuk 13.4 point 3), so the reconnect sync performs it
  /// (point 4).
  ///
  /// The queue row *is* the local suppression: it survives a restart, it is
  /// keyed by the same `serverId:itemId` the on-deck list is keyed by, and it
  /// disappears exactly when the write finally lands. A second in-memory
  /// suppression set beside it would be a second answer to "is this title
  /// still in Verder kijken".
  Future<String?> queueRemoveFromContinueWatching({required ServerId serverId, required String itemId}) =>
      _queueWatchStatusAction(
        serverId: serverId,
        itemId: itemId,
        actionType: OfflineActionType.removedFromContinueWatching.id,
      );

  /// Global keys of the Continue Watching removals still waiting for their
  /// server. A surface rebuilding the row after a restart filters these out,
  /// so a card the user already dismissed does not come back while its write
  /// is still queued.
  Future<Set<String>> pendingContinueWatchingRemovalKeys() async {
    final profileId = _activeProfileId;
    final actions = profileId == null || profileId.isEmpty
        ? await _database.getPendingWatchActions()
        : await _database.getPendingWatchActions(profileId: profileId);
    return {
      for (final action in actions)
        if (action.actionType == OfflineActionType.removedFromContinueWatching.id) action.globalKey,
    };
  }

  Future<String?> _queueWatchStatusAction({
    required ServerId serverId,
    required String itemId,
    required String actionType,
  }) async {
    final clientScopeId = await _clientScopeIdForItem(ServerId(serverId), itemId);
    await _database.insertWatchAction(
      profileId: _activeProfileId,
      serverId: serverId,
      clientScopeId: clientScopeId,
      ratingKey: itemId,
      actionType: actionType,
    );

    appLogger.d('Queued offline mark $actionType: $serverId:$itemId');
    notifyListeners();
    return clientScopeId;
  }

  /// Check if an item should be considered watched based on progress percentage.
  bool isWatchedByProgress(int viewOffset, int duration, {ServerId? serverId}) {
    final threshold = serverId != null ? getWatchedThreshold(serverId) : 0.9;
    return isWatchedProgress(positionMs: viewOffset, durationMs: duration, threshold: threshold);
  }

  /// Get the local watch status for a media item.
  ///
  /// Returns:
  /// - `true` if item was marked as watched locally or progress >= server threshold
  /// - `false` if item was marked as unwatched locally
  /// - `null` if no local watched/unwatched action exists (use cached server data)
  Future<bool?> getLocalWatchStatus(String globalKey, {String? clientScopeId}) async {
    await _adoptLegacyWatchActionsForActiveProfile();
    final expectedScope = clientScopeId ?? _activeClientScopeIdForGlobalKey(globalKey);
    final profileId = _activeProfileId;
    final actions = await _database.getWatchActionsForKey(
      globalKey,
      profileId: profileId,
      filterProfile: profileId != null,
      clientScopeId: expectedScope,
      filterClientScope: expectedScope != null,
    );
    return WatchStateResolver.fromActions(actions).isWatched;
  }

  /// Get local watch statuses for multiple items in a single database query.
  ///
  /// Returns a map of globalKey -> watch status (true/false/null).
  /// More efficient than calling getLocalWatchStatus multiple times.
  Future<Map<String, bool?>> getLocalWatchStatusesBatched(
    Set<String> globalKeys, {
    Map<String, String?>? clientScopeIdsByGlobalKey,
  }) async {
    if (globalKeys.isEmpty) return {};
    await _adoptLegacyWatchActionsForActiveProfile();

    final scopes = clientScopeIdsByGlobalKey ?? _activeClientScopeIdsForGlobalKeys(globalKeys);
    final profileId = _activeProfileId;
    final actions = await _database.getWatchActionsForKeys(
      globalKeys,
      profileId: profileId,
      filterProfile: profileId != null,
      clientScopeIdsByGlobalKey: scopes,
    );
    final result = <String, bool?>{};

    for (final key in globalKeys) {
      result[key] = WatchStateResolver.fromActions(actions[key] ?? const []).isWatched;
    }

    return result;
  }

  /// Get the local view offset (resume position) for a media item.
  ///
  /// Returns the locally tracked position, or null if none exists. Explicit
  /// watched/unwatched actions clear resume by resolving to a zero offset.
  Future<int?> getLocalViewOffset(String globalKey, {String? clientScopeId}) async {
    await _adoptLegacyWatchActionsForActiveProfile();
    final expectedScope = clientScopeId ?? _activeClientScopeIdForGlobalKey(globalKey);
    final profileId = _activeProfileId;
    final actions = await _database.getWatchActionsForKey(
      globalKey,
      profileId: profileId,
      filterProfile: profileId != null,
      clientScopeId: expectedScope,
      filterClientScope: expectedScope != null,
    );
    final snapshot = WatchStateResolver.fromActions(actions);
    final offset = snapshot.hasViewOffsetMs ? snapshot.viewOffsetMs : null;
    return offset != null && offset > 0 ? offset : null;
  }

  /// The same local view offset as [getLocalViewOffset], carrying the
  /// timestamp of the action that produced it.
  ///
  /// [PlaybackResumeResolver] needs that timestamp: without it the only
  /// available rule is "local always wins", which is what let a downloaded
  /// file resume behind a server position another device had already moved
  /// past. The queue has no field that separates a user seek from a tracker
  /// tick, so every record reports as passive offline playback; a genuinely
  /// deliberate local action would have to be recorded as such at its source.
  Future<LocalResumeProgress?> getLocalResumeProgress(String globalKey, {String? clientScopeId}) async {
    await _adoptLegacyWatchActionsForActiveProfile();
    final expectedScope = clientScopeId ?? _activeClientScopeIdForGlobalKey(globalKey);
    final profileId = _activeProfileId;
    final actions = await _database.getWatchActionsForKey(
      globalKey,
      profileId: profileId,
      filterProfile: profileId != null,
      clientScopeId: expectedScope,
      filterClientScope: expectedScope != null,
    );

    final latest = WatchStateResolver.latestAction(actions);
    if (latest == null) return null;

    final snapshot = WatchStateResolver.fromActions(actions);
    final offset = snapshot.hasViewOffsetMs ? snapshot.viewOffsetMs : null;
    if (offset == null || offset <= 0) return null;

    return LocalResumeProgress(
      position: Duration(milliseconds: offset),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(latest.updatedAt),
      intent: PlaybackResumeIntent.passive,
      origin: PlaybackResumeOrigin.offlinePlayback,
    );
  }

  Future<int> getPendingSyncCount() async {
    await _adoptLegacyWatchActionsForActiveProfile();
    final profileId = _activeProfileId;
    // No maxSyncAttempts filter: actions that exhausted their retries are
    // still unsynced — hiding them would show "0 pending" while local watch
    // progress silently never reaches the server.
    return profileId == null || profileId.isEmpty
        ? _database.getPendingSyncCount()
        : _database.getPendingSyncCount(profileId: profileId);
  }

  /// Sync all pending items to their respective servers.
  ///
  /// Called automatically when connectivity is restored, or manually.
  /// Actions are batched by server to reduce connectivity lookups.
  ///
  /// [queueIfBusy] is for a caller that just wrote a row: a sync already running
  /// has read its list, so that row would otherwise wait for the next reconnect.
  Future<void> syncPendingItems({bool queueIfBusy = false}) async {
    if (_isSyncing) {
      appLogger.d('Sync already in progress, skipping');
      if (queueIfBusy) _syncRequested = true;
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      await _adoptLegacyWatchActionsForActiveProfile();
      await _giveExhaustedRowsAnotherRound();
      final profileId = _activeProfileId;
      final pendingActions = profileId == null || profileId.isEmpty
          ? await _database.getPendingWatchActions()
          : await _database.getPendingWatchActions(profileId: profileId);

      if (pendingActions.isEmpty) {
        appLogger.d('No pending watch actions to sync');
        return;
      }

      appLogger.i('Syncing ${pendingActions.length} pending watch actions');

      for (final action in pendingActions) {
        // These rows belong to the profile that read them. The clients below
        // are looked up per row: after a switch they are the next profile's.
        if (profileId != _activeProfileId) {
          appLogger.d('Profile changed during the sync; leaving the rest for that profile');
          break;
        }
        // During a bind the clients and their rights are still those of the
        // last profile. The rows stay for the pass after it.
        if (isProfileBinding?.call() == true) {
          appLogger.d('Profile binding during the sync; leaving the rest for the next pass');
          break;
        }
        // A row can date from before this client knew whose server it is.
        if (_isCopyAction(action) && _serverManager.isSomeoneElsesServer(ServerId(action.serverId))) {
          await _database.deleteWatchAction(action.id);
          continue;
        }
        if (action.syncAttempts >= maxSyncAttempts) {
          appLogger.w(
            'Skipping action ${action.id} - exceeded retry limit '
            '(${action.syncAttempts} attempts). Last error: ${action.lastError}',
          );
          continue;
        }

        final synced = await _withOnlineClientForAction(action, (client) async {
          try {
            final landed = await replayOfflineWatchAction(
              client,
              action,
              isCurrent: () => profileId == _activeProfileId && isProfileBinding?.call() != true,
            );
            await _database.deleteReplayedWatchAction(action);
            appLogger.d('Successfully synced action ${action.id}: ${action.actionType} for ${action.ratingKey}');
            if (landed) _announceOwnPlay(client, action);
          } on ReplayInterrupted {
            appLogger.d('Profile changed or binding during the replay of ${action.id}; it stays queued');
          } catch (e) {
            appLogger.w('Failed to sync action ${action.id}: $e');
            if (_isCopyAction(action) && !copyWriteStaysQueued(client, e)) {
              await _database.deleteReplayedWatchAction(action);
            } else {
              await _database.updateSyncAttempt(action.id, e.toString());
            }
          }
        });
        if (!synced) {
          appLogger.d('Keeping action ${action.id} queued until server is available');
          continue;
        }
      }
      _stoppedForBind = isProfileBinding?.call() == true;
      await _reannouncePendingContinueWatchingRemovals();
    } finally {
      _isSyncing = false;
      notifyListeners();
      if (_syncRequested) {
        _syncRequested = false;
        unawaited(syncPendingItems());
      }
    }
  }

  static bool _isCopyAction(OfflineWatchProgressItem action) =>
      action.actionType == OfflineActionType.mirroredProgress.id ||
      action.actionType == OfflineActionType.mirroredWatched.id ||
      action.actionType == OfflineActionType.mirroredUnwatched.id;

  void _announceOwnPlay(MediaServerClient client, OfflineWatchProgressItem action) {
    final listener = onOwnPlayReplayed;
    final position = action.viewOffset;
    final duration = action.duration;
    if (listener == null || position == null || duration == null) return;
    if (action.actionType != OfflineActionType.progress.id) return;
    final profileId = _activeProfileId;
    unawaited(
      client
          .fetchItem(action.ratingKey)
          .then((item) {
            if (item == null || profileId != _activeProfileId) return;
            listener(
              item.copyWith(serverId: action.serverId),
              Duration(milliseconds: position),
              Duration(milliseconds: duration),
              watched: action.shouldMarkWatched,
            );
          })
          .catchError((Object e) {
            appLogger.d('Could not reach the copies of ${action.globalKey}', error: e);
          }),
    );
  }

  /// A failure that outlasts its [maxSyncAttempts] used to wait for the app to
  /// go offline and back, which never happens while another server is up. The
  /// first sync of a run counts, so a restart does not start the wait over.
  Future<void> _giveExhaustedRowsAnotherRound() async {
    final current = _now();
    final last = _lastExhaustedReset;
    if (last != null && current.difference(last) < exhaustedRetryInterval) return;
    _lastExhaustedReset = current;
    await _database.resetExhaustedSyncAttempts(maxSyncAttempts);
  }

  /// Re-states hoofdstuk 13.4 point 3's suppression for every removal still
  /// waiting on its server.
  ///
  /// A queued removal outlives the app, but the on-deck suppression that made
  /// the card disappear does not: `DiscoverProvider` holds it in memory, keyed
  /// by global key, and rebuilds empty on every launch. Without this the user
  /// would dismiss a card, close Pleya while a server was down, and find the
  /// card back — with the write still queued, so nothing was wrong except what
  /// they could see.
  ///
  /// Announcing rather than exposing a getter keeps the dependency one-way.
  /// The surfaces already listen to [WatchStateNotifier] for exactly this
  /// event and their suppression is self-cleaning, so a re-announcement for a
  /// title the server has meanwhile dropped costs one set entry that the next
  /// on-deck apply removes again.
  Future<void> _reannouncePendingContinueWatchingRemovals() async {
    final Set<String> keys;
    try {
      keys = await pendingContinueWatchingRemovalKeys();
    } catch (e) {
      appLogger.d('Could not read pending Continue Watching removals', error: e);
      return;
    }
    for (final globalKey in keys) {
      final parsed = parseGlobalKey(globalKey);
      if (parsed == null) continue;
      WatchStateNotifier().notify(
        WatchStateEvent(
          itemId: parsed.ratingKey,
          serverId: ServerId(parsed.serverId),
          changeType: WatchStateChangeType.removedFromContinueWatching,
          parentChain: const [],
          mediaType: MediaKind.unknown.id,
        ),
      );
    }
  }

  Future<String?> _clientScopeIdForItem(ServerId serverId, String itemId) async {
    // A downloaded row's clientScopeId is a cache/source hint, not an owner.
    // Offline watch actions are user-owned, so a new local action follows the
    // currently active scoped Jellyfin client. Once queued, _clientForAction
    // replays that exact scope even if the active user changes later.
    final client = _serverManager.getClient(serverId);
    if (client != null) {
      final scopeId = client.cacheServerId;
      if (scopeId != serverId) return scopeId;
    }
    final download = await _database.getDownloadedMedia(buildGlobalKey(ServerId(serverId), itemId));
    final downloadedScopeId = download?.clientScopeId;
    if (downloadedScopeId != null && downloadedScopeId.isNotEmpty) return downloadedScopeId;
    return null;
  }

  Future<({MediaServerClient client, String? clientScopeId})?> _clientForAction(OfflineWatchProgressItem action) async {
    final scopeId = action.clientScopeId;
    if (scopeId != null && scopeId.isNotEmpty) {
      final scoped = _serverManager.getJellyfinClientByCompoundId(scopeId);
      if (scoped != null) return (client: scoped, clientScopeId: scopeId);
    }
    final client = _serverManager.getClient(ServerId(action.serverId));
    if (client == null) return null;
    if (client.backend == MediaBackend.jellyfin && client.cacheServerId != action.serverId) {
      appLogger.w(
        'Refusing to sync unscoped Jellyfin action ${action.id} for ${action.serverId}:${action.ratingKey}; '
        'no queued client scope is available',
      );
      return null;
    }
    // A row is written for one account. The client on this server can be
    // another's, and its token would write this viewing there.
    final clientScope = switch (client) {
      ScopedMediaServerClient(:final scopedServerId) => scopedServerId,
      _ => null,
    };
    if (clientScope != null && scopeId != null && scopeId.isNotEmpty && clientScope != scopeId) {
      appLogger.d('Action ${action.id} belongs to scope $scopeId; skipping');
      return null;
    }
    return (client: client, clientScopeId: action.clientScopeId);
  }

  Future<bool> _withOnlineClientForAction(
    OfflineWatchProgressItem action,
    Future<void> Function(MediaServerClient client) callback,
  ) async {
    final resolved = await _clientForAction(action);
    if (resolved == null) {
      appLogger.d('No client for server ${action.serverId} scope ${action.clientScopeId}, skipping');
      return false;
    }

    if (!_serverManager.isClientOnline(ServerId(action.serverId), clientScopeId: resolved.clientScopeId)) {
      appLogger.d('Server ${action.serverId} scope ${resolved.clientScopeId} is offline, skipping');
      return false;
    }

    await callback(resolved.client);
    return true;
  }

  Map<String, String?> _activeClientScopeIdsForGlobalKeys(Set<String> globalKeys) {
    final scopes = <String, String?>{};
    for (final globalKey in globalKeys) {
      final scopeId = _activeClientScopeIdForGlobalKey(globalKey);
      if (scopeId != null) scopes[globalKey] = scopeId;
    }
    return scopes;
  }

  String? _activeClientScopeIdForGlobalKey(String globalKey) {
    final parsed = parseGlobalKey(globalKey);
    if (parsed == null) return null;
    return _activeClientScopeIdForServer(parsed.serverId);
  }

  String? _activeClientScopeIdForServer(ServerId serverId) {
    final client = _serverManager.getClient(serverId);
    if (client == null) return null;
    final scopeId = client.cacheServerId;
    return scopeId == serverId ? null : scopeId;
  }

  Future<MediaServerClient?> _clientForDownloadScope(ServerId serverId, String? clientScopeId) async {
    if (clientScopeId != null && clientScopeId.isNotEmpty) {
      final scoped = _serverManager.getJellyfinClientByCompoundId(clientScopeId);
      if (scoped != null) return scoped;
    }
    return _serverManager.getClient(serverId);
  }

  Future<T?> _withOnlineClientForDownloadScope<T>(
    ServerId serverId,
    String? clientScopeId,
    Future<T> Function(MediaServerClient client) callback,
  ) async {
    final client = await _clientForDownloadScope(ServerId(serverId), clientScopeId);
    if (client == null) {
      appLogger.d('No client for server $serverId scope $clientScopeId, skipping');
      return null;
    }

    if (!_serverManager.isClientOnline(ServerId(serverId), clientScopeId: clientScopeId)) {
      appLogger.d('Server $serverId scope $clientScopeId is offline, skipping');
      return null;
    }

    return callback(client);
  }

  /// Sync watch states for all episodes in a single season.
  ///
  /// Returns the number of episodes synced, or -1 on failure.
  Future<int> _syncSeasonEpisodes(
    MediaServerClient client,
    ServerId serverId,
    String seasonRatingKey,
    Set<String> downloadedEpisodeKeys,
  ) async {
    try {
      final seasonEpisodes = await client.fetchChildren(seasonRatingKey);
      int synced = 0;

      for (final episode in seasonEpisodes) {
        if (!downloadedEpisodeKeys.contains(episode.id)) continue;

        final cacheServerId = client.cacheServerId;
        final prior = await client.cache.getMetadata(ServerId(cacheServerId), episode.id);
        final isWatched = (episode.viewCount ?? 0) > 0;

        if (prior != null) {
          // Existing cached row — patch in the watch-state and rollup
          // fields without disturbing Media/Chapter blobs.
          final wasWatched = (prior.viewCount ?? 0) > 0;
          await client.cache.applyWatchState(
            serverId: ServerId(cacheServerId),
            itemId: episode.id,
            isWatched: isWatched,
            viewOffsetMs: episode.viewOffsetMs,
            lastViewedAt: episode.lastViewedAt,
            viewedLeafCount: episode.viewedLeafCount,
          );
          if (wasWatched != isWatched) {
            WatchStateNotifier().notifyWatched(
              item: episode,
              isNowWatched: isWatched,
              cacheServerId: client.cacheServerId,
            );
          }
        } else {
          // No cached row yet — populate the canonical row via fetchItem
          // (cache-fallback mixin writes the response to cache for free)
          // and then stamp the watch snapshot. Transition is unknowable
          // without a prior row, so we skip the notify to match the
          // previous synthesize-fresh-row behaviour.
          try {
            await client.fetchItem(episode.id);
            await client.cache.applyWatchState(
              serverId: ServerId(cacheServerId),
              itemId: episode.id,
              isWatched: isWatched,
              viewOffsetMs: episode.viewOffsetMs,
              lastViewedAt: episode.lastViewedAt,
              viewedLeafCount: episode.viewedLeafCount,
            );
          } catch (e) {
            appLogger.d('Cache populate failed for ${episode.id}', error: e);
          }
        }
        synced++;
      }

      return synced;
    } catch (e) {
      appLogger.d('Failed to sync watch states for season $seasonRatingKey: $e');
      return -1;
    }
  }

  /// Fetch latest watch states from server and update local cache.
  ///
  /// Called when coming online or on app startup to pull any watch state
  /// changes made on other devices.
  ///
  /// Optimized to fetch episodes by season (one API call per season)
  /// instead of one API call per episode.
  Future<void> syncWatchStatesFromServer() async {
    try {
      final profileId = _activeProfileId;
      if (profileId == null || profileId.isEmpty) {
        appLogger.d('Skipping watch-state pull — no active profile');
        return;
      }

      await _database.adoptLegacyDownloadsForProfile(profileId);
      final ownedKeys = await _database.getDownloadOwnerKeysForProfile(profileId);
      if (ownedKeys.isEmpty) {
        appLogger.d('No active-profile downloads to sync watch states for');
        return;
      }

      // Pull watch state only for downloads visible to the active profile. The
      // physical rows are shared across profiles, but server watch state is not.
      final downloadedItems = (await _database.getAllDownloadedMetadata())
          .where((item) => ownedKeys.contains(item.globalKey))
          .toList();

      if (downloadedItems.isEmpty) {
        appLogger.d('No downloaded items to sync watch states for');
        return;
      }

      appLogger.i('Syncing watch states from server for ${downloadedItems.length} items');

      // Separate episodes (with season parent) from other items (movies,
      // etc.), using the active scoped client for user-owned Jellyfin watch
      // state. Downloads are shared, but server watch state is per user.
      // Structure: (serverId, clientScopeId) -> seasonRatingKey -> Set<episodeRatingKey>
      final episodesByScopeAndSeason = <({ServerId serverId, String? clientScopeId}), Map<String, Set<String>>>{};
      // Structure: (serverId, clientScopeId) -> List<ratingKey>
      final nonEpisodeItems = <({ServerId serverId, String? clientScopeId}), List<String>>{};

      for (final item in downloadedItems) {
        final scope = (
          serverId: ServerId(item.serverId),
          clientScopeId: _activeClientScopeIdForServer(ServerId(item.serverId)),
        );
        if (item.type == 'episode' && item.parentRatingKey != null) {
          // Group episodes by server and season for batch fetching
          episodesByScopeAndSeason
              .putIfAbsent(scope, () => {})
              .putIfAbsent(item.parentRatingKey!, () => {})
              .add(item.ratingKey);
        } else {
          // Movies, or episodes without parent (fallback to individual fetch)
          nonEpisodeItems.putIfAbsent(scope, () => []).add(item.ratingKey);
        }
      }

      int syncedCount = 0;
      int seasonCount = 0;

      // Fetch episodes by season (batch) - one API call per season
      for (final scopeEntry in episodesByScopeAndSeason.entries) {
        final scope = scopeEntry.key;
        final seasonMap = scopeEntry.value;

        await _withOnlineClientForDownloadScope(scope.serverId, scope.clientScopeId, (client) async {
          for (final seasonEntry in seasonMap.entries) {
            final result = await _syncSeasonEpisodes(client, scope.serverId, seasonEntry.key, seasonEntry.value);
            if (result >= 0) {
              syncedCount += result;
              seasonCount++;
            }
          }
        });
      }

      // Fetch non-episode items individually (movies, etc.)
      for (final entry in nonEpisodeItems.entries) {
        final scope = entry.key;
        final ratingKeys = entry.value;

        await _withOnlineClientForDownloadScope(scope.serverId, scope.clientScopeId, (client) async {
          for (final ratingKey in ratingKeys) {
            try {
              // Snapshot prior viewCount through the neutral cache so we
              // can detect a watched-status change from another device.
              final prior = await client.cache.getMetadata(ServerId(client.cacheServerId), ratingKey);
              final wasWatched = (prior?.viewCount ?? 0) > 0;

              // fetchItem already caches the full API response (with
              // chapters/markers) via the client's internal cache layer.
              final metadata = await client.fetchItem(ratingKey);
              if (metadata != null) {
                syncedCount++;
                final isWatched = (metadata.viewCount ?? 0) > 0;
                // Without a cached row there is no transition to report, as for
                // the episodes above. Pleya Server keeps no such row: this would
                // count the same viewing again on every pull.
                if (prior != null && wasWatched != isWatched) {
                  WatchStateNotifier().notifyWatched(
                    item: metadata,
                    isNowWatched: isWatched,
                    cacheServerId: client.cacheServerId,
                  );
                }
              }
            } catch (e) {
              appLogger.d('Failed to sync watch state for $ratingKey: $e');
            }
          }
        });
      }

      final movieCount = nonEpisodeItems.values.fold(0, (a, b) => a + b.length);
      appLogger.i('Synced watch states: $seasonCount seasons, $movieCount other items ($syncedCount total)');

      // Notify download provider to refresh metadata from updated cache
      if (syncedCount > 0) {
        onWatchStatesRefreshed?.call();
      }

      notifyListeners();
    } catch (e) {
      appLogger.w('Error syncing watch states from server: $e');
    }
  }

  /// Clear all pending watch actions (e.g., when logging out).
  Future<void> clearAll() async {
    await _database.clearAllWatchActions();
    notifyListeners();
  }

  @override
  void dispose() {
    _isShutDown = true;
    if (_offlineModeSource != null && _offlineModeListener != null) {
      _offlineModeSource!.removeListener(_offlineModeListener!);
    }
    super.dispose();
  }
}
