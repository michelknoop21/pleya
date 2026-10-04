part of 'assistant_provider.dart';

/// The keychain failed and this device has no local copy to fall back to.
/// Not "not configured": a synced config may exist that this read missed.
class AssistantProviderStoreException implements Exception {
  const AssistantProviderStoreException(this.cause);
  final Object cause;

  // Type only: the native message is an OSStatus, but keep it out of logs.
  @override
  String toString() => 'AssistantProviderStoreException(${cause.runtimeType})';
}

/// The keychain holds a config this version cannot read, most likely from a
/// newer Pleya on another device. A save replaces it only when asked to.
class AssistantProviderUnreadableException implements Exception {
  const AssistantProviderUnreadableException();

  @override
  String toString() => 'AssistantProviderUnreadableException()';
}

/// Provider settings for the user's Apple devices. On iOS and tvOS one item
/// in the iCloud keychain (`PleyaKeychain`); elsewhere, and as a fallback
/// when the keychain fails, one vault-protected prefs blob under a key that
/// `PreferenceSyncPolicy` marks secret: never synced, never exported.
class AssistantProviderStore {
  AssistantProviderStore({PleyaKeychain? keychain}) : _injectedKeychain = keychain;
  static final AssistantProviderStore instance = AssistantProviderStore();

  static const String key = 'assistant_provider';

  /// Bumped by every [save] and [clear], wherever the settings screen was
  /// opened from, so Big P's availability follows without a reopen.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  final PleyaKeychain? _injectedKeychain;

  /// Every load, save and clear runs after the one before, so a migration on
  /// the pending path can never interleave with a save.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  // Resolved per call: TV detection may finish after [instance] exists.
  PleyaKeychain? get _keychain => _injectedKeychain ?? (PleyaKeychain.supported ? const PleyaKeychain() : null);

  /// Set while the prefs blob holds a save the keychain refused. Its value is
  /// the fingerprint of the synced item that save replaced: the blob beats
  /// only that item, never a newer one another device saved since. When that
  /// read failed too, the last item this device saw ([seenKey]) stands in.
  /// `unknown` only when this device never read the keychain: the blob then
  /// goes up only into an empty keychain, a decodable item wins over it and
  /// an undecodable one is left alone. After a `|` follows the fingerprint of
  /// the blob the marker was written for: the two are separate prefs writes,
  /// and a marker left next to another blob gives that blob no right to go
  /// up or to stay. A marker without one (written before the blob was named)
  /// cannot show which blob it was for, so its blob never goes up either.
  /// Device-local.
  static const String pendingKey = 'assistant_provider_pending';

  /// Fingerprint of the keychain item as this device last read, wrote or
  /// migrated it. Not a secret; device-local, never synced.
  static const String seenKey = 'assistant_provider_seen';

  /// The keychain first, then the old prefs blob, which moves to the keychain
  /// and leaves the prefs only once a readback matches. A keychain error
  /// never deletes the blob; with no blob to fall back to it throws
  /// [AssistantProviderStoreException] rather than reading as unset.
  Future<AssistantProviderConfig?> load() => _serial(() async => current = await _load());

  /// The config of the last [load], [save] or [clear], for readers that
  /// cannot await (title facts read the TMDB key and the online switch per
  /// lookup). Big P loads the config at the start of every ask.
  static AssistantProviderConfig? current;

