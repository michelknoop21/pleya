import 'dart:async';
import 'package:pleya/media/ids.dart';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/playback_progress_tracker.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

import '../test_helpers/prefs.dart';

// NOTE on coverage scope:
// `PlaybackProgressTracker` periodically samples the player's position and
// reports it to either an online [PlexClient] or the offline queue. The
// periodic [Timer] is purely a wall-clock concern — instead of trying to
// virtualize it, we exercise the routing/threshold/scrobble logic directly
// through the public [PlaybackProgressTracker.sendProgress].
//
// Coverage:
//   - Constructor invariants (offline ↔ offlineWatchService, online ↔ client).
//   - Online routing: 'stopped' awaits, 'playing'/'paused' fire-and-forget.
//   - Threshold gating: scrobbles once when percent >= server threshold.
//   - Scrobble idempotency: a second sendProgress past threshold is a no-op.
//   - Offline routing: queues a progress update via the database.
//   - Offline progress with null serverId is a no-op (no queue write).
//   - 'stopped' event emits a WatchStateNotifier.notifyProgress.
//   - dispose() / stopTracking() are idempotent.
//
// What is NOT covered (by design):
//   - The periodic [Timer.periodic] tick itself — we'd need to either drive
//     real time (flaky) or inject a clock dependency (out of scope).
//   - The exponential-backoff state — observable only across multiple ticks
//     under wall time.

/// Fake Player whose state is mutable from the test.
class _FakePlayer implements Player {
  PlayerState _state;
  final PlayerStreams _streams = const PlayerStreams(
    playing: Stream<bool>.empty(),
    completed: Stream<bool>.empty(),
    buffering: Stream<bool>.empty(),
    position: Stream<Duration>.empty(),
    duration: Stream<Duration>.empty(),
    seekable: Stream<bool>.empty(),
    buffer: Stream<Duration>.empty(),
    volume: Stream<double>.empty(),
    rate: Stream<double>.empty(),
    tracks: Stream<Tracks>.empty(),
    track: Stream<TrackSelection>.empty(),
    log: Stream<PlayerLog>.empty(),
    error: Stream<PlayerError>.empty(),
    audioDevice: Stream<AudioDevice>.empty(),
    audioDevices: Stream<List<AudioDevice>>.empty(),
    bufferRanges: Stream<List<BufferRange>>.empty(),
    playbackRestart: Stream<void>.empty(),
    backendSwitched: Stream<void>.empty(),
  );

  _FakePlayer({
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    bool playing = true,
    Tracks tracks = const Tracks(),
    TrackSelection track = const TrackSelection(),
  }) : _state = PlayerState(playing: playing, duration: duration, position: position, tracks: tracks, track: track);

  @override
  PlayerState get state => _state;

  @override
  PlayerStreams get streams => _streams;

  set position(Duration value) {
    _state = _state.copyWith(position: value);
  }

  set duration(Duration value) {
    _state = _state.copyWith(duration: value);
  }

  set playing(bool value) {
    _state = _state.copyWith(playing: value);
  }

