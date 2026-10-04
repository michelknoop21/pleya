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
  /// the fingerprint of the synced item that save replaced (`unknown` when
  /// that read failed too): the blob beats only that item, never a newer one
  /// another device saved since. Device-local.
  static const String pendingKey = 'assistant_provider_pending';

  /// The keychain first, then the old prefs blob, which moves to the keychain
  /// and leaves the prefs only once a readback matches. A keychain error
  /// never deletes the blob; with no blob to fall back to it throws
  /// [AssistantProviderStoreException] rather than reading as unset.
  Future<AssistantProviderConfig?> load() => _serial(_load);

  Future<AssistantProviderConfig?> _load() async {
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
    final prefs = await BaseSharedPreferencesService.sharedCache();
    var legacy = await _readLegacy();
    final marker = prefs.getString(pendingKey);
    if (legacy != null && marker != null) {
      // A save the keychain refused earlier wins only while the synced item
      // is still the one it was saved over (or that could not be read then).
      if (keychainError != null || marker == _unknown || marker == _fingerprint(synced)) {
        // ponytail: an 'unknown' marker still lets a stale blob win over a
        // newer decodable save from another device; only an unreadable item
        // is spared, since replacing that needs the Vervangen prompt.
        final unreadable = marker == _unknown && synced != null && _decode(synced) == null;
        if (keychainError == null && !unreadable) await _migrate(keychain, legacy.json);
        return legacy.config;
      }
      // Another device saved or cleared since: its state wins.
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
    if (keychainError == null && synced == null) await _migrate(keychain, legacy.json);
    return legacy.config;
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
      await _removeLegacy();
    } else {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      // Marker first: a marker without a blob is harmless, the reverse is not.
      if (keychain != null) await prefs.setString(pendingKey, readFailed ? _unknown : _fingerprint(current));
      await prefs.setString(key, await CredentialVault.protect(json));
    }
    changes.value++;
  }

  /// Wipes both stores. A failed keychain delete throws: the synced config
  /// would otherwise come back on the next load. The keychain goes first, so
  /// a delete that throws does not cost a pending blob.
  Future<void> clear() => _serial(_clear);

  Future<void> _clear() async {
    try {
      await _keychain?.delete(key);
      await _removeLegacy();
    } finally {
      changes.value++;
    }
  }

  /// Writes [json] and drops the prefs blob after an equal readback. A
  /// readback that differs most likely is another device's sync landing in
  /// between: the blob stays, nothing is deleted, the next load decides.
  Future<void> _migrate(PleyaKeychain keychain, String json) async {
    try {
      if (await keychain.write(key, json) && await keychain.read(key) == json) await _removeLegacy();
    } catch (e) {
      appLogger.w('Assistant keychain migration failed', error: e.runtimeType);
    }
  }

  static const String _unknown = 'unknown';

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
  }
}
