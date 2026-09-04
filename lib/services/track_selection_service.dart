import 'dart:async';

import '../mpv/mpv.dart';

import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_server_user_profile.dart';
import '../media/media_source_info.dart';
import '../media/playback_language_intent.dart';
import '../media/playback_language_notice.dart';
import '../media/pleya_profile_language_preferences.dart';
import '../media/track_language_choice.dart';
import '../utils/future_extensions.dart';
import '../utils/app_logger.dart';
import '../utils/language_codes.dart';

// These functions match MPV tracks to Plex tracks by properties (language,
// codec, title, etc.) instead of list index, since the two may be ordered
// differently.

/// Score how well an MPV subtitle track matches a Plex subtitle track.
/// Language (+10 / +1 exact) and codec (+5) carry the most weight; title,
/// forced flag, and identical ordinal position (only when [ordinalMatches]
/// is true) add smaller nudges.
int _scoreSubtitleMatch(SubtitleTrack mpvTrack, MediaSubtitleTrack plexTrack, {required bool ordinalMatches}) {
  int score = 0;

  if (_languagesMatch(mpvTrack.language, plexTrack.languageCode)) {
    score += 10;
    if (_languageCodesExactMatch(mpvTrack.language, plexTrack.languageCode)) {
      score += 1;
    }
  }

  if (_subtitleCodecsMatch(mpvTrack.codec, plexTrack.codec)) {
    score += 5;
  }

  score += _titleScore(mpvTrack.title, plexTrack.title, plexTrack.displayTitle);

  if (mpvTrack.isForced == plexTrack.forced) {
    score += 2;
  }

  if (ordinalMatches) {
    score += 1;
  }

  return score;
}

/// Score how well an MPV audio track matches a Plex audio track.
/// Language (+10 / +1 exact) and codec (+5) dominate; channel count (+3),
/// title match (+2), and identical ordinal position ([ordinalMatches], +1)
/// act as tiebreakers.
int _scoreAudioMatch(AudioTrack mpvTrack, MediaAudioTrack plexTrack, {required bool ordinalMatches}) {
  int score = 0;

  if (_languagesMatch(mpvTrack.language, plexTrack.languageCode)) {
    score += 10;
    if (_languageCodesExactMatch(mpvTrack.language, plexTrack.languageCode)) {
      score += 1;
    }
  }

  if (_audioCodecsMatch(mpvTrack.codec, plexTrack.codec)) {
    score += 5;
  }

  if (mpvTrack.channels != null && plexTrack.channels != null && mpvTrack.channels == plexTrack.channels) {
    score += 3;
  }

  if (_titlesMatch(mpvTrack.title, plexTrack.title, plexTrack.displayTitle)) {
    score += 2;
  }

  if (ordinalMatches) {
    score += 1;
  }

  return score;
}

/// Find the MPV subtitle track that matches a Plex subtitle track
SubtitleTrack? findMpvTrackForPlexSubtitle(
  MediaSubtitleTrack plexTrack,
  List<SubtitleTrack> mpvTracks, {
  List<MediaSubtitleTrack>? allPlexTracks,
}) {
  if (mpvTracks.isEmpty) return null;

  // For external subtitles, match by URI containing the Plex key
  if (plexTrack.isExternal && plexTrack.key != null) {
    for (final mpvTrack in mpvTracks) {
      if (mpvTrack.isExternal && mpvTrack.uri != null) {
        // Check if the MPV URI contains the Plex key path
        if (mpvTrack.uri!.contains(plexTrack.key!)) {
          return mpvTrack;
        }
      }
    }
  }

  // For internal subtitles, use scoring based on properties
  SubtitleTrack? bestMatch;
  int bestScore = 0;

  // Ordinal tiebreaker: precompute position of plexTrack among internal tracks
  final internalMpvTracks = allPlexTracks != null ? mpvTracks.where((t) => !t.isExternal).toList() : null;
  final plexOrdinal = allPlexTracks != null
      ? allPlexTracks.where((t) => !t.isExternal).toList().indexOf(plexTrack)
      : -1;

  for (final mpvTrack in mpvTracks) {
    // Skip external tracks when matching internal Plex tracks
    if (!plexTrack.isExternal && mpvTrack.isExternal) continue;

    final ordinalMatches =
        internalMpvTracks != null && plexOrdinal >= 0 && internalMpvTracks.indexOf(mpvTrack) == plexOrdinal;

    final score = _scoreSubtitleMatch(mpvTrack, plexTrack, ordinalMatches: ordinalMatches);

    if (score > bestScore) {
      bestScore = score;
      bestMatch = mpvTrack;
    }
  }

  // Require at least language match for a valid match
  return bestScore >= 10 ? bestMatch : null;
}

/// Find the Plex subtitle track that matches an MPV subtitle track
MediaSubtitleTrack? findPlexTrackForMpvSubtitle(
  SubtitleTrack mpvTrack,
  List<MediaSubtitleTrack> plexTracks, {
  List<SubtitleTrack>? allMpvTracks,
}) {
  if (plexTracks.isEmpty) return null;

  // For external subtitles, match by URI containing the Plex key
  if (mpvTrack.isExternal && mpvTrack.uri != null) {
    for (final plexTrack in plexTracks) {
      if (plexTrack.isExternal && plexTrack.key != null) {
        if (mpvTrack.uri!.contains(plexTrack.key!)) {
          return plexTrack;
        }
      }
    }
  }

  // For internal subtitles, use scoring based on properties
  MediaSubtitleTrack? bestMatch;
  int bestScore = 0;

  // Ordinal tiebreaker: precompute position of mpvTrack among internal tracks
  final internalPlexTracks = allMpvTracks != null ? plexTracks.where((t) => !t.isExternal).toList() : null;
  final mpvOrdinal = allMpvTracks != null ? allMpvTracks.where((t) => !t.isExternal).toList().indexOf(mpvTrack) : -1;

  for (final plexTrack in plexTracks) {
    // Skip external Plex tracks when matching internal MPV tracks
    if (!mpvTrack.isExternal && plexTrack.isExternal) continue;

    final ordinalMatches =
        internalPlexTracks != null && mpvOrdinal >= 0 && internalPlexTracks.indexOf(plexTrack) == mpvOrdinal;

    final score = _scoreSubtitleMatch(mpvTrack, plexTrack, ordinalMatches: ordinalMatches);

    if (score > bestScore) {
      bestScore = score;
      bestMatch = plexTrack;
    }
  }

  // Require at least language match for a valid match
  return bestScore >= 10 ? bestMatch : null;
}

