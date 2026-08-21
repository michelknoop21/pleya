import 'language_codes.dart';
import 'track_label_builder.dart';

/// Values that name a language without naming one. Kept apart from a genuine
/// code so an untagged track neither proves nor disproves a match.
const _emptyLanguageVocabulary = {
  'unknown',
  'onbekend',
  'und',
  'undetermined',
  'undefined',
  'no title',
  'mis',
  'mul',
  'zxx',
};

Map<String, String>? _englishNameIndex;

/// Lazily built index of English language names to ISO 639-1 codes, so a
/// server that reports `language: "Dutch"` and no code is still comparable
/// with an mpv track tagged `nld`. Names with comma-separated aliases
/// ("Bengali, Bangla") contribute every alias.
Map<String, String> _nameIndex() {
  final existing = _englishNameIndex;
  if (existing != null) return existing;
  final index = <String, String>{};
  for (final entry in LanguageCodes.getAllLanguages()) {
    for (final alias in entry.name.split(',')) {
      final key = alias.trim().toLowerCase();
      if (key.isNotEmpty) index.putIfAbsent(key, () => entry.code);
    }
  }
  return _englishNameIndex = index;
}

/// Reduces any way a backend or container names a language to one ISO 639-1
/// code, or null when it names none.
///
/// Accepts 639-1, both 639-2 revisions and an English display name, so the
/// three vocabularies in play (mpv container tags, Plex display names,
/// Jellyfin codes) become directly comparable. Returns null rather than a
/// guess: an unrecognised value is not evidence of anything.
String? normalizeLanguageCode(String? raw) {
  final cleaned = cleanTrackMetadataValue(raw)?.trim().toLowerCase();
  if (cleaned == null || cleaned.isEmpty) return null;
  if (_emptyLanguageVocabulary.contains(cleaned)) return null;

  final base = cleaned.split(RegExp('[-_]')).first;
  if (base.isEmpty || _emptyLanguageVocabulary.contains(base)) return null;

  final code = LanguageCodes.getIso6391Code(base);
  if (code != null) return code;

  return _nameIndex()[cleaned];
}

const _subtitleCodecCanonical = <String, String>{
  'subrip': 'srt',
  'srt': 'srt',
  'ass': 'ass',
  'ssa': 'ass',
  'pgs': 'pgs',
  'pgssub': 'pgs',
  'hdmv_pgs_subtitle': 'pgs',
  'vobsub': 'vobsub',
  'dvdsub': 'vobsub',
  'dvd_subtitle': 'vobsub',
  'webvtt': 'vtt',
  'vtt': 'vtt',
  'mov_text': 'tx3g',
  'tx3g': 'tx3g',
  'dvb_sub': 'dvbsub',
  'dvb_subtitle': 'dvbsub',
  'dvbsub': 'dvbsub',
};

/// Canonical name for a subtitle codec, so `subrip` and `srt` compare equal.
/// Unknown codecs pass through lowercased rather than being dropped.
String? normalizeSubtitleCodec(String? raw) {
  final cleaned = raw?.trim().toLowerCase();
  if (cleaned == null || cleaned.isEmpty) return null;
  return _subtitleCodecCanonical[cleaned] ?? cleaned;
}

/// Comparable form of a track title: codec suffix stripped, placeholders
/// dropped, punctuation flattened, and any token that merely restates the
/// language or the forced flag removed. Null when nothing meaningful is left.
String? normalizeTrackTitle(String? raw, {String? codec, String? languageCode}) {
  final cleaned = cleanSubtitleTitle(raw, codec: codec);
  if (cleaned == null) return null;

  var value = cleaned.trim().toLowerCase();
  if (_emptyLanguageVocabulary.contains(value)) return null;

  value = value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  if (value.isEmpty) return null;

  final languageName = languageCode == null ? null : LanguageCodes.getLanguageName(languageCode)?.toLowerCase();
  final drop = <String>{
    'forced',
    if (languageCode != null) languageCode,
    if (languageName != null) ...languageName.split(RegExp(r'[^a-z0-9]+')),
  };
  final tokens = value.split(' ').where((token) => token.isNotEmpty && !drop.contains(token)).toList();
  if (tokens.isEmpty) return null;
  return tokens.join(' ');
}