  Future<AssistantProviderConfig?> _load({bool again = false}) async {
    final keychain = _keychain;
    if (keychain == null) return (await _readLegacy())?.config;
    String? synced;
    Object? keychainError;
    try {
      synced = await keychain.read(key);
    } catch (e) {
      keychainError = e;
      appLogger.w('Assistant keychain read failed', error: e.runtimeType);
    }
    if (keychainError == null) await _remember(synced);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    var legacy = await _readLegacy();
    final marker = prefs.getString(pendingKey);
    if (legacy != null && marker != null) {
      final bar = marker.indexOf('|');
      final over = bar < 0 ? marker : marker.substring(0, bar);
      // A save cut off between its two prefs writes: the marker is the new
      // save's, the blob still the old one. That blob is no longer anyone's
      // config: it goes, whatever the keychain says.
      final stale = bar >= 0 && marker.substring(bar + 1) != _fingerprint(legacy.json);
      if (!stale) {
        // A save the keychain refused earlier. While the keychain still fails
        // it is all this device has.
        if (keychainError != null) return _blobOrSuperseded(legacy.config, again, keychainError);
        final current = over == _fingerprint(synced) || (over == _unknown && synced == null);
        // An item this version cannot read is never overwritten from here,
        // not even one this device has seen before: the blob stays this
        // device's config until a save with Vervangen.
        // ponytail: an old marker (no `|`) over a readable but undecodable item
        // keeps the blob and writes nothing. Dropping it would cost a device
        // with a real waiting save its config; the blob never goes up. The same
        // marker over an empty keychain drops the blob too (below): accepted,
        // an old-format marker proves nothing about which blob it was for.
        if ((current || over == _unknown) && synced != null && _decode(synced) == null) return legacy.config;
        // It goes up only over the item it was saved over (a hash marker), or
        // into an empty keychain. With an 'unknown' marker its read failed, so
        // any config in the keychain now may be newer: a decodable one wins.
        // A marker that names no blob gives no such right.
        if (current && bar >= 0) {
          if (await _migrate(keychain, legacy.json, synced)) return legacy.config;
          return _overtaken(again);
        }
      }
      // Another device saved or cleared since, the keychain holds a config
      // where the read had failed, or the blob is not the marker's: the
      // keychain's state wins.
      appLogger.d('Assistant pending config dropped: the keychain item changed since the save');
      await _removeLegacy();
      legacy = null;
    }
    final fromKeychain = synced == null ? null : _decode(synced);
    if (fromKeychain != null) {
      // ponytail: last writer wins, as iCloud itself does. Two Apple TVs with
      // different configs end up with one.
      await _removeLegacy();
      return fromKeychain;
    }
    if (legacy == null) {
      // An item that does not decode (a newer app version on another device)
      // is not "not configured" either.
      if (keychainError != null || synced != null) {
        throw AssistantProviderStoreException(keychainError ?? 'undecodable keychain item');
      }
      return null;
    }
    // That undecodable item is never overwritten by this device's older blob.
    if (keychainError == null && synced == null && !await _migrate(keychain, legacy.json, null)) {
      return _overtaken(again);
    }
    return _blobOrSuperseded(legacy.config, again, keychainError);
  }

  /// The blob as this device's config, unless this load is the retry of one
  /// that saw the item change: the blob then is superseded, and a read that
  /// fails now must not bring it back.
  AssistantProviderConfig _blobOrSuperseded(AssistantProviderConfig blob, bool superseded, Object? keychainError) {
    if (superseded && keychainError != null) throw AssistantProviderStoreException(keychainError);
    return blob;
  }

  /// The item changed between this load's read and its migration: the blob
  /// is superseded, so the load decides again from the new item. Once; a
  /// keychain that changes again is a read that missed, not "unset".
  Future<AssistantProviderConfig?> _overtaken(bool again) {
    if (again) throw const AssistantProviderStoreException('keychain item keeps changing');
    return _load(again: true);
  }

  /// The keychain when it takes the write; otherwise the prefs path keeps
  /// working on this device, marked pending with the synced item it was
  /// saved over. An item this version cannot read is replaced only with
  /// [replaceUnreadable]; without it [AssistantProviderUnreadableException].
  Future<void> save(AssistantProviderConfig config, {bool replaceUnreadable = false}) =>
      _serial(() => _save(config, replaceUnreadable));

