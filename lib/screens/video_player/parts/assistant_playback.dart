part of '../../video_player_screen.dart';

extension _VideoPlayerAssistantPlayback on VideoPlayerScreenState {
  /// Native IDs can contain authenticated external subtitle URLs. Keep them
  /// exclusively inside the adapter; the revision exposes only a local counter.
  String _assistantPlaybackRevision(Player currentPlayer) {
    _assistantPlaybackChanges.observe((currentPlayer, currentPlayer.state.track, currentPlayer.state.tracks));
    return '$_playbackGeneration:${_assistantPlaybackChanges.value}';
  }

  void _registerAssistantPlayback() {
    // In-place source reloads keep their registration. A tool that made the
    // change can resample the committed new session through the same lease.
    if (_assistantRegisteredPlayer == player && _releaseAssistantPlayback != null) return;
    _releaseAssistantPlayback?.call();
    _stopAssistantPlaybackRevision?.call();
    final registeredPlayer = player;
    _assistantRegisteredPlayer = registeredPlayer;
    if (registeredPlayer != null) {
      _stopAssistantPlaybackRevision = _assistantPlaybackChanges.bind(
        registeredPlayer,
        isCurrent: () => mounted && player == registeredPlayer,
      );
    }
    final playbackState = context.read<PlaybackStateProvider?>();
    final profile = context.read<ActiveProfileProvider?>();
    final hidden = context.read<HiddenLibrariesProvider?>();
    final manager = context.read<MultiServerProvider?>()?.serverManager;
    final profileId = profile?.activeId;
    if (playbackState == null || profile == null || hidden == null || manager == null || profileId == null) return;
    late final AssistantPlaybackServices service;
    bool sourceAllowed() {
      if (!mounted ||
          !identical(playbackState.assistantPlayback, service) ||
          _isExiting.value ||
          profile.activeId != profileId ||
          profile.isBinding ||
          !profile.lastBindingSucceeded ||
          !hidden.isInitialized) {
        return false;
      }
      final currentPlayer = player;
      final session = _playbackSession;
      if (currentPlayer == null || session == null || currentPlayer.state.completed || !_isPlayerInitialized) {
        return false;
      }
      final metadata = session.metadata;
      final id = ServerId.tryParse(metadata.serverId);
      final library = metadata.libraryGlobalKey;
      if (id == null || library == null || hidden.isLibraryHidden(library) || !manager.isServerVisible(id)) {
        return false;
      }
      final client = manager.getClient(id);
      if (client == null || (!session.isOffline && !identical(client, session.reportingClient))) return false;
      return true;
    }

    bool available() => sourceAllowed() && _playbackTransition == _PlaybackTransition.idle;

    service = AssistantPlaybackServices(
      available: available,
      isCurrent: (snapshot) =>
          available() &&
          snapshot.sessionId == _assistantPlaybackSessionId &&
          snapshot.revision == _assistantPlaybackRevision(player!),
      sample: () async {
        if (!available()) return null;
        final currentPlayer = player!;
        final session = _playbackSession!;
        final revision = _assistantPlaybackRevision(currentPlayer);
        final generation = _playbackGeneration;
        final sampler = PerformanceStatsService(currentPlayer);
        final stats = await sampler.sample();
        sampler.dispose();
        if (!available() || player != currentPlayer || revision != _assistantPlaybackRevision(currentPlayer)) {
          return null;
        }
        bool sameAttempt() =>
            available() &&
            player == currentPlayer &&
            _playbackGeneration == generation &&
            _canControlPlaybackFromRemote();
        bool reloadScope() =>
            sourceAllowed() &&
            player == currentPlayer &&
            _canControlPlaybackFromRemote() &&
            _playbackSession?.metadata.globalKey == session.metadata.globalKey;
        bool guard() => sameAttempt() && revision == _assistantPlaybackRevision(currentPlayer);
        final actions = <AssistantPlaybackAction>[];
        final nativeAudio = currentPlayer.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
        final nativeSubs = currentPlayer.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
        final selectedAudio = currentPlayer.state.track.audio;
        final selectedSub = currentPlayer.state.track.subtitle;
        if (_canControlPlaybackFromRemote()) {
          // These are the exact player-selection + preference callbacks used
          // by the track sheet, not just the preference callback on its own.
          if (!session.isTranscoding) {
            for (final (index, track) in nativeAudio.indexed) {
              if (track.id == selectedAudio?.id) continue;
              actions.add(
                AssistantPlaybackAction(
                  kind: AssistantPlaybackActionKind.audio,
                  label: 'Audio ${index + 1}',
                  execute: (taskCurrent) async {
                    if (!taskCurrent() || !guard() || !currentPlayer.state.tracks.audio.contains(track)) return false;
                    return assistantSelectPlaybackTrack(
                      player: currentPlayer,
                      revisions: _assistantPlaybackChanges,
                      select: () => currentPlayer.selectAudioTrack(track),
                      persist: (live) => _onAudioTrackChanged(track, isCurrent: live),
                      isCurrent: () => taskCurrent() && sameAttempt(),
                      selectionMatches: () => currentPlayer.state.track.audio?.id == track.id,
                    );
                  },
                ),
              );
            }
          }
          // Burned-in subtitles cannot be disabled through a native track.
          // Plex's existing source-track route is offered separately below.
          if (session.result.streamEvidence.subtitle != PlaybackSubtitleDecision.burn) {
            for (final (index, track) in [SubtitleTrack.off, ...nativeSubs].indexed) {
              if (track.id == (selectedSub?.id ?? 'no')) continue;
              actions.add(
                AssistantPlaybackAction(
                  kind: AssistantPlaybackActionKind.subtitle,
                  label: index == 0 ? 'Subtitles off' : 'Subtitle $index',
                  execute: (taskCurrent) async {
                    if (!taskCurrent() ||
                        !guard() ||
                        (track != SubtitleTrack.off && !currentPlayer.state.tracks.subtitle.contains(track))) {
                      return false;
                    }
                    return assistantSelectPlaybackTrack(
                      player: currentPlayer,
                      revisions: _assistantPlaybackChanges,
                      select: () => currentPlayer.selectSubtitleTrack(track),
                      persist: (live) => _onSubtitleTrackChanged(track, isCurrent: live),
                      isCurrent: () => taskCurrent() && sameAttempt(),
                      selectionMatches: () => (currentPlayer.state.track.subtitle?.id ?? 'no') == track.id,
                    );
                  },
                ),
              );
            }
          }
          if (!session.isOffline && !widget.isLive) {
            for (final (index, version) in session.availableVersions.indexed) {
              if (index == session.mediaIndex || !version.isPlayable) continue;
              actions.add(
                AssistantPlaybackAction(
                  kind: AssistantPlaybackActionKind.version,
                  label: 'Version ${index + 1}',
                  execute: (taskCurrent) async {
                    if (!taskCurrent() || !guard()) return false;
                    await _switchPlaybackSource(
                      newMediaIndex: index,
                      isCurrent: () => taskCurrent() && guard(),
                      shouldContinue: () => taskCurrent() && reloadScope(),
                    );
                    return available() &&
                        player == currentPlayer &&
                        _playbackSession?.metadata.globalKey == session.metadata.globalKey &&
                        _effectiveSelectedMediaIndex == index;
                  },
                ),
              );
            }
            if (_serverSupportsTranscoding) {
              for (final preset in TranscodeQualityPreset.displayOrder) {
                if (preset == session.qualityPreset) continue;
                actions.add(
                  AssistantPlaybackAction(
                    kind: AssistantPlaybackActionKind.quality,
                    label: 'Quality ${preset.name}',
                    execute: (taskCurrent) async {
                      if (!taskCurrent() || !guard()) return false;
                      await _switchPlaybackSource(
                        newPreset: preset,
                        isCurrent: () => taskCurrent() && guard(),
                        shouldContinue: () => taskCurrent() && reloadScope(),
                      );
                      return available() &&
                          player == currentPlayer &&
                          _playbackSession?.metadata.globalKey == session.metadata.globalKey &&
                          _selectedQualityPreset == preset;
                    },
                  ),
                );
              }
            }
            if (session.isTranscoding) {
              for (final (index, track) in (session.mediaInfo?.audioTracks ?? const <MediaAudioTrack>[]).indexed) {
                if (track.id == _selectedAudioStreamId) continue;
                if (session.metadata.backend == MediaBackend.plex && session.mediaInfo?.partId == null) continue;
                actions.add(
                  AssistantPlaybackAction(
                    kind: AssistantPlaybackActionKind.audio,
                    label: 'Source audio ${index + 1}',
                    execute: (taskCurrent) async {
                      if (!taskCurrent() || !guard()) return false;
                      await _switchPlaybackSource(
                        newAudioStreamId: track.id,
                        isCurrent: () => taskCurrent() && guard(),
                        shouldContinue: () => taskCurrent() && reloadScope(),
                      );
                      return available() &&
                          player == currentPlayer &&
                          _playbackSession?.metadata.globalKey == session.metadata.globalKey &&
                          _selectedAudioStreamId == track.id;
                    },
                  ),
                );
              }
              if (session.metadata.backend == MediaBackend.plex && session.mediaInfo?.partId != null) {
                final sourceSubtitles = _sourceSubtitleTracksForControls();
                actions.addAll(
                  assistantSourceSubtitleActions(
                    streamIds: [for (final track in sourceSubtitles) track.id],
                    selectedId: _selectedSourceSubtitleStreamIdForControls(sourceSubtitles),
                    isCurrent: guard,
                    switchSource: (id, taskCurrent) async {
                      await _switchPlaybackSource(
                        newSubtitleStreamId: id,
                        isCurrent: () => taskCurrent() && guard(),
                        shouldContinue: () => taskCurrent() && reloadScope(),
                      );
                      return taskCurrent() &&
                          available() &&
                          player == currentPlayer &&
                          _playbackSession?.metadata.globalKey == session.metadata.globalKey &&
                          _selectedSourceSubtitleStreamIdForControls(_sourceSubtitleTracksForControls()) == id;
                    },
                  ),
                );
              }
            }
          }
        }
        final sourceAudioTracks = session.mediaInfo?.audioTracks ?? const <MediaAudioTrack>[];
        final sourceSubTracks = session.mediaInfo?.subtitleTracks ?? const <MediaSubtitleTrack>[];
        final audioMatches = sourceAudioTracks
            .where(
              (t) => session.isTranscoding
                  ? t.id == _selectedAudioStreamId
                  : selectedAudio != null &&
                        t.languageCode == selectedAudio.language &&
                        playbackCodec(t.codec) != null &&
                        playbackCodec(t.codec) == playbackCodec(selectedAudio.codec),
            )
            .toList();
        final subMatches = sourceSubTracks
            .where(
              (t) => session.result.streamEvidence.subtitle == PlaybackSubtitleDecision.burn
                  ? t.selected
                  : selectedSub != null &&
                        t.languageCode == selectedSub.language &&
                        playbackCodec(t.codec) != null &&
                        playbackCodec(t.codec) == playbackCodec(selectedSub.codec),
            )
            .toList();
        final sourceAudio = audioMatches.length == 1 ? audioMatches.single : null;
        final sourceSub = subMatches.length == 1 ? subMatches.single : null;
        return AssistantPlaybackSnapshot(
          sessionId: _assistantPlaybackSessionId,
          revision: revision,
          playMethod: session.playMethod,
          isTranscoding: session.isTranscoding,
          isOffline: session.isOffline,
          streamEvidence: session.result.streamEvidence,
          sourceVideoCodec: session.result.selectedVersion?.videoCodec,
          sourceAudioCodec: sourceAudio?.codec,
          sourceSubtitleCodec: sourceSub?.codec,
          mediaIndex: session.mediaIndex,
          quality: session.qualityPreset.name,
          audioTrack: nativeAudio.indexWhere((t) => t.id == selectedAudio?.id),
          subtitleTrack: selectedSub?.id == 'no' ? -1 : nativeSubs.indexWhere((t) => t.id == selectedSub?.id),
          audioTracks: [
            for (final (i, t) in nativeAudio.indexed)
              AssistantPlaybackTrack(
                index: i,
                language: t.language,
                codec: t.codec,
                selected: t.id == selectedAudio?.id,
              ),
          ],
          subtitleTracks: [
            for (final (i, t) in nativeSubs.indexed)
              AssistantPlaybackTrack(index: i, language: t.language, codec: t.codec, selected: t.id == selectedSub?.id),
          ],
          stats: stats,
          actions: actions,
        );
      },
    );
    _releaseAssistantPlayback = playbackState.registerAssistantPlayback(service);
  }
}
