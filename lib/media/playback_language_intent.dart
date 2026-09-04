/// What the viewer *wants* to hear and read, as opposed to which concrete
/// track this episode ended up with (DEC-096 lid 1 and lid 8).
///
/// The distinction is the whole point of LANG1. A resolved track belongs to one
/// episode on one source: a stream id, an index, even "the Dutch track that was
/// playing" are all answers to "what did this file offer", and carrying them to
/// the next episode makes a temporary fallback permanent. An intent is the
/// question instead — "English subtitles" — and every episode answers it again
/// against its own track list.
///
/// Backend-neutral on purpose. The same intent resolves against Plex, against
/// Jellyfin, against Pleya Server and against an offline download; nothing here
/// knows which one it is.
library;

import 'pleya_profile_language_preferences.dart';
import 'track_language_choice.dart';

/// Which layer of DEC-096 an intent came from. Carried so the resolver and the
/// toast can say *why* something plays, and so a fallback can be told apart
/// from a choice.
enum PlaybackIntentOrigin {
  /// The viewer changed a track by hand during this playback. The highest
  /// layer, and the only one a real action creates.
  session,

  /// The series preference, from `TrackPreferenceStore`.
  series,

  /// The Pleya profile's global preference.
  global,
}

/// A language intent, at one origin. Every field is optional: an intent that
/// says nothing about subtitles leaves the layer below it to answer.
class PlaybackLanguageIntent {
  final PlaybackIntentOrigin origin;

  final String? audioLanguage;

  /// Match the title only to break a tie between two tracks in the same
  /// language. Never a reason to reject a language match on its own.
  final String? audioTitle;

  /// "Whatever this was made in." More specific than [audioLanguage], so it
  /// wins over it when both are set.
  final bool useOriginalAudio;

  final String? subtitleLanguage;
  final String? subtitleTitle;
  final bool subtitleForced;

  /// The viewer turned subtitles off on purpose. Distinct from a null
  /// [subtitleLanguage], which means this layer has no opinion at all — only
  /// the first may override what the source pre-selects.
  final bool subtitlesOff;

  const PlaybackLanguageIntent({
    required this.origin,
    this.audioLanguage,
    this.audioTitle,
    this.useOriginalAudio = false,
    this.subtitleLanguage,
    this.subtitleTitle,
    this.subtitleForced = false,
    this.subtitlesOff = false,
  });

  bool get hasAudio => useOriginalAudio || (audioLanguage != null && audioLanguage!.isNotEmpty);

  bool get hasSubtitle => subtitlesOff || (subtitleLanguage != null && subtitleLanguage!.isNotEmpty);

  bool get isEmpty => !hasAudio && !hasSubtitle;

  /// The series layer, from a remembered choice. Null when there is none.
  static PlaybackLanguageIntent? fromSeriesChoice(TrackLanguageChoice? choice) {
    if (choice == null || choice.isEmpty) return null;
    return PlaybackLanguageIntent(
      origin: PlaybackIntentOrigin.series,
      audioLanguage: choice.audioLanguage,
      audioTitle: choice.audioTitle,
      subtitleLanguage: choice.subtitleLanguage,
      subtitleTitle: choice.subtitleTitle,
      subtitleForced: choice.subtitleForced,
      subtitlesOff: choice.subtitlesOff,
    );
  }

  /// The global layer, from the Pleya profile. Null when the profile has no
  /// opinion, so the resolver falls straight through to the source.
  ///
  /// [PleyaProfileLanguagePreferences.subtitleFallbackLanguage] is deliberately
  /// *not* folded in here: it is not what the viewer wants, it is what to try
  /// when they cannot have it, and the resolver applies it after every intent
  /// layer has missed.
  static PlaybackLanguageIntent? fromProfile(PleyaProfileLanguagePreferences? preferences) {
    if (preferences == null) return null;
    final subtitlesOff = preferences.subtitlePolicy == SubtitleDisplayPolicy.never;
    final intent = PlaybackLanguageIntent(
      origin: PlaybackIntentOrigin.global,
      audioLanguage: preferences.audioLanguage,
      useOriginalAudio: preferences.useOriginalAudio,
      subtitleLanguage: subtitlesOff ? null : preferences.subtitleLanguage,
      subtitlesOff: subtitlesOff,
    );
    return intent.isEmpty ? null : intent;
  }

  /// The layers of DEC-096 in order, most specific first, with the empty ones
  /// left out. A field an earlier layer is silent about is answered by a later
  /// one, so a session intent that only names subtitles still lets the series
  /// preference decide the audio.
  static List<PlaybackLanguageIntent> layers({
    PlaybackLanguageIntent? session,
    TrackLanguageChoice? series,
    PleyaProfileLanguagePreferences? global,
  }) => [if (session != null && !session.isEmpty) session, ?fromSeriesChoice(series), ?fromProfile(global)];

  /// The first layer with something to say about audio, or null.
  static PlaybackLanguageIntent? resolveAudio(List<PlaybackLanguageIntent> layers) =>
      layers.where((layer) => layer.hasAudio).firstOrNull;

  /// The first layer with something to say about subtitles, or null.
  static PlaybackLanguageIntent? resolveSubtitle(List<PlaybackLanguageIntent> layers) =>
      layers.where((layer) => layer.hasSubtitle).firstOrNull;

  @override
  String toString() =>
      'PlaybackLanguageIntent(${origin.name}, audio: ${useOriginalAudio ? 'original' : audioLanguage}, '
      'subtitle: ${subtitlesOff ? 'off' : subtitleLanguage})';
}
