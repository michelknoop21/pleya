/// Reads and writes the Pleya profile's global audio/subtitle preference
/// (DEC-096 lid 5).
///
/// No new storage family: the exact shape of [TrackPreferenceStore] and
/// `SourcePreferenceStore` — a `SettingsService` `JsonPref` map keyed by
/// `{profileScope}` off `StorageService.activeUserScope()`, serialised through
/// one write lock. One entry per profile, so unlike those two there is no LRU
/// cap to keep: there is nothing to evict.
///
/// Backend-neutral by construction. The preference belongs to the Pleya
/// profile, so it holds for Plex, for Jellyfin, for Pleya Server and for
/// offline playback alike; nothing here looks at [MediaBackend]. Mirroring a
/// choice back onto a *server* profile is a separate, capability-gated concern
/// that lives with the backend that has the capability.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_server_user_profile.dart';
import '../media/pleya_profile_language_preferences.dart';
import '../utils/app_logger.dart';
import 'settings_service.dart';
import 'storage_service.dart';

class PleyaProfileLanguagePreferenceStore {
  PleyaProfileLanguagePreferenceStore._();

  static Future<void> _writeLock = Future<void>.value();

  /// `whenComplete`, not `then`: a failing write must still release the queue,
  /// or one bad write stalls every later one forever.
  static Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Drop the write queue — see `TrackPreferenceStore.resetForTesting`, which
  /// documents why a static lock chain has to be resettable between tests.
  @visibleForTesting
  static void resetForTesting() => _writeLock = Future<void>.value();

  /// `{profileScope}`. An empty scope (no active profile) is a valid namespace
  /// of its own, so signed-out playback never reads or writes a signed-in
  /// profile's preference.
  static Future<String> _storageKey() async {
    final storage = await StorageService.getInstance();
    return storage.activeUserScope() ?? '';
  }

  /// The profile namespace the page and the switch rows read their entry from.
  ///
  /// Public because the settings surfaces need the same key this store writes
  /// under, and a second expression of "which profile am I" is how two of them
  /// end up disagreeing.
  static Future<String> activeScope() => _storageKey();

  /// The active profile's preference, or an all-default one when it has none.
  ///
  /// Never null: "no opinion" is a legitimate state that the resolver handles
  /// by falling through to the source, and a null here would only push that
  /// same branch onto every caller.
  static Future<PleyaProfileLanguagePreferences> read() async {
    try {
      final settings = await SettingsService.getInstance();
      final stored = settings.read(SettingsService.pleyaProfileLanguagePreferences);
      return stored[await _storageKey()] ?? const PleyaProfileLanguagePreferences();
    } catch (e) {
      appLogger.w('Failed to read the profile language preference', error: e);
      return const PleyaProfileLanguagePreferences();
    }
  }

  /// Replace the active profile's preference.
  static Future<void> write(PleyaProfileLanguagePreferences preferences) => update((_) => preferences);

