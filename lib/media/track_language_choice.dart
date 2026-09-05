/// The last audio/subtitle choice a user made by hand for a series (or a
/// standalone movie), stored so the next episode starts the same way.
///
/// Languages, not stream ids: a Plex `streamID` belongs to one part, so it
/// means nothing on the following episode. Title and forced are kept only to
/// break a tie between two tracks that share a language.
class TrackLanguageChoice {
  final String? audioLanguage;
  final String? audioTitle;

  final String? subtitleLanguage;
  final String? subtitleTitle;
  final bool subtitleForced;

  /// The user switched subtitles off on purpose. Distinct from a null
  /// [subtitleLanguage], which means they never chose at all — only the first
  /// may override what the server pre-selects.
  final bool subtitlesOff;

  /// Epoch milliseconds of the last write, used to evict the oldest entries
  /// once the map outgrows its cap.
  final int updatedAt;

  /// Where this choice came from, so the management page of mockup 31 A can
  /// name it: the series, its poster, the episode it was made in and the
  /// device it was made on.
  ///
  /// Kept on the entry rather than looked up when the page opens. The page
  /// lists preferences across every server the profile ever played from,
  /// including one that has since been removed or is offline, and a lookup
  /// would leave exactly those rows blank. Costs about 120 bytes an entry,
  /// which is what moved [TrackPreferenceStore.maxEntries] down to its
  /// current value.
  ///
  /// Never part of resolution. Nothing in `TrackSelectionService` reads any of
  /// it, and a missing field only ever costs the page a line of prose.
  final TrackChoiceProvenance? provenance;

  const TrackLanguageChoice({
    this.audioLanguage,
    this.audioTitle,
    this.subtitleLanguage,
    this.subtitleTitle,
    this.subtitleForced = false,
    this.subtitlesOff = false,
    this.provenance,
    required this.updatedAt,
  });

  bool get hasAudio => audioLanguage != null && audioLanguage!.isNotEmpty;

  bool get hasSubtitle => subtitlesOff || (subtitleLanguage != null && subtitleLanguage!.isNotEmpty);

  /// Nothing worth persisting — used to drop an entry instead of storing an
  /// empty one.
  bool get isEmpty => !hasAudio && !hasSubtitle;

  /// What to write into Plex's `subtitleMode` for this choice.
  ///
  /// Plex's own values, as the metadata editor labels them
  /// (`plex_metadata_edit_adapter.dart`): 0 is "manually selected", so nothing
  /// turns on by itself; 1 is "shown with foreign audio"; 2 is "always
  /// enabled". A remembered forced track maps onto 1 because that is the
  /// closest thing Plex offers, not because Plex calls it forced.
  ///
  /// Null when the user never chose, so the show's existing setting is left
  /// alone rather than reset.
  int? get plexSubtitleMode {
    if (!hasSubtitle) return null;
    if (subtitlesOff) return 0;
    return subtitleForced ? 1 : 2;
  }

  /// The language to write alongside [plexSubtitleMode]. An explicit "off" is
  /// sent as an empty string: Plex reads that as "no language preference",
  /// which is what mode 0 already says.
  String? get plexSubtitleLanguage => subtitlesOff ? '' : subtitleLanguage;

  TrackLanguageChoice copyWithAudio({
    String? language,
    String? title,
    TrackChoiceProvenance? provenance,
    required int updatedAt,
  }) => TrackLanguageChoice(
    audioLanguage: language,
    audioTitle: title,
    subtitleLanguage: subtitleLanguage,
    subtitleTitle: subtitleTitle,
    subtitleForced: subtitleForced,
    subtitlesOff: subtitlesOff,
    // A write refreshes the provenance, because "gekozen op ... bij S2E4"
    // describes the newest choice and not the first one. A caller that has
    // none to offer leaves the previous line standing rather than blanking it.
    provenance: provenance ?? this.provenance,
    updatedAt: updatedAt,
  );