  set completed(bool value) {
    _state = _state.copyWith(completed: value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Recording fake [PlexClient] that captures every progress / scrobble call
/// without touching the network.
class _FakePlexClient implements PlexClient {
  _FakePlexClient({this.thresholdPercent = 90});

  /// Watched-threshold percentage to report. Defaults to 90 (matches
  /// production fallback).
  final int thresholdPercent;

  /// Override [PlexClient.watchedThresholdPercent] without going through
  /// `_serverPrefs`.
  @override
  int get watchedThresholdPercent => thresholdPercent;

  /// markWatchedFromPlaybackStop resolves the event's cacheServerId from
  /// [serverId] after the transport call.
  @override
  ServerId get serverId => ServerId('scrobbler');

  @override
  double get watchedThreshold => thresholdPercent / 100.0;

  /// Plex relies on the explicit markWatched call (no auto-mark from the stop
  /// report), so the scrobble path hits [markWatched].
  @override
  bool get marksWatchedOnPlaybackStopped => false;

  /// (ratingKey, time, state, duration) tuples for every updateProgress call.
  final List<({String ratingKey, int time, String state, int? duration})> updateProgressCalls = [];

  /// Rating keys passed to markWatched.
  final List<String> markWatchedCalls = [];

  /// PlaySessionIds forwarded through the reportPlayback* methods.
  final List<String?> playbackSessionIds = [];

  final List<({String? mediaSourceId, int? audioStreamIndex, int? subtitleStreamIndex})> playbackStreamSelections = [];

  /// If non-null, the next reportPlayback*/markWatched call throws this.
  Object? throwOnNextCall;

  @override
  Future<void> updateProgress(
    String ratingKey, {
    required int time,
    required String state,
    int? duration,
    String? sessionIdentifier,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    if (throwOnNextCall != null) {
      final err = throwOnNextCall!;
      throwOnNextCall = null;
      throw err;
    }
    updateProgressCalls.add((ratingKey: ratingKey, time: time, state: state, duration: duration));
  }

  // The interface report* methods delegate to updateProgress so existing
  // assertions on `updateProgressCalls` keep working.
  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    playbackSessionIds.add(playSessionId);
    playbackStreamSelections.add((
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    ));
    return updateProgress(itemId, time: position.inMilliseconds, state: 'playing', duration: duration?.inMilliseconds);
  }

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    bool isPaused = false,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    playbackSessionIds.add(playSessionId);
    playbackStreamSelections.add((
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    ));
    return updateProgress(
      itemId,
      time: position.inMilliseconds,
      state: isPaused ? 'paused' : 'playing',
      duration: duration.inMilliseconds,
    );
  }

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) {
    playbackSessionIds.add(playSessionId);
    playbackStreamSelections.add((mediaSourceId: mediaSourceId, audioStreamIndex: null, subtitleStreamIndex: null));
    return updateProgress(itemId, time: position.inMilliseconds, state: 'stopped', duration: duration?.inMilliseconds);
  }

  // Transport-only, like production: the single watch event for the stop
  // flow is emitted by markWatchedFromPlaybackStop after this returns.
  @override
  Future<void> markWatched(MediaItem item) async {
    if (throwOnNextCall != null) {
      final err = throwOnNextCall!;
      throwOnNextCall = null;
      throw err;
    }
    markWatchedCalls.add(item.id);
  }

  @override
  Future<void> markAsWatched(String ratingKey) async {
    if (throwOnNextCall != null) {
      final err = throwOnNextCall!;
      throwOnNextCall = null;
      throw err;
    }
    markWatchedCalls.add(ratingKey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedStartClient extends _FakePlexClient {
  final Completer<void> startCompleter = Completer<void>();

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await startCompleter.future;
    await super.reportPlaybackStarted(
      itemId: itemId,
      position: position,
      duration: duration,
      playSessionId: playSessionId,
      playMethod: playMethod,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
  }
}

/// Jellyfin-style backend: the playback-stopped report marks the item played
/// server-side, so the in-player scrobble path must emit only the local watch
/// event and skip the explicit server mark (#1287).
class _StopMarksWatchedClient extends _FakePlexClient {
  @override
  bool get marksWatchedOnPlaybackStopped => true;

  @override
  ServerId get serverId => ServerId('srv');
}

const Object _defaultServerId = Object();

MediaItem _meta({String ratingKey = '42', Object? serverId = _defaultServerId, String? type = 'movie'}) => MediaItem(
  id: ratingKey,
  backend: MediaBackend.plex,
  kind: MediaKind.fromString(type),
  title: 'Test Item',
  serverId: identical(serverId, _defaultServerId) ? ServerId('srv') : serverId as ServerId?,
);

void main() {
  setUp(resetSharedPreferencesForTest);

  // ============================================================
  // Constructor assertions
  // ============================================================

  group('constructor assertions', () {
    test('offline=true requires offlineWatchService', () {
      expect(
        () => PlaybackProgressTracker(client: null, metadata: _meta(), player: _FakePlayer(), isOffline: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('offline=false requires client', () {
      expect(
        () => PlaybackProgressTracker(client: null, metadata: _meta(), player: _FakePlayer(), isOffline: false),
        throwsA(isA<AssertionError>()),
      );
    });

    test('valid online construction succeeds', () {
      final tracker = PlaybackProgressTracker(
        client: _FakePlexClient(),
        metadata: _meta(),
        player: _FakePlayer(),
        isOffline: false,
      );
      addTearDown(tracker.dispose);
      // No assertion — the constructor returned cleanly.
      expect(tracker, isNotNull);
    });
  });

  // ============================================================
  // sendProgress: short-circuit on duration=0
  // ============================================================

  group('sendProgress: duration guard', () {
    test('does NOT send progress when duration is zero (player not yet ready)', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(); // duration = Duration.zero
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');
      expect(client.updateProgressCalls, isEmpty);
      expect(client.markWatchedCalls, isEmpty);
    });
  });

  // ============================================================
  // sendProgress: online routing
  // ============================================================

  group('sendProgress: online', () {
    test('"stopped" awaits the underlying call and reports correct args', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');

      // updateProgress is awaited synchronously when state == 'stopped'.
      expect(client.updateProgressCalls, hasLength(1));
      final call = client.updateProgressCalls.single;
      expect(call.ratingKey, '42');
      expect(call.time, 30000); // 30s in ms
      expect(call.state, 'stopped');
      expect(call.duration, 100000); // 100s in ms
    });

    test('"stopped" can override stale player position for completion', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 12), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped', positionOverride: const Duration(seconds: 100));

      expect(client.updateProgressCalls.single.time, 100000);
      expect(client.markWatchedCalls, ['42']);
    });

    test('"playing" fires-and-forgets but eventually invokes updateProgress', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      // The unawaited Future may not have settled yet — drain microtasks.
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls, hasLength(1));
      expect(client.updateProgressCalls.single.state, 'playing');
    });

    test('forwards PlaySessionId to started, progress, and stopped reports', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
        playSessionId: 'play-session-1',
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      // The position has to move: a report that repeats the previous state and
      // position is now dropped on purpose.
      player.position = const Duration(seconds: 15);
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      await tracker.sendProgress('stopped');

      expect(client.updateProgressCalls.map((call) => call.state), ['playing', 'playing', 'stopped']);
      expect(client.playbackSessionIds, ['play-session-1', 'play-session-1', 'play-session-1']);
    });

    test('coalesces concurrent start reports while the first start is in flight', () async {
      final client = _DelayedStartClient();
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      expect(client.updateProgressCalls, isEmpty);

      client.startCompleter.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.map((call) => call.state), ['playing']);
    });

    test('orders stopped after an in-flight start report', () async {
      final client = _DelayedStartClient();
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      final stopFuture = tracker.sendProgress('stopped');
      await Future<void>.delayed(Duration.zero);
      expect(client.updateProgressCalls, isEmpty);

      client.startCompleter.complete();
      await stopFuture;

      expect(client.updateProgressCalls.map((call) => call.state), ['playing', 'stopped']);
    });

    test('does not send queued progress after terminal stopped state', () async {
      final client = _DelayedStartClient();
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      final stopFuture = tracker.sendProgress('stopped');
      client.startCompleter.complete();
      await stopFuture;

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.map((call) => call.state), ['playing', 'stopped']);
    });

    test('coalesces concurrent stopped reports into one terminal stop', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      final events = <WatchStateEvent>[];
      final sub = WatchStateNotifier().forItem('42').listen(events.add);
      addTearDown(sub.cancel);

      await Future.wait([tracker.sendProgress('stopped'), tracker.sendProgress('stopped')]);
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.map((call) => call.state), ['stopped']);
      expect(events.where((e) => e.changeType == WatchStateChangeType.progressUpdate), hasLength(1));
    });

    test('allows a later stopped report to retry after final stop fails', () async {
      final client = _FakePlexClient()..throwOnNextCall = Exception('network blip');
      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');
      expect(client.updateProgressCalls, isEmpty);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      expect(client.updateProgressCalls, isEmpty);

      await tracker.sendProgress('stopped');
      expect(client.updateProgressCalls.map((call) => call.state), ['stopped']);
    });

    test('maps current player tracks to server stream indexes for progress reports', () async {
      final client = _FakePlexClient();
      const selectedAudio = AudioTrack(id: 'audio_1', language: 'jpn');
      const subtitlesOff = SubtitleTrack(id: 'no');
      final player = _FakePlayer(
        position: const Duration(seconds: 5),
        duration: const Duration(seconds: 100),
        tracks: const Tracks(
          audio: [
            AudioTrack(id: 'audio_0', language: 'eng'),
            selectedAudio,
          ],
          subtitle: [SubtitleTrack(id: 'text_0', language: 'eng')],
        ),
        track: const TrackSelection(audio: selectedAudio, subtitle: subtitlesOff),
      );
      final mediaInfo = MediaSourceInfo(
        videoUrl: '',
        audioTracks: [
          MediaAudioTrack(id: 1, languageCode: 'eng', selected: false),
          MediaAudioTrack(id: 2, languageCode: 'jpn', selected: true),
        ],
        subtitleTracks: [MediaSubtitleTrack(id: 3, languageCode: 'eng', selected: false, forced: false)],
        chapters: const [],
        mediaSourceId: 'source-1',
      );
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
        mediaInfo: mediaInfo,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      // Second report needs a moved position; a repeat of the same state and
      // position no longer reaches the backend.
      player.position = player.state.position + const Duration(seconds: 10);
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      final progressSelection = client.playbackStreamSelections[1];
      expect(progressSelection.mediaSourceId, 'source-1');
      expect(progressSelection.audioStreamIndex, 2);
      expect(progressSelection.subtitleStreamIndex, -1);
    });

    test('Jellyfin progress reports selected source audio when player exposes a single output track', () async {
      final client = _FakePlexClient();
      const outputAudio = AudioTrack(id: 'audio_0', language: 'jpn');
      const subtitlesOff = SubtitleTrack(id: 'no');
      final player = _FakePlayer(
        position: const Duration(seconds: 5),
        duration: const Duration(seconds: 100),
        tracks: const Tracks(
          audio: [outputAudio],
          subtitle: [SubtitleTrack(id: 'text_0', language: 'eng')],
        ),
        track: const TrackSelection(audio: outputAudio, subtitle: subtitlesOff),
      );
      final mediaInfo = MediaSourceInfo(
        videoUrl: '',
        audioTracks: [
          MediaAudioTrack(id: 1, languageCode: 'eng', selected: false),
          MediaAudioTrack(id: 4, languageCode: 'jpn', selected: true, external: true),
        ],
        subtitleTracks: [MediaSubtitleTrack(id: 3, languageCode: 'eng', selected: false, forced: false)],
        chapters: const [],
        mediaSourceId: 'source-1',
      );
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: MediaItem(id: '42', backend: MediaBackend.jellyfin, kind: MediaKind.movie, serverId: 'srv'),
        player: player,
        isOffline: false,
        mediaInfo: mediaInfo,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      // Second report needs a moved position; a repeat of the same state and
      // position no longer reaches the backend.
      player.position = player.state.position + const Duration(seconds: 10);
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      final progressSelection = client.playbackStreamSelections[1];
      expect(progressSelection.mediaSourceId, 'source-1');
      expect(progressSelection.audioStreamIndex, 4);
      expect(progressSelection.subtitleStreamIndex, -1);
    });

    test('stopped reports only resolve media source and do not include selected streams', () async {
      final client = _FakePlexClient();
      const selectedAudio = AudioTrack(id: 'audio_1', language: 'jpn');
      final player = _FakePlayer(
        position: const Duration(seconds: 5),
        duration: const Duration(seconds: 100),
        tracks: const Tracks(
          audio: [selectedAudio],
          subtitle: [SubtitleTrack(id: 'text_0', language: 'eng')],
        ),
        track: const TrackSelection(
          audio: selectedAudio,
          subtitle: SubtitleTrack(id: 'text_0', language: 'eng'),
        ),
      );
      final mediaInfo = MediaSourceInfo(
        videoUrl: '',
        audioTracks: [MediaAudioTrack(id: 2, languageCode: 'jpn', selected: true)],
        subtitleTracks: [MediaSubtitleTrack(id: 3, languageCode: 'eng', selected: true, forced: false)],
        chapters: const [],
        mediaSourceId: 'source-1',
      );
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
        mediaInfo: mediaInfo,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');

      expect(client.playbackStreamSelections, hasLength(1));
      expect(client.playbackStreamSelections.single.mediaSourceId, 'source-1');
      expect(client.playbackStreamSelections.single.audioStreamIndex, isNull);
      expect(client.playbackStreamSelections.single.subtitleStreamIndex, isNull);
    });
  });

  // ============================================================
  // Threshold gating + scrobble
  // ============================================================

  group('threshold gating', () {
    test('does NOT scrobble when percent < watchedThresholdPercent', () async {
      // 89% < 90% threshold.
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: const Duration(seconds: 89), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');
      expect(client.markWatchedCalls, isEmpty);
    });

    test('scrobbles when percent >= watchedThresholdPercent', () async {
      // 95% >= 90% threshold.
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: const Duration(seconds: 95), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');

      expect(client.markWatchedCalls, ['42']);
    });

    test('backend that marks watched on stop skips the explicit server mark (#1287)', () async {
      // Jellyfin: /Sessions/Playing/Stopped marks the item played server-side,
      // so an explicit markWatched here would double-scrobble via the Trakt
      // plugin. The local watch event must still fire (UI + Plezy's own Trakt
      // sync, which key on `watched` events, not progress).
      final client = _StopMarksWatchedClient();
      final player = _FakePlayer(position: const Duration(seconds: 95), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      final watched = <WatchStateEvent>[];
      final sub = WatchStateNotifier()
          .forItem('42')
          .where((e) => e.changeType == WatchStateChangeType.watched)
          .listen(watched.add);
      addTearDown(sub.cancel);

      await tracker.sendProgress('stopped');
      await Future<void>.delayed(Duration.zero);

      expect(client.markWatchedCalls, isEmpty);
      expect(watched, hasLength(1));
    });

    test('respects a custom server threshold (e.g. 80%)', () async {
      // 81% >= 80%, but < 90% default.
      final client = _FakePlexClient(thresholdPercent: 80);
      final player = _FakePlayer(position: const Duration(seconds: 81), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');
      expect(client.markWatchedCalls, ['42']);
    });

    test('scrobble is idempotent across multiple progress calls', () async {
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: const Duration(seconds: 95), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped');
      await tracker.sendProgress('stopped');
      await tracker.sendProgress('stopped');

      // markAsWatched fired exactly once — _scrobbled stays true.
      expect(client.markWatchedCalls, hasLength(1));
    });

    test('a failed scrobble is retried on the next call (resets _scrobbled)', () async {
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: const Duration(seconds: 95), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      // First call: updateProgress succeeds, then markAsWatched throws.
      // To make the *second* method (markAsWatched) throw, we need a flag that
      // only triggers on the 2nd call. The fake's `throwOnNextCall` consumes
      // on the first call, which is updateProgress. Workaround: arm the throw
      // immediately before sendProgress, so updateProgress fails. The catch
      // branch in PlaybackProgressTracker still bumps the failure counter for
      // online stopped calls (and skips scrobble). Then arm again — updateProgress
      // succeeds (because the throw was consumed) — and assert markAsWatched
      // succeeds and scrobbles.
      //
      // To target ONLY markAsWatched, we instead use a custom client.
      final precise = _ScrobblePreciseClient(thresholdPercent: 90, failScrobbleFirstTime: true);
      final tracker2 = PlaybackProgressTracker(
        client: precise,
        metadata: _meta(ratingKey: '42'),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker2.dispose);

      await tracker2.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      expect(precise.markWatchedAttempts, 1);

      // Retry — markAsWatched now succeeds. The position moves because a
      // report repeating the previous state and position is suppressed.
      player.position = player.state.position + const Duration(seconds: 1);
      await tracker2.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      expect(precise.markWatchedAttempts, 2);
      expect(precise.markWatchedSuccesses, 1);
    });
  });

  // ============================================================
  // Offline routing
  // ============================================================

  group('sendProgress: offline', () {
    Future<({OfflineWatchSyncService svc, AppDatabase db, MultiServerManager mgr})> makeOfflineService() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final mgr = MultiServerManager();
      final svc = OfflineWatchSyncService(database: db, serverManager: mgr);
      return (svc: svc, db: db, mgr: mgr);
    }

    test('queues a progress update via the offline service', () async {
      final (svc: svc, db: db, mgr: mgr) = await makeOfflineService();
      addTearDown(() async {
        svc.dispose();
        mgr.dispose();
        await db.close();
      });

      final player = _FakePlayer(position: const Duration(seconds: 12), duration: const Duration(seconds: 60));
      final tracker = PlaybackProgressTracker(
        client: null,
        metadata: _meta(ratingKey: '42', serverId: ServerId('srv')),
        player: player,
        isOffline: true,
        offlineWatchService: svc,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');

      // Local DB now has a progress row for srv:42.
      final action = await db.getLatestWatchAction('srv:42');
      expect(action, isNotNull);
      expect(action!.actionType, 'progress');
      expect(action.viewOffset, 12000); // 12s in ms
      expect(action.duration, 60000);
    });

    test('offline + null serverId is a no-op (does NOT throw, does NOT queue)', () async {
      final (svc: svc, db: db, mgr: mgr) = await makeOfflineService();
      addTearDown(() async {
        svc.dispose();
        mgr.dispose();
        await db.close();
      });

      final player = _FakePlayer(position: const Duration(seconds: 5), duration: const Duration(seconds: 60));
      final tracker = PlaybackProgressTracker(
        client: null,
        metadata: _meta(ratingKey: '42', serverId: null), // <— no serverId
        player: player,
        isOffline: true,
        offlineWatchService: svc,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      expect(await svc.getPendingSyncCount(), 0);
    });

    test('online local playback queues fallback progress when reporting fails', () async {
      final (svc: svc, db: db, mgr: mgr) = await makeOfflineService();
      addTearDown(() async {
        svc.dispose();
        mgr.dispose();
        await db.close();
      });

      final client = _FakePlexClient()..throwOnNextCall = StateError('offline');
      final player = _FakePlayer(position: const Duration(seconds: 10), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
        offlineWatchService: svc,
        queueOnOnlineFailure: true,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('stopped', positionOverride: const Duration(seconds: 100));

      final action = await db.getLatestWatchAction('srv:42');
      expect(action, isNotNull);
      expect(action!.viewOffset, 100000);
      expect(action.shouldMarkWatched, isTrue);
    });
  });

  // ============================================================
  // WatchStateNotifier emission on 'stopped'
  // ============================================================

  group('WatchStateNotifier event on "stopped"', () {
    test('emits a progress-update event when stopped past position 0', () async {
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      // Subscribe before triggering the event.
      final events = <WatchStateEvent>[];
      final sub = WatchStateNotifier().forItem('42').listen(events.add);
      addTearDown(sub.cancel);

      await tracker.sendProgress('stopped');
      // Stream is broadcast — give it a microtask.
      await Future<void>.delayed(Duration.zero);

      // We expect at least one progressUpdate event for ratingKey=42.
      final progressEvents = events.where((e) => e.changeType == WatchStateChangeType.progressUpdate).toList();
      expect(progressEvents, isNotEmpty);
      expect(progressEvents.first.viewOffset, 30000);
    });

    test('does NOT emit on "stopped" if position is 0 (no real watch)', () async {
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: Duration.zero, duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: 'no-watch', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      final events = <WatchStateEvent>[];
      final sub = WatchStateNotifier().forItem('no-watch').listen(events.add);
      addTearDown(sub.cancel);

      await tracker.sendProgress('stopped');
      await Future<void>.delayed(Duration.zero);

      // No progressUpdate event.
      expect(events.where((e) => e.changeType == WatchStateChangeType.progressUpdate), isEmpty);
    });

    test('does NOT emit a progress event when scrobble already fired', () async {
      // 95% triggers a scrobble (markAsWatched → notifyWatched). The progress
      // event must be suppressed by the `_scrobbled` flag.
      final client = _FakePlexClient(thresholdPercent: 90);
      final player = _FakePlayer(position: const Duration(seconds: 95), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: 'scrobbler', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
      );
      addTearDown(tracker.dispose);

      final events = <WatchStateEvent>[];
      final sub = WatchStateNotifier().forItem('scrobbler').listen(events.add);
      addTearDown(sub.cancel);

      await tracker.sendProgress('stopped');
      await Future<void>.delayed(Duration.zero);

      // Watched event from markAsWatched fires; progressUpdate is suppressed.
      final watched = events.where((e) => e.changeType == WatchStateChangeType.watched).toList();
      final progress = events.where((e) => e.changeType == WatchStateChangeType.progressUpdate).toList();
      expect(watched, hasLength(1));
      expect(progress, isEmpty);
    });
  });

  // ============================================================
  // startTracking / stopTracking / dispose lifecycle
  // ============================================================

  group('lifecycle', () {
    test('startTracking + stopTracking is a clean no-op for an inactive player', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(playing: false); // not active
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      tracker.startTracking();
      tracker.stopTracking();

      // No initial 'playing' progress was sent because the player wasn't active.
      // Drain anyway in case the unawaited future raced.
      await Future<void>.delayed(Duration.zero);
      expect(client.updateProgressCalls, isEmpty);
    });

    test('startTracking is idempotent: a second call logs a warning and no-ops', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(playing: false); // skip the immediate fire
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(),
        player: player,
        isOffline: false,
        updateInterval: const Duration(hours: 1), // long enough that no tick fires in the test window
      );
      addTearDown(tracker.dispose);

      tracker.startTracking();
      tracker.startTracking(); // second call should warn and bail
      tracker.stopTracking();
      // No exception is the contract.
    });

    test('dispose is idempotent', () {
      final client = _FakePlexClient();
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(),
        player: _FakePlayer(playing: false),
        isOffline: false,
      );
      tracker.dispose();
      // Calling dispose again must not throw.
      expect(tracker.dispose, returnsNormally);
    });
  });

  // ============================================================
  // Report suppression, seek reporting, and the removed paused heartbeat
  // ============================================================

  group('report suppression', () {
    test('a repeat of the same state and position is not written', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.length, 1);
    });

    test('sub-second drift counts as the same position', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      player.position = const Duration(milliseconds: 30400);
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.length, 1);
    });

    test('a moved position is written', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      player.position = const Duration(seconds: 45);
      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.map((c) => c.time), [30000, 45000]);
    });

    test('a state change at the same position is written once', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      await tracker.sendProgress('paused');
      await Future<void>.delayed(Duration.zero);
      await tracker.sendProgress('paused');
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.map((c) => c.state), ['playing', 'paused']);
    });

    test('force writes a repeat the caller knows is meaningful', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      await tracker.sendProgress('playing', force: true);
      await Future<void>.delayed(Duration.zero);

      expect(client.updateProgressCalls.length, 2);
    });

    test('hasReportablePositionChange reflects movement since the last report', () async {
      final client = _FakePlexClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
      final tracker = PlaybackProgressTracker(client: client, metadata: _meta(), player: player, isOffline: false);
      addTearDown(tracker.dispose);

      expect(tracker.hasReportablePositionChange, isTrue, reason: 'nothing reported yet');

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);
      expect(tracker.hasReportablePositionChange, isFalse);

      player.position = const Duration(seconds: 45);
      expect(tracker.hasReportablePositionChange, isTrue);
    });
  });

  group('paused heartbeat removal', () {
    test('a paused player writes nothing on any number of ticks', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 10),
          playing: false,
        );
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );

        tracker.startTracking();
        // The old heartbeat fired every sixth tick (~60s). Ten minutes of
        // ticks is ten chances for it to write the same stale position.
        async.elapse(const Duration(minutes: 10));
        tracker.dispose();

        expect(client.updateProgressCalls, isEmpty);
      });
    });

    test('Mutiny: a paused player never re-reports its older position', () {
      // MacBook paused with 1:03 remaining; the Apple TV plays on. Before the
      // change, the paused MacBook wrote 'paused' at its own position every
      // ~60 seconds, and each of those writes moved the server back.
      fakeAsync((async) {
        final client = _FakePlexClient();
        const runtime = Duration(hours: 1, minutes: 40);
        final macbook = _FakePlayer(position: runtime - const Duration(minutes: 63), duration: runtime, playing: false);
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: macbook,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );

        tracker.startTracking();
        async.elapse(const Duration(minutes: 30));
        tracker.dispose();

        expect(client.updateProgressCalls, isEmpty);
      });
    });

    test('an active player still ticks', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );

        tracker.startTracking();
        async.flushMicrotasks();
        player.position = const Duration(seconds: 40);
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        tracker.dispose();

        expect(client.updateProgressCalls.map((c) => c.time), [30000, 40000]);
      });
    });
  });

  group('seek reporting', () {
    test('a seek reports after the trailing debounce, without waiting for a tick', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(client.updateProgressCalls.map((c) => c.time), [300000]);
      });
    });

    test('a scrub gesture collapses into one report', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        for (final minute in [2, 3, 4, 5]) {
          player.position = Duration(minutes: minute);
          tracker.onSeek();
          async.elapse(const Duration(milliseconds: 100));
        }
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(client.updateProgressCalls.map((c) => c.time), [300000]);
      });
    });

    test('a seek resets the periodic timer instead of firing alongside it', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        // Seek at t+8s: the pre-change periodic timer would still fire at
        // t+10s. After the reset the next tick is a full interval past the
        // seek report, so nothing lands in between.
        async.elapse(const Duration(seconds: 8));
        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        expect(client.updateProgressCalls.map((c) => c.time), [300000]);

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(client.updateProgressCalls.map((c) => c.time), [300000], reason: 'timer was restarted at the seek');
      });
    });

    test('the seek report is not swallowed by the 30-second notify throttle', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        final events = <WatchStateEvent>[];
        final sub = WatchStateNotifier().stream.listen(events.add);
        addTearDown(sub.cancel);

        tracker.startTracking();
        async.flushMicrotasks();
        events.clear();

        // Only 10 seconds further than the last notified position: without
        // the force flag the delta throttle would drop this entirely.
        player.position = const Duration(seconds: 40);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(events.map((e) => e.viewOffset), [40000]);
      });
    });

    test('a seek during an active failure backoff is postponed, not dropped', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();

        // Fail one report so the backoff arms.
        client.throwOnNextCall = StateError('network down');
        player.position = const Duration(seconds: 45);
        tracker.sendProgress('playing');
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(client.updateProgressCalls, isEmpty);

        // Positive control: once the backoff has burned its skipped tick, the
        // very same seek does report. Without this the test above would pass
        // just as happily if seeks never reported at all.
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        client.updateProgressCalls.clear();
        player.position = const Duration(minutes: 6);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        expect(client.updateProgressCalls.map((c) => c.time), [360000]);
      });
    });

    // A backoff delays a seek report; it must never lose it. The paused case is
    // the one that actually bit: the periodic timer only runs while something
    // plays, so a dropped seek on a paused player left the server on the
    // pre-seek position with nothing left to correct it.
    test('a seek made during a backoff still arrives once the backoff expires', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();

        client.throwOnNextCall = StateError('network down');
        player.position = const Duration(seconds: 45);
        tracker.sendProgress('playing');
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        expect(client.updateProgressCalls, isEmpty, reason: 'backoff is still active');

        async.elapse(const Duration(seconds: 11));
        async.flushMicrotasks();
        expect(
          client.updateProgressCalls.map((c) => c.time),
          contains(300000),
          reason: 'the postponed seek position reaches the backend after the backoff',
        );
      });
    });

    test('a seek during a backoff arrives even while the player is paused', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();

        client.throwOnNextCall = StateError('network down');
        player.position = const Duration(seconds: 45);
        tracker.sendProgress('playing');
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        // Seek, then pause. The periodic timer now reports nothing at all, so
        // the deferred seek is the only path left.
        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        player.playing = false;

        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(client.updateProgressCalls.map((c) => c.time), [300000]);
        expect(client.updateProgressCalls.map((c) => c.state), ['paused']);
      });
    });

    test('several seeks during one backoff still produce a single report', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();

        client.throwOnNextCall = StateError('network down');
        player.position = const Duration(seconds: 45);
        tracker.sendProgress('playing');
        async.flushMicrotasks();
        client.updateProgressCalls.clear();
        player.playing = false;

        for (final minute in [2, 3, 4, 5]) {
          player.position = Duration(minutes: minute);
          tracker.onSeek();
          async.elapse(const Duration(milliseconds: 100));
        }
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(client.updateProgressCalls.map((c) => c.time), [300000]);
      });
    });

    test('a postponed seek is dropped when an ordinary report already delivered that position', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();

        client.throwOnNextCall = StateError('network down');
        player.position = const Duration(seconds: 45);
        tracker.sendProgress('playing');
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();

        // The periodic timer burns the remaining backoff tick and reports the
        // very same position. The postponed seek must not repeat it.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(
          client.updateProgressCalls.where((c) => c.time == 300000).length,
          1,
          reason: 'position 5:00 reaches the backend exactly once',
        );
      });
    });

    test('stopTracking discards a postponed seek instead of firing it later', () {
      fakeAsync((async) {
        final client = _FakePlexClient();
        final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(minutes: 10));
        final tracker = PlaybackProgressTracker(
          client: client,
          metadata: _meta(),
          player: player,
          isOffline: false,
          updateInterval: const Duration(seconds: 10),
        );
        addTearDown(tracker.dispose);

        tracker.startTracking();
        async.flushMicrotasks();

        client.throwOnNextCall = StateError('network down');
        player.position = const Duration(seconds: 45);
        tracker.sendProgress('playing');
        async.flushMicrotasks();
        client.updateProgressCalls.clear();

        player.position = const Duration(minutes: 5);
        tracker.onSeek();
        tracker.stopTracking();

        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        expect(client.updateProgressCalls, isEmpty);
      });
    });
  });

  // ============================================================
  // The exit path must not wait on the final report
  // ============================================================

  group('stopped report deadline', () {
    Future<({OfflineWatchSyncService svc, AppDatabase db, MultiServerManager mgr})> makeOfflineService() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final mgr = MultiServerManager();
      return (svc: OfflineWatchSyncService(database: db, serverManager: mgr), db: db, mgr: mgr);
    }

    test('a stop report that never answers releases the caller and is queued locally', () async {
      // The PS-4 acceptance round, in one test: two devices on one tunnel, the
      // watch-state POST sitting in a connect timeout, and the player teardown
      // waiting behind it. Twelve seconds of black screen (log kzq7c, back at
      // 21:52:44.566, POST failed at 21:52:56.559). Whoever calls this gets
      // control back inside the deadline; the position goes to the queue.
      final (svc: svc, db: db, mgr: mgr) = await makeOfflineService();
      addTearDown(() async {
        svc.dispose();
        mgr.dispose();
        await db.close();
      });

      final client = _HangingStopClient();
      final player = _FakePlayer(position: const Duration(seconds: 30), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
        offlineWatchService: svc,
        // Deliberately NOT queueOnOnlineFailure: the terminal report queues
        // regardless, because nothing comes after it to carry the position.
        stoppedReportTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(tracker.dispose);

      final stopwatch = Stopwatch()..start();
      await tracker.sendStoppedProgressOnce(positionOverride: const Duration(seconds: 30));
      stopwatch.stop();

      expect(
        client.stopCompleter.isCompleted,
        isFalse,
        reason: 'the report is still in flight — the caller was released, not the request',
      );
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'returned after the deadline, not after the connect timeout',
      );

      final action = await db.getLatestWatchAction('srv:42');
      expect(action, isNotNull, reason: 'the position PS-4 hangs on must not be dropped');
      expect(action!.actionType, 'progress');
      expect(action.viewOffset, 30000);
    });

    test('a stop report that fails outright is queued without queueOnOnlineFailure', () async {
      final (svc: svc, db: db, mgr: mgr) = await makeOfflineService();
      addTearDown(() async {
        svc.dispose();
        mgr.dispose();
        await db.close();
      });

      final client = _FakePlexClient()..throwOnNextCall = StateError('connect timed out');
      final player = _FakePlayer(position: const Duration(seconds: 20), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
        offlineWatchService: svc,
      );
      addTearDown(tracker.dispose);

      await tracker.sendStoppedProgressOnce(positionOverride: const Duration(seconds: 20));

      final action = await db.getLatestWatchAction('srv:42');
      expect(action, isNotNull);
      expect(action!.viewOffset, 20000);
    });

    test('an ordinary progress failure still respects queueOnOnlineFailure', () async {
      // The forced queue is the stop report's alone. A periodic tick has a next
      // tick to carry the position, so nothing changes for it.
      final (svc: svc, db: db, mgr: mgr) = await makeOfflineService();
      addTearDown(() async {
        svc.dispose();
        mgr.dispose();
        await db.close();
      });

      final client = _FakePlexClient()..throwOnNextCall = StateError('network down');
      final player = _FakePlayer(position: const Duration(seconds: 20), duration: const Duration(seconds: 100));
      final tracker = PlaybackProgressTracker(
        client: client,
        metadata: _meta(ratingKey: '42', serverId: ServerId('srv')),
        player: player,
        isOffline: false,
        offlineWatchService: svc,
      );
      addTearDown(tracker.dispose);

      await tracker.sendProgress('playing');
      await Future<void>.delayed(Duration.zero);

      expect(await svc.getPendingSyncCount(), 0);
    });
  });
}

