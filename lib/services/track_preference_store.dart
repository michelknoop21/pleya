import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/track_language_choice.dart';
import '../media/unified/identity_evidence.dart';
import '../utils/app_logger.dart';
import 'pleya_share/pleya_share_device_name.dart';
import 'pleya_profile_language_preference_store.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Remembers the audio/subtitle language a user picked by hand, per series or
/// movie, so the next episode does not fall back to the server default.
///
/// Sits on [SettingsService.trackLanguagePreferences], which rides the existing
/// allow-by-default iCloud key-value sync: nothing extra is needed for the
/// choice to reach the user's other Apple devices.
///
/// Serialises every write through a Completer chain. The stored value is one
/// map holding every title, and the audio and the subtitle write for the same
/// episode are fired in one breath without awaiting (`TrackSelectionService`),
/// so two updates are routinely in flight at once. They survive that today
/// only because `SharedPreferencesWithCache.setString` fills its in-memory
/// cache synchronously, which leaves no suspension point between the read and
/// the write. That is an implementation detail of a package, not a contract:
/// the moment it awaits before caching, or an encode step turns async, the
/// second writer reads a stale snapshot and drops the first one's entry. The
/// lock makes the invariant belong to the store that owns the map.
class TrackPreferenceStore {
  TrackPreferenceStore._();

  /// One global lock: the shared state is the whole map, not a single entry,
  /// and [_capped] has to reason about an up-to-date map as well.
  static Future<void> _writeLock = Future<void>.value();

  /// `whenComplete`, not `then`: a failing action must still release the queue,
  /// otherwise one bad write stalls every later one forever.
  static Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Drop the queue and the cached device name.
  ///
  /// The lock is a static chain, and a future created inside a widget test's
  /// zone never completes once that test is torn down — every later write then
  /// waits on a link that will never arrive. One test's leftovers are not the
  /// next test's problem, so the chain is resettable.
  @visibleForTesting
  static void resetForTesting() {
    _writeLock = Future<void>.value();
    _deviceName = null;
  }

  /// Beyond this many titles the oldest entries are dropped. The whole map is
  /// one iCloud KVS value with a 100 KB ceiling.
  ///
  /// Was 500 while an entry held languages alone at well under 100 bytes. The
  /// provenance the management page shows — series title, poster path, server,
  /// episode, device — roughly triples that, so the cap comes down to keep the
  /// same headroom under the same ceiling. Nobody accumulates 250 series
  /// preferences; the cap exists so that a decade of watching cannot silently
  /// grow past a limit the sync layer enforces by refusing the whole value.
  static const int maxEntries = 250;

  /// The *logical* series key, when this item carries evidence strong enough to
  /// name its show across sources — today the show's stable catalogue GUID
  /// (DEC-096 lid 7).
  ///
  /// Null is the normal answer for most items, and the caller then uses
  /// [serverSeriesKeyFor]. Deliberately no title-and-year merge: a wrong merge
  /// is worse than a missed one, and two series sharing a name would otherwise
  /// share a language. Deliberately not the episode's own `guid` either — per
  /// `identity_evidence.dart` an episode GUID is evidence about the episode and
  /// never about its show.
  ///
  /// Per backend, today: Plex reports `grandparentGuid` on an episode row and
  /// gets a logical key. Jellyfin answers an episode with `SeriesId`, which is
  /// server-local, so it does not. Pleya Server's `/v1` `Item` schema carries
  /// no identity token at all, so it does not either — that is a protocol gap
  /// to close deliberately in a phase that may change the contract, not
  /// something to paper over here.
  static String? logicalSeriesKeyFor(MediaItem metadata) {
    if (metadata.kind != MediaKind.episode && metadata.kind != MediaKind.season) return null;
    final guid = normalizeStableGuid(metadata.grandparentGuid);
    if (guid == null) return null;
    return 'show:$identityTokenNamespaceGuid:$guid';
  }

  /// The per-source key: the show's id on this server, or a movie's own id.
  /// Matches [SettingsService.mediaVersionPreferences], and stays the fallback
  /// and migration path for everything without a logical identity.
  static String serverSeriesKeyFor(MediaItem metadata) => metadata.grandparentId ?? metadata.id;

  /// The key an entry is *written* under: logical where there is one, per
  /// source otherwise.
  static String seriesKeyFor(MediaItem metadata) => logicalSeriesKeyFor(metadata) ?? serverSeriesKeyFor(metadata);

