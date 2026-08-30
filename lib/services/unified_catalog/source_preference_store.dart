/// Remembers which source a user last chose for a logical title (hoofdstuk
/// 14.8 of docs/tvos-unified-experience.md).
///
/// **This only ever sets initial focus.** Hoofdstuk 14.8 is explicit that a
/// title with more than one usable source still opens the picker; a remembered
/// choice never selects a source on the user's behalf. That rule lives in
/// `UnifiedActivationCoordinator`, which is the only thing that reads this
/// store — nothing here can auto-route, because nothing here decides anything.
///
/// No new storage family: this is `TrackPreferenceStore`'s exact shape — a
/// `SettingsService` `JsonPref` map, keyed by `{profileScope}|{key}` off
/// `StorageService.activeUserScope()`, capped by recency, and serialised
/// through one write lock. The reasons are the same ones written up there:
/// the shared state is the whole map rather than one entry, so two writes in
/// flight would otherwise each read a snapshot from before the other queued.
library;

import 'dart:async';

import '../../media/unified/canonical_media_identity.dart';
import '../../media/unified/remembered_source_choice.dart';
import '../../utils/app_logger.dart';
import '../settings_service.dart';
import '../storage_service.dart';

class SourcePreferenceStore {
  SourcePreferenceStore._();

  static Future<void> _writeLock = Future<void>.value();

  /// `whenComplete`, not `then`: a failing write must still release the queue.
  static Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Beyond this many titles the least recently chosen entries are dropped.
  /// Matches [TrackPreferenceStore]'s cap for the same reason: the whole map
  /// is one iCloud KVS value under a 100 KB ceiling, and an entry costs well
  /// under 100 bytes.
  static const int maxEntries = 500;

  /// The stable half of the storage key, or null when this title has no
  /// canonical identity to hang a preference on.
  ///
  /// [CanonicalMediaIdentity.bucketKey] rather than `UnifiedMediaGroup.groupId`
  /// deliberately: hoofdstuk 11.9 scopes `groupId` to the provider session, so
  /// storing under it would write an entry that can never be read back.
  /// A null bucket key (no title, or an episode missing its indices) means
  /// there is no cross-session identity, and the honest answer is to remember
  /// nothing rather than invent a key that collides with the next such title.
  static String? preferenceKeyFor(CanonicalMediaIdentity identity) => identity.bucketKey;

  /// `{profileScope}|{bucketKey}`. An empty scope (no active profile) is a
  /// namespace of its own, so a signed-out session never reads or writes a
  /// signed-in profile's entry.
  static Future<String?> _storageKey(CanonicalMediaIdentity identity) async {
    final key = preferenceKeyFor(identity);
    if (key == null) return null;
    final storage = await StorageService.getInstance();
    return '${storage.activeUserScope() ?? ''}|$key';
  }

  /// The remembered `sourceKey` for [identity], or null when there is none.
  ///
  /// A caller must still check that the returned key names a source that
  /// currently exists and is online — hoofdstuk 14.8 falls back to the best
  /// online source when it does not. This store never validates on the
  /// caller's behalf, because it has no view of live sources.
  static Future<String?> read(CanonicalMediaIdentity identity) async {
    try {
      final key = await _storageKey(identity);
      if (key == null) return null;
      final settings = await SettingsService.getInstance();
      final choice = settings.read(SettingsService.unifiedSourcePreferences)[key];
      if (choice == null || choice.isEmpty) return null;
      return choice.sourceKey;
    } catch (e) {
      appLogger.w('Failed to read remembered source choice', error: e);
      return null;
    }
  }

  /// Records that the user picked [sourceKey] for [identity].
  ///
  /// A no-op for an identity with no [preferenceKeyFor] — see there.
  static Future<void> remember(CanonicalMediaIdentity identity, String sourceKey) {
    return _locked(() async {
      try {
        if (sourceKey.isEmpty) return;
        final key = await _storageKey(identity);
        if (key == null) return;
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.unifiedSourcePreferences);
        final next = Map<String, RememberedSourceChoice>.from(stored);
        next[key] = RememberedSourceChoice(sourceKey: sourceKey, updatedAt: DateTime.now().millisecondsSinceEpoch);
        await settings.write(SettingsService.unifiedSourcePreferences, capped(next));
      } catch (e) {
        appLogger.w('Failed to remember source choice', error: e);
      }
    });
  }

  /// Drops every entry belonging to [profileScope]. Called when a profile is
  /// deleted (hoofdstuk 14.8: "Profiel verwijderen wist de voorkeuren").
  ///
  /// Scoping lives in the key, so this is a prefix sweep. Leaving the entries
  /// to age out of the LRU instead would keep a deleted profile's viewing
  /// history on disk for as long as the map has room — which is exactly what
  /// 14.8 forbids, and a privacy question rather than a housekeeping one
  /// (hoofdstuk 22).
  static Future<void> clearForProfileScope(String profileScope) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.unifiedSourcePreferences);
        final next = Map<String, RememberedSourceChoice>.from(stored)
          ..removeWhere((key, _) => keyBelongsToScope(key, profileScope));
        if (next.length == stored.length) return;
        await settings.write(SettingsService.unifiedSourcePreferences, next);
      } catch (e) {
        appLogger.w('Failed to clear source choices for deleted profile', error: e);
      }
    });
  }

  /// Whether a storage key belongs to [profileScope]. Split out so the prefix
  /// rule is testable without shared preferences: the separator is `|`, and
  /// only the part before the *first* one is the scope — a bucket key can
  /// itself contain `:` and, for a title with a pipe in it, `|`.
  static bool keyBelongsToScope(String storageKey, String profileScope) {
    final separator = storageKey.indexOf('|');
    if (separator < 0) return false;
    return storageKey.substring(0, separator) == profileScope;
  }

  /// Drops the least recently chosen entries once the map exceeds
  /// [maxEntries]. Visible for testing; callers go through [remember].
  static Map<String, RememberedSourceChoice> capped(Map<String, RememberedSourceChoice> entries) {
    if (entries.length <= maxEntries) return entries;
    final byAge = entries.entries.toList()..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    return Map.fromEntries(byAge.take(maxEntries));
  }
}
