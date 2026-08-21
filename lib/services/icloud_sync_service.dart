import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../connection/connection.dart';
import 'base_shared_preferences_service.dart';
import 'preferences/icloud_kvs_transport.dart';
import 'preferences/preference_merge_strategies.dart';
import 'preferences/preference_refresh.dart';
import 'preferences/portable_server_ids.dart';
import 'preferences/preference_device_id.dart';
import 'preferences/preference_sync_coordinator.dart';
import 'preferences/preference_transport.dart';
import 'settings_service.dart';
import 'storage_service.dart';

/// Mirrors user settings across the signed-in user's Apple devices.
///
/// This is a facade now. It owns nothing: [PreferenceSyncCoordinator] holds the
/// mutation pipeline, the policy, the scope, conflict metadata, reconcile and
/// status, and [ICloudKvsTransport] holds the channels. Keeping the class is
/// only about the call sites that already say `ICloudSyncService.instance`.
///
/// What changed underneath, and why:
/// - a removal now reaches the store. The old local-write hook received a key,
///   read the value back, found `null`, and stopped, so only a full reconcile
///   ever propagated a delete;
/// - syncability is decided by an explicit registry instead of an
///   allow-by-default denylist, so a new preference no longer opts itself in;
/// - a value that outgrows the transport cap is skipped *and* held back from
///   the prune. It used to be deleted from the store, because the prune worked
///   on absence from the push set;
/// - the write is awaited, so a transport failure lands in the status instead
///   of an unawaited future.
///
/// No-op on Android/Linux/Windows: the native plugin only exists on Apple
/// platforms (tvOS reports itself as iOS).
class ICloudSyncService {
  ICloudSyncService._(this._settings, this._coordinator);

  final SettingsService _settings;
  final PreferenceSyncCoordinator _coordinator;

  static const String metaVersionKey = PreferenceSyncCoordinator.metaVersionKey;
  static const int formatVersion = PreferenceSyncCoordinator.formatVersion;

  /// Per-value size cap, mirrored from the transport for callers that still ask
  /// this class.
  static const int maxValueBytes = 100 * 1024;

  static ICloudSyncService? _instance;
  static ICloudSyncService? get instance => _instance;

  PreferenceSyncCoordinator get coordinator => _coordinator;

  ValueListenable<PreferenceSyncStatus> get status => _coordinator.status;

  /// Called after remote changes are applied so the app can reload derived
  /// state (theme, locale, keyboard shortcuts): the same surface as an import.
  set onRemoteChangesApplied(VoidCallback? callback) => _coordinator.onRemoteChangesApplied = callback;

  @visibleForTesting
  static bool get debugForceSupported => ICloudKvsTransport.debugForceSupported;

  @visibleForTesting
  static set debugForceSupported(bool value) => ICloudKvsTransport.debugForceSupported = value;

  static bool get _supported => ICloudKvsTransport.supported;

  bool get _enabled => _settings.read(SettingsService.icloudSyncEnabled);

  /// Wire the mutation pipeline and, if the toggle is on, subscribe and merge.
  /// Safe to call on any platform; no-ops off Apple platforms.
  static Future<void> start({
    required SettingsService settings,
    required StorageService storage,
    VoidCallback? onRemoteChangesApplied,
  }) async {
    if (!_supported || _instance != null) return;
    // A dedicated id, not the Plex client identifier: that one is sent to
    // plex.tv and identifies the device to a third party.
    final deviceId = await PreferenceDeviceId.getOrCreate(settings.prefs);
    final coordinator = PreferenceSyncCoordinator(
      prefs: settings.prefs,
      activeProfileId: storage.getActiveProfileId,
      enabled: () => settings.read(SettingsService.icloudSyncEnabled),
      deviceId: deviceId,
      transport: ICloudKvsTransport(),
      onRemoteChangesApplied: onRemoteChangesApplied,
      onLocalStateChanged: settings.refreshListenables,
    )..onRuntimeRefresh = PreferenceRefreshBus.instance.invalidate;
    final svc = ICloudSyncService._(settings, coordinator);
    _instance = svc;
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    // A key-value store can change while the process is suspended, and the
    // notification for that change can be delivered to nobody. Coming back to
    // the foreground is therefore a reconcile trigger, not a hope.
    svc._lifecycle = AppLifecycleListener(
      onResume: () => unawaited(coordinator.requestReconcile(ReconcileTrigger.foreground)),
    );
    await coordinator.refreshAvailability();
    if (svc._enabled) await coordinator.requestReconcile(ReconcileTrigger.boot);
  }

  AppLifecycleListener? _lifecycle;

  /// Tell the engine which server ids identify the same server everywhere.
  ///
  /// Called once the connection registry exists and again whenever connections
  /// change. Until then nothing library-scoped is transported: a server id
  /// whose origin is unknown is treated as device-local, not as portable.
  void updatePortableServerIds(Iterable<Connection> connections) {
    _coordinator.serverIdPortability = PortableServerIds.fromConnections(connections).predicate;
  }

