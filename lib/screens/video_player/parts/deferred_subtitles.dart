part of '../../video_player_screen.dart';

/// How long the wait may stay silent: a cached track or an MP4 is there at once.
const Duration _kDeferredSubtitleNoticeDelay = Duration(seconds: 2);
const Duration _kDeferredSubtitleToastDuration = Duration(seconds: 4);

extension _DeferredSubtitles on VideoPlayerScreenState {
  Future<void> _attachDeferredSubtitle(File file, DeferredSubtitle subtitle) async {
    final currentPlayer = player;
    if (currentPlayer == null) throw StateError('The player is gone');
    // Same form as a downloaded sidecar, which both mpv and ExoPlayer open.
    await currentPlayer.addSubtitleTrack(
      uri: 'file://${file.path}',
      title: subtitle.title,
      language: subtitle.language,
      select: true,
    );
  }

  void _onDeferredSubtitleStatus() {
    _deferredSubtitleNotice?.cancel();
    switch (_deferredSubtitles.status) {
      case DeferredSubtitleStatus.preparing:
        _deferredSubtitleNotice = Timer(_kDeferredSubtitleNoticeDelay, () {
          if (!mounted || _deferredSubtitles.status != DeferredSubtitleStatus.preparing) return;
          _toastController.show(
            Symbols.subtitles_rounded,
            t.videoControls.subtitlesPreparing,
            duration: _kDeferredSubtitleToastDuration,
          );
        });
      case DeferredSubtitleStatus.failed:
        _toastController.show(
          Symbols.subtitles_off_rounded,
          t.videoControls.subtitlesPrepareFailed,
          duration: _kDeferredSubtitleToastDuration,
        );
      case DeferredSubtitleStatus.idle:
        break;
    }
  }
}
