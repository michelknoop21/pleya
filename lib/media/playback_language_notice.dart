/// What the player owes the viewer to say about a language decision — mockups
/// 31 C and 31 D.
///
/// A notice is *semantic*: which kind of track, what was wanted, what is
/// playing, and where the wish came from. It carries no sentence and no icon.
/// The player screen turns it into the toast, because the wording is a product
/// decision that belongs with the surface and not with the resolver.
///
/// Two of them, and they are the two halves of DEC-096 the viewer can actually
/// observe: a deliberate choice was remembered (31 C), or a wanted language was
/// not in this episode and something else is playing for now (31 D). Nothing
/// else is worth interrupting a picture for.
library;

/// Which track a notice is about.
enum LanguageTrackKind { audio, subtitles }

sealed class PlaybackLanguageNotice {
  const PlaybackLanguageNotice({required this.kind, this.seriesTitle});

  final LanguageTrackKind kind;

  /// The series this is about, or null for a movie and for an episode whose
  /// metadata carries no show title. The sentence drops the name rather than
  /// inventing one.
  final String? seriesTitle;
}

/// Mockup 31 C: the viewer picked a language and Pleya kept it.
class LanguageChoiceRemembered extends PlaybackLanguageNotice {
  const LanguageChoiceRemembered({
    required super.kind,
    required this.language,
    required this.storedForSeries,
    this.subtitlesOff = false,
    this.globalLanguage,
    super.seriesTitle,
  });

  /// The chosen language, as an ISO code. Null when [subtitlesOff].
  final String? language;

  /// The choice was "no subtitles", which is a choice and not an absence.
  final bool subtitlesOff;

  /// Whether the choice became the series preference, or holds for this
  /// playback alone because "Onthoud keuzes per serie" is off (DEC-096 lid 3).
  /// The toast says which, because those are different promises.
  final bool storedForSeries;

  /// The profile's own language for this kind, so the toast can say what did
  /// *not* change. Null when the profile has no opinion, and the sentence then
  /// leaves that clause out.
  final String? globalLanguage;
}

/// Mockup 31 D: this episode does not have the wanted language.
class LanguageFallbackApplied extends PlaybackLanguageNotice {
  const LanguageFallbackApplied({
    required super.kind,
    required this.wantedLanguage,
    required this.fromSeriesPreference,
    this.actualLanguage,
    this.subtitlesOff = false,
    super.seriesTitle,
  });

  /// The language the preference asked for, as an ISO code.
  final String wantedLanguage;

  /// What is playing instead. Null with [subtitlesOff], and null for an audio
  /// track whose own language the file does not name.
  final String? actualLanguage;

  /// Subtitles went off because neither the wanted language nor the fallback
  /// language is in this episode — the end of the subtitle contract.
  final bool subtitlesOff;

  /// Whether the unmet wish was the series preference or the global one. The
  /// toast names the right owner: "Je voorkeur voor Severance" against "Je
  /// globale voorkeur".
  final bool fromSeriesPreference;
}
