/// The Pleya profile's own audio/subtitle preference — the global layer of
/// DEC-096, and the owner of it.
///
/// Deliberately not the server profile. The requirement is that the preference
/// holds for *all* content, across servers and across backends, and a Plex
/// account or a Jellyfin user only ever speaks for its own server. Those
/// remain a mirror (Plex) or a seed (both), never the authority.
///
/// Intent, never a track. What is stored is "Dutch subtitles", "the original
/// audio language", "subtitles only with foreign audio" — never a stream id or
/// a track index, which belong to one episode on one source and mean nothing
/// on the next one (DEC-096 lid 8).
library;

/// When subtitles should come on at all.
enum SubtitleDisplayPolicy {
  /// Only when the audio is not in the viewer's own language.
  foreignAudioOnly,

  /// Always, when a track in a wanted language exists.
  always,

  /// Never automatically; the viewer turns them on by hand.
  never,
}

/// A profile-wide audio/subtitle preference. Every field is optional: an
/// untouched profile means "no opinion", and resolution then falls through to
/// the source and the file, which is the fourth layer of DEC-096.
class PleyaProfileLanguagePreferences {
  /// The wanted audio language, as an ISO code. Null when [useOriginalAudio]
  /// carries the intent instead, or when the viewer has no opinion.
  final String? audioLanguage;

  /// "Whatever language this was made in." Outranks [audioLanguage] because it
  /// is the more specific statement of intent; a title with no known original
  /// language falls back to the source default, never to a guess.
  final bool useOriginalAudio;

  /// The wanted subtitle language, as an ISO code.
  final String? subtitleLanguage;

  /// The language to try when [subtitleLanguage] is not in this episode.
  ///
  /// A real preference with a row of its own, not a hardcoded English
  /// (DEC-096 lid 3). Seeded once from the ranked list on the server profile
  /// where there is one, and independently editable after that. When this
  /// language is missing too, subtitles go off — never "the first available
  /// track".
  final String? subtitleFallbackLanguage;

  /// When subtitles come on by themselves.
  final SubtitleDisplayPolicy? subtitlePolicy;

  /// Whether a deliberate switch during a series writes a series override.
  /// Off means the switch holds for that playback session only.
  final bool rememberPerSeries;

  /// Whether a series preference is also written onto the show in Plex.
  ///
  /// A mirror, and only where the backend has the capability. A failed write
  /// never invalidates the Pleya preference and never rolls anything back
  /// (DEC-096 lid 6).
  final bool mirrorToPlex;

  /// Epoch milliseconds of the last write. Lets a later sync reconcile two
  /// devices without inventing an ordering.
  final int updatedAt;

  /// Whether a one-time seed from a server profile has already run, so a
  /// second server signing in later cannot overwrite what the viewer set.
  final bool seeded;

  const PleyaProfileLanguagePreferences({
    this.audioLanguage,
    this.useOriginalAudio = false,
    this.subtitleLanguage,
    this.subtitleFallbackLanguage,
    this.subtitlePolicy,
    this.rememberPerSeries = true,
    this.mirrorToPlex = true,
    this.updatedAt = 0,
    this.seeded = false,
  });

  /// Nothing the viewer chose — only the defaults. Used to decide whether a
  /// seed from a server profile may still run.
  bool get isUnset =>
      audioLanguage == null &&
      !useOriginalAudio &&
      subtitleLanguage == null &&
      subtitleFallbackLanguage == null &&
      subtitlePolicy == null;

  /// `null` clears nothing — pass [clearAudioLanguage] and friends to empty a
  /// field, the way "Gebruik globale voorkeur" needs to.
  PleyaProfileLanguagePreferences copyWith({
    String? audioLanguage,
    bool clearAudioLanguage = false,
    bool? useOriginalAudio,
    String? subtitleLanguage,
    bool clearSubtitleLanguage = false,
    String? subtitleFallbackLanguage,
    bool clearSubtitleFallbackLanguage = false,
    SubtitleDisplayPolicy? subtitlePolicy,
    bool clearSubtitlePolicy = false,
    bool? rememberPerSeries,
    bool? mirrorToPlex,
    int? updatedAt,
    bool? seeded,
  }) => PleyaProfileLanguagePreferences(
    audioLanguage: clearAudioLanguage ? null : (audioLanguage ?? this.audioLanguage),
    useOriginalAudio: useOriginalAudio ?? this.useOriginalAudio,
    subtitleLanguage: clearSubtitleLanguage ? null : (subtitleLanguage ?? this.subtitleLanguage),
    subtitleFallbackLanguage: clearSubtitleFallbackLanguage
        ? null
        : (subtitleFallbackLanguage ?? this.subtitleFallbackLanguage),
    subtitlePolicy: clearSubtitlePolicy ? null : (subtitlePolicy ?? this.subtitlePolicy),
    rememberPerSeries: rememberPerSeries ?? this.rememberPerSeries,
    mirrorToPlex: mirrorToPlex ?? this.mirrorToPlex,
    updatedAt: updatedAt ?? this.updatedAt,
    seeded: seeded ?? this.seeded,
  );

  /// Short keys: the whole map is one iCloud key-value entry under a 100 KB
  /// ceiling, so the field names are part of the budget. Same reasoning as
  /// [TrackLanguageChoice].
  Map<String, Object?> toJson() => {
    if (audioLanguage != null) 'a': audioLanguage,
    if (useOriginalAudio) 'ao': true,
    if (subtitleLanguage != null) 's': subtitleLanguage,
    if (subtitleFallbackLanguage != null) 'sf': subtitleFallbackLanguage,
    if (subtitlePolicy != null) 'sp': subtitlePolicy!.name,
    if (!rememberPerSeries) 'rp': false,
    if (!mirrorToPlex) 'mp': false,
    if (seeded) 'sd': true,
    'u': updatedAt,
  };

  static PleyaProfileLanguagePreferences fromJson(Map<String, dynamic> json) => PleyaProfileLanguagePreferences(
    audioLanguage: json['a'] as String?,
    useOriginalAudio: json['ao'] == true,
    subtitleLanguage: json['s'] as String?,
    subtitleFallbackLanguage: json['sf'] as String?,
    subtitlePolicy: _policyFromName(json['sp'] as String?),
    rememberPerSeries: json['rp'] != false,
    mirrorToPlex: json['mp'] != false,
    updatedAt: (json['u'] as num?)?.toInt() ?? 0,
    seeded: json['sd'] == true,
  );

  /// An unknown name means a newer build wrote a policy this one does not
  /// know. Falling back to null (no opinion) keeps that value readable rather
  /// than crashing on it, and the newer build still owns the real setting.
  static SubtitleDisplayPolicy? _policyFromName(String? name) {
    if (name == null) return null;
    for (final policy in SubtitleDisplayPolicy.values) {
      if (policy.name == name) return policy;
    }
    return null;
  }

  @override
  String toString() =>
      'PleyaProfileLanguagePreferences(audio: ${useOriginalAudio ? 'original' : audioLanguage}, '
      'subtitle: $subtitleLanguage, fallback: $subtitleFallbackLanguage, policy: ${subtitlePolicy?.name})';
}
