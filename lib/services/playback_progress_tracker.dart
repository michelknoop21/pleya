import 'dart:async';
import '../media/ids.dart';

import '../mpv/mpv.dart';

import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../media/media_source_info.dart';
import 'offline_watch_sync_service.dart';
import 'playback_report_session.dart';
import 'playback_write_authority.dart';
import 'settings_service.dart';
import 'track_selection_service.dart';
import '../utils/app_logger.dart';
import '../utils/watch_state_notifier.dart';

/// Tracks playback progress and reports it to the active media server.
///
/// Both Plex and Jellyfin go through the unified
/// [MediaServerClient.reportPlayback*] surface — Plex maps the three signals
/// onto `/:/timeline` updates with appropriate `state`, Jellyfin uses the
/// three `/Sessions/Playing*` endpoints. Scrobble fires once the position
/// crosses the client's [watchedThreshold] (per-server pref on Plex, fixed
/// 90% on Jellyfin).
class PlaybackProgressTracker {
  /// Server client for online progress updates (null when offline). Pinned
  /// for the tracker's lifetime — one playback session against the server
  /// that started it; if that server is removed mid-playback, reports fail
  /// and are queued/dropped rather than re-routed.
  final MediaServerClient? client;

  /// Metadata of the media being played
  final MediaItem metadata;

  /// Video player instance
  final Player player;

  /// Whether playback is in offline mode
  final bool isOffline;

  /// Service for queuing offline progress updates
  final OfflineWatchSyncService? offlineWatchService;

  /// Queue the latest progress locally if online reporting fails. Used for
  /// downloaded/local playback where playback can continue without a server.
  final bool queueOnOnlineFailure;

  final String? playMethod;

  /// Backend session ID to echo in progress reports. Jellyfin uses this to
  /// associate `/Sessions/Playing*` calls with a transcoded playback session.
  final String? playSessionId;

  /// Source-level stream metadata for mapping local player track ids back to
  /// Jellyfin stream indexes in playback-progress reports.
  final MediaSourceInfo? mediaInfo;

  /// Local observation of whether this player may still write watch state.
  /// Null keeps the pre-existing behaviour of always reporting.
  final ObservedPlaybackAuthority? authority;

  /// Timer for periodic progress updates
  Timer? _progressTimer;

  /// Trailing debounce for a seek, so scrubbing reports once at the end of the
  /// gesture instead of once per intermediate position.
  Timer? _seekReportTimer;

  /// A seek is waiting to be reported. Survives a failure backoff: the report
  /// is postponed, never dropped.
  bool _pendingSeekReport = false;

  /// The pending seek has already waited out at least one backoff round. Only
  /// then is it worth checking whether an ordinary report beat us to it.
  bool _seekReportDeferred = false;

  StreamSubscription<TrackSelection>? _trackSelectionSubscription;

  /// Update interval (default: 10 seconds)
  final Duration updateInterval;

  /// Counts consecutive online progress failures for backoff logic.
  int _consecutiveFailures = 0;

  /// Timer ticks to skip before retrying after failures (exponential backoff).
  int _ticksToSkip = 0;

  /// Whether we've already scrobbled (marked as watched) for this playback session.
  bool _scrobbled = false;

  /// Whether the final stopped progress event was already emitted locally.
  bool _stopProgressNotified = false;

  Future<void>? _stoppedProgressFuture;

  /// A `stopped` that was still in flight when the player resumed. The next
  /// stop waits for it instead of being answered with it.
  Future<void>? _stopToDrain;

  Duration? _lastProgressNotifiedPosition;

  static const Duration _progressNotifyDelta = Duration(seconds: 30);

  /// State and position of the last report that actually reached the backend.
  /// A report that would repeat both is dropped: re-sending the same position
  /// is how a paused player kept overwriting a further-along one elsewhere.
  String? _lastReportedState;
  Duration? _lastReportedPosition;

  /// Sub-second drift is not movement. Anything smaller than this counts as
  /// the same position.
  static const Duration _minReportDelta = Duration(seconds: 1);

  /// How long to wait after the last seek before reporting the new position.
  static const Duration _seekReportDebounce = Duration(milliseconds: 500);

  final PlaybackReportSession? _reportSession;

