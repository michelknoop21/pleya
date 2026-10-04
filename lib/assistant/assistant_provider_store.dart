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

  // Resolved per call: TV detection may finish after [instance] exists.
  PleyaKeychain? get _keychain => _injectedKeychain ?? (PleyaKeychain.supported ? const PleyaKeychain() : null);

  /// The keychain first, then the old prefs blob, which moves to the keychain
  /// and leaves the prefs only once a readback matches. A keychain error
  /// never deletes the blob; with no blob to fall back to it throws
  /// [AssistantProviderStoreException] rather than reading as unset.
  Future<AssistantProviderConfig?> load() async {
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
    final fromKeychain = synced == null ? null : _decode(synced);
    if (fromKeychain != null) {
      // ponytail: last writer wins, as iCloud itself does. Two Apple TVs with
      // different configs end up with one; a save whose keychain write failed
      // (so it fell back to the prefs) loses to an older synced item here.
      await _removeLegacy();
      return fromKeychain;
    }
    final legacy = await _readLegacy();
    if (legacy == null) {
      if (keychainError != null) throw AssistantProviderStoreException(keychainError);
      return null;
    }
    // An item that exists but does not decode (a newer app version on another
    // device) is never overwritten by this device's older blob.
    if (keychainError == null && synced == null) await _migrate(keychain, legacy.json);
    return legacy.config;
  }

  /// The keychain when it takes the write; otherwise the prefs path keeps
  /// working on this device.
  Future<void> save(AssistantProviderConfig config) async {
    _registerSecrets(config);
    final json = jsonEncode(config.toJson());
    var stored = false;
    final keychain = _keychain;
    if (keychain != null) {
      try {
        stored = await keychain.write(key, json);
      } catch (e) {
        appLogger.w('Assistant keychain write failed', error: e.runtimeType);
      }
    }
    if (stored) {
      await _removeLegacy();
    } else {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString(key, await CredentialVault.protect(json));
    }
    changes.value++;
  }

  /// Wipes both stores. A failed keychain delete throws: the synced config
  /// would otherwise come back on the next load.
  Future<void> clear() async {
    try {
      await _removeLegacy();
      await _keychain?.delete(key);
    } finally {
      changes.value++;
    }
  }

  Future<void> _migrate(PleyaKeychain keychain, String json) async {
    try {
      if (await keychain.write(key, json) && await keychain.read(key) == json) await _removeLegacy();
    } catch (e) {
      appLogger.w('Assistant keychain migration failed', error: e.runtimeType);
    }
  }

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