/// Find the MPV audio track that matches a Plex audio track
AudioTrack? findMpvTrackForPlexAudio(
  MediaAudioTrack plexTrack,
  List<AudioTrack> mpvTracks, {
  List<MediaAudioTrack>? allPlexTracks,
}) {
  if (mpvTracks.isEmpty) return null;

  AudioTrack? bestMatch;
  int bestScore = 0;
  final plexOrdinal = allPlexTracks?.indexOf(plexTrack) ?? -1;

  for (final mpvTrack in mpvTracks) {
    final ordinalMatches = plexOrdinal >= 0 && mpvTracks.indexOf(mpvTrack) == plexOrdinal;

    final score = _scoreAudioMatch(mpvTrack, plexTrack, ordinalMatches: ordinalMatches);

    if (score > bestScore) {
      bestScore = score;
      bestMatch = mpvTrack;
    }
  }

  // Require at least language match for a valid match
  return bestScore >= 10 ? bestMatch : null;
}

/// Find the Plex audio track that matches an MPV audio track
MediaAudioTrack? findPlexTrackForMpvAudio(
  AudioTrack mpvTrack,
  List<MediaAudioTrack> plexTracks, {
  List<AudioTrack>? allMpvTracks,
}) {
  if (plexTracks.isEmpty) return null;

  MediaAudioTrack? bestMatch;
  int bestScore = 0;
  final mpvOrdinal = allMpvTracks?.indexOf(mpvTrack) ?? -1;

  for (final plexTrack in plexTracks) {
    final ordinalMatches = mpvOrdinal >= 0 && plexTracks.indexOf(plexTrack) == mpvOrdinal;

    final score = _scoreAudioMatch(mpvTrack, plexTrack, ordinalMatches: ordinalMatches);

    if (score > bestScore) {
      bestScore = score;
      bestMatch = plexTrack;
    }
  }

  // Require at least language match for a valid match
  return bestScore >= 10 ? bestMatch : null;
}

/// Check if two language codes match exactly (after normalizing case and stripping region suffixes)
bool _languageCodesExactMatch(String? a, String? b) {
  if (a == null || b == null) return false;
  return a.toLowerCase().split('-').first == b.toLowerCase().split('-').first;
}

/// Check if two language codes refer to the same language
/// Handles both ISO 639-1 (2-letter) and ISO 639-2 (3-letter) codes
bool _languagesMatch(String? mpvLang, String? plexLang) {
  if (mpvLang == null || plexLang == null) return false;

  final mpvNormalized = mpvLang.toLowerCase().split('-').first;
  final plexNormalized = plexLang.toLowerCase().split('-').first;

  // Direct match
  if (mpvNormalized == plexNormalized) return true;

  final mpvVariations = LanguageCodes.getVariations(mpvNormalized);
  return mpvVariations.contains(plexNormalized);
}

/// Check if two subtitle codec strings match
/// Handles common aliases (e.g., subrip/srt, ass/ssa)
bool _subtitleCodecsMatch(String? mpvCodec, String? plexCodec) {
  if (mpvCodec == null || plexCodec == null) return false;

  final mpvNorm = mpvCodec.toLowerCase();
  final plexNorm = plexCodec.toLowerCase();

  if (mpvNorm == plexNorm) return true;

  // Common subtitle codec aliases
  const aliases = {
    'subrip': ['srt', 'subrip'],
    'srt': ['srt', 'subrip'],
    'ass': ['ass', 'ssa'],
    'ssa': ['ass', 'ssa'],
    'pgs': ['pgs', 'hdmv_pgs_subtitle'],
    'hdmv_pgs_subtitle': ['pgs', 'hdmv_pgs_subtitle'],
    'vobsub': ['vobsub', 'dvd_subtitle'],
    'dvd_subtitle': ['vobsub', 'dvd_subtitle'],
    'webvtt': ['webvtt', 'vtt'],
    'vtt': ['webvtt', 'vtt'],
  };

  final mpvAliases = aliases[mpvNorm] ?? [mpvNorm];
  return mpvAliases.contains(plexNorm);
}

/// Check if two audio codec strings match
/// Handles common aliases (e.g., ac3/a52, dts variants)
bool _audioCodecsMatch(String? mpvCodec, String? plexCodec) {
  if (mpvCodec == null || plexCodec == null) return false;

  final mpvNorm = mpvCodec.toLowerCase();
  final plexNorm = plexCodec.toLowerCase();

  if (mpvNorm == plexNorm) return true;

  // Common audio codec aliases
  const aliases = {
    'ac3': ['ac3', 'a52', 'eac3', 'dolby digital'],
    'a52': ['ac3', 'a52'],
    'eac3': ['eac3', 'e-ac-3', 'dolby digital plus', 'ac3'],
    'dts': ['dts', 'dca'],
    'dca': ['dts', 'dca'],
    'aac': ['aac', 'mp4a'],
    'mp4a': ['aac', 'mp4a'],
    'truehd': ['truehd', 'mlp'],
    'mlp': ['truehd', 'mlp'],
    'flac': ['flac'],
    'opus': ['opus'],
    'vorbis': ['vorbis', 'ogg'],
    'mp3': ['mp3', 'mp3float'],
  };

  final mpvAliases = aliases[mpvNorm] ?? [mpvNorm];
  return mpvAliases.contains(plexNorm);
}

