import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/track_language_choice.dart';
import '../media/unified/identity_evidence.dart';
import '../utils/app_logger.dart';
import 'pleya_share/pleya_share_device_name.dart';
import 'preferences/preference_merge_strategies.dart';
import 'preferences/preference_sync_policy.dart';
import 'preferences/preference_sync_scope.dart';
import 'pleya_profile_language_preference_store.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Remembers the audio/subtitle language a user picked by hand, per series or
/// movie, so the next episode does not fall back to the server default.
///
/// Sits on [SettingsService.trackLanguagePreferences], a global map registered
/// with the `profileKeyedMap` merge family (DEC-131): the Plex Home profile's
/// entries reach the user's other Apple devices, a local profile's stay here.
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

  /// Beyond this many titles the oldest entries are dropped, and at most this
  /// many tombstones are kept. The whole map is one iCloud KVS value with a
  /// 100 KB ceiling, which the sync layer enforces by refusing the whole value.
  ///
  /// Was 500 while an entry held languages alone, then 250 once the provenance
  /// the management page shows arrived. Measured on the wire with long titles
  /// (kvs_footprint_test), a live entry costs up to about 490 bytes and a
  /// tombstone about 120, so 250 live entries alone already passed the
  /// ceiling, and tombstones had no bound but their lifetime. 100 of each is
  /// about 61 KB, which leaves room for titles in scripts that take three
  /// bytes a character.
  static const int maxEntries = 100;

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
        final now = DateTime.now().millisecondsSinceEpoch;
        var removed = false;
        for (final key in _candidateKeys(metadata)) {
          if (next['$scope|$key']?.isEmpty == false) removed = true;
          _remove(next, '$scope|$key', now);
        }
        if (!removed) return;
        await settings.write(SettingsService.trackLanguagePreferences, _capped(next));
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
        if (stored['$scope|$seriesKey']?.isEmpty != false) return;
        final next = Map<String, TrackLanguageChoice>.from(stored);
        _remove(next, '$scope|$seriesKey', DateTime.now().millisecondsSinceEpoch);
        await settings.write(SettingsService.trackLanguagePreferences, _capped(next));
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
          if ('$scope|$candidate' != key) {
            _remove(next, '$scope|$candidate', now);
          }
        }
        if (updated.isEmpty) {
          _remove(next, key, now);
        } else {
          next[key] = updated;
        }
        await settings.write(SettingsService.trackLanguagePreferences, _capped(next));
      } catch (e) {
        appLogger.w('Failed to remember track languages', error: e);
      }
    });
  }

  /// Remove the entry under [key]. For a scope that syncs, the removal has to
  /// reach the other devices, so it becomes a tombstone: an empty choice
  /// stamped [now], which every reader here already skips and the
  /// `profileKeyedMap` merge settles by timestamp like any other entry
  /// (DEC-131). A scope that never leaves this device just loses the key.
  ///
  /// Only a live entry is removed: a key that never held one, or already holds
  /// a tombstone, is left alone, so a removal is stamped once and ages out.
  static void _remove(Map<String, TrackLanguageChoice> entries, String key, int now) {
    if (entries[key]?.isEmpty != false) return;
    if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(key))) {
      entries[key] = TrackLanguageChoice(updatedAt: now);
    } else {
      entries.remove(key);
    }
  }

  /// Keeps the [maxEntries] most recently written live entries and as many of
  /// the newest tombstones, and drops tombstones older than
  /// `profileKeyedMapTombstoneLifetime`.
  ///
  /// Tombstones have a budget of their own, so a burst of removals cannot push
  /// out the choices still in use. An evicted entry of a scope that syncs
  /// becomes a tombstone rather than vanishing: the merge is a union, so a key
  /// that simply disappeared here would come back from the store, and the map
  /// would grow to every device's history past the 100 KB ceiling. The
  /// tombstone is stamped one past the evicted entry, not now, so an edit
  /// another device made since still wins.
  static Map<String, TrackLanguageChoice> _capped(Map<String, TrackLanguageChoice> entries) {
    final expiredBefore = DateTime.now().millisecondsSinceEpoch - profileKeyedMapTombstoneLifetime.inMilliseconds;
    final live = entries.entries.where((e) => !e.value.isEmpty).toList()..sort(_newestFirst);
    // ponytail: a tombstone past the budget goes before its lifetime is up, so a
    // device offline since that removal can bring the entry back, exactly as
    // after expiry. Budgeting bytes instead of entries would keep more of them.
    final tombstones = <String, TrackLanguageChoice>{
      for (final e in live.skip(maxEntries))
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)))
          e.key: TrackLanguageChoice(updatedAt: e.value.updatedAt + 1),
      for (final e in entries.entries)
        if (e.value.isEmpty && e.value.updatedAt >= expiredBefore) e.key: e.value,
    }.entries.toList()..sort(_newestFirst);
    return {
      for (final e in live.take(maxEntries)) e.key: e.value,
      for (final e in tombstones.take(maxEntries)) e.key: e.value,
    };
  }

  /// Newest first, ties by key, so every device keeps the same entries.
  static int _newestFirst(MapEntry<String, TrackLanguageChoice> a, MapEntry<String, TrackLanguageChoice> b) {
    final byTime = b.value.updatedAt.compareTo(a.value.updatedAt);
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  }

  /// The sync family for this map: `profileKeyedMap`, with [_capped] run over
  /// every inbound union.
  ///
  /// Each device caps its own writes, but the union of two capped maps holds
  /// up to twice the cap. A device that only receives would keep that union
  /// and push it back, over the store's ceiling, until its own next write. The
  /// cap stays out of the shared merge, which also serves the profile language
  /// map.
  static PreferenceMergeFamily mergeFamily() {
    final shared = buildProfileKeyedMapFamily();
    return PreferenceMergeFamily(
      name: PreferenceMergeFamilies.trackLanguageMap,
      inbound: (local, remote) => _cappedRaw(shared.inbound(local, remote)),
      outbound: shared.outbound,
      removed: shared.removed,
    );
  }

  /// [_capped] over a stored JSON value. A value this store cannot decode is
  /// passed through untouched: capping is housekeeping, not a reason to fail
  /// the apply.
  static Object? _cappedRaw(Object? raw) {
    if (raw is! String) return raw;
    final pref = SettingsService.trackLanguagePreferences;
    try {
      return pref.encode(_capped(pref.decode(json.decode(raw))));
    } catch (_) {
      return raw;
    }
  }
}
