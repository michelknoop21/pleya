import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import 'base_shared_preferences_service.dart';
import 'settings_export_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// How the key-value-store sync facility is doing on this device.
///
/// Availability and health are separate questions, and conflating them is what
/// made an Apple TV claim it was signed out of iCloud. [unsupported] and
/// [signedOut] say the facility cannot be used at all; [warning] and [error]
/// say a usable facility hit a problem. Only the first two may disable the
/// control.
enum ICloudSyncStatus {
  /// No native key-value store on this platform (Android, Linux, Windows), or
  /// the plugin is missing from the build.
  unsupported,

  /// An Apple platform whose iCloud account is genuinely absent, so writes
  /// would stay on this device. iOS and macOS only: tvOS has no account-level
  /// signal to read, and its entitlement is what authorises the store.
  signedOut,

  /// Usable, and nothing has failed since the last successful call.
  ok,

  /// Usable, but something was dropped: a value over the per-key cap, or the
  /// 1MB store quota. Sync keeps running and picks the key up again later.
  warning,

  /// Usable in principle, but the last call to the store failed. This is a
  /// transport fault, not a missing account — the control stays on.
  error;

  /// Whether the facility can be used at all. [warning] and [error] are health,
  /// not availability, so they stay usable.
  bool get isUsable => this == ok || this == warning || this == error;
}

/// Mirrors user settings across the signed-in user's Apple devices via
/// NSUbiquitousKeyValueStore (iCloud key-value store).
///
/// Per-key, last-writer-wins. Values are the same typed JSON markers the
/// export uses (`{"type":"int","value":42}`); KVS keys are the export *base*
/// keys (user prefix stripped). Eligibility, encoding and user-scoping are all
/// delegated to [SettingsExportService], so the sync and export/import surfaces
/// can never diverge on what is (and isn't) allowed to leave the device.
///
/// Loop prevention is by construction: remote changes are applied with direct
/// `prefs.setX(...)` (never [BaseSharedPreferencesService.write]), so they don't
/// re-fire the local-write hook. [_applyingRemote] is a belt-and-braces guard.
///
/// No-op on Android/Linux/Windows — the native plugin only exists on Apple
/// platforms (tvOS reports itself as iOS), where it is authorised by the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement.
class ICloudSyncService {
  ICloudSyncService._(this._settings, this._activeUserScope);

  static const MethodChannel _channel = MethodChannel('com.pleya/icloud_kvs');
  static const EventChannel _events = EventChannel('com.pleya/icloud_kvs/events');

  /// Meta key carrying the sync format version. Skipped on apply. Namespaced
  /// with `__` so it can never collide with a real (denylisted-or-not) pref.
  static const String metaVersionKey = '__syncFormatVersion';
  static const int formatVersion = 1;

  // NSUbiquitousKeyValueStoreChangeReason values.
  static const int _reasonServerChange = 0;
  static const int _reasonInitialSync = 1;
  static const int _reasonQuotaViolation = 2;
  static const int _reasonAccountChange = 3;

  final SettingsService _settings;
  final String? Function() _activeUserScope;

  StreamSubscription<dynamic>? _eventSub;
  bool _applyingRemote = false;

  /// Called after remote changes are applied so the app can reload derived
  /// state (theme, locale, keyboard shortcuts) — same surface as an import.
  VoidCallback? onRemoteChangesApplied;

  final ValueNotifier<ICloudSyncStatus> _status = ValueNotifier(ICloudSyncStatus.ok);

  /// Live health of the sync facility, for the settings tile to render.
  /// Starts optimistic so the control is usable before the first probe returns.
  ValueListenable<ICloudSyncStatus> get status => _status;

  /// Report a status, but never let a [warning] erase a standing [error]:
  /// a dropped oversized key is the smaller of the two problems, and the
  /// error clears on the next call that actually succeeds.
  void _setStatus(ICloudSyncStatus next) {
    if (next == ICloudSyncStatus.warning && _status.value == ICloudSyncStatus.error) return;
    _status.value = next;
  }

  /// A call that reached the store clears a standing transport error, and only
  /// that: a [warning] (a key we chose to drop) is still true, and an account
  /// verdict is not ours to overturn from a plumbing call.
  void _clearTransportError() {
    if (_status.value == ICloudSyncStatus.error) _status.value = ICloudSyncStatus.ok;
  }

  static ICloudSyncService? _instance;
  static ICloudSyncService? get instance => _instance;