/// A stop report that never answers — the connect-timeout case, without the
/// wall-clock wait.
class _HangingStopClient extends _FakePlexClient {
  final Completer<void> stopCompleter = Completer<void>();

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    await stopCompleter.future;
    return super.reportPlaybackStopped(
      itemId: itemId,
      position: position,
      duration: duration,
      playSessionId: playSessionId,
      mediaSourceId: mediaSourceId,
      report: report,
    );
  }
}

/// A more precise fake than [_FakePlexClient]: lets the test independently
/// fail the scrobble (markWatched) without touching the progress signals.
class _ScrobblePreciseClient implements PlexClient {
  _ScrobblePreciseClient({this.thresholdPercent = 90, this.failScrobbleFirstTime = false});

  final int thresholdPercent;
  @override
  int get watchedThresholdPercent => thresholdPercent;

  @override
  double get watchedThreshold => thresholdPercent / 100.0;

  @override
  bool get marksWatchedOnPlaybackStopped => false;

  bool failScrobbleFirstTime;
  int markWatchedAttempts = 0;
  int markWatchedSuccesses = 0;

  @override
  Future<void> updateProgress(
    String ratingKey, {
    required int time,
    required String state,
    int? duration,
    String? sessionIdentifier,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {}

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    bool isPaused = false,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {}

  @override
  Future<void> markWatched(MediaItem item) async {
    markWatchedAttempts++;
    if (failScrobbleFirstTime) {
      failScrobbleFirstTime = false;
      throw StateError('simulated scrobble failure');
    }
    markWatchedSuccesses++;
  }

  @override
  Future<void> markAsWatched(String ratingKey, {MediaItem? item}) async {
    markWatchedAttempts++;
    if (failScrobbleFirstTime) {
      failScrobbleFirstTime = false;
      throw StateError('simulated scrobble failure');
    }
    markWatchedSuccesses++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
