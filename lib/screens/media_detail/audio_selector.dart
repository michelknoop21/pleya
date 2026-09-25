part of '../media_detail_screen.dart';

extension _MediaDetailAudioSelector on _MediaDetailScreenState {
  MediaItem? _audioTargetFor(MediaItem metadata) {
    if (metadata.isMovie || metadata.isEpisode) return metadata;
    if (metadata.isShow) return _onDeckEpisode ?? (_episodes.isEmpty ? null : _episodes.first);
    if (metadata.isSeason) return _episodes.isEmpty ? null : _episodes.first;
    return null;
  }

  void _scheduleDetailAudioTracksLoad(MediaItem metadata) {
    if (widget.isOffline) return;
    final target = _audioTargetFor(metadata);
    if (target == null || target.id == _detailAudioTargetId || _detailAudioLoadInFlight) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadDetailAudioTracks(target));
    });
  }

  Future<void> _loadDetailAudioTracks(MediaItem target) async {
    if (_detailAudioLoadInFlight) return;
    final serverId = target.serverId ?? _metadata.serverId;
    final client = serverId == null ? null : context.tryGetMediaClientForServer(ServerId(serverId));
    if (client == null) return;

    _updateDetailAudioState(() {
      _detailAudioLoadInFlight = true;
      _detailAudioTargetId = target.id;
      _detailAudioTarget = target.copyWith(
        serverId: serverId,
        serverName: target.serverName ?? _metadata.serverName,
        libraryId: target.libraryId ?? _metadata.libraryId,
        libraryTitle: target.libraryTitle ?? _metadata.libraryTitle,
      );
      _detailAudioTracks = const [];
      _selectedDetailAudioTrackId = null;
    });

    try {
      final results = await Future.wait<Object?>([
        client.getFileInfo(_detailAudioTarget!),
        TrackPreferenceStore.read(target),
      ]);
      if (!mounted || _detailAudioTargetId != target.id) return;
      final fileInfo = results[0] as MediaFileInfo?;
      final choice = results[1] as TrackLanguageChoice?;
      final tracks = fileInfo?.audioTracks ?? const <MediaAudioTrack>[];
      MediaAudioTrack? selected;
      if (choice?.audioLanguage case final language?) {
        for (final track in tracks) {
          final code = track.languageCode ?? track.language;
          if (code == language && (choice?.audioTitle == null || choice!.audioTitle == track.title)) {
            selected = track;
            break;
          }
        }
      }
      selected ??= tracks.where((track) => track.selected).firstOrNull;
      _updateDetailAudioState(() {
        _detailAudioTracks = tracks;
        _selectedDetailAudioTrackId = selected?.id;
      });
    } catch (e) {
      appLogger.d('Failed to load detail audio tracks', error: e);
    } finally {
      if (mounted && _detailAudioTargetId == target.id) {
        _updateDetailAudioState(() => _detailAudioLoadInFlight = false);
      }
    }
  }

  Widget _buildMobileAudioSelector() {
    return MobileAudioTrackSelector(
      tracks: _detailAudioTracks,
      selectedTrackId: _selectedDetailAudioTrackId,
      onPressed: _detailAudioTracks.length > 1 ? () => unawaited(_chooseDetailAudioTrack()) : null,
    );
  }

  Future<void> _chooseDetailAudioTrack() async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final track = await showMobileAudioTrackPickerSheet(
      context,
      tracks: _detailAudioTracks,
      selectedTrackId: _selectedDetailAudioTrackId,
    );
    if (track == null || !mounted) return;

    final language = track.languageCode ?? track.language;
    if (language != null && language.isNotEmpty) {
      await TrackPreferenceStore.saveAudio(target, language: language, title: track.title);
    }
    if (!mounted) return;
    _updateDetailAudioState(() => _selectedDetailAudioTrackId = track.id);
    final playedId = target.id;
    await navigateToVideoPlayerWithRefresh(
      context,
      metadata: target,
      isOffline: widget.isOffline,
      preferredAudioTrack: AudioTrack(
        id: track.id.toString(),
        title: track.title ?? track.displayTitle,
        language: language,
        codec: track.codec,
        channels: track.channels,
        profile: track.profile,
        isDefault: track.selected,
      ),
      onRefresh: () => unawaited(refreshAfterPlayback(playedItemId: playedId)),
    );
  }
}