  Future<void> _save(AssistantProviderConfig config, bool replaceUnreadable) async {
    _registerSecrets(config);
    final json = jsonEncode(config.toJson());
    var stored = false;
    String? current;
    var readFailed = false;
    final keychain = _keychain;
    if (keychain != null) {
      try {
        current = await keychain.read(key);
        await _remember(current);
      } catch (e) {
        readFailed = true;
        appLogger.w('Assistant keychain read failed', error: e.runtimeType);
      }
      if (current != null && !replaceUnreadable && _decode(current) == null) {
        throw const AssistantProviderUnreadableException();
      }
      // Unread, the item might be one this version cannot decode: no blind
      // overwrite, the prefs take it with an 'unknown' marker.
      if (!readFailed || replaceUnreadable) {
        try {
          stored = await keychain.write(key, json);
        } catch (e) {
          appLogger.w('Assistant keychain write failed', error: e.runtimeType);
        }
      }
    }
    if (stored) {
      await _remember(json);
      await _removeLegacy();
    } else {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final over = readFailed ? prefs.getString(seenKey) ?? _unknown : _fingerprint(current);
      // Marker first: a marker without a blob is harmless, the reverse is not.
      // Cut off before the blob, the marker names a blob that is not there.
      if (keychain != null) await prefs.setString(pendingKey, _marker(over, json));
      await prefs.setString(key, await CredentialVault.protect(json));
    }
    AssistantProviderStore.current = config;
    changes.value++;
  }

  /// Wipes both stores. A failed keychain delete throws: the synced config
  /// would otherwise come back on the next load. The keychain goes first, so
  /// a delete that throws does not cost a pending blob.
  Future<void> clear() => _serial(_clear);

  Future<void> _clear() async {
    try {
      final keychain = _keychain;
      if (keychain != null) {
        await keychain.delete(key);
        await _remember(null);
      }
      await _removeLegacy();
    } finally {
      current = null;
      changes.value++;
    }
  }

  /// Writes [json] over [expected] and drops the prefs blob after an equal
  /// readback. A readback that differs most likely is another device's sync
  /// landing in between: the blob stays, nothing is deleted, the next load
  /// decides. False when the item no longer is [expected] or the readback
  /// shows another item than [json] (overtaken: the caller decides again);
  /// a readback that fails stays true.
  ///
  /// ponytail: the keychain has no compare-and-swap. The read right before
  /// the write narrows the window for another device's sync to the two
  /// native calls; it does not close it.
  Future<bool> _migrate(PleyaKeychain keychain, String json, String? expected) async {
    try {
      if (await keychain.read(key) != expected) return false;
      if (!await keychain.write(key, json)) return true;
      // The blob is now a copy of the item it wrote. Should the readback
      // fail, it may go up again over that item only: not into a keychain
      // another device cleared since.
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString(pendingKey, _marker(_fingerprint(json), json));
      final back = await keychain.read(key);
      if (back == json) {
        await _remember(json);
        await _removeLegacy();
      } else if (back != null) {
        return false;
      }
    } catch (e) {
      appLogger.w('Assistant keychain migration failed', error: e.runtimeType);
    }
    return true;
  }

  static const String _unknown = 'unknown';

  /// [over] is the synced item the blob [json] may replace.
  static String _marker(String over, String json) => '$over|${_fingerprint(json)}';

  Future<void> _remember(String? synced) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(seenKey, _fingerprint(synced));
  }

  /// What the pending marker remembers of the synced item: its SHA-256, or
  /// `none` when there was none.
  static String _fingerprint(String? synced) =>
      synced == null ? 'none' : sha256.convert(utf8.encode(synced)).toString();

  Future<({String json, AssistantProviderConfig config})?> _readLegacy() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final json = await CredentialVault.reveal(raw);
      final config = _decode(json);
      return config == null ? null : (json: json, config: config);
    } catch (_) {
      // Unreadable is "not configured": the setup state offers a way back.
      return null;
    }
  }

  Future<void> _removeLegacy() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    if (prefs.getString(key) != null) await prefs.remove(key);
    if (prefs.getString(pendingKey) != null) await prefs.remove(pendingKey);
  }

  static AssistantProviderConfig? _decode(String json) {
    try {
      final config = AssistantProviderConfig.fromJson(jsonDecode(json) as Map<String, Object?>);
      if (config != null) _registerSecrets(config);
      return config;
    } catch (_) {
      return null;
    }
  }

  static void _registerSecrets(AssistantProviderConfig config) {
    LogRedactionManager.registerCustomValue(config.apiKey);
    LogRedactionManager.registerCustomValue(config.headerValue);
    LogRedactionManager.registerCustomValue(config.ollamaWebKey);
    LogRedactionManager.registerCustomValue(config.tmdbKey);
  }
}
