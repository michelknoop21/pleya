import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import '../credential_vault.dart';
import '../pleya_keychain.dart';
import 'tracker_constants.dart';
import 'tracker_session.dart';

/// Per-Plex-profile session persistence for any tracker service.
///
/// Keyed by `user_{uuid}_{baseKey}` so each Plex Home profile gets its own
/// stored session. The storage key remains service-specific, while the payload
/// is the unified [TrackerSession] JSON shape.
///
/// Pass an empty `userUuid` to fall back to a single global slot (used
/// before a profile has been selected).
///
/// Where the session lives:
/// - iOS and tvOS: one item in the keychain of this device
///   ([PleyaKeychain.deviceOnly]), never in iCloud. A prefs marker
///   (`<key>_kc`) records that the item belongs to this install; keychain
///   items outlive an uninstall, and an item without marker is never read,
///   so a reinstall starts disconnected. A missing marker deletes nothing:
///   prefs can read empty (a launch before the first unlock) while the item
///   is valid. The next connect overwrites what an earlier install left.
/// - Elsewhere, and whenever the keychain refuses: a [CredentialVault]
///   protected blob in the prefs, under the key the plaintext session used.
///
/// A blob in the prefs is always the newest state (a session from before the
/// move, or a save the keychain refused) and wins over the keychain item. It
/// leaves the prefs only after the keychain read back the same value.
class TrackerAccountStore {
  static final Map<TrackerService, TrackerAccountStore> _stores = {
    TrackerService.mal: TrackerAccountStore._(TrackerService.mal, 'mal_session'),
    TrackerService.anilist: TrackerAccountStore._(TrackerService.anilist, 'anilist_session'),
    TrackerService.simkl: TrackerAccountStore._(TrackerService.simkl, 'simkl_session'),
    TrackerService.trakt: TrackerAccountStore._(TrackerService.trakt, 'trakt_session'),
  };

  static TrackerAccountStore forService(TrackerService service) => _stores[service]!;

  final TrackerService service;
  final String _baseKey;

  TrackerAccountStore._(this.service, this._baseKey);

  /// Every load, save and clear runs after the one before, so a migration can
  /// never interleave with a save and put an older session back.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  // Resolved per call: TV detection may finish after the store exists.
  PleyaKeychain? get _keychain => PleyaKeychain.supported ? const PleyaKeychain.deviceOnly() : null;

  String _scopedKey(String userUuid) => userUuid.isEmpty ? _baseKey : 'user_${userUuid}_$_baseKey';

  static String _markerKey(String key) => '${key}_kc';

  Future<TrackerSession?> load(String userUuid) => _serial(() => _load(_scopedKey(userUuid)));

  Future<void> save(String userUuid, TrackerSession session) =>
      _serial(() => _save(_scopedKey(userUuid), session.encode()));

  Future<void> clear(String userUuid) => _serial(() => _clear(_scopedKey(userUuid)));

  Future<TrackerSession?> _load(String key) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final keychain = _keychain;
    final blob = prefs.getString(key);

    if (blob != null) {
      final String json;
      try {
        json = await CredentialVault.reveal(blob);
      } catch (_) {
        return null;
      }
      final session = _decode(json);
      // A blob that no longer decodes stays where it is, as before the move.
      if (session == null) return null;
      if (keychain != null) {
        await _moveToKeychain(prefs, keychain, key, json);
      } else if (!CredentialVault.isProtected(blob)) {
        await prefs.setString(key, await CredentialVault.protect(json));
      }
      return session;
    }

    if (keychain == null) return null;
    final marker = prefs.getBool(_markerKey(key));
    if (marker == false) {
      // A clear whose delete the keychain refused: try again.
      if (await _deleteItem(keychain, key)) await prefs.remove(_markerKey(key));
      return null;
    }
    // No marker: not ours to read, and not ours to delete either.
    if (marker != true) return null;
    try {
      final json = await keychain.read(key);
      return json == null ? null : _decode(json);
    } catch (e) {
      // Type only: the native message is an OSStatus, keep it out of the log.
      appLogger.w('Trackers: reading the ${service.name} session from the keychain failed (${e.runtimeType})');
      return null;
    }
  }

  Future<void> _save(String key, String json) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final keychain = _keychain;
    if (keychain != null && await _moveToKeychain(prefs, keychain, key, json)) return;
    // No keychain here, or it refused: the protected blob is now the newest
    // state. An older keychain item may remain; the blob wins on load.
    await prefs.setString(key, await CredentialVault.protect(json));
  }

  Future<void> _clear(String key) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(key);
    final keychain = _keychain;
    if (keychain == null || await _deleteItem(keychain, key)) {
      await prefs.remove(_markerKey(key));
    } else {
      // The item is still there. `false` keeps it unread and lets the next
      // load retry the delete.
      await prefs.setBool(_markerKey(key), false);
    }
  }

  /// Writes [json] to the keychain and drops the prefs blob once the keychain
  /// read back the same value. False leaves the prefs untouched.
  Future<bool> _moveToKeychain(
    SharedPreferencesWithCache prefs,
    PleyaKeychain keychain,
    String key,
    String json,
  ) async {
    // The marker goes first: an app that dies after the keychain write must
    // find its own item again. A refused write puts the old marker back, so
    // an item of an earlier install never becomes readable.
    final before = prefs.getBool(_markerKey(key));
    if (before != true) {
      // Whatever sits under this key is not a live session of this install.
      // It goes before the marker does, so the marker never stands next to
      // an item of an earlier install.
      if (!await _deleteItem(keychain, key)) return false;
      await prefs.setBool(_markerKey(key), true);
    }
    var stored = false;
    try {
      stored = await keychain.write(key, json) && await keychain.read(key) == json;
    } catch (e) {
      appLogger.w('Trackers: the keychain refused the ${service.name} session (${e.runtimeType})');
    }
    if (!stored) {
      if (before == null) {
        await prefs.remove(_markerKey(key));
      } else if (before == false) {
        await prefs.setBool(_markerKey(key), false);
      }
      return false;
    }
    await prefs.remove(key);
    return true;
  }

  /// True once the item is gone.
  Future<bool> _deleteItem(PleyaKeychain keychain, String key) async {
    try {
      await keychain.delete(key);
      return true;
    } catch (e) {
      appLogger.w('Trackers: removing the ${service.name} session from the keychain failed (${e.runtimeType})');
      return false;
    }
  }

  TrackerSession? _decode(String json) {
    try {
      return TrackerSession.decode(json, service: service);
    } catch (_) {
      return null;
    }
  }
}

TrackerAccountStore trackerAccountStore(TrackerService service) => TrackerAccountStore.forService(service);
