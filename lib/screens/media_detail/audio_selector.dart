part of '../media_detail_screen.dart';

extension _MediaDetailAudioSelector on _MediaDetailScreenState {
  MediaItem? _audioTargetFor(MediaItem metadata) {
    if (metadata.isMovie || metadata.isEpisode) return metadata;
    if (metadata.isShow) return _onDeckEpisode ?? (_episodes.isEmpty ? null : _episodes.first);
    if (metadata.isSeason) return _episodes.isEmpty ? null : _episodes.first;
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
        _detailFileInfo = fileInfo;
        _selectedDetailAudioTrackId = selected?.id;
        _selectedDetailSubtitleTrackId = _rememberedSubtitle(fileInfo?.subtitleTracks ?? const [], choice)?.id;
      });
    } catch (e) {
      appLogger.d('Failed to load detail audio tracks', error: e);
    } finally {
      if (mounted && _detailAudioTargetId == target.id) {
        _updateDetailAudioState(() => _detailAudioLoadInFlight = false);
      }
    }
  }

  /// The subtitle the next playback starts with: the remembered choice when
  /// there is one ("Uit" gives null), the server's pick otherwise.
  MediaSubtitleTrack? _rememberedSubtitle(List<MediaSubtitleTrack> tracks, TrackLanguageChoice? choice) {
    if (choice?.subtitlesOff ?? false) return null;
    if (choice?.subtitleLanguage case final language?) {
      for (final track in tracks) {
        if ((track.languageCode ?? track.language) == language &&
            track.forced == choice!.subtitleForced &&
            (choice.subtitleTitle == null || choice.subtitleTitle == track.title)) {
          return track;
        }
      }
    }
    return tracks.where((track) => track.selected).firstOrNull;
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

  /// Remembers the track for the next Hervatten/Afspelen; starts nothing.
  Future<void> _chooseDetailAudioTrack(BuildContext sheetContext) async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final track = await showMobileAudioTrackPickerSheet(
      sheetContext,
      tracks: _detailAudioTracks,
      selectedTrackId: _selectedDetailAudioTrackId,
      scopeLabel: _trackScopeLabel(target),
    );
    if (track == null || !mounted) return;

    final language = track.languageCode ?? track.language;
    if (language != null && language.isNotEmpty) {
      await TrackPreferenceStore.saveAudio(target, language: language, title: track.title);
    }
    if (!mounted) return;
    _updateDetailAudioState(() => _selectedDetailAudioTrackId = track.id);
  }

  Future<void> _chooseDetailSubtitleTrack(BuildContext sheetContext) async {
    final target = _detailAudioTarget;
    if (target == null) return;
    final choice = await showMobileSubtitleTrackPickerSheet(
      sheetContext,
      tracks: _detailSubtitleTracks,
      selectedTrackId: _selectedDetailSubtitleTrackId,
      scopeLabel: _trackScopeLabel(target),
    );
    if (choice == null || !mounted) return;

    final track = choice.track;
    if (track == null) {
      await TrackPreferenceStore.saveSubtitle(target, off: true);
    } else if ((track.languageCode ?? track.language) case final language? when language.isNotEmpty) {
      await TrackPreferenceStore.saveSubtitle(target, language: language, title: track.title, forced: track.forced);
    }
    if (!mounted) return;
    _updateDetailAudioState(() => _selectedDetailSubtitleTrackId = track?.id);
  }
}