/// Score how well titles match.
/// Returns 3 for a real text match, 1 for null/empty (non-contradicting), 0 for mismatch.
int _titleScore(String? mpvTitle, String? plexTitle, String? plexDisplayTitle) {
  if (mpvTitle == null || mpvTitle.isEmpty) return 1; // No title to contradict — mild bonus

  final mpvNorm = mpvTitle.toLowerCase().trim();

  // Check exact match with either Plex title
  if (plexTitle != null && plexTitle.toLowerCase().trim() == mpvNorm) return 3;
  if (plexDisplayTitle != null && plexDisplayTitle.toLowerCase().trim() == mpvNorm) return 3;

  // Check if one contains the other (partial match)
  if (plexTitle != null && plexTitle.toLowerCase().contains(mpvNorm)) return 3;
  if (plexDisplayTitle != null && plexDisplayTitle.toLowerCase().contains(mpvNorm)) return 3;

  return 0;
}

/// Check if titles match (fuzzy comparison) — used by audio matching
bool _titlesMatch(String? mpvTitle, String? plexTitle, String? plexDisplayTitle) {
  return _titleScore(mpvTitle, plexTitle, plexDisplayTitle) > 0;
}

int _mediaTrackStreamIndex(int id, int? index) => index ?? id;

/// Which layer of DEC-096 produced a selection.
///
/// The first three are *intent* — what the viewer wants — and the rest are
/// *source*: what this file and this server happen to offer. A source-layer
/// result is by definition temporary, which is why nothing below
/// [globalProfile] may ever be written back as a preference.
enum TrackSelectionPriority {
  /// Layer 1: a real action by the viewer during this playback.
  sessionIntent,

  /// Layer 2: the series preference.
  sticky,

  /// Layer 3: the Pleya profile's global preference.
  globalProfile,

  /// A concrete track carried in by a same-item reload. Below every intent
  /// layer on purpose: it is a resolved track, not a wish, and letting it
  /// outrank the layers above is what made a one-episode fallback permanent
  /// (DEC-096 lid 1).
  navigation,

  /// Layer 4a: the source's own pre-selected stream.
  serverSelected,

  /// Layer 4b: a per-media language field on the item.
  perMedia,

  /// Layer 4c: the *server* profile — a mirror, never the authority.
  profile,

  /// Layer 4d: the profile's subtitle fallback language, used only after every
  /// wanted language missed (DEC-096 lid 3).
  fallbackLanguage,

  /// Layer 4e: the file's own default track.
  defaultTrack,

  /// Subtitles off (subtitle only).
  off,
}

/// Result of track selection including the selected track and which priority was used
class TrackSelectionResult<T> {
  final T track;
  final TrackSelectionPriority priority;

  const TrackSelectionResult(this.track, this.priority);
}

/// Service for selecting and applying audio and subtitle tracks based on
/// preferences, user profiles, and per-media settings.
class TrackSelectionService {
  final Player player;
  final MediaServerUserProfile? profileSettings;
  final MediaItem metadata;
  final MediaSourceInfo? plexMediaInfo;

  /// The language this user last picked by hand for this series or movie, or
  /// null when they never did. Layer 2 of DEC-096.
  final TrackLanguageChoice? stickyChoice;

  /// The Pleya profile's global preference — layer 3, and the owner of the
  /// global layer (DEC-096 lid 5). Applies to every backend alike: Plex,
  /// Jellyfin, Pleya Server and offline playback. Null means the profile has
  /// no opinion and resolution falls through to the source.
  final PleyaProfileLanguagePreferences? globalPreferences;

  /// A track the viewer switched to by hand earlier in this playback session —
  /// layer 1, and the only layer a real action creates. Never the currently
  /// playing track, never a fallback, never something carried over from the
  /// previous episode's resolution.
  final PlaybackLanguageIntent? sessionIntent;

  TrackSelectionService({
    required this.player,
    this.profileSettings,
    required this.metadata,
    this.plexMediaInfo,
    this.stickyChoice,
    this.globalPreferences,
    this.sessionIntent,
  });

  /// The intent layers of DEC-096 in order, most specific first.
  late final List<PlaybackLanguageIntent> _intentLayers = PlaybackLanguageIntent.layers(
    session: sessionIntent,
    series: stickyChoice,
    global: globalPreferences,
  );

  /// The priority to report for a hit on [intent]'s layer.
  static TrackSelectionPriority _priorityFor(PlaybackLanguageIntent intent) => switch (intent.origin) {
    PlaybackIntentOrigin.session => TrackSelectionPriority.sessionIntent,
    PlaybackIntentOrigin.series => TrackSelectionPriority.sticky,
    PlaybackIntentOrigin.global => TrackSelectionPriority.globalProfile,
  };

