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

  const TrackLanguageChoice({
    this.audioLanguage,
    this.audioTitle,
    this.subtitleLanguage,
    this.subtitleTitle,
    this.subtitleForced = false,
    this.subtitlesOff = false,
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

  TrackLanguageChoice copyWithAudio({String? language, String? title, required int updatedAt}) => TrackLanguageChoice(
    audioLanguage: language,
    audioTitle: title,
    subtitleLanguage: subtitleLanguage,
    subtitleTitle: subtitleTitle,
    subtitleForced: subtitleForced,
    subtitlesOff: subtitlesOff,
    updatedAt: updatedAt,
  );

  TrackLanguageChoice copyWithSubtitle({
    String? language,
    String? title,
    bool forced = false,
    bool off = false,
    required int updatedAt,
  }) => TrackLanguageChoice(
    audioLanguage: audioLanguage,
    audioTitle: audioTitle,
    subtitleLanguage: off ? null : language,
    subtitleTitle: off ? null : title,
    subtitleForced: !off && forced,
    subtitlesOff: off,
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
    'u': updatedAt,
  };

  static TrackLanguageChoice fromJson(Map<String, dynamic> json) => TrackLanguageChoice(
    audioLanguage: json['a'] as String?,
    audioTitle: json['at'] as String?,
    subtitleLanguage: json['s'] as String?,
    subtitleTitle: json['st'] as String?,
    subtitleForced: json['sf'] == true,
    subtitlesOff: json['so'] == true,
    updatedAt: (json['u'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() =>
      'TrackLanguageChoice(audio: $audioLanguage, subtitle: ${subtitlesOff ? 'off' : subtitleLanguage})';
}
