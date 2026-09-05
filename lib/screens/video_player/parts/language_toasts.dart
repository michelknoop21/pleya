/// The two language toasts of mockups 31 C and 31 D.
///
/// The player screen owns the wording because the sentence is a product
/// decision: `TrackManager` reports *what happened* to a language, and this is
/// where that becomes "onthouden voor Severance" or "nu Nederlands". Keeping
/// the two apart is what lets the resolver stay testable without a widget tree
/// and the copy change without touching playback.
///
/// The presentation contract of DEC-096 lid 10 is inherited rather than
/// re-implemented: `PlayerToastController` auto-hides, and `video_controls`
/// draws the pill inside an `IgnorePointer` in the existing top zone, so the
/// toast cannot take focus, cannot block a press and cannot land on the
/// subtitles. All that is chosen here is the duration — three seconds, because
/// a two-line sentence is read rather than glanced at.
part of '../../video_player_screen.dart';

/// How long a language toast stays up. The rate pill's 1.2 seconds is for a
/// value you glance at; these carry a sentence about the next episode.
const Duration _kLanguageToastDuration = Duration(seconds: 3);

extension _LanguageToasts on VideoPlayerScreenState {
  void _showLanguageToast(PlaybackLanguageNotice notice) {
    if (!mounted) return;
    switch (notice) {
      case LanguageChoiceRemembered():
        _showRememberedToast(notice);
      case LanguageFallbackApplied():
        _showFallbackToast(notice);
    }
  }

  /// 31 C. Says which promise was made — the series preference, or this
  /// playback only — and that the global preference did not move.
  void _showRememberedToast(LanguageChoiceRemembered notice) {
    final kind = _languageKindLabel(notice.kind);
    final language = notice.subtitlesOff
        ? t.languageSettings.off
        : (languageDisplayName(notice.language) ?? notice.language ?? '');
    final title = notice.seriesTitle;
    final global = languageDisplayName(notice.globalLanguage);

    final headline = notice.storedForSeries
        ? (title == null
              ? '$kind: $language'
              : t.languageSettings.toastRemembered(kind: kind, language: language, title: title))
        : t.languageSettings.toastSessionOnly(kind: kind, language: language);

    final detail = notice.storedForSeries
        ? (global == null
              ? t.languageSettings.toastRememberedDetailNoGlobal
              : t.languageSettings.toastRememberedDetail(global: global))
        : (title == null ? null : t.languageSettings.toastSessionOnlyDetail(title: title));

    _toastController.show(_languageKindIcon(notice.kind), headline, detail: detail, duration: _kLanguageToastDuration);
  }

  /// 31 D. What is missing, what is playing instead, and — the point of the
  /// toast — that the stored preference is untouched and comes back on its own.
  void _showFallbackToast(LanguageFallbackApplied notice) {
    final wanted = languageDisplayName(notice.wantedLanguage) ?? notice.wantedLanguage;
    final actual = languageDisplayName(notice.actualLanguage);
    final title = notice.seriesTitle;

    final headline = notice.subtitlesOff || actual == null
        ? t.languageSettings.toastFallbackOff(wanted: wanted)
        : t.languageSettings.toastFallback(
            wanted: wanted,
            kind: _languageKindLabel(notice.kind).toLowerCase(),
            actual: actual,
          );

    final detail = notice.fromSeriesPreference && title != null
        ? t.languageSettings.toastFallbackDetailSeries(title: title, wanted: wanted)
        : t.languageSettings.toastFallbackDetailGlobal(wanted: wanted);

    _toastController.show(
      _languageKindIcon(notice.kind),
      headline,
      detail: detail,
      accent: true,
      duration: _kLanguageToastDuration,
    );
  }

  String _languageKindLabel(LanguageTrackKind kind) =>
      kind == LanguageTrackKind.audio ? t.languageSettings.kindAudio : t.languageSettings.kindSubtitles;

  IconData _languageKindIcon(LanguageTrackKind kind) =>
      kind == LanguageTrackKind.audio ? Symbols.volume_up_rounded : Symbols.closed_caption_rounded;
}