  /// The original audio language of this title, when the metadata knows it.
  ///
  /// Today: never. None of the four backends carries an original-language
  /// field — Plex and Jellyfin do not expose one on the item, and the `/v1`
  /// contract has no property for it either — so this is the seam that answers
  /// once one of them does, and nothing more.
  ///
  /// Deliberately *not* "the first audio track", and deliberately not the
  /// track the container marks default either. Track order says nothing about
  /// what a thing was made in, and guessing is how a Japanese show starts in
  /// its English dub. Null means unknown, which sends "Originele taal" through
  /// to the source's own default — exactly the fallback DEC-096 lid 3
  /// prescribes, and exactly what the row's own subtitle in mockup 31 A
  /// promises the viewer.
  String? get _originalAudioLanguage => null;

  /// Build list of preferred languages from a user profile
  List<String> _buildPreferredLanguages(MediaServerUserProfile profile, {required bool isAudio}) {
    final primary = isAudio ? profile.defaultAudioLanguage : profile.defaultSubtitleLanguage;
    final list = isAudio ? profile.defaultAudioLanguages : profile.defaultSubtitleLanguages;

    final result = <String>[];
    if (primary != null && primary.isNotEmpty) {
      result.add(primary);
    }
    if (list != null) {
      result.addAll(list);
    }
    return result;
  }

  /// Find a track by preferred language with variation lookup and logging
  T? _findTrackByPreferredLanguage<T>(
    List<T> tracks,
    String preferredLanguage,
    String? Function(T) getLanguage,
    String Function(T) getDescription,
    String trackType,
  ) {
    final languageVariations = LanguageCodes.getVariations(preferredLanguage);
    return _findTrackByLanguageVariations<T>(
      tracks,
      preferredLanguage,
      languageVariations,
      getLanguage,
      getDescription,
      trackType,
    );
  }

  /// Apply a filter to tracks, falling back to original if filter produces empty result
  /// Generic track matching for audio and subtitle tracks
  /// Returns the best matching track based on hierarchical criteria:
  /// 1. Exact match (id + title + language)
  /// 2. Partial match (title + language)
  /// 3. Language-only match
  T? findBestTrackMatch<T>(
    List<T> availableTracks,
    T preferred,
    String Function(T) getId,
    String? Function(T) getTitle,
    String? Function(T) getLanguage,
  ) {
    if (availableTracks.isEmpty) return null;

    // Filter out auto and no tracks
    final validTracks = availableTracks.where((t) => getId(t) != 'auto' && getId(t) != 'no').toList();
    if (validTracks.isEmpty) return null;

    final preferredId = getId(preferred);
    final preferredTitle = getTitle(preferred);
    final preferredLanguage = getLanguage(preferred);

    // Try to match: id, title, and language
    for (final track in validTracks) {
      if (getId(track) == preferredId && getTitle(track) == preferredTitle && getLanguage(track) == preferredLanguage) {
        return track;
      }
    }

    // Try to match: title and language
    for (final track in validTracks) {
      if (getTitle(track) == preferredTitle && getLanguage(track) == preferredLanguage) {
        return track;
      }
    }

    // Try to match: language only
    for (final track in validTracks) {
      if (getLanguage(track) == preferredLanguage) {
        return track;
      }
    }

    return null;
  }

  AudioTrack? findBestAudioMatch(List<AudioTrack> availableTracks, AudioTrack preferred) {
    return findBestTrackMatch<AudioTrack>(availableTracks, preferred, (t) => t.id, (t) => t.title, (t) => t.language);
  }

  AudioTrack? findAudioTrackByProfile(List<AudioTrack> availableTracks, MediaServerUserProfile profile) {
    if (availableTracks.isEmpty || !profile.autoSelectAudio) return null;

    final preferredLanguages = _buildPreferredLanguages(profile, isAudio: true);
    if (preferredLanguages.isEmpty) return null;

    for (final preferredLanguage in preferredLanguages) {
      final match = _findTrackByPreferredLanguage<AudioTrack>(
        availableTracks,
        preferredLanguage,
        (t) => t.language,
        (t) => t.title ?? 'Track ${t.id}',
        'audio track',
      );
      if (match != null) return match;
    }

    return null;
  }

  SubtitleTrack? _findSubtitleTrackByProfile(
    List<SubtitleTrack> availableTracks,
    MediaServerUserProfile profile, {
    bool forcedOnly = false,
  }) {
    final candidates = forcedOnly ? availableTracks.where((track) => track.isForced).toList() : availableTracks;
    if (candidates.isEmpty) return null;

    final preferredLanguages = _buildPreferredLanguages(profile, isAudio: false);
    if (preferredLanguages.isEmpty) return null;

    for (final preferredLanguage in preferredLanguages) {
      final match = _findTrackByPreferredLanguage<SubtitleTrack>(
        candidates,
        preferredLanguage,
        (track) => track.language,
        (track) => track.title ?? 'Track ${track.id}',
        'subtitle track',
      );
      if (match != null) return match;
    }

    return null;
  }

  SubtitleTrack? _findDefaultSubtitleTrack(List<SubtitleTrack> availableTracks) {
    for (final track in availableTracks) {
      if (track.isDefault) return track;
    }
    return null;
  }

  SubtitleTrack? _findFirstSubtitleTrack(List<SubtitleTrack> availableTracks) {
    return availableTracks.isEmpty ? null : availableTracks.first;
  }

  SubtitleTrack? _findForcedSubtitleTrack(List<SubtitleTrack> availableTracks) {
    for (final track in availableTracks) {
      if (track.isForced) return track;
    }
    return null;
  }

  bool _audioMatchesProfile(AudioTrack? selectedAudioTrack, MediaServerUserProfile profile) {
    if (selectedAudioTrack == null) return false;
    final preferredLanguages = _buildPreferredLanguages(profile, isAudio: true);
    if (preferredLanguages.isEmpty) return false;
    return preferredLanguages.any((language) => languageMatches(selectedAudioTrack.language, language));
  }