  /// True when iCloud is signed in. A nil ubiquity token means logged out, and
  /// sync would silently no-op, so the UI disables the toggle.
  Future<bool> isAvailable() async => await _coordinator.transport?.isAvailable() ?? false;

  /// Turn sync on: persist the toggle, then pull remote and upload local keys.
  Future<void> enable() async {
    await _settings.write(SettingsService.icloudSyncEnabled, true);
    await _coordinator.refreshAvailability();
    await _coordinator.requestReconcile(ReconcileTrigger.enabled);
  }

  /// Turn sync off: persist the toggle and stop listening. Store contents are
  /// left intact so re-enabling later still merges.
  Future<void> disable() async {
    await _settings.write(SettingsService.icloudSyncEnabled, false);
    await _coordinator.dispose();
    await _coordinator.refreshAvailability();
  }

  /// Reconcile after a bulk local change. Import and reset are the two: both
  /// rewrote local state deliberately, so neither pulls the store first.
  Future<void> pushAll({ReconcileTrigger trigger = ReconcileTrigger.imported}) =>
      _coordinator.requestReconcile(trigger);

  /// [pushAll] only when the toggle is on.
  Future<void> pushAllIfEnabled({ReconcileTrigger trigger = ReconcileTrigger.imported}) async {
    if (_enabled) await pushAll(trigger: trigger);
  }

  // ---- Legacy inbound compatibility ------------------------------------------

  static bool isLocalProgressKey(String baseKey) =>
      baseKey.startsWith('local_progress_') || baseKey.startsWith('local_watched_');

  /// Merge two JSON progress maps: progress = max, watched = OR.
  ///
  /// **Legacy inbound compatibility only.** This never ran on the path it was
  /// written for. `local_progress_*` and `local_watched_*` are produced by
  /// `LocalFolderClient`, which uses the legacy `SharedPreferences.getInstance()`
  /// store, while the sync engine reads the `SharedPreferencesWithCache` store.
  /// The legacy migration copies once and deletes nothing, so the two have been
  /// separate ever since: outgoing, the live value is not visible to the push,
  /// and incoming, the merged result is written where nothing reads it.
  ///
  /// It stays only to read progress maps that older Pleya versions already put
  /// in the cloud without corrupting them. Removal condition: once the sync
  /// format moves to v2 and no supported client still writes v1 progress
  /// entries, this and [isLocalProgressKey] go, together with the keys'
  /// runtime-cache registrations.
  ///
  /// The behaviour itself moved to the merge registry, where it is a registered
  /// family like any other. This is the call site's name for it.
  static String mergeProgressMaps(String? local, String incoming, {required bool watchedMap}) =>
      mergeProgressMapJson(local, incoming, watchedMap: watchedMap);

  // ---- Testing ---------------------------------------------------------------

  @visibleForTesting
  static ICloudSyncService debugCreate({
    required SettingsService settings,
    String? Function()? activeUserScope,
    VoidCallback? onRemoteChangesApplied,
    PreferenceTransport? transport,
    String deviceId = 'test-device',
  }) {
    ICloudKvsTransport.debugForceSupported = true;
    final scope = activeUserScope ?? () => null;
    final coordinator = PreferenceSyncCoordinator(
      prefs: settings.prefs,
      // Tests hand in a raw scope value rather than a profile id. A Plex Home
      // UUID and a bare scope string are the same thing to the storage layer,
      // so wrap it in the profile-id shape the coordinator expects.
      activeProfileId: () {
        final s = scope();
        return s == null || s.isEmpty ? null : s;
      },
      enabled: () => settings.read(SettingsService.icloudSyncEnabled),
      deviceId: deviceId,
      transport: transport ?? ICloudKvsTransport(),
      onRemoteChangesApplied: onRemoteChangesApplied,
      onLocalStateChanged: settings.refreshListenables,
    )..onRuntimeRefresh = PreferenceRefreshBus.instance.invalidate;
    final svc = ICloudSyncService._(settings, coordinator);
    _instance = svc;
    BaseSharedPreferencesService.onMutation = coordinator.apply;
    return svc;
  }

  /// Drive the remote-event path directly (fakes an EventChannel emission).
  @visibleForTesting
  Future<void> debugHandleEvent(Map<String, dynamic> event) async {
    if (!_enabled) return;
    final change = ICloudKvsTransport.translateEvent(event);
    if (change == null) return;
    switch (change.reason) {
      case RemoteChangeReason.quotaExceeded:
        return;
      case RemoteChangeReason.accountChanged:
        await _coordinator.refreshAvailability();
        await _coordinator.requestReconcile(ReconcileTrigger.accountChanged);
      case RemoteChangeReason.serverChange:
      case RemoteChangeReason.initialSync:
        if (change.changedKeys.isNotEmpty) await _coordinator.applyRemoteKeys(change.changedKeys);
    }
  }

  @visibleForTesting
  static void debugReset() {
    _instance?._lifecycle?.dispose();
    unawaited(_instance?._coordinator.dispose());
    _instance = null;
    ICloudKvsTransport.debugForceSupported = false;
    BaseSharedPreferencesService.onMutation = null;
  }
}
