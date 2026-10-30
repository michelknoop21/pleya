part of '../../pleya_server_client.dart';

/// Direct play and watch state on Pleya Protocol v1: everything PS-4 added.
///
/// ## One event type, six server-side rules
///
/// A watch-state update is a gebeurtenis and not a value. The client says what
/// happened; the server decides what that means for the canonical state, using
/// the ownership model from DEC-049. Three fields carry the client's half of
/// that conversation and all three sit behind
/// [PleyaCapabilities.watchStateOwnership], because `WatchStateEvent` is a
/// closed schema and an older server refuses the whole request rather than
/// ignoring a field it does not know:
///
///   * `explicit_action: playback_started` is the only way to acquire the write
///     right. A progress report never acquires it, not even when the previous
///     owner's lease has expired;
///   * `cause` says whether someone pressed play (`user_started`, takes over
///     regardless of another device's lease) or whether this session is
///     reopening its own (`reclaim`, only once the lease has run out);
///   * `base_revision` is the causality claim. The server applies the write
///     only when it matches the current revision, so a device that acted on a
///     stale view cannot overwrite a newer state.
///
/// The answer is always the current state, including when the event was
/// refused. That is why [_applyWatchState] records the revision from every
/// answer: a refused write teaches this client what it missed, and the next
/// write carries the right claim.
///
/// ## The stream URL carries no credential
///
/// `GET /stream/{version_id}` is class `authenticated`, and this client
/// authorises it with a bearer header rather than with the query-string stream
/// token. The token in a URL exists for players that cannot set a header; mpv
/// can, and a credential that never enters a URL never enters a log, a referrer
/// or a shell history either. [PleyaServerClient.streamHeaders] carries it.
mixin _PleyaServerPlaybackMethods on _PleyaServerRequests {
  /// Where deferred subtitles are written; the app's temporary directory unless a test says otherwise.
  @visibleForTesting
  Directory? subtitleTempDirectory;

  /// The watched fraction the server uses when a report carries no `completed`.
  /// Kept in step with `watch.WatchedFraction` on the server side.
  static const double _watchedFraction = 0.9;

  // ---------------------------------------------------------------------------
  // Direct play
  // ---------------------------------------------------------------------------

  /// Resolve an item to a playable URL.
  ///
  /// With `capabilities.playback_plan` the server picks the version and says
  /// how it is delivered (S17); this client follows that plan. Without the
  /// flag, or when the plan call fails, it behaves as it did in PS-4: direct
  /// play of the selected version, where a file this device cannot decode
  /// fails visibly in the player. A plan the server could not make is not a
  /// reason to refuse playback, because the device report may be wrong and the
  /// player is the better judge of last resort.
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    if (_closed) throw PlaybackException('The playback connection is closed.');
    var effectiveOptions = options;
    final versions = options.metadata.mediaVersions ?? const <MediaVersion>[];
    if (versions.isEmpty) {
      return PlaybackInitializationResult(availableVersions: const []);
    }

    var index = options.selectedMediaIndex >= 0 && options.selectedMediaIndex < versions.length
        ? options.selectedMediaIndex
        : 0;

    final sourceId = options.selectedMediaSourceId;
    if (sourceId != null) {
      index = versions.indexWhere((version) => version.id == sourceId);
      if (index < 0) throw PlaybackException('The selected media version is no longer available.');
    }
    await _releaseTranscodeSession(options.metadata.id);
    var plan = await _planPlayback(
      options.metadata.id,
      versions,
      index,
      explicit: sourceId != null || index != 0,
      options: options,
    );
    if (plan != null) {
      final planned = versions.indexWhere((v) => v.id == plan?.versionId);
      if (planned >= 0) index = planned;
      appLogger.d('PleyaServerClient: plan ${plan.deliveryMode?.wire} because ${plan.reason.code}');
    }
    int? preferredSubtitleId;
    final selector = options.selectSourceTracks;
    if (selector != null &&
        (plan?.sessionId == null || plan?.deliveryMode == PleyaDeliveryMode.directPlay) &&
        options.selectedSubtitleStreamId == null &&
        wireCapabilities.transcode &&
        wireCapabilities.playbackPlan &&
        wireCapabilities.playbackSubtitles) {
      preferredSubtitleId = await _directPlaySubtitle(selector, versions[index]);
    }
    if (selector != null &&
        plan?.sessionId != null &&
        plan?.deliveryMode != PleyaDeliveryMode.directPlay &&
        (wireCapabilities.playbackAudioSelection || wireCapabilities.playbackSubtitles)) {
      try {
        final source = PleyaServerMappers.mediaSourceInfo(versions[index]);
        final choice = await selector(source);
        final audioIndex = options.selectedAudioStreamId ?? choice.audioStreamId;
        final subtitleId = options.selectedSubtitleStreamId ?? choice.subtitleStreamId;
        final defaultAudio = source.audioTracks.where((t) => t.selected).firstOrNull ?? source.audioTracks.firstOrNull;
        final audioChanges =
            options.selectedAudioStreamId == null &&
            audioIndex != null &&
            audioIndex != defaultAudio?.id &&
            wireCapabilities.playbackAudioSelection;
        final subtitle = source.subtitleTracks.where((t) => t.id == subtitleId).firstOrNull;
        if (subtitleId != null && subtitleId != 0 && subtitle == null) {
          throw PlaybackException('The selected subtitle stream is no longer available.');
        }
        final needsBurn =
            options.selectedSubtitleStreamId == null &&
            subtitle != null &&
            {'pgs', 'dvdsub'}.contains(subtitle.codec) &&
            wireCapabilities.playbackSubtitles;
        preferredSubtitleId = subtitleId;
        if (audioChanges || needsBurn) {
          await _stopPlanSession(plan?.sessionId);
          plan = null;
          effectiveOptions = PlaybackInitializationOptions(
            metadata: options.metadata,
            selectedMediaIndex: index,
            selectedMediaSourceId: versions[index].id,
            qualityPreset: options.qualityPreset,
            selectedAudioStreamId: audioChanges ? audioIndex : options.selectedAudioStreamId,
            selectedSubtitleStreamId: needsBurn ? subtitleId : options.selectedSubtitleStreamId,
            sessionIdentifier: options.sessionIdentifier,
            transcodeSessionId: options.transcodeSessionId,
          );
          plan = await _planPlayback(options.metadata.id, versions, index, explicit: true, options: effectiveOptions);
        }
      } catch (_) {
        await _stopPlanSession(plan?.sessionId);
        rethrow;
      }
    }
    final version = versions[index];
    final videoUrl = plan?.sessionId != null && plan?.deliveryMode != PleyaDeliveryMode.directPlay
        ? '${connection.baseUrl}${plan!.streamUrl}'
        : _streamUrl(version.id);
    final mediaInfo = PleyaServerMappers.mediaSourceInfo(
      version,
      baseUrl: connection.baseUrl,
      videoUrl: videoUrl,
      selectedSubtitleId: effectiveOptions.selectedSubtitleStreamId ?? preferredSubtitleId,
      deliverEmbeddedText:
          wireCapabilities.embeddedSubtitles && plan != null && plan.deliveryMode != PleyaDeliveryMode.directPlay,
    );
    final subtitles = [
      for (final track in mediaInfo.subtitleTracks)
        if (plan?.subtitle?.action != 'burn' && track.isExternalFile && track.key != null)
          SubtitleTrack.uri(
            track.key!,
            title: track.title,
            language: track.languageCode,
            codec: track.codec,
            isDefault: track.selected,
            isForced: track.forced,
          ),
    ];

    final deferredSubtitle = plan?.subtitle?.action == 'burn' ? null : _deferredEmbeddedSubtitle(mediaInfo);

    // Warm the header before the player opens the URL. The token is short
    // lived and minted per request everywhere else; here mpv holds the URL, so
    // the one thing this call has to guarantee is that the header handed to it
    // is fresh at open time.
    try {
      if (_closed) throw PlaybackException('The playback connection is closed.');
      await _session.authHeaders();
      if (_closed) throw PlaybackException('The playback connection is closed.');
    } catch (_) {
      await _stopPlanSession(plan?.sessionId);
      rethrow;
    }

    // A delivery the server converts comes with a session: the player opens
    // its HLS playlist, and this client keeps the session alive until the
    // playback is reported stopped.
    final sessionId = plan?.sessionId;
    if (plan != null && sessionId != null && plan.deliveryMode != PleyaDeliveryMode.directPlay) {
      _holdTranscodeSession(options.metadata.id, sessionId);
      return PlaybackInitializationResult(
        availableVersions: versions,
        videoUrl: '${connection.baseUrl}${plan.streamUrl}',
        selectedMediaIndex: index,
        isTranscoding: plan.deliveryMode == PleyaDeliveryMode.transcode,
        activeAudioStreamId: plan.selectedAudioStreamId == null ? null : effectiveOptions.selectedAudioStreamId,
        playMethod: plan.deliveryMode == PleyaDeliveryMode.transcode ? 'Transcode' : 'DirectStream',
        playSessionId: _watchLedger.sessionFor(options.metadata.id, _mintSessionId),
        streamEvidence: PlaybackStreamEvidence(
          subtitle: plan.subtitle?.action == 'burn' ? PlaybackSubtitleDecision.burn : null,
        ),
        mediaInfo: mediaInfo,
        externalSubtitles: subtitles,
        deferredSubtitle: deferredSubtitle,
      );
    }

    return PlaybackInitializationResult(
      availableVersions: versions,
      videoUrl: _streamUrl(version.id),
      selectedMediaIndex: index,
      playMethod: 'DirectPlay',
      playSessionId: _watchLedger.sessionFor(options.metadata.id, _mintSessionId),
      mediaInfo: mediaInfo,
      externalSubtitles: subtitles,
      deferredSubtitle: deferredSubtitle,
    );
  }

  /// The selected embedded track of an HLS delivery, which drops the track from
  /// the stream. It stays out of [PlaybackInitializationResult.externalSubtitles]:
  /// mpv loads those during open and does not repeat, so a track the server is
  /// still reading would hold the film back and then fail. Unselected tracks
  /// stay in the source controls and cost the server nothing until chosen.
  DeferredSubtitle? _deferredEmbeddedSubtitle(MediaSourceInfo info) {
    final track = info.subtitleTracks.where((t) => t.selected && !t.isExternalFile && t.key != null).firstOrNull;
    final id = track?.sourceStreamId;
    if (track == null || id == null) return null;
    return DeferredSubtitle(
      title: track.displayTitle ?? track.title,
      language: track.languageCode,
      load: (abort) async {
        final text = await fetchPleyaSubtitleWhenReady(
          abort: abort,
          get: (attempt) {
            if (_closed) throw const PleyaSubtitleUnavailable(null);
            return _getSubtitle(id, attempt);
          },
        );
        return writePleyaSubtitleFile(text, track.codec ?? 'srt', directory: subtitleTempDirectory);
      },
    );
  }

  Future<MediaSourceInfo?> fetchCachedMediaSourceInfo(String itemId) =>
      CachedPlaybackMetadataService.fetchMediaSourceInfo(
        backend: MediaBackend.pleyaServer,
        cacheServerId: connection.id,
        itemId: itemId,
        baseUrl: connection.baseUrl,
      );

  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    final versions = item.mediaVersions;
    if (versions == null || versions.isEmpty) return null;
    final version = versions.first;
    final source = PleyaServerMappers.mediaSourceInfo(version, baseUrl: connection.baseUrl);
    final part = version.parts.firstOrNull;
    final audio = source.audioTracks.firstOrNull;
    return MediaFileInfo(
      container: version.container,
      videoCodec: version.videoCodec,
      videoResolution: version.videoResolution,
      width: version.width,
      height: version.height,
      bitrate: version.bitrate,
      duration: part?.durationMs,
      fileSize: part?.sizeBytes,
      audioCodec: audio?.codec,
      audioChannels: audio?.channels,
      audioTracks: source.audioTracks,
      subtitleTracks: source.subtitleTracks,
    );
  }

  /// The subtitle the player will select after opening [version] directly.
  ///
  /// The file carries every track, so nothing needs planning; the source
  /// controls just have to show what mpv is about to do. A preference that
  /// cannot be resolved here is no reason to refuse the playback.
  Future<int?> _directPlaySubtitle(SourceTrackSelector selector, MediaVersion version) async {
    try {
      final source = PleyaServerMappers.mediaSourceInfo(version);
      final subtitleId = (await selector(source)).subtitleStreamId;
      return subtitleId == 0 || source.subtitleTracks.any((t) => t.id == subtitleId) ? subtitleId : null;
    } catch (e) {
      appLogger.d('PleyaServerClient: no subtitle preference for direct play', error: e);
      return null;
    }
  }

  Future<void> _stopPlanSession(String? id) async {
    if (id case final String sessionId) {
      try {
        await _adminSend('DELETE', '/playback/sessions/${Uri.encodeComponent(sessionId)}');
      } catch (e) {
        appLogger.d('PleyaServerClient: could not stop the unopened plan session', error: e);
      }
    }
  }

  /// The transcode sessions this client keeps alive, by item id.
  final Map<String, ({String sessionId, Timer timer})> _transcodeSessions = {};

  /// How often a held session is told it is still wanted. The server reaps a
  /// session after a minute without a heartbeat or a file request.
  static const Duration _heartbeatEvery = Duration(seconds: 15);

  void _holdTranscodeSession(String itemId, String sessionId) {
    final timer = Timer.periodic(_heartbeatEvery, (t) async {
      try {
        await _adminSend('POST', '/playback/sessions/$sessionId/heartbeat');
      } on MediaServerHttpException catch (e) {
        // 404: the server forgot it (timeout, restart). Nothing left to keep.
        if (e.statusCode == 404) t.cancel();
      } catch (e) {
        appLogger.d('PleyaServerClient: transcode heartbeat failed', error: e);
      }
    });
    _transcodeSessions[itemId] = (sessionId: sessionId, timer: timer);
  }

  Future<void> _releaseTranscodeSession(String itemId) async {
    final held = _transcodeSessions.remove(itemId);
    if (held == null) return;
    held.timer.cancel();
    try {
      await _adminSend('DELETE', '/playback/sessions/${held.sessionId}');
    } catch (e) {
      appLogger.d('PleyaServerClient: stopping the transcode session failed', error: e);
    }
  }

  /// Stop every held session: used when the client closes.
  Future<void> _releaseAllTranscodeSessions() async {
    for (final itemId in _transcodeSessions.keys.toList()) {
      await _releaseTranscodeSession(itemId);
    }
  }

  /// Ask the server for a plan. Null means "no plan, keep direct play": the
  /// server does not offer one, the call failed, or the plan names a delivery
  /// this build does not know (an unknown mode must not change what we play).
  ///
  /// An automatic first version lets the server choose. A stable source id
  /// carries explicit intent, including selection of the first version.
  Future<PleyaPlaybackPlan?> _planPlayback(
    String itemId,
    List<MediaVersion> versions,
    int index, {
    required bool explicit,
    required PlaybackInitializationOptions options,
  }) async {
    final quality = options.qualityPreset;
    final audioIndex = options.selectedAudioStreamId;
    final subtitleIndex = options.selectedSubtitleStreamId;
    final sourceSubtitles = PleyaServerMappers.mediaSourceInfo(versions[index]).subtitleTracks;
    final subtitle = subtitleIndex == null || subtitleIndex == 0
        ? null
        : sourceSubtitles.where((s) => s.id == subtitleIndex).firstOrNull;
    if (subtitleIndex != null && subtitleIndex != 0 && subtitle == null) {
      throw PlaybackException('The selected subtitle stream is no longer available.');
    }
    final subtitleMode = subtitleIndex == null
        ? null
        : subtitleIndex == 0
        ? 'off'
        : {'pgs', 'dvdsub'}.contains(subtitle?.codec)
        ? 'burn'
        : 'external';
    final requiresSession = !quality.isOriginal || audioIndex != null || subtitleMode == 'burn';
    final selected = requiresSession || subtitleIndex != null;
    if ((subtitleIndex != null && !wireCapabilities.playbackSubtitles) ||
        (!quality.isOriginal && !wireCapabilities.playbackQuality) ||
        (audioIndex != null && !wireCapabilities.playbackAudioSelection) ||
        (selected && !wireCapabilities.playbackPlan)) {
      throw PlaybackException('The server does not support this playback selection.');
    }
    if (!wireCapabilities.playbackPlan) return null;
    String? audioId;
    if (audioIndex != null) {
      audioId = versions[index].parts.firstOrNull?.streams
          .where((stream) => stream.kind == MediaStreamKind.audio && stream.index == audioIndex)
          .firstOrNull
          ?.id;
      if (audioId == null) throw PlaybackException('The selected audio stream is no longer available.');
    }
    String? receivedSessionId;
    try {
      final json = await _postJson('/playback/plan', {
        'item_id': itemId,
        if (explicit || audioId != null || subtitleIndex != null) 'version_id': versions[index].id,
        if (audioId != null) 'audio_stream_id': audioId,
        if (subtitleMode != null)
          'subtitle': {'mode': subtitleMode, if (subtitle != null) 'stream_id': subtitle.sourceStreamId},
        if (!quality.isOriginal)
          'quality': {'max_video_bitrate_kbps': quality.videoBitrateKbps, 'max_height': quality.resolutionHeight},
        'capabilities': pleyaDeviceCapabilitiesToWire(DeviceCapabilitiesService.currentSnapshot),
      });
      if (json == null) {
        if (selected) throw PlaybackException('The requested playback selection could not be prepared.');
        return null;
      }
      receivedSessionId = json['session_id'] is String ? json['session_id'] as String : null;
      final plan = PleyaPlaybackPlan.fromJson(json);
      final wrongSource =
          plan.itemId != itemId ||
          !versions.any((v) => v.id == plan.versionId) ||
          ((explicit || audioId != null || subtitleIndex != null) && plan.versionId != versions[index].id);
      final wrongQuality =
          !quality.isOriginal &&
          (plan.deliveryMode != PleyaDeliveryMode.transcode ||
              plan.maxVideoBitrateKbps != quality.videoBitrateKbps ||
              plan.maxHeight != quality.resolutionHeight);
      final wrongSubtitle =
          subtitleMode != null &&
          (plan.subtitle?.action != subtitleMode ||
              (subtitle != null && plan.subtitle?.streamId != subtitle.sourceStreamId) ||
              (subtitleMode == 'external' &&
                  plan.subtitle?.url !=
                      '$pleyaProtocolPrefix/subtitles/${Uri.encodeComponent(subtitle!.sourceStreamId!)}') ||
              (subtitleMode == 'burn' && plan.deliveryMode != PleyaDeliveryMode.transcode));
      if (wrongSource ||
          (selected &&
              (plan.deliveryMode == null ||
                  wrongQuality ||
                  wrongSubtitle ||
                  (audioId != null && plan.selectedAudioStreamId != audioId) ||
                  (requiresSession &&
                      (plan.sessionId == null || plan.deliveryMode == PleyaDeliveryMode.directPlay))))) {
        throw PlaybackException('The server did not apply the requested playback selection.');
      }
      if (plan.deliveryMode == PleyaDeliveryMode.directPlay) return plan;
      if (plan.deliveryMode != null && plan.sessionId != null) return plan;
      await _stopPlanSession(receivedSessionId);
      return null;
    } on PleyaWireFormatException catch (e) {
      await _stopPlanSession(receivedSessionId);
      if (selected) throw PlaybackException('The server returned an invalid playback selection.');
      appLogger.w('PleyaServerClient: playback plan did not match the contract', error: e);
      return null;
    } catch (e) {
      await _stopPlanSession(receivedSessionId);
      if (selected) throw PlaybackException('The requested playback selection could not be prepared.');
      appLogger.d('PleyaServerClient: no playback plan, playing directly', error: e);
      return null;
    }
  }

  /// A URL an external player can open on its own.
  ///
  /// This is the one place the query-string stream token belongs: VLC and MX
  /// Player get a URL and nothing else, so a header is not an option. The token
  /// opens one version and has no rights on the rest of the API.
  Future<String?> resolveExternalPlaybackUrl(MediaItem item, {int mediaIndex = 0, String? mediaSourceId}) async {
    final versions = item.mediaVersions ?? const <MediaVersion>[];
    if (versions.isEmpty) return null;
    final index = mediaSourceId != null
        ? versions.indexWhere((version) => version.id == mediaSourceId)
        : (mediaIndex >= 0 && mediaIndex < versions.length ? mediaIndex : 0);
    if (index < 0) return null;
    final versionId = versions[index].id;

    // An external player URL is optional: a failed mint is "no URL", not an
    // error the caller has to handle (`_postJson` throws on failure).
    final Map<String, dynamic>? json;
    try {
      json = await _postJson('/auth/stream-token', {'version_id': versionId});
    } catch (e) {
      appLogger.d('PleyaServerClient: stream token mint failed', error: e);
      return null;
    }
    if (json == null) return null;
    try {
      final token = PleyaStreamToken.fromJson(json);
      return Uri.parse(_streamUrl(versionId)).replace(queryParameters: {'stream_token': token.streamToken}).toString();
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: stream token did not match the contract', error: e);
      return null;
    }
  }

  String _streamUrl(String versionId) =>
      '${connection.baseUrl}$pleyaProtocolPrefix/stream/${Uri.encodeComponent(versionId)}';

  // ---------------------------------------------------------------------------
  // Watch state: reporting
  // ---------------------------------------------------------------------------

  /// Someone pressed play. This is the acquisition, and the only event that
  /// takes the write right from another device.
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
    final session = _watchLedger.openSession(itemId, _mintSessionId);
    await _applyWatchState(
      itemId: itemId,
      sessionId: session,
      position: position,
      duration: duration,
      action: 'playback_started',
      cause: 'user_started',
    );
  }

  /// A passive progress tick. Never acquires ownership; a device that is not
  /// the owner reports into the void by design, and the answer tells it so.
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
  }) async {
    await _applyWatchState(
      itemId: itemId,
      sessionId: _watchLedger.sessionFor(itemId, _mintSessionId),
      position: position,
      duration: duration,
    );
  }

  /// The last tick of a viewing.
  ///
  /// `completed` is computed here rather than left to the server's threshold,
  /// because the player knows whether the user reached the end or closed the
  /// screen at eighty percent, and those look identical from a position alone.
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async {
    final completed =
        duration != null &&
        duration.inMilliseconds > 0 &&
        position.inMilliseconds >= _watchedFraction * duration.inMilliseconds;

    await _releaseTranscodeSession(itemId);
    await _applyWatchState(
      itemId: itemId,
      sessionId: _watchLedger.sessionFor(itemId, _mintSessionId),
      position: position,
      duration: duration,
      completed: completed,
      // An offline replay is a backlog, and the server treats a backlog as
      // history: it never acquires ownership and never moves a newer canonical
      // state. Reporting it as live would be a lie the server cannot detect.
      backlog: report.isOfflineReplay,
      occurredAt: report.isOfflineReplay ? report.recordedAt : null,
    );
    _watchLedger.closeSession(itemId);
  }

  // ---------------------------------------------------------------------------
  // Watch state: explicit actions
  // ---------------------------------------------------------------------------

  /// Mark watched. Ignores another device's lease, by rule 5.
  Future<void> markWatched(MediaItem item) async => _applyWatchState(
    itemId: item.id,
    sessionId: _watchLedger.sessionFor(item.id, _mintSessionId),
    position: Duration.zero,
    duration: item.durationMs == null ? null : Duration(milliseconds: item.durationMs!),
    action: 'mark_watched',
  );

  Future<void> markUnwatched(MediaItem item) async => _applyWatchState(
    itemId: item.id,
    sessionId: _watchLedger.sessionFor(item.id, _mintSessionId),
    position: Duration.zero,
    action: 'mark_unwatched',
  );

  /// Hide from Continue Watching.
  ///
  /// The protocol has no separate flag for it, so this is `mark_unwatched`:
  /// position zero and not watched is exactly the state that keeps a title out
  /// of the row. A dedicated flag arrives with the personal layer in PS-9P;
  /// until then this is the honest mapping and not a workaround, because the
  /// visible outcome is the one the user asked for.
  Future<void> removeFromContinueWatching(MediaItem item) async => markUnwatched(item);

  // ---------------------------------------------------------------------------
  // Watch state: reading
  // ---------------------------------------------------------------------------

  /// Titles this identity finished, newest first.
  ///
  /// `GET /watch-state` sorts on `updated_at` descending, so the watched ones
  /// come out in the right order without a second sort; what it cannot do is
  /// filter, so the finished ones are picked out here. The page is capped
  /// rather than walked: this feeds a recommendation row, and a row that is
  /// briefly short is repairable where a request that never returns is not.
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async {
    if (!wireCapabilities.watchState) return const [];

    final json = await _getJson('/watch-state', queryParameters: {'limit': '100'});
    if (json == null) return const [];

    final List<PleyaWatchStateEntry> entries;
    try {
      entries = PleyaWatchStateEntry.pageFromJson(json);
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /watch-state did not match the contract', error: e);
      return const [];
    }

    final wanted = <String>[];
    for (final entry in entries) {
      _watchLedger.remember(entry.itemId, entry.state.revision);
      if (entry.state.watched && wanted.length < limit) wanted.add(entry.itemId);
    }
    if (wanted.isEmpty) return const [];

    final items = await Future.wait(wanted.map(fetchItem));
    return [
      for (final item in items)
        if (item != null) item,
    ];
  }

  // ---------------------------------------------------------------------------
  // The one place an event is built
  // ---------------------------------------------------------------------------

  /// Build, send and account for one watch-state event.
  ///
  /// Every caller goes through here so the three ownership fields are decided
  /// in one place. Scattering them would make "does this event acquire the
  /// lease" a property of the call site instead of of the action.
  Future<void> _applyWatchState({
    required String itemId,
    required String sessionId,
    required Duration position,
    Duration? duration,
    String action = 'none',
    String? cause,
    bool completed = false,
    bool backlog = false,
    DateTime? occurredAt,
  }) async {
    if (!wireCapabilities.watchState) return;

    final event = PleyaWatchStateEvent(
      itemId: itemId,
      sessionId: sessionId,
      positionMs: position.inMilliseconds,
      durationMs: duration?.inMilliseconds,
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
      completed: completed,
      action: action,
      cause: cause,
      backlog: backlog,
      // Only under the capability, and the type drops it again when the flag is
      // off: the request schema is closed, so sending it to a server that
      // predates DEC-049 fails the whole call rather than dropping the field.
      baseRevision: wireCapabilities.watchStateOwnership ? _watchLedger.revisionOf(itemId) : null,
    );

    final body = event.toJson(ownership: wireCapabilities.watchStateOwnership);
    final json = await _postJson('/watch-state', body);
    if (json == null) return;
    try {
      final state = PleyaUserState.fromJson(json);
      _watchLedger.remember(itemId, state.revision);
      if (state.ownedByThisSession == false) {
        // Not an error, and not something the user should see. Another device
        // holds the lease, and this client keeps reporting so it can take over
        // when the lease runs out.
        appLogger.d('PleyaServerClient: another session owns $itemId');
      }
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: watch-state answer did not match the contract', error: e);
    }
  }

  String _mintSessionId() => const Uuid().v4();
}