  TrackSelectionResult<SubtitleTrack>? _selectSubtitleTrackByProfile(
    List<SubtitleTrack> availableTracks,
    AudioTrack? selectedAudioTrack,
  ) {
    final profile = profileSettings;
    final mode = profile?.subtitleMode;
    if (profile == null || mode == null || mode == SubtitlePlaybackMode.defaultMode) return null;

    SubtitleTrack? selected;
    switch (mode) {
      case SubtitlePlaybackMode.none:
        selected = SubtitleTrack.off;
        break;
      case SubtitlePlaybackMode.onlyForced:
        selected =
            _findSubtitleTrackByProfile(availableTracks, profile, forcedOnly: true) ??
            _findForcedSubtitleTrack(availableTracks) ??
            SubtitleTrack.off;
        break;
      case SubtitlePlaybackMode.always:
        selected =
            _findSubtitleTrackByProfile(availableTracks, profile) ??
            _findDefaultSubtitleTrack(availableTracks) ??
            _findFirstSubtitleTrack(availableTracks) ??
            SubtitleTrack.off;
        break;
      case SubtitlePlaybackMode.smart:
        if (_audioMatchesProfile(selectedAudioTrack, profile)) {
          selected =
              _findSubtitleTrackByProfile(availableTracks, profile, forcedOnly: true) ??
              _findForcedSubtitleTrack(availableTracks) ??
              SubtitleTrack.off;
        } else {
          selected =
              _findSubtitleTrackByProfile(availableTracks, profile) ??
              _findDefaultSubtitleTrack(availableTracks) ??
              _findFirstSubtitleTrack(availableTracks) ??
              SubtitleTrack.off;
        }
        break;
      case SubtitlePlaybackMode.defaultMode:
        return null;
    }

    return TrackSelectionResult(selected, TrackSelectionPriority.profile);
  }

  SubtitleTrack? findBestSubtitleMatch(List<SubtitleTrack> availableTracks, SubtitleTrack preferred) {
    // Handle special "no subtitles" case
    if (preferred.id == 'no') {
      return SubtitleTrack.off;
    }

    return findBestTrackMatch<SubtitleTrack>(
      availableTracks,
      preferred,
      (t) => t.id,
      (t) => t.title,
      (t) => t.language,
    );
  }

  /// Find a track matching a preferred language from a list of tracks
  /// Returns the first track whose language matches any variation of the preferred language
  T? _findTrackByLanguageVariations<T>(
    List<T> tracks,
    String _,
    List<String> languageVariations,
    String? Function(T) getLanguage,
    String Function(T) _,
    String _,
  ) {
    for (final track in tracks) {
      final trackLang = getLanguage(track)?.toLowerCase();
      if (trackLang != null && languageVariations.any((lang) => trackLang.startsWith(lang))) {
        return track;
      }
    }
    return null;
  }

  /// Checks if a track language matches a preferred language
  ///
  /// Handles both 2-letter (ISO 639-1) and 3-letter (ISO 639-2) codes
  /// Also handles bibliographic variants and region codes (e.g., "en-US")
  bool languageMatches(String? trackLanguage, String? preferredLanguage) {
    if (trackLanguage == null || preferredLanguage == null) {
      return false;
    }

    final track = trackLanguage.toLowerCase();
    final preferred = preferredLanguage.toLowerCase();

    // Direct match
    if (track == preferred) return true;

    // Extract base language codes (handle region codes like "en-US")
    final trackBase = track.split('-').first;
    final preferredBase = preferred.split('-').first;

    if (trackBase == preferredBase) return true;

    // Get all variations of the preferred language (e.g., "en" → ["en", "eng"])
    final variations = LanguageCodes.getVariations(preferredBase);

    // Check if track's base code matches any variation
    return variations.contains(trackBase);
  }

  /// Pick the track whose language matches [language], breaking a tie between
  /// same-language tracks on [title]. Null when no track speaks that language.
  T? _matchByLanguage<T>(
    List<T> tracks,
    String? language,
    String? title,
    String? Function(T) getLanguage,
    String? Function(T) getTitle,
  ) {
    if (language == null || language.isEmpty) return null;
    final matches = tracks.where((t) => languageMatches(getLanguage(t), language)).toList();
    if (matches.isEmpty) return null;
    if (title == null || title.isEmpty) return matches.first;
    return matches.where((t) => getTitle(t) == title).firstOrNull ?? matches.first;
  }