  /// Only Apple platforms ship the native plugin — tvOS included, since an
  /// Apple TV reports itself as iOS. Non-null overrides the platform answer in
  /// tests, which necessarily run on a host that is itself supported.
  @visibleForTesting
  static bool? debugSupportedOverride;
  static bool get _supported => debugSupportedOverride ?? (Platform.isIOS || Platform.isMacOS);

  bool get _enabled => _settings.read(SettingsService.icloudSyncEnabled);

  /// Wire the local-write hook and, if the toggle is on, subscribe + merge.
  /// Safe to call on any platform; no-ops off Apple platforms.
  static Future<void> start({
    required SettingsService settings,
    required StorageService storage,
    VoidCallback? onRemoteChangesApplied,
  }) async {
    if (!_supported || _instance != null) return;
    final svc = ICloudSyncService._(settings, storage.activeUserScope)..onRemoteChangesApplied = onRemoteChangesApplied;
    _instance = svc;
    BaseSharedPreferencesService.onKeyWritten = svc._onLocalWrite;
    if (svc._enabled) await svc._activate();
  }

  /// Whether *Pleya's* key-value settings sync can be used here — not whether
  /// iCloud Drive exists. The native side answers per platform: iOS and macOS
  /// read the iCloud account, tvOS answers yes on the strength of its
  /// `ubiquity-kvstore-identifier` entitlement, because the account token it
  /// used to read is an iCloud *Drive* signal that is always nil on tvOS.
  ///
  /// A channel failure is a transport fault and returns true: the platform is
  /// still supported, so the control stays usable and the fault shows up as
  /// [ICloudSyncStatus.error]. Only a missing plugin is treated as genuinely
  /// unavailable, because then there is no store to talk to at all.
  Future<bool> isAvailable() async {
    if (!_supported) {
      _setStatus(ICloudSyncStatus.unsupported);
      return false;
    }
    try {
      final available = (await _channel.invokeMethod<bool>('isAvailable')) ?? false;
      _setStatus(available ? ICloudSyncStatus.ok : ICloudSyncStatus.signedOut);
      return available;
    } on MissingPluginException catch (e) {
      appLogger.w('iCloud KVS plugin missing from this build', error: e);
      _setStatus(ICloudSyncStatus.unsupported);
      return false;
    } catch (e) {
      appLogger.w('iCloud isAvailable failed', error: e);
      _setStatus(ICloudSyncStatus.error);
      return true;
    }
  }

  /// Turn sync on: persist the toggle, then pull remote (remote wins) and
  /// upload locally-unique keys.
  Future<void> enable() async {
    await _settings.write(SettingsService.icloudSyncEnabled, true);
    await _activate();
  }

  /// Turn sync off: persist the toggle and stop listening. KVS contents are
  /// left intact so re-enabling later still merges.
  Future<void> disable() async {
    await _settings.write(SettingsService.icloudSyncEnabled, false);
    await _eventSub?.cancel();
    _eventSub = null;
  }

  /// Enable-flow: subscribe → remote wins → upload local-unique keys.
  Future<void> _activate() async {
    _subscribe();
    try {
      await _channel.invokeMethod('synchronize');
      await _applyAllRemote();
      await pushAll();
    } catch (e, st) {
      appLogger.e('iCloud sync activation failed', error: e, stackTrace: st);
      _setStatus(ICloudSyncStatus.error);
    }
  }

  void _subscribe() {
    _eventSub ??= _events.receiveBroadcastStream().listen(
      _onRemoteEvent,
      onError: (Object e) => appLogger.w('iCloud KVS event error', error: e),
    );
  }

  // ---- Remote → local -------------------------------------------------------

  Future<void> _onRemoteEvent(dynamic event) async {
    if (!_enabled || event is! Map) return;
    final reason = event['reason'] as int? ?? -1;
    switch (reason) {
      case _reasonQuotaViolation:
        appLogger.w('iCloud KVS quota exceeded — some settings may not sync');
        _setStatus(ICloudSyncStatus.warning);
        return;
      case _reasonAccountChange:
        // iCloud account switched — re-apply everything from the new store.
        await _applyAllRemote();
        return;
      case _reasonServerChange:
      case _reasonInitialSync:
      default:
        final keys = (event['changedKeys'] as List?)?.cast<String>() ?? const <String>[];
        if (keys.isNotEmpty) await _applyRemoteKeys(keys);
    }
  }