  TrackLanguageChoice copyWithSubtitle({
    String? language,
    String? title,
    bool forced = false,
    bool off = false,
    TrackChoiceProvenance? provenance,
    required int updatedAt,
  }) => TrackLanguageChoice(
    audioLanguage: audioLanguage,
    audioTitle: audioTitle,
    subtitleLanguage: off ? null : language,
    subtitleTitle: off ? null : title,
    subtitleForced: !off && forced,
    subtitlesOff: off,
    provenance: provenance ?? this.provenance,
    updatedAt: updatedAt,
  );

  /// Short keys: the whole map lives in one iCloud key-value entry with a
  /// 100 KB ceiling, so the field names are part of the budget.
  Map<String, Object?> toJson() => {
    if (audioLanguage != null) 'a': audioLanguage,
    if (audioTitle != null) 'at': audioTitle,
    if (subtitleLanguage != null) 's': subtitleLanguage,
    if (subtitleTitle != null) 'st': subtitleTitle,
    if (subtitleForced) 'sf': true,
    if (subtitlesOff) 'so': true,
    if (provenance != null) 'p': provenance!.toJson(),
    'u': updatedAt,
  };

  static TrackLanguageChoice fromJson(Map<String, dynamic> json) => TrackLanguageChoice(
    audioLanguage: json['a'] as String?,
    audioTitle: json['at'] as String?,
    subtitleLanguage: json['s'] as String?,
    subtitleTitle: json['st'] as String?,
    subtitleForced: json['sf'] == true,
    subtitlesOff: json['so'] == true,
    provenance: json['p'] is Map<String, dynamic>
        ? TrackChoiceProvenance.fromJson(json['p'] as Map<String, dynamic>)
        : null,
    updatedAt: (json['u'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() =>
      'TrackLanguageChoice(audio: $audioLanguage, subtitle: ${subtitlesOff ? 'off' : subtitleLanguage})';
}

/// What the management page needs to describe a stored choice.
///
/// Presentation only, and deliberately so: every field here is something the
/// viewer reads, never something resolution acts on. Each is optional, because
/// each backend answers a different subset — a Pleya Server episode carries no
/// show poster path today, and a movie has no season or episode number at all.
class TrackChoiceProvenance {
  /// The show's title, or the movie's. What the row is called.
  final String? title;

  /// The show's poster on [serverId]. Meaningless without that server, which
  /// is why the two travel together.
  final String? posterPath;

  /// The server the choice was made on. Not part of the key — the preference
  /// deliberately outlives one server (DEC-096 lid 7) — but the only way to
  /// resolve [posterPath] back into an image.
  final String? serverId;

  /// Season and episode of the moment the viewer chose. Null for a movie.
  final int? seasonNumber;
  final int? episodeNumber;

  /// The device the choice was made on, as its owner named it.
  final String? deviceName;

  const TrackChoiceProvenance({
    this.title,
    this.posterPath,
    this.serverId,
    this.seasonNumber,
    this.episodeNumber,
    this.deviceName,
  });

  bool get isEmpty =>
      title == null &&
      posterPath == null &&
      serverId == null &&
      seasonNumber == null &&
      episodeNumber == null &&
      deviceName == null;

  /// "S2E4", or null when this is not an episode.
  String? get episodeLabel {
    final season = seasonNumber;
    final episode = episodeNumber;
    if (season == null || episode == null) return null;
    return 'S${season}E$episode';
  }

  /// Short keys, same budget reasoning as [TrackLanguageChoice.toJson].
  Map<String, Object?> toJson() => {
    if (title != null) 't': title,
    if (posterPath != null) 'i': posterPath,
    if (serverId != null) 'sv': serverId,
    if (seasonNumber != null) 'sn': seasonNumber,
    if (episodeNumber != null) 'en': episodeNumber,
    if (deviceName != null) 'd': deviceName,
  };

  static TrackChoiceProvenance fromJson(Map<String, dynamic> json) => TrackChoiceProvenance(
    title: json['t'] as String?,
    posterPath: json['i'] as String?,
    serverId: json['sv'] as String?,
    seasonNumber: (json['sn'] as num?)?.toInt(),
    episodeNumber: (json['en'] as num?)?.toInt(),
    deviceName: json['d'] as String?,
  );
}