  /// Every key this item may be found under, best first. Read walks the list so
  /// an entry written before LANG1 — under the server key — keeps applying
  /// until a write promotes it.
  static List<String> _candidateKeys(MediaItem metadata) {
    final logical = logicalSeriesKeyFor(metadata);
    final server = serverSeriesKeyFor(metadata);
    return logical == null ? [server] : [logical, server];
  }

  /// How a write learns the name of the device it is running on.
  ///
  /// A seam, not a setting: the real implementation asks the platform once and
  /// a test replaces it, so a stored provenance line is deterministic instead
  /// of being whatever the build machine is called.
  @visibleForTesting
  static Future<String> Function() deviceNameProvider = pleyaShareDeviceName;

  /// Resolved once per process. The name does not change while the app runs,
  /// and a platform channel round trip per track change would sit in the path
  /// of every episode start.
  static Future<String>? _deviceName;

  /// What the management page of mockup 31 A needs to describe this entry.
  ///
  /// Reads the *show's* fields where there are any: the entry is the series'
  /// preference, so its poster and title are the show's, while the season and
  /// episode number describe the moment. A movie has no grandparent and falls
  /// back to its own title and poster, which is exactly what its row shows.
  static Future<TrackChoiceProvenance> _provenanceFor(MediaItem metadata) async {
    String? deviceName;
    try {
      deviceName = await (_deviceName ??= deviceNameProvider());
    } catch (e) {
      // A device without a name is a missing line on one row, never a reason
      // to lose the choice the viewer just made.
      _deviceName = null;
      appLogger.d('Failed to resolve the device name for a track preference', error: e);
    }
    final isEpisode = metadata.kind == MediaKind.episode;
    return TrackChoiceProvenance(
      title: metadata.grandparentTitle ?? metadata.title,
      posterPath: metadata.grandparentThumbPath ?? metadata.thumbPath,
      serverId: metadata.serverId,
      seasonNumber: isEpisode ? metadata.parentIndex : null,
      episodeNumber: isEpisode ? metadata.index : null,
      deviceName: deviceName,
    );
  }

  /// The profile half of every storage key: `{profileScope}|{seriesKey}`. An
  /// empty scope (no active profile) is a valid namespace of its own, so
  /// signed-out playback never reads or writes a signed-in profile's entry.
  static Future<String> _scope() async {
    final storage = await StorageService.getInstance();
    return storage.activeUserScope() ?? '';
  }

  static Future<TrackLanguageChoice?> read(MediaItem metadata) async {
    try {
      final settings = await SettingsService.getInstance();
      final stored = settings.read(SettingsService.trackLanguagePreferences);
      final scope = await _scope();
      for (final key in _candidateKeys(metadata)) {
        final choice = stored['$scope|$key'];
        if (choice != null && !choice.isEmpty) return choice;
      }
      return null;
    } catch (e) {
      appLogger.w('Failed to read remembered track languages', error: e);
      return null;
    }
  }

  static Future<void> saveAudio(MediaItem metadata, {String? language, String? title}) => _update(
    metadata,
    (current, now, provenance) =>
        current.copyWithAudio(language: language, title: title, provenance: provenance, updatedAt: now),
  );

  static Future<void> saveSubtitle(
    MediaItem metadata, {
    String? language,
    String? title,
    bool forced = false,
    bool off = false,
  }) => _update(
    metadata,
    (current, now, provenance) => current.copyWithSubtitle(
      language: language,
      title: title,
      forced: forced,
      off: off,
      provenance: provenance,
      updatedAt: now,
    ),
  );