  Future<void> _applyAllRemote() async {
    final all = await _getAll();
    if (all != null && all.isNotEmpty) await _applyEntries(all);
  }

  Future<void> _applyRemoteKeys(List<String> keys) async {
    final all = await _getAll();
    // null = channel read failed. Do NOT infer removals from a failed read —
    // absent-in-`all` only means "removed remotely" when the read succeeded,
    // otherwise we'd wipe local settings on a transient channel error.
    if (all == null) return;
    final entries = <String, String?>{for (final k in keys) k: all[k]};
    await _applyEntries(entries);
  }

  /// Apply KVS base-key entries to local prefs. `null` value = remove.
  /// Bypasses [BaseSharedPreferencesService.write] so it never echoes to KVS.
  Future<void> _applyEntries(Map<String, String?> entries) async {
    final uuid = _activeUserScope();
    final prefs = _settings.prefs;
    _applyingRemote = true;
    var changed = false;
    try {
      for (final entry in entries.entries) {
        final baseKey = entry.key;
        if (baseKey.startsWith('__')) continue; // meta keys
        if (!SettingsExportService.isExportable(baseKey)) continue;
        final scoped = SettingsExportService.isUserScopedBaseKey(baseKey);
        if (scoped && (uuid == null || uuid.isEmpty)) continue; // no user to scope to
        final targetKey = scoped ? SettingsExportService.syncTargetKey(baseKey, uuid!) : baseKey;

        final raw = entry.value;
        if (raw == null) {
          await prefs.remove(targetKey);
          changed = true;
          continue;
        }
        final decoded = _decode(raw);
        if (decoded == null) continue;
        var value = decoded.$2;
        // Local playback progress: merge instead of overwrite, so progress
        // made on another device can never be rolled back by a stale writer
        // (progress = max, watched = OR — same semantics as the server sync).
        if (isLocalProgressKey(baseKey) && value is String) {
          value = mergeProgressMaps(
            prefs.getString(targetKey),
            value,
            watchedMap: baseKey.startsWith('local_watched_'),
          );
        }
        final ok = await SettingsExportService.writeTyped(prefs, targetKey, decoded.$1, value);
        if (ok) changed = true;
      }
    } finally {
      _applyingRemote = false;
    }
    if (changed) {
      _settings.refreshListenables();
      onRemoteChangesApplied?.call();
    }
  }

  // ---- Local → remote -------------------------------------------------------

  /// Local-write hook. Mirrors one eligible key to KVS. Skips remote-apply
  /// echoes, disabled state, other users' scopes and denylisted keys.
  void _onLocalWrite(String fullKey) {
    if (_applyingRemote || !_enabled) return;
    final baseKey = SettingsExportService.syncBaseKey(fullKey, currentUserUuid: _activeUserScope());
    if (baseKey == null) return;
    final entry = SettingsExportService.encodeValue(_settings.prefs.get(fullKey));
    if (entry == null) return;
    final encoded = json.encode(entry);
    // KVS quota is 1MB total: a huge local-library progress map must not
    // starve every other setting. Skip oversized values; the map keeps
    // syncing again as soon as it shrinks below the cap.
    if (encoded.length > maxValueBytes) {
      appLogger.w('iCloud sync: skipping $baseKey (${encoded.length} bytes > $maxValueBytes)');
      _setStatus(ICloudSyncStatus.warning);
      return;
    }
    unawaited(_set(baseKey, encoded));
  }

  /// Per-value size cap (KVS totals 1MB across all keys).
  static const int maxValueBytes = 100 * 1024;

  static bool isLocalProgressKey(String baseKey) =>
      baseKey.startsWith('local_progress_') || baseKey.startsWith('local_watched_');

  /// Merge two JSON progress maps: progress = max, watched = OR. Unknown
  /// items from both sides are kept; corrupt input falls back to [local].
  static String mergeProgressMaps(String? local, String incoming, {required bool watchedMap}) {
    try {
      final localMap = local == null ? <String, dynamic>{} : json.decode(local) as Map<String, dynamic>;
      final incomingMap = json.decode(incoming) as Map<String, dynamic>;
      final merged = Map<String, dynamic>.from(localMap);
      incomingMap.forEach((key, value) {
        final existing = merged[key];
        if (watchedMap) {
          merged[key] = (existing == true) || (value == true);
        } else {
          final a = existing is num ? existing : 0;
          final b = value is num ? value : 0;
          merged[key] = a > b ? a : b;
        }
      });
      return json.encode(merged);
    } catch (_) {
      return local ?? incoming;
    }
  }