  /// Apply [apply] to the active profile's preference under the write lock.
  ///
  /// The lock spans the whole transaction, the leading awaits included: held
  /// any later, two writers would both park on [SettingsService] and
  /// [_storageKey] and then take turns writing a snapshot each had read before
  /// it ever queued. Same invariant [TrackPreferenceStore] documents.
  static Future<void> update(PleyaProfileLanguagePreferences Function(PleyaProfileLanguagePreferences current) apply) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final key = await _storageKey();
        final stored = settings.read(SettingsService.pleyaProfileLanguagePreferences);
        final current = stored[key] ?? const PleyaProfileLanguagePreferences();
        final updated = apply(current).copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);

        final next = Map<String, PleyaProfileLanguagePreferences>.from(stored)..[key] = updated;
        await settings.write(SettingsService.pleyaProfileLanguagePreferences, next);
      } catch (e) {
        appLogger.w('Failed to write the profile language preference', error: e);
      }
    });
  }

  /// Bring this profile's preference up to date once: move the two legacy
  /// device switches onto it, then seed the language rows from a server profile
  /// if one happens to be available.
  ///
  /// Backend-neutral entry point, and that matters. The seed alone would never
  /// run for a Pleya Server setup — the `/v1` contract has no user-profile
  /// resource to seed *from* — so a profile that never touches Plex or Jellyfin
  /// would keep the app defaults instead of the switches the viewer had already
  /// set. Callers pass whatever server profile they have, including null.
  ///
  /// Idempotent and cheap after the first run: everything below is guarded on
  /// [PleyaProfileLanguagePreferences.seeded], so a repeat is one in-memory
  /// read.
  static Future<void> ensureInitialised(MediaServerUserProfile? profile) async {
    await migrateLegacySwitches();
    await seedFromServerProfile(profile);
  }

  /// Derive an initial preference from a server profile, once.
  ///
  /// DEC-096 lid 3 allows the fallback language to be seeded from the ranked
  /// list a server profile already carries. Seeding is not ownership: it runs
  /// only while the profile has no preference of its own ([isUnset]) and only
  /// once ([PleyaProfileLanguagePreferences.seeded]), so a second server
  /// signing in later can never overwrite what the viewer set, and no
  /// "first server wins" race decides anything after that first run.
  ///
  /// A server profile with nothing to offer still marks the seed as done: the
  /// question "has this profile been seeded" is about the moment, not about
  /// whether that moment produced a value.
  static Future<void> seedFromServerProfile(MediaServerUserProfile? profile) {
    return update((current) {
      if (current.seeded) return current;
      // No server profile to seed from — a Pleya-Server-only setup, or an
      // offline start. Still mark the profile as initialised: the question is
      // "has this profile been through its one-time setup", not "did that setup
      // find something", and leaving it open would let a Plex account signing
      // in months later overwrite rows the viewer had edited by hand.
      if (profile == null || !current.isUnset) return current.copyWith(seeded: true);

      final audio = _firstNonEmpty([profile.defaultAudioLanguage, ...?profile.defaultAudioLanguages]);
      final subtitles = _firstNonEmpty([profile.defaultSubtitleLanguage, ...?profile.defaultSubtitleLanguages]);
      // The *second* entry in the ranked list is what the server profile
      // already means by "and otherwise this one", which is exactly the
      // fallback language. Absent a second entry there is nothing to seed and
      // the row simply starts empty.
      final fallback = _firstNonEmpty(
        [...?profile.defaultSubtitleLanguages].where((language) => language != subtitles).toList(),
      );

      return current.copyWith(
        audioLanguage: audio,
        subtitleLanguage: subtitles,
        subtitleFallbackLanguage: fallback,
        subtitlePolicy: _policyFrom(profile.subtitleMode),
        seeded: true,
      );
    });
  }

  /// Move the two device-wide switches that used to live under Instellingen ▸
  /// Afspelen onto the profile, once.
  ///
  /// [SettingsService.rememberTrackSelections] and
  /// [SettingsService.writeSeriesLanguageToServer] were single booleans for the
  /// whole device. DEC-096 lid 5 makes them fields of the profile preference,
  /// and lid 9 makes this page their only owner, so the old prefs become the
  /// migration source and nothing else.
  ///
  /// Runs at most once per profile, keyed on the same [seeded] flag as the
  /// server-profile seed: both answer "has this profile been initialised", and
  /// splitting them would let a re-run undo a deliberate change.
  static Future<void> migrateLegacySwitches() {
    return update((current) {
      if (current.seeded) return current;
      final settings = SettingsService.instance;
      return current.copyWith(
        rememberPerSeries: settings.read(SettingsService.rememberTrackSelections),
        mirrorToPlex: settings.read(SettingsService.writeSeriesLanguageToServer),
      );
    });
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return null;
  }

  /// Map a backend's subtitle mode onto Pleya's own policy where the two mean
  /// the same thing. `defaultMode` and `smart` say "let the source decide",
  /// which is the absence of a Pleya policy rather than one of its values.
  static SubtitleDisplayPolicy? _policyFrom(SubtitlePlaybackMode? mode) => switch (mode) {
    SubtitlePlaybackMode.none => SubtitleDisplayPolicy.never,
    SubtitlePlaybackMode.always => SubtitleDisplayPolicy.always,
    SubtitlePlaybackMode.onlyForced => SubtitleDisplayPolicy.foreignAudioOnly,
    SubtitlePlaybackMode.smart || SubtitlePlaybackMode.defaultMode || null => null,
  };
}