  PlaybackProgressTracker({
    required this.client,
    required this.metadata,
    required this.player,
    this.isOffline = false,
    this.offlineWatchService,
    this.queueOnOnlineFailure = false,
    this.playMethod,
    this.playSessionId,
    this.mediaInfo,
    this.authority,
    this.updateInterval = const Duration(seconds: 10),
  }) : assert(!isOffline || offlineWatchService != null, 'offlineWatchService is required when isOffline is true'),
       assert(isOffline || client != null, 'client is required when isOffline is false'),
       _reportSession = isOffline || client == null
           ? null
           : PlaybackReportSession(
               client: client,
               itemId: metadata.id,
               playSessionId: playSessionId,
               playMethod: playMethod,
               authority: authority,
             );

  void startTracking() {
    if (_progressTimer != null) {
      appLogger.w('Progress tracking already started');
      return;
    }

    if (!isOffline) {
      _trackSelectionSubscription = player.streams.track.listen((_) {
        if (!player.state.isActive && (_reportSession?.isIdle ?? true)) return;
        final state = player.state.isActive ? 'playing' : 'paused';
        unawaited(_sendProgress(state));
      });
    }

    // Send initial progress immediately (don't wait for first timer tick)
    if (player.state.isActive) {
      _sendProgress('playing');
    }

    _startPeriodicTimer();

    appLogger.d('Started progress tracking (interval: ${updateInterval.inSeconds}s, offline: $isOffline)');
  }