  /// Select the best audio track along the four layers of DEC-096:
  ///
  /// 1. the viewer's own action in this playback, then the series preference,
  ///    then the Pleya profile — all three as *intent*, resolved fresh against
  ///    this file's tracks;
  /// 2. a concrete track carried in by a same-item reload;
  /// 3. the source: its pre-selected stream, the item's own language field,
  ///    the server profile, and finally the file's default track.
  ///
  /// Layer order is backend-neutral. Plex, Jellyfin, Pleya Server and offline
  /// playback all run this same cascade; only the source layer differs between
  /// them, because only the source layer is about a particular server.
  TrackSelectionResult<AudioTrack>? selectAudioTrack(
    List<AudioTrack> availableTracks,
    AudioTrack? preferredAudioTrack,
  ) {
    if (availableTracks.isEmpty) return null;

    AudioTrack? trackToSelect;

    // Layers 1-3: the first intent that names a language this file actually
    // has. A layer that names one the file lacks does not stop the search —
    // "English, and otherwise whatever my profile says" is the whole point of
    // having layers.
    for (final intent in _intentLayers.where((layer) => layer.hasAudio)) {
      final language = intent.useOriginalAudio ? _originalAudioLanguage : intent.audioLanguage;
      // "Original language" with no metadata to say what that is: no match,
      // and the search moves on rather than inventing one.
      if (language == null || language.isEmpty) continue;

      final match = _matchByLanguage<AudioTrack>(
        availableTracks,
        language,
        intent.audioTitle,
        (t) => t.language,
        (t) => t.title,
      );
      if (match != null) {
        appLogger.d('Audio: honouring $language from the ${intent.origin.name} layer');
        return TrackSelectionResult(match, _priorityFor(intent));
      }
    }

    // Below every intent layer: a concrete track a same-item reload carried in.
    if (preferredAudioTrack != null) {
      trackToSelect = findBestAudioMatch(availableTracks, preferredAudioTrack);
      if (trackToSelect != null) {
        return TrackSelectionResult(trackToSelect, TrackSelectionPriority.navigation);
      }
    }

    // Layer 4a: the source's pre-selected stream.
    final info = plexMediaInfo;
    if (info != null && availableTracks.isNotEmpty) {
      final serverSelectedTrack = info.audioTracks.where((t) => t.selected).firstOrNull;

      if (serverSelectedTrack != null) {
        final matchedMpvTrack = findMpvTrackForPlexAudio(
          serverSelectedTrack,
          availableTracks,
          allPlexTracks: info.audioTracks,
        );

        if (matchedMpvTrack != null) {
          return TrackSelectionResult(matchedMpvTrack, TrackSelectionPriority.serverSelected);
        }
      } else if (metadata.backend == MediaBackend.jellyfin) {
        final defaultStreamIndex = info.defaultAudioStreamIndex;
        final defaultTrack = defaultStreamIndex != null
            ? info.audioTracks
                  .where((track) => _mediaTrackStreamIndex(track.id, track.index) == defaultStreamIndex)
                  .firstOrNull
            : null;

        if (defaultTrack != null) {
          final matchedMpvTrack = findMpvTrackForPlexAudio(
            defaultTrack,
            availableTracks,
            allPlexTracks: info.audioTracks,
          );

          if (matchedMpvTrack != null) {
            return TrackSelectionResult(matchedMpvTrack, TrackSelectionPriority.serverSelected);
          }
        }
      }
    }

    // Layer 4b: the item's own language field.
    if (metadata.audioLanguage != null) {
      final matchedTrack = availableTracks.firstWhere(
        (track) => languageMatches(track.language, metadata.audioLanguage),
        orElse: () => availableTracks.first,
      );
      if (languageMatches(matchedTrack.language, metadata.audioLanguage)) {
        return TrackSelectionResult(matchedTrack, TrackSelectionPriority.perMedia);
      }
    }

    // Layer 4c: the *server* profile — a mirror of a preference, not its owner.
    if (profileSettings != null) {
      trackToSelect = findAudioTrackByProfile(availableTracks, profileSettings!);
      if (trackToSelect != null) {
        return TrackSelectionResult(trackToSelect, TrackSelectionPriority.profile);
      }
    }

    // Layer 4d: the file's own default track.
    trackToSelect = availableTracks.firstWhere((t) => t.isDefault, orElse: () => availableTracks.first);
    return TrackSelectionResult(trackToSelect, TrackSelectionPriority.defaultTrack);
  }

  /// The best subtitle track in [language], preferring one whose forced flag
  /// matches [forced] and breaking a remaining tie on [title].
  SubtitleTrack? _matchSubtitleLanguage(
    List<SubtitleTrack> availableTracks,
    String? language,
    String? title,
    bool forced,
  ) {
    if (language == null || language.isEmpty) return null;
    final forcedMatch = availableTracks.where((t) => t.isForced == forced).toList();
    return _matchByLanguage<SubtitleTrack>(forcedMatch, language, title, (t) => t.language, (t) => t.title) ??
        _matchByLanguage<SubtitleTrack>(availableTracks, language, title, (t) => t.language, (t) => t.title);
  }

  /// Select the best subtitle track along the four layers of DEC-096.
  ///
  /// Same cascade as [selectAudioTrack], with one rule of its own: when every
  /// intent layer named a language this episode does not have, the profile's
  /// **subtitle fallback language** gets a turn, and only when that misses too
  /// do subtitles go off. Never "the first available track" — a viewer who
  /// asked for English does not want Hungarian (DEC-096 lid 3).
  ///
  /// A fallback is temporary by construction: it returns a source-layer
  /// priority, and only the intent layers are ever written back as a
  /// preference.
  TrackSelectionResult<SubtitleTrack> selectSubtitleTrack(
    List<SubtitleTrack> availableTracks,
    SubtitleTrack? preferredSubtitleTrack,
    AudioTrack? selectedAudioTrack,
  ) {
    // Layers 1-3. An explicit "off" counts as a choice at its layer and is
    // honoured even when subtitle tracks exist.
    for (final intent in _intentLayers.where((layer) => layer.hasSubtitle)) {
      if (intent.subtitlesOff) {
        appLogger.d('Subtitles: honouring off from the ${intent.origin.name} layer');
        return TrackSelectionResult(SubtitleTrack.off, _priorityFor(intent));
      }
      final match = _matchSubtitleLanguage(
        availableTracks,
        intent.subtitleLanguage,
        intent.subtitleTitle,
        intent.subtitleForced,
      );
      if (match != null) {
        appLogger.d('Subtitles: honouring ${intent.subtitleLanguage} from the ${intent.origin.name} layer');
        return TrackSelectionResult(match, _priorityFor(intent));
      }
    }

    // The wanted language is not in this episode. Before falling through to
    // the source, give the profile's fallback language its turn — but only
    // when an intent layer actually wanted something, so a profile with no
    // opinion at all still gets the source's own behaviour.
    if (_intentLayers.any((layer) => layer.hasSubtitle && !layer.subtitlesOff)) {
      final fallbackLanguage = globalPreferences?.subtitleFallbackLanguage;
      if (fallbackLanguage != null && fallbackLanguage.isNotEmpty) {
        final match = _matchSubtitleLanguage(availableTracks, fallbackLanguage, null, false);
        if (match != null) {
          appLogger.d('Subtitles: falling back to $fallbackLanguage for this episode only');
          return TrackSelectionResult(match, TrackSelectionPriority.fallbackLanguage);
        }
      }
      // Wanted a language, could not have it, and could not have the fallback
      // either. Off — never a track in a language nobody asked for.
      appLogger.d('Subtitles: no wanted or fallback language in this episode, going off');
      return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.off);
    }