  /// Push every eligible local key to KVS and drop KVS keys that no longer
  /// exist locally (propagates removals and settings-reset). Used by the
  /// enable-merge and by bulk paths that bypass [write] (import/reset).
  Future<void> pushAll() async {
    if (!_supported) return;
    final uuid = _activeUserScope();
    final prefs = _settings.prefs;

    final eligible = <String, String>{};
    for (final fullKey in prefs.keys) {
      final baseKey = SettingsExportService.syncBaseKey(fullKey, currentUserUuid: uuid);
      if (baseKey == null) continue;
      final entry = SettingsExportService.encodeValue(prefs.get(fullKey));
      if (entry == null) continue;
      eligible[baseKey] = json.encode(entry);
    }

    await _set(metaVersionKey, json.encode({'type': 'int', 'value': formatVersion}));
    for (final e in eligible.entries) {
      await _set(e.key, e.value);
    }

    final remote = await _getAll();
    if (remote != null) {
      for (final k in remote.keys) {
        if (k.startsWith('__')) continue;
        if (eligible.containsKey(k)) continue;
        // With no signed-in user, a user-scoped cloud key belongs to some
        // other account — absence locally means "not mine", not "deleted".
        // Pruning it here would wipe another device's per-user settings.
        if ((uuid == null || uuid.isEmpty) && SettingsExportService.isUserScopedBaseKey(k)) continue;
        await _remove(k);
      }
    }

    try {
      await _channel.invokeMethod('synchronize');
    } catch (_) {
      // best-effort flush; the OS coalesces uploads anyway
    }
  }

  /// [pushAll] only when the toggle is on. Called after bulk paths that bypass
  /// [write] (settings import, reset).
  Future<void> pushAllIfEnabled() async {
    if (_enabled) await pushAll();
  }

  // ---- Channel plumbing -----------------------------------------------------

  /// Returns the full KVS contents, or null when the channel read fails.
  /// Callers must treat null as "unknown", never as "empty" — see
  /// [_applyRemoteKeys] and [pushAll] for why the distinction matters.
  Future<Map<String, String>?> _getAll() async {
    try {
      final all = (await _channel.invokeMapMethod<String, String>('getAll')) ?? const <String, String>{};
      _clearTransportError();
      return all;
    } catch (e) {
      appLogger.w('iCloud getAll failed', error: e);
      _setStatus(ICloudSyncStatus.error);
      return null;
    }
  }

  Future<void> _set(String key, String value) async {
    try {
      await _channel.invokeMethod('set', {'key': key, 'value': value});
      _clearTransportError();
    } catch (e) {
      appLogger.w('iCloud set failed for $key', error: e);
      _setStatus(ICloudSyncStatus.error);
    }
  }

  Future<void> _remove(String key) async {
    try {
      await _channel.invokeMethod('remove', {'key': key});
      _clearTransportError();
    } catch (e) {
      appLogger.w('iCloud remove failed for $key', error: e);
      _setStatus(ICloudSyncStatus.error);
    }
  }

  /// Decode a stored `{"type":..,"value":..}` JSON string to a (type, value)
  /// pair, or null when malformed.
  (String, Object?)? _decode(String jsonStr) {
    try {
      final m = json.decode(jsonStr);
      if (m is! Map) return null;
      final type = m['type'];
      if (type is! String) return null;
      return (type, m['value']);
    } catch (_) {
      return null;
    }
  }

  // ---- Testing --------------------------------------------------------------

  @visibleForTesting
  static ICloudSyncService debugCreate({
    required SettingsService settings,
    String? Function()? activeUserScope,
    VoidCallback? onRemoteChangesApplied,
  }) {
    debugSupportedOverride = true;
    final svc = ICloudSyncService._(settings, activeUserScope ?? () => null)
      ..onRemoteChangesApplied = onRemoteChangesApplied;
    _instance = svc;
    BaseSharedPreferencesService.onKeyWritten = svc._onLocalWrite;
    return svc;
  }

  /// Drive the remote-event path directly (fakes an EventChannel emission).
  @visibleForTesting
  Future<void> debugHandleEvent(Map<String, dynamic> event) => _onRemoteEvent(event);

  @visibleForTesting
  static void debugReset() {
    _instance?._eventSub?.cancel();
    _instance?._status.dispose();
    _instance = null;
    debugSupportedOverride = null;
    BaseSharedPreferencesService.onKeyWritten = null;
  }
}