  /// The periodic timer only reports while something is actually playing.
  ///
  /// There used to be a paused heartbeat here, firing a `paused` report every
  /// six ticks "to keep the server session alive". It also re-sent the same
  /// position indefinitely, so a player left paused on one device kept writing
  /// its stale position over a device that was still watching. A session
  /// keep-alive, if one turns out to be needed, belongs in a separate call that
  /// does not touch the canonical position.
  void _startPeriodicTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(updateInterval, (timer) {
      if (!player.state.isActive) return;
      // Skip ticks when backing off after consecutive failures to avoid
      // flooding the network with doomed requests during an outage.
      if (_ticksToSkip > 0) {
        _ticksToSkip--;
        return;
      }
      _sendProgress('playing');
    });
  }

  /// Report a seek right away instead of waiting for the next periodic tick.
  ///
  /// A jump is the one position change the throttles must not swallow: without
  /// this, seeking and closing within the tick window left the server on the
  /// pre-seek position. The trailing debounce collapses a scrub gesture into
  /// one report, and the periodic timer is restarted so the next tick is a full
  /// interval away.
  ///
  /// A failure backoff delays the report, it does not cancel it. Dropping it
  /// was worse than it looked: the periodic timer only runs while something is
  /// playing, so seeking and then pausing during a backoff left the server on
  /// the pre-seek position until playback happened to resume. The deferred
  /// re-arm drains [_ticksToSkip] at the same rate a playing timer would, so it
  /// makes progress while paused too.
  void onSeek() {
    _pendingSeekReport = true;
    _armSeekReportTimer(_seekReportDebounce);
  }

  void _armSeekReportTimer(Duration delay) {
    _seekReportTimer?.cancel();
    _seekReportTimer = Timer(delay, _fireSeekReport);
  }

  void _fireSeekReport() {
    _seekReportTimer = null;
    if (!_pendingSeekReport) return;
    if (_ticksToSkip > 0) {
      // Still backing off. Burn one tick's worth of wait and try again, so a
      // paused player converges instead of holding the seek forever.
      _ticksToSkip--;
      _seekReportDeferred = true;
      _armSeekReportTimer(updateInterval);
      return;
    }
    final wasDeferred = _seekReportDeferred;
    _pendingSeekReport = false;
    _seekReportDeferred = false;
    // A report that had to wait may already have been delivered by an ordinary
    // progress update in the meantime; a fresh seek is always worth sending.
    if (wasDeferred && !hasReportablePositionChange) return;
    _startPeriodicTimer();
    unawaited(_sendProgress(player.state.isActive ? 'playing' : 'paused', force: true));
  }

  /// Whether the current position differs enough from the last reported one to
  /// be worth a write. Used by the lifecycle paths to decide between one final
  /// report and none at all.
  bool get hasReportablePositionChange {
    final last = _lastReportedPosition;
    if (last == null) return true;
    return (player.state.position - last).abs() >= _minReportDelta;
  }

  void stopTracking() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _seekReportTimer?.cancel();
    _seekReportTimer = null;
    _pendingSeekReport = false;
    _seekReportDeferred = false;
    _trackSelectionSubscription?.cancel();
    _trackSelectionSubscription = null;
    appLogger.d('Stopped progress tracking');
  }

  /// [state] can be 'playing', 'paused', or 'stopped'.
  ///
  /// [force] bypasses the "same state, same position" suppression for a report
  /// the caller knows is meaningful even though it repeats the last one.
  Future<void> sendProgress(String state, {Duration? positionOverride, bool force = false}) async {
    await _sendProgress(state, positionOverride: positionOverride, force: force);
  }

  Future<void> sendStoppedProgressOnce({Duration? positionOverride}) {
    final existing = _stoppedProgressFuture;
    if (existing != null) return existing;
    // A stop that was still on the wire when the player resumed has to land
    // first. Without the wait this report would reach a session that is still
    // `stopping`, be answered with the old stop's future, and the position the
    // user actually left at would never be written.
    final draining = _stopToDrain;
    _stopToDrain = null;
    final future = draining == null
        ? sendProgress('stopped', positionOverride: positionOverride)
        : draining.then((_) => sendProgress('stopped', positionOverride: positionOverride));
    _stoppedProgressFuture = future;
    return future;
  }

  /// Re-arm the reporting after a terminal `stopped`, so the player can open a
  /// new session. Called on autoplay cancel, on an episode change, and on the
  /// resume that follows a backgrounded player.
  ///
  /// The order matters. [PlaybackReportSession.resetAfterStop] knows how to
  /// defer while a stop is in flight; the tracker's own latch does not, so it is
  /// handed to [_stopToDrain] instead of being dropped.
  void resumeAfterStoppedReport() {
    _reportSession?.resetAfterStop();
    // Never overwrite a drain that is still waiting. Two re-arms before the
    // next stop (autoplay cancelled at the end of a film, then a trip to the
    // home screen) would otherwise drop the first one, and the exit stop would
    // again be answered by a stop that is still on the wire.
    _stopToDrain = _stoppedProgressFuture ?? _stopToDrain;
    _stoppedProgressFuture = null;
    // The suppression cache describes what a *live* session was told, and a stop
    // ended that session. It matters because a report fired during the stopped
    // window is refused by the session but still remembered here: without this
    // the first report of the new session looks like a repeat of one the server
    // never received and is dropped.
    //
    // Only the state is forgotten, not the position. `hasReportablePositionChange`
    // reads the position, and a null there would tell the lifecycle layer that
    // something moved when nothing did, which is the repeat-position write the
    // whole suppression exists to prevent.
    _lastReportedState = null;
  }

  Future<void> _sendProgress(String state, {Duration? positionOverride, bool force = false}) async {
    Duration? attemptedPosition;
    Duration? attemptedDuration;
    try {
      final duration = player.state.duration;
      final position = _clampPosition(positionOverride ?? player.state.position, duration);
      attemptedPosition = position;
      attemptedDuration = duration;

      // Don't send progress if no duration (not ready)
      if (duration.inMilliseconds == 0) {
        return;
      }

      if (!force && !_isWorthReporting(state, position)) {
        return;
      }
      _lastReportedState = state;
      _lastReportedPosition = position;

      if (isOffline) {
        // Queue progress update for later sync
        await _sendOfflineProgress(position, duration);
        _notifyProgressIfNeeded(position, duration, isFinal: state == 'stopped', force: force);
      } else if (state == 'stopped') {
        // Stopped must complete before disposal
        final accepted = await _sendOnlineProgress(state, position, duration);
        _resetBackoff();
        if (accepted) {
          _notifyProgressIfNeeded(position, duration, isFinal: true);
        }
      } else {
        // Fire-and-forget for playing/paused — avoid blocking the Dart event loop
        unawaited(
          _sendOnlineProgress(state, position, duration)
              .then((accepted) {
                _resetBackoff();
                if (accepted) {
                  _notifyProgressIfNeeded(position, duration, force: force);
                }
              })
              .catchError((Object e) {
                _consecutiveFailures++;
                // Exponential backoff: skip 1, 2, 4, 8... ticks (capped at 6 ≈ 60s)
                _ticksToSkip = (1 << (_consecutiveFailures - 1)).clamp(1, 6);
                appLogger.d(
                  'Progress update failed ($_consecutiveFailures consecutive), '
                  'skipping next $_ticksToSkip tick(s)',
                  error: e,
                );
                unawaited(_queueOnlineFailureProgress(position, duration));
              }),
        );
      }
    } catch (e) {
      if (!isOffline) {
        _consecutiveFailures++;
        _ticksToSkip = (1 << (_consecutiveFailures - 1)).clamp(1, 6);
        appLogger.d(
          'Progress update failed ($_consecutiveFailures consecutive), '
          'skipping next $_ticksToSkip tick(s)',
          error: e,
        );
        await _queueOnlineFailureProgress(
          attemptedPosition ?? player.state.position,
          attemptedDuration ?? player.state.duration,
        );
      } else {
        appLogger.d('Failed to send progress update (non-critical)', error: e);
      }
    }
  }

  Duration _clampPosition(Duration position, Duration duration) {
    if (duration.inMilliseconds <= 0) return position;
    if (position.isNegative) return Duration.zero;
    if (position > duration) return duration;
    return position;
  }

  Future<void> _queueOnlineFailureProgress(Duration position, Duration duration) async {
    if (!queueOnOnlineFailure || offlineWatchService == null) return;
    if (duration.inMilliseconds == 0) return;
    try {
      await _sendOfflineProgress(_clampPosition(position, duration), duration);
    } catch (e) {
      appLogger.d('Failed to queue fallback progress after online report failure', error: e);
    }
  }

  void _resetBackoff() {
    if (_consecutiveFailures > 0) {
      _consecutiveFailures = 0;
      _ticksToSkip = 0;
    }
  }

  /// Whether this report says anything the backend does not already know.
  ///
  /// A state change always does. A position that moved does. Repeating both is
  /// the write that put an old position back, so it is dropped. `stopped` is
  /// exempt: the lifecycle layer decides whether to emit one at all, and once
  /// it does the report is terminal.
  bool _isWorthReporting(String state, Duration position) {
    if (state == 'stopped') return true;
    final lastState = _lastReportedState;
    final lastPosition = _lastReportedPosition;
    if (lastState == null || lastPosition == null) return true;
    if (lastState != state) return true;
    return (position - lastPosition).abs() >= _minReportDelta;
  }

  /// [isFinal] is the terminal stop notification, which fires at most once per
  /// session. [force] only bypasses the 30-second delta, for a jump the user
  /// made deliberately; it does not consume the terminal latch.
  void _notifyProgressIfNeeded(Duration position, Duration duration, {bool isFinal = false, bool force = false}) {
    if (_scrobbled) return;
    if (position.inMilliseconds <= 0 || duration.inMilliseconds <= 0) return;
    if (isFinal) {
      if (_stopProgressNotified) return;
      _stopProgressNotified = true;
    } else if (!force) {
      final last = _lastProgressNotifiedPosition;
      if (last != null && (position - last).abs() < _progressNotifyDelta) return;
    }

    _lastProgressNotifiedPosition = position;
    WatchStateNotifier().notifyProgress(
      item: metadata,
      viewOffset: position.inMilliseconds,
      duration: duration.inMilliseconds,
      watchedThreshold: client?.watchedThreshold ?? 0.9,
    );
  }

  /// Send progress update to the active server through the unified
  /// [MediaServerClient.reportPlayback*] surface.
  Future<bool> _sendOnlineProgress(String state, Duration position, Duration duration) async {
    final c = client;
    final session = _reportSession;
    if (c == null || session == null) return false;

    final accepted = await session.report(
      PlaybackReportSnapshot(
        state: state,
        position: position,
        duration: duration,
        resolveStreamSelection: state == 'stopped'
            ? _currentStreamSelectionForStopped
            : _currentStreamSelectionForProgress,
      ),
    );

    if (accepted) {
      await _maybeScrobble(c, position, duration);
    }
    return accepted;
  }

  PlaybackStreamSelection _currentStreamSelectionForStopped() {
    final info = mediaInfo;
    return info == null ? PlaybackStreamSelection.none : PlaybackStreamSelection(mediaSourceId: info.mediaSourceId);
  }

  Future<void> _maybeScrobble(MediaServerClient c, Duration position, Duration duration) async {
    // Explicitly scrobble once progress crosses the watched threshold.
    // Some servers (Plex with no active play session, Jellyfin always)
    // don't auto-mark from progress updates alone.
    if (!_scrobbled && duration.inMilliseconds > 0) {
      final percent = position.inMilliseconds / duration.inMilliseconds;
      final threshold = c.watchedThreshold;
      if (percent >= threshold) {
        _scrobbled = true;
        try {
          // Backends that mark the item played from the playback-stopped report
          // (Jellyfin) only emit the local watch event here — an explicit
          // markWatched would double-scrobble via the Trakt plugin (#1287).
          // Plex still issues the server call. Either path emits the watched
          // event through WatchStateNotifier, so no extra notify is needed.
          await c.markWatchedFromPlaybackStop(metadata);
          appLogger.d(
            'Scrobbled ${metadata.id} (${(percent * 100).toStringAsFixed(0)}% >= ${(threshold * 100).toStringAsFixed(0)}%)',
          );
        } catch (e) {
          appLogger.w('Failed to scrobble ${metadata.id}', error: e);
          _scrobbled = false; // Retry on next tick
        }
      }
    }
  }

  Future<PlaybackStreamSelection> _currentStreamSelectionForProgress() async {
    final info = mediaInfo;
    if (info == null) {
      return PlaybackStreamSelection.none;
    }

    if (!await _shouldReportTrackSelections()) {
      return PlaybackStreamSelection(mediaSourceId: info.mediaSourceId);
    }

    return PlaybackStreamSelection(
      mediaSourceId: info.mediaSourceId,
      audioStreamIndex: _currentAudioStreamIndex(info),
      subtitleStreamIndex: _currentSubtitleStreamIndex(info),
    );
  }

  Future<bool> _shouldReportTrackSelections() async {
    try {
      final settings = await SettingsService.getInstance();
      return settings.read(SettingsService.rememberTrackSelections);
    } catch (e) {
      appLogger.d('Could not read track-selection persistence setting; reporting selected streams', error: e);
      return true;
    }
  }

  int? _currentAudioStreamIndex(MediaSourceInfo info) {
    final playerAudioTracks = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (metadata.backend == MediaBackend.jellyfin &&
        (info.audioTracks.any((track) => track.isExternal) || playerAudioTracks.length <= 1)) {
      final selectedSourceTrack = _selectedSourceAudioTrack(info);
      if (selectedSourceTrack != null) return selectedSourceTrack.id;
    }

    final track = player.state.track.audio;
    if (track == null) return null;

    final ordinal = playerAudioTracks.indexOf(track);
    if (ordinal >= 0 && ordinal < info.audioTracks.length) return info.audioTracks[ordinal].id;

    final matched = findPlexTrackForMpvAudio(track, info.audioTracks, allMpvTracks: player.state.tracks.audio);
    if (matched != null) return matched.id;

    final parsedId = int.tryParse(track.id);
    if (parsedId != null && info.audioTracks.any((t) => t.id == parsedId)) return parsedId;

    return null;
  }

  MediaAudioTrack? _selectedSourceAudioTrack(MediaSourceInfo info) {
    for (final track in info.audioTracks) {
      if (track.selected) return track;
    }
    final defaultIndex = info.defaultAudioStreamIndex;
    if (defaultIndex == null) return null;
    for (final track in info.audioTracks) {
      if (track.id == defaultIndex) return track;
    }
    return null;
  }

  int? _currentSubtitleStreamIndex(MediaSourceInfo info) {
    final track = player.state.track.subtitle;
    if (track == null || track.id == 'no') return -1;

    if (track.isExternal && track.uri != null) {
      for (final mediaTrack in info.subtitleTracks) {
        final key = mediaTrack.key;
        if (mediaTrack.isExternal && key != null && track.uri!.contains(key)) {
          return mediaTrack.id;
        }
      }
    }

    final ordinal = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList().indexOf(track);
    if (ordinal >= 0 && ordinal < info.subtitleTracks.length) return info.subtitleTracks[ordinal].id;

    final matched = findPlexTrackForMpvSubtitle(track, info.subtitleTracks, allMpvTracks: player.state.tracks.subtitle);
    if (matched != null) return matched.id;

    final parsedId = int.tryParse(track.id);
    if (parsedId != null && info.subtitleTracks.any((t) => t.id == parsedId)) return parsedId;

    return null;
  }

  /// Queue progress update locally (offline mode)
  Future<void> _sendOfflineProgress(Duration position, Duration duration) async {
    final serverId = metadata.serverId;
    if (serverId == null) {
      appLogger.w('Cannot queue offline progress: serverId is null');
      return;
    }

    await offlineWatchService!.queueProgressUpdate(
      serverId: ServerId(serverId),
      itemId: metadata.id,
      viewOffset: position.inMilliseconds,
      duration: duration.inMilliseconds,
    );

    final percent = (position.inMilliseconds / duration.inMilliseconds * 100);
    appLogger.d(
      'Offline progress queued: ${position.inSeconds}s / ${duration.inSeconds}s (${percent.toStringAsFixed(1)}%)',
    );
  }

  void dispose() {
    stopTracking();
  }
}