    // Below every intent layer: a concrete track a same-item reload carried in.
    if (preferredSubtitleTrack != null) {
      if (preferredSubtitleTrack.id == 'no') {
        return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.navigation);
      } else if (availableTracks.isNotEmpty) {
        final subtitleToSelect = findBestSubtitleMatch(availableTracks, preferredSubtitleTrack);
        if (subtitleToSelect != null) {
          return TrackSelectionResult(subtitleToSelect, TrackSelectionPriority.navigation);
        }
      }
    }

    // Layer 4a: trust the source's selected track. Plex computes this from
    // account/show/per-item prefs; Jellyfin exposes DefaultSubtitleStreamIndex.
    final info = plexMediaInfo;
    if (info != null) {
      final serverSelectedTrack = availableTracks.isNotEmpty
          ? info.subtitleTracks.where((track) => track.selected).firstOrNull
          : null;

      if (serverSelectedTrack != null) {
        final matchedMpvTrack = findMpvTrackForPlexSubtitle(
          serverSelectedTrack,
          availableTracks,
          allPlexTracks: info.subtitleTracks,
        );

        if (matchedMpvTrack != null) {
          return TrackSelectionResult(matchedMpvTrack, TrackSelectionPriority.serverSelected);
        }
      } else if (metadata.backend == MediaBackend.jellyfin) {
        final defaultStreamIndex = info.defaultSubtitleStreamIndex;
        if (defaultStreamIndex == -1) {
          return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.serverSelected);
        }

        final defaultTrack = defaultStreamIndex != null && availableTracks.isNotEmpty
            ? info.subtitleTracks
                  .where((track) => _mediaTrackStreamIndex(track.id, track.index) == defaultStreamIndex)
                  .firstOrNull
            : null;

        if (defaultTrack != null) {
          final matchedMpvTrack = findMpvTrackForPlexSubtitle(
            defaultTrack,
            availableTracks,
            allPlexTracks: info.subtitleTracks,
          );

          if (matchedMpvTrack != null) {
            return TrackSelectionResult(matchedMpvTrack, TrackSelectionPriority.serverSelected);
          }
        }
      } else if (metadata.backend == MediaBackend.plex && info.subtitleTracks.isNotEmpty) {
        // Server has subtitle tracks but none selected — trust that decision
        return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.serverSelected);
      }
    }

    // Layer 4b: the server profile's subtitle mode, where the backend exposes
    // one (Jellyfin). Plex keeps using the selected-stream path above.
    final profileSelectedTrack = _selectSubtitleTrackByProfile(availableTracks, selectedAudioTrack);
    if (profileSelectedTrack != null) return profileSelectedTrack;

    // Layer 4c: the file's own default subtitle.
    final defaultTrack = _findDefaultSubtitleTrack(availableTracks);
    if (defaultTrack != null) {
      return TrackSelectionResult(defaultTrack, TrackSelectionPriority.defaultTrack);
    }

    // Nothing wanted it on.
    return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.off);
  }

  /// The intent layer that decided what this episode *should* sound or read
  /// like, or null when no layer had an opinion.
  ///
  /// "Original audio" with no metadata to say what that is counts as no
  /// opinion: there is nothing to name in a sentence, and the source's own
  /// default is then the right answer rather than a disappointment.
  ({PlaybackLanguageIntent intent, String language})? _wantedLayer({required bool isSubtitle}) {
    for (final intent in _intentLayers.where((layer) => isSubtitle ? layer.hasSubtitle : layer.hasAudio)) {
      if (isSubtitle) {
        if (intent.subtitlesOff) return null;
        final language = intent.subtitleLanguage;
        if (language != null && language.isNotEmpty) return (intent: intent, language: language);
        continue;
      }
      final language = intent.useOriginalAudio ? _originalAudioLanguage : intent.audioLanguage;
      if (language != null && language.isNotEmpty) return (intent: intent, language: language);
    }
    return null;
  }

  /// What this resolution owes the viewer, per mockup 31 D, or null when it
  /// gave them what they asked for.
  ///
  /// Reads the outcome, not the intent: a [priority] on one of the three intent
  /// layers means the wish was met, and everything below it means this episode
  /// could not honour it. That is the same line DEC-096 lid 1 draws between an
  /// intent and a resolution, so there is one definition of "fell back" in the
  /// product rather than a second one written for the toast.
  PlaybackLanguageNotice? fallbackNotice({
    required bool isSubtitle,
    required TrackSelectionPriority priority,
    required String? actualLanguage,
    required bool isOff,
  }) {
    const met = {
      TrackSelectionPriority.sessionIntent,
      TrackSelectionPriority.sticky,
      TrackSelectionPriority.globalProfile,
    };
    if (met.contains(priority)) return null;

    final wanted = _wantedLayer(isSubtitle: isSubtitle);
    if (wanted == null) return null;
    // The wanted language is playing after all — a source layer happened to
    // land on it, and there is nothing to report.
    if (!isOff && languageMatches(actualLanguage, wanted.language)) return null;

    return LanguageFallbackApplied(
      kind: isSubtitle ? LanguageTrackKind.subtitles : LanguageTrackKind.audio,
      wantedLanguage: wanted.language,
      actualLanguage: isOff ? null : actualLanguage,
      subtitlesOff: isOff,
      fromSeriesPreference: wanted.intent.origin == PlaybackIntentOrigin.series,
      seriesTitle: metadata.grandparentTitle ?? metadata.title,
    );
  }

  /// Select and apply audio and subtitle tracks based on preferences
  Future<void> selectAndApplyTracks({
    AudioTrack? preferredAudioTrack,
    SubtitleTrack? preferredSubtitleTrack,
    SubtitleTrack? preferredSecondarySubtitleTrack,
    double? defaultPlaybackSpeed,
    // Typed as returning a future rather than `Function(...)`: both are fired
    // without awaiting below, and `unawaited` needs a real future to accept.
    //
    // `userInitiated: false` here, always. Everything this method does is
    // automatic resolution, so the callback may tell the server which stream is
    // now playing but must never write a preference: that is the difference
    // between a resolution and an intent, and blurring it is what let a
    // one-episode fallback overwrite a series preference (DEC-096 lid 1).
    Future<void> Function(AudioTrack, {required bool userInitiated})? onAudioTrackChanged,
    Future<void> Function(SubtitleTrack, {required bool userInitiated})? onSubtitleTrackChanged,
    // Fires at most twice per item — once for audio, once for subtitles — and
    // only when this episode could not honour a wanted language.
    void Function(PlaybackLanguageNotice)? onLanguageNotice,
  }) async {
    // Wait for tracks to be loaded
    if (player.state.tracks.audio.isEmpty && player.state.tracks.subtitle.isEmpty) {
      try {
        await player.streams.tracks
            .where((t) => t.audio.isNotEmpty || t.subtitle.isNotEmpty)
            .first
            .namedTimeout(const Duration(seconds: 10), operation: 'track loading');
      } catch (_) {
        // Timeout or stream closed — proceed with whatever state we have
      }
    }

    if (player.disposed) return;

    // Get real tracks (excluding auto and no)
    final realAudioTracks = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final realSubtitleTracks = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();

    // Select and apply audio track
    final audioResult = selectAudioTrack(realAudioTracks, preferredAudioTrack);
    AudioTrack? selectedAudioTrack;
    if (audioResult != null) {
      selectedAudioTrack = audioResult.track;
      appLogger.d(
        'Audio: ${selectedAudioTrack.title ?? selectedAudioTrack.language ?? "Track ${selectedAudioTrack.id}"} [${audioResult.priority.name}]',
      );
      unawaited(player.selectAudioTrack(selectedAudioTrack));

      // Tell the source which stream is playing, so a transcode session and
      // the server's own bookkeeping follow along. Deliberately not awaited:
      // that must not hold up applying the tracks.
      if (onAudioTrackChanged != null) {
        unawaited(onAudioTrackChanged(selectedAudioTrack, userInitiated: false));
      }

      if (onLanguageNotice != null) {
        final notice = fallbackNotice(
          isSubtitle: false,
          priority: audioResult.priority,
          actualLanguage: selectedAudioTrack.language,
          isOff: false,
        );
        if (notice != null) onLanguageNotice(notice);
      }
    }

    // Select and apply subtitle track
    final subtitleResult = selectSubtitleTrack(realSubtitleTracks, preferredSubtitleTrack, selectedAudioTrack);
    final selectedSubtitleTrack = subtitleResult.track;
    final subtitleName = selectedSubtitleTrack.id == 'no'
        ? 'OFF'
        : (selectedSubtitleTrack.title ?? selectedSubtitleTrack.language ?? 'Track ${selectedSubtitleTrack.id}');
    appLogger.d('Subtitle: $subtitleName [${subtitleResult.priority.name}]');
    unawaited(player.selectSubtitleTrack(selectedSubtitleTrack));

    // Same as the audio side above: fire and forget, on purpose.
    if (onSubtitleTrackChanged != null) {
      unawaited(onSubtitleTrackChanged(selectedSubtitleTrack, userInitiated: false));
    }

    if (onLanguageNotice != null) {
      final notice = fallbackNotice(
        isSubtitle: true,
        priority: subtitleResult.priority,
        actualLanguage: selectedSubtitleTrack.language,
        isOff: selectedSubtitleTrack.id == 'no',
      );
      if (notice != null) onLanguageNotice(notice);
    }

    // Apply preferred secondary subtitle track if provided (mpv-only)
    if (preferredSecondarySubtitleTrack != null &&
        preferredSecondarySubtitleTrack.id != 'no' &&
        player.supportsSecondarySubtitles &&
        realSubtitleTracks.isNotEmpty) {
      final secondaryMatch = findBestSubtitleMatch(realSubtitleTracks, preferredSecondarySubtitleTrack);
      if (secondaryMatch != null && secondaryMatch.id != 'no') {
        appLogger.d(
          'Secondary subtitle: ${secondaryMatch.title ?? secondaryMatch.language ?? "Track ${secondaryMatch.id}"}',
        );
        unawaited(player.selectSecondarySubtitleTrack(secondaryMatch));
      }
    }

    // Apply default playback speed from settings
    if (defaultPlaybackSpeed != null && defaultPlaybackSpeed != 1.0) {
      unawaited(player.setRate(defaultPlaybackSpeed));
    }
  }
}
