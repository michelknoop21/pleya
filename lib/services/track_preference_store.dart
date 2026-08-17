import '../media/media_item.dart';
import '../media/track_language_choice.dart';
import '../utils/app_logger.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Remembers the audio/subtitle language a user picked by hand, per series or
/// movie, so the next episode does not fall back to the server default.
///
/// Sits on [SettingsService.trackLanguagePreferences], which rides the existing
/// allow-by-default iCloud key-value sync: nothing extra is needed for the
/// choice to reach the user's other Apple devices.
class TrackPreferenceStore {
  TrackPreferenceStore._();

  /// Beyond this many titles the oldest entries are dropped. The whole map is
  /// one iCloud KVS value with a 100 KB ceiling; an entry costs well under
  /// 100 bytes, so this leaves ample headroom.
  static const int maxEntries = 500;

  /// Series are keyed by their show so every episode resolves to one entry;
  /// movies key on themselves. Matches [SettingsService.mediaVersionPreferences].
  static String seriesKeyFor(MediaItem metadata) => metadata.grandparentId ?? metadata.id;

  /// `{profileScope}|{seriesKey}`. An empty scope (no active profile) is a
  /// valid namespace of its own, so signed-out playback never reads or writes
  /// a signed-in profile's entry.
  static Future<String> _storageKey(MediaItem metadata) async {
    final storage = await StorageService.getInstance();
    return '${storage.activeUserScope() ?? ''}|${seriesKeyFor(metadata)}';
  }

  static Future<TrackLanguageChoice?> read(MediaItem metadata) async {
    try {
      final settings = await SettingsService.getInstance();
      return settings.read(SettingsService.trackLanguagePreferences)[await _storageKey(metadata)];
    } catch (e) {
      appLogger.w('Failed to read remembered track languages', error: e);
      return null;
    }
  }

  static Future<void> saveAudio(MediaItem metadata, {String? language, String? title}) =>
      _update(metadata, (current, now) => current.copyWithAudio(language: language, title: title, updatedAt: now));

  static Future<void> saveSubtitle(
    MediaItem metadata, {
    String? language,
    String? title,
    bool forced = false,
    bool off = false,
  }) => _update(
    metadata,
    (current, now) =>
        current.copyWithSubtitle(language: language, title: title, forced: forced, off: off, updatedAt: now),
  );

  static Future<void> _update(
    MediaItem metadata,
    TrackLanguageChoice Function(TrackLanguageChoice current, int now) apply,
  ) async {
    try {
      final settings = await SettingsService.getInstance();
      final key = await _storageKey(metadata);
      final stored = settings.read(SettingsService.trackLanguagePreferences);
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = apply(stored[key] ?? TrackLanguageChoice(updatedAt: now), now);

      final next = Map<String, TrackLanguageChoice>.from(stored);
      if (updated.isEmpty) {
        next.remove(key);
      } else {
        next[key] = updated;
      }
      await settings.write(SettingsService.trackLanguagePreferences, _capped(next));
    } catch (e) {
      appLogger.w('Failed to remember track languages', error: e);
    }
  }

  /// Drops the least recently written entries once the map exceeds [maxEntries].
  static Map<String, TrackLanguageChoice> _capped(Map<String, TrackLanguageChoice> entries) {
    if (entries.length <= maxEntries) return entries;
    final byAge = entries.entries.toList()..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    return Map.fromEntries(byAge.take(maxEntries));
  }
}