  /// Drop this title's series preference entirely — the "Gebruik globale
  /// voorkeur" action of mockup 31 B.
  ///
  /// Removes the entry under *every* key this item resolves to, the legacy
  /// server key included: leaving one behind would let it be read back the
  /// moment the logical key is gone, and an emptied-but-present entry would
  /// block the global layer just as effectively as a full one.
  ///
  /// Not gated on [SettingsService.rememberTrackSelections]. Turning the
  /// switch off stops new overrides from appearing; it must never stop the
  /// viewer from removing one that already exists.
  static Future<void> clear(MediaItem metadata) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final scope = await _scope();
        final stored = settings.read(SettingsService.trackLanguagePreferences);
        final next = Map<String, TrackLanguageChoice>.from(stored);
        var removed = false;
        for (final key in _candidateKeys(metadata)) {
          if (next.remove('$scope|$key') != null) removed = true;
        }
        if (!removed) return;
        await settings.write(SettingsService.trackLanguagePreferences, next);
      } catch (e) {
        appLogger.w('Failed to clear the remembered track languages', error: e);
      }
    });
  }

  /// Drop the entry stored under one exact key — what the management page of
  /// mockup 31 A acts on.
  ///
  /// The page lists keys, not items: an entry may belong to a series on a
  /// server this device no longer has, and rebuilding a [MediaItem] just to
  /// reach [clear] would make exactly those rows unremovable. Same rule as
  /// [clear] otherwise: not gated on the remember switch, because turning it
  /// off must never stop a viewer from removing an override that exists.
  static Future<void> clearKey(String seriesKey) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final scope = await _scope();
        final stored = settings.read(SettingsService.trackLanguagePreferences);
        if (!stored.containsKey('$scope|$seriesKey')) return;
        final next = Map<String, TrackLanguageChoice>.from(stored)..remove('$scope|$seriesKey');
        await settings.write(SettingsService.trackLanguagePreferences, next);
      } catch (e) {
        appLogger.w('Failed to clear a remembered track language', error: e);
      }
    });
  }

  /// Every series preference belonging to the active profile, newest first —
  /// what the Serievoorkeuren column of mockup 31 A lists.
  static Future<List<({String key, TrackLanguageChoice choice})>> readAllForActiveScope() async {
    try {
      final settings = await SettingsService.getInstance();
      final scope = await _scope();
      final prefix = '$scope|';
      final entries = <({String key, TrackLanguageChoice choice})>[
        for (final entry in settings.read(SettingsService.trackLanguagePreferences).entries)
          if (entry.key.startsWith(prefix) && !entry.value.isEmpty)
            (key: entry.key.substring(prefix.length), choice: entry.value),
      ];
      entries.sort((a, b) => b.choice.updatedAt.compareTo(a.choice.updatedAt));
      return entries;
    } catch (e) {
      appLogger.w('Failed to read the remembered track languages', error: e);
      return const [];
    }
  }

  /// The lock spans the whole transaction, the two leading awaits included:
  /// held any later, both writers would still park on [SettingsService] and
  /// [_storageKey] and then take turns writing a snapshot each had read before
  /// it ever queued.
  static Future<void> _update(
    MediaItem metadata,
    TrackLanguageChoice Function(TrackLanguageChoice current, int now, TrackChoiceProvenance provenance) apply,
  ) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        // The switch belongs to the store, not to its callers. It used to be
        // checked at each write site, which meant every new one had to
        // remember — and a path that forgot (the transcoding source switch did,
        // for months) wrote an override the viewer had asked not to have
        // (DEC-096 lid 3). Its owner is the profile, not a device-wide pref.
        if (!(await PleyaProfileLanguagePreferenceStore.read()).rememberPerSeries) return;

        final scope = await _scope();
        final key = '$scope|${seriesKeyFor(metadata)}';
        final stored = settings.read(SettingsService.trackLanguagePreferences);
        final now = DateTime.now().millisecondsSinceEpoch;

        // Lazy migration: a write is the moment an entry stored under the old
        // per-server key moves to the logical one. Reading it first means the
        // promotion carries the whole choice over, not just the field this
        // write touches, and the old key only goes once the new value is in
        // the same map that is about to be persisted — never a delete that
        // could outlive a failed write.
        final candidates = _candidateKeys(metadata);
        TrackLanguageChoice? current;
        for (final candidate in candidates) {
          current = stored['$scope|$candidate'];
          if (current != null && !current.isEmpty) break;
          current = null;
        }

        final updated = apply(current ?? TrackLanguageChoice(updatedAt: now), now, await _provenanceFor(metadata));

        final next = Map<String, TrackLanguageChoice>.from(stored);
        for (final candidate in candidates) {
          if ('$scope|$candidate' != key) next.remove('$scope|$candidate');
        }
        if (updated.isEmpty) {
          next.remove(key);
        } else {
          next[key] = updated;
        }
        await settings.write(SettingsService.trackLanguagePreferences, _capped(next));
      } catch (e) {
        appLogger.w('Failed to remember track languages', error: e);
      }
    });
  }

  /// Drops the least recently written entries once the map exceeds [maxEntries].
  static Map<String, TrackLanguageChoice> _capped(Map<String, TrackLanguageChoice> entries) {
    if (entries.length <= maxEntries) return entries;
    final byAge = entries.entries.toList()..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    return Map.fromEntries(byAge.take(maxEntries));
  }
}
