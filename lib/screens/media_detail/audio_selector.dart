part of '../media_detail_screen.dart';

extension _MediaDetailAudioSelector on _MediaDetailScreenState {
  MediaItem? _audioTargetFor(MediaItem metadata) {
    if (metadata.isMovie || metadata.isEpisode) return metadata;
    if (metadata.isShow) return _onDeckEpisode ?? (_episodes.isEmpty ? null : _episodes.first);
    if (metadata.isSeason) return _seasonNextEpisode;
    return null;
  }

  List<MediaAudioTrack> get _detailAudioTracks => _detailFileInfo?.audioTracks ?? const [];
  List<MediaSubtitleTrack> get _detailSubtitleTracks => _detailFileInfo?.subtitleTracks ?? const [];

  // Offline too: Plex answers getFileInfo from its cache, so a downloaded
  // item keeps its table.
  void _scheduleDetailAudioTracksLoad(MediaItem metadata) {
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
      _detailFileInfo = null;
      _selectedDetailAudioTrackId = null;
      _selectedDetailSubtitleTrackId = null;
      _detailAudioPickId = null;
      _detailSubtitlePickId = null;
      _detailSubtitlePicked = false;
    });

    try {
      final fileInfo = await client.getFileInfo(_detailAudioTarget!);
      if (fileInfo == null || !mounted || _detailAudioTargetId != target.id) return;
      await _showDetailTracksPlaybackStartsWith(target, fileInfo);
    } catch (e) {
      appLogger.d('Failed to load detail audio tracks', error: e);
    } finally {
      if (mounted && _detailAudioTargetId == target.id) {
        _updateDetailAudioState(() => _detailAudioLoadInFlight = false);
      }
    }
  }

  /// Sets the table to the tracks the next playback from this page starts
  /// with ([resolveDetailTracks]), the page's own pick included. [loaded]
  /// is the file just loaded, otherwise the one on the page.
  Future<void> _showDetailTracksPlaybackStartsWith(MediaItem target, [MediaFileInfo? loaded]) async {
    final info = loaded ?? _detailFileInfo;
    if (info == null) return;
    final pick = _detailTrackPickFor(target);
    final resolved = await resolveDetailTracks(target, info, audioPick: pick.audio, subtitlePick: pick.subtitle);
    if (!mounted || _detailAudioTargetId != target.id) return;
    _updateDetailAudioState(() {
      _detailFileInfo = info;
      _selectedDetailAudioTrackId = resolved.audioId;
      _selectedDetailSubtitleTrackId = resolved.subtitleId;
      _detailPickRemembered = resolved.remembered;
    });
  }

  /// [sheetContext] sits under the page's own OverlaySheetHost, which the
  /// State's context does not.
  Widget _buildMobileTechTable(BuildContext sheetContext, MediaItem metadata) {
    final info = _detailFileInfo;
    final target = _detailAudioTarget;
    if (info == null || target == null) return const SizedBox.shrink();
    final audio = _detailAudioTracks.where((track) => track.id == _selectedDetailAudioTrackId).firstOrNull;
    final subtitle = _detailSubtitleTracks.where((track) => track.id == _selectedDetailSubtitleTrackId).firstOrNull;
    return DetailTechTable(
      heading: metadata.isSeason && target.parentIndex != null && target.index != null
          ? t.discover.techEpisode(season: target.parentIndex!, episode: target.index!)
          : null,
      videoLabel: detailVideoLabel(info, item: target),
      audioLabel: audio == null ? null : detailAudioLabel(audio),
      onAudioTap: _detailAudioTracks.length > 1 ? () => unawaited(_chooseDetailAudioTrack(sheetContext)) : null,
      subtitleLabel: subtitle?.label.primary ?? t.common.off,
      onSubtitleTap: _detailSubtitleTracks.isEmpty ? null : () => unawaited(_chooseDetailSubtitleTrack(sheetContext)),
    );
  }

  /// "Sintel · geldt voor deze film" or "… · voor deze serie": an episode's
  /// choice is stored per series ([TrackPreferenceStore.seriesKeyFor]).
  String _trackScopeLabel(MediaItem target) => target.isEpisode
      ? t.discover.trackScopeSeries(title: target.grandparentTitle ?? target.title ?? '')
      : t.discover.trackScopeMovie(title: target.title ?? '');

  /// Stores the track as the series preference when "per serie onthouden" is
  /// on (the store checks), keeps it as this page's pick for the player, and
  /// shows what playback will then start with. Starts nothing.
  Future<void> _chooseDetailAudioTrack(BuildContext sheetContext) async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final track = await showMobileAudioTrackPickerSheet(
      sheetContext,
      tracks: _detailAudioTracks,
      selectedTrackId: _selectedDetailAudioTrackId,
      scopeLabel: _trackScopeLabel(target),
      remembered: _detailPickRemembered,
    );
    if (track == null || !mounted) return;

    final language = track.languageCode ?? track.language;
    if (language != null && language.isNotEmpty) {
      await TrackPreferenceStore.saveAudio(target, language: language, title: track.title);
    }
    if (!mounted) return;
    _updateDetailAudioState(() => _detailAudioPickId = track.id);
    await _showDetailTracksPlaybackStartsWith(target);
  }

  Future<void> _chooseDetailSubtitleTrack(BuildContext sheetContext) async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final choice = await showMobileSubtitleTrackPickerSheet(
      sheetContext,
      tracks: _detailSubtitleTracks,
      selectedTrackId: _selectedDetailSubtitleTrackId,
      scopeLabel: _trackScopeLabel(target),
      remembered: _detailPickRemembered,
    );
    if (choice == null || !mounted) return;

    final track = choice.track;
    if (track == null) {
      await TrackPreferenceStore.saveSubtitle(target, off: true);
    } else if ((track.languageCode ?? track.language) case final language? when language.isNotEmpty) {
      await TrackPreferenceStore.saveSubtitle(target, language: language, title: track.title, forced: track.forced);
    }
    if (!mounted) return;
    _updateDetailAudioState(() {
      _detailSubtitlePickId = track?.id;
      _detailSubtitlePicked = true;
    });
    await _showDetailTracksPlaybackStartsWith(target);
  }

  /// The tracks picked on this page for [item], for the player to start with.
  /// Held in the page, so the pick also holds when the store keeps nothing
  /// (remembering switched off, or a track without a language code).
  ({AudioTrack? audio, SubtitleTrack? subtitle}) _detailTrackPickFor(MediaItem item) {
    if (item.id != _detailAudioTargetId) return (audio: null, subtitle: null);
    final audio = _detailAudioTracks.where((track) => track.id == _detailAudioPickId).firstOrNull;
    final subtitle = _detailSubtitleTracks.where((track) => track.id == _detailSubtitlePickId).firstOrNull;
    return (
      audio: audio == null ? null : detailPlayerAudioTrack(audio),
      subtitle: !_detailSubtitlePicked
          ? null
          : subtitle == null
          ? SubtitleTrack.off
          : detailPlayerSubtitleTrack(subtitle),
    );
  }
}
