import '../media/media_source_info.dart';

/// The language to remember after a source-stream switch, or null when the
/// stream says nothing worth remembering.
///
/// While Plex transcodes, the track pickers do not swap an mpv track: they
/// select a different source stream and reload the session. That path carries
/// stream ids, not mpv tracks, so resolving the id back to a language is what
/// stands between a picked subtitle and [TrackPreferenceStore] hearing about it.
class SourceStreamLanguage {
  const SourceStreamLanguage({required this.language, this.title, this.forced = false});

  final String language;
  final String? title;
  final bool forced;
}

/// Resolves [streamId] against [tracks].
///
/// Returns null when the stream is unknown or carries no language code: that
/// says nothing about what to pick on the next episode, so the previous choice
/// is better left alone than overwritten with a blank.
///
/// `languageCode` is preferred over `language` because the first is the ISO
/// code the matcher compares against, while the second is often a display name
/// ("Dutch") that would never match a track tagged `nld`.
SourceStreamLanguage? subtitleStreamLanguage(List<MediaSubtitleTrack> tracks, int streamId) {
  final track = tracks.where((t) => t.id == streamId).firstOrNull;
  if (track == null) return null;
  final language = track.languageCode ?? track.language;
  if (language == null || language.isEmpty) return null;
  return SourceStreamLanguage(language: language, title: track.title, forced: track.forced);
}

/// Audio counterpart of [subtitleStreamLanguage]. Audio has no forced flag.
SourceStreamLanguage? audioStreamLanguage(List<MediaAudioTrack> tracks, int streamId) {
  final track = tracks.where((t) => t.id == streamId).firstOrNull;
  if (track == null) return null;
  final language = track.languageCode ?? track.language;
  if (language == null || language.isEmpty) return null;
  return SourceStreamLanguage(language: language, title: track.title);
}
