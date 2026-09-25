import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import 'preference_legacy_bootstrap.dart';
import 'preference_key_mapper.dart';
import 'preference_merge_strategies.dart';
import 'preference_mutation.dart';
import 'preference_reconcile_scheduler.dart';
import 'preference_reconciler.dart';
import 'preference_refresh.dart';
import 'preference_remote_apply.dart';
import 'preference_revision.dart';
import 'preference_revision_store.dart';
import 'preference_single_send.dart';
import 'preference_sync_policy.dart';
import 'preference_sync_scope.dart';
import 'preference_sync_status.dart';
import 'preference_transport.dart';
import 'preference_value_portability.dart';

// The status model moved out of this file but stayed part of its surface:
// everything that holds a coordinator also reads its status.
export 'preference_reconcile_scheduler.dart' show ReconcileTrigger;
export 'preference_refresh.dart';
export 'preference_sync_status.dart';

/// Owns everything above the transport: mutation intake, policy, scope,
/// conflict metadata, reconcile and status.
///
/// The layer it replaces had two problems that no amount of care at the call
/// sites could fix. It hung off `void Function(String key)`, which cannot tell
/// a set from a remove (the hook read the value back and got `null`, so a
/// removal never travelled) and cannot tell a user's choice from a migration.
/// And it started its work with `unawaited(...)`, so a failed push had nowhere
/// to be reported.
///
/// Since DEC-131 the wire format carries the envelope: a record is
/// `{"type","value","t","d"}` and a removal is a tombstone `{"x":true,"t","d"}`.
/// Both live in the `__pleya_pref_v2/` namespace the previous build already
/// reads; that build ignores `t` and `d` and skips a tombstone, so the formats
/// coexist. A record without a stamp is one the previous build wrote and
/// counts as [legacyRevisionAt].
class PreferenceSyncCoordinator {
  PreferenceSyncCoordinator({
    required SharedPreferencesWithCache prefs,
    required String? Function() activeProfileId,
    required bool Function() enabled,
    required String deviceId,
    IsServerIdPortable? isServerIdPortable,
    bool? useV2CloudFormat,
    PreferenceTransport? transport,
    VoidCallback? onRemoteChangesApplied,
    VoidCallback? onLocalStateChanged,
  }) : _prefs = prefs,
       _keys = PreferenceKeyMapper(
         activeProfileId: activeProfileId,
         v2Format: useV2CloudFormat ?? v2CloudFormatEnabled,
         isServerIdPortable: isServerIdPortable ?? noServerIdIsPortable,
       ),
       _enabled = enabled,
       _deviceId = deviceId,
       _transport = transport,
       onRemoteChangesApplied = onRemoteChangesApplied,
       onLocalStateChanged = onLocalStateChanged;

  final SharedPreferencesWithCache _prefs;

  /// Key mapping, scope and merges. See [PreferenceKeyMapper].
  final PreferenceKeyMapper _keys;
  final bool Function() _enabled;
  final String _deviceId;

  /// See [PreferenceKeyMapper.isServerIdPortable].
  set serverIdPortability(IsServerIdPortable predicate) => _keys.isServerIdPortable = predicate;

  PreferenceTransport? _transport;

  /// Called after remote changes landed, so derived runtime state can reload.
  VoidCallback? onRemoteChangesApplied;

  /// Called with the runtime families a batch invalidated.
  ///
  /// Separate from [onRemoteChangesApplied], which is the blunt "something
  /// changed" signal the locale reload hangs off. This one names what went
  /// stale, so a provider reloads its own slice instead of the app rebuilding.
  void Function(Set<PreferenceRefreshFamily>)? onRuntimeRefresh;

  /// Called after any local change, so listenables that read prefs directly can
  /// refresh.
  VoidCallback? onLocalStateChanged;

  StreamSubscription<RemotePreferenceChange>? _changeSub;

  final ValueNotifier<PreferenceSyncStatus> status = ValueNotifier(const PreferenceSyncStatus());

  PreferenceTransport? get transport => _transport;

  /// Whether the cloud content has been migrated to the scoped, enveloped v2
  /// format.
  ///
  /// On in every build since the v2 cutover: nothing writes a flat v1 key any
  /// more. Since DEC-131 v2 records also carry the revision envelope, and a
  /// removal travels as a tombstone.
  ///
  /// The two formats differ in more than the key shape, which is why the switch
  /// is readable per instance rather than only as a constant. Under v1 the
  /// cloud key carries no profile identity, so an incoming profile-scoped
  /// record cannot be applied at all: `preference_remote_apply.dart` hands it
  /// to `PreferenceQuarantine` instead of to whichever profile happens to be
  /// active. Under v2 the profile is in the key, so the same record applies
  /// normally.
  static const bool v2CloudFormatEnabled = true;

  /// This instance's format. Equals [v2CloudFormatEnabled] in the app; tests
  /// drive both sides.
  bool get usesV2CloudFormat => _keys.v2Format;

  // ---- Scope ----------------------------------------------------------------

  PreferenceSyncScope scopeFor(String baseKey) => _keys.scopeFor(baseKey);

  /// The active profile's scope identifier, the value `StorageService` uses for
  /// its `user_<scope>_` prefixes.
  String? get activeUserScope => _keys.activeProfileScope.id;

  /// See [PreferenceKeyMapper.cloudKeyFor].
  String? cloudKeyFor(String fullKey) => _keys.cloudKeyFor(fullKey);

  /// See [PreferenceKeyMapper.baseKeyOf].
  String? baseKeyOf(String fullKey) => _keys.baseKeyOf(fullKey);

  PreferenceMergeRegistry get mergeRegistry => _keys.merges;

  // ---- Mutation intake ------------------------------------------------------

  /// The single entry point for every preference change the engine owns.
  ///
  /// Returns once the transport has been told, or immediately when the mutation
  /// stays on the device. Callers await it, which is the whole point: a failed
  /// push now reaches [status] instead of vanishing into an unawaited future.
  Future<void> apply(PreferenceMutation mutation) async {
    if (mutation.source != PreferenceSource.remote) onLocalStateChanged?.call();
    if (mutation.key == PreferenceSyncScope.activeProfileIdKey && mutation.source != PreferenceSource.remote) {
      // The active profile decides which namespace this device reads and
      // writes, so changing it is a reconcile trigger like any other. Noticing
      // it here rather than at the profile screen means every path that
      // switches profiles is covered, including the bootstrap and the cleanup.
      unawaited(requestReconcile(ReconcileTrigger.profileChanged));
    }
    if (!mutation.mayTravel) return;

    final baseKey = _keys.baseKeyOf(mutation.key);
    if (baseKey == null) return;

    // Stamped before any gate that holds the send back. An unstamped local
    // value loses to every stamped remote record (see [remoteStampWins]), so a
    // user's write that skipped the stamp would be overwritten by the next
    // remote batch, however old that batch is.
    final stampKey = _keys.stampKeyFor(baseKey);
    if (mutation.stampsUserChange && PreferenceSyncPolicyRegistry.maySync(baseKey)) {
      _revisionStore.stampUserChange(stampKey, removed: mutation.operation == PreferenceOperation.remove);
    }

    if (!_enabled()) return;
    final transport = _transport;
    if (transport == null) return;
    final availability = status.value.availability;
    if (availability == PreferenceSyncAvailability.unavailable || availability == PreferenceSyncAvailability.unknown) {
      // Signed out, or not known yet. The change is stamped above, so the
      // first reconcile once the store is there carries it; writing now would
      // only produce a "last sent" time for a value that went nowhere.
      return;
    }

    final cloudKey = _keys.cloudKeyFor(mutation.key);
    if (cloudKey == null) return;

    _setStatus(status.value.starting(DateTime.now()));
    try {
      if (mutation.operation == PreferenceOperation.remove) {
        // A removal is a first-class change. v1 lost it here: the hook only had
        // a key, read `null` back, and stopped. Since DEC-131 it travels as a
        // tombstone rather than as an absent key, so the other device can tell
        // "deleted" from "never had it".
        final tombstone = encodeTombstone(_revisionStore.stampOf(stampKey), key: _keys.keyTagFor(baseKey));
        if (exceedsTransportLimits(transport, cloudKey, tombstone)) {
          appLogger.w('preference sync: removal of ${_category(baseKey)} exceeds the transport limits');
          _setStatus(status.value.copyWith(oversize: status.value.oversize + 1).raise(PreferenceSyncHealth.warning));
          return;
        }
        await transport.write(cloudKey, tombstone);
        _setStatus(status.value.writeSucceeded(DateTime.now()));
        return;
      }

      // A family with an outgoing merge reads the store and writes from that
      // read, so it takes a turn: a reconcile or a remote batch in between
      // would change the store under it.
      if (_keys.merges.familyFor(baseKey)?.mergesOutgoing ?? false) {
        await _exclusively(
          () => _singleSend.send(transport, baseKey, cloudKey, stampKey, mutation.value, readFirst: true),
        );
      } else {
        await _singleSend.send(transport, baseKey, cloudKey, stampKey, mutation.value, readFirst: false);
      }
    } catch (e) {
      _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: _errorCategory(e)));
      appLogger.w('preference sync: transport write failed for ${_category(baseKey)}');
    }
  }

  late final PreferenceSingleSend _singleSend = PreferenceSingleSend(
    keys: _keys,
    revisionStore: _revisionStore,
    status: status,
  );

  // ---- Conflict metadata ----------------------------------------------------

  /// See [PreferenceRevisionStore.storeKey].
  static const String revisionStoreKey = PreferenceRevisionStore.storeKey;

  /// See [PreferenceRevisionStore.legacyAt].
  static const int legacyRevisionAt = PreferenceRevisionStore.legacyAt;

  late final PreferenceRevisionStore _revisionStore = PreferenceRevisionStore(_prefs, _deviceId);

  /// Record a revision for a value that was already present, without pretending
  /// the user just chose it. Idempotent.
  Future<void> bootstrapLegacyRevision(String baseKey) async {
    if (!PreferenceSyncPolicyRegistry.maySync(baseKey)) return;
    await _revisionStore.bootstrapLegacy(_keys.stampKeyFor(baseKey));
  }

  /// The last deliberate local change to [baseKey], or null when this device
  /// never made one. This is the half of [PreferenceRevision] that has to be
  /// kept locally so a remote snapshot has something to be compared against.
  PreferenceRevision? localRevision(String baseKey) {
    final entry = _revisionStore.all()[_keys.stampKeyFor(baseKey)];
    if (entry is! Map) return null;
    final at = entry['t'];
    final device = entry['d'];
    if (at is! int || device is! String) return null;
    final deleted = entry['x'] == true;
    final localKey = _keys.localKeyFor(baseKey);
    final value = deleted || localKey == null ? null : _prefs.get(localKey);
    if (!deleted && value == null) return null;
    return PreferenceRevision(value: value, updatedAt: at, deviceId: device, deleted: deleted);
  }

  /// Forget every stamp. Used when the account under the store changes (the
  /// stamps describe edits against another account's history) and by tests.
  Future<void> clearRevisions() => _revisionStore.clear();

  // ---- Reconciliation lifecycle ---------------------------------------------

  late final PreferenceReconcileScheduler _scheduler = PreferenceReconcileScheduler(
    run: (triggers) => _exclusively(() => _runReconcile(triggers)),
    onError: (e) {
      _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: _errorCategory(e)));
      appLogger.w('preference sync: reconcile failed (${_errorCategory(e)})');
    },
  );

  /// The tail of the queue a reconcile run and a remote event take turns on.
  Future<void> _turn = Future<void>.value();

  /// Run [body] after every earlier reconcile run and remote event finished.
  ///
  /// A reconcile reads the store once and decides from that snapshot. A remote
  /// event applied in the middle would change local state under it, and the
  /// event's own read would race the reconcile's writes, so the two queue.
  ///
  /// Each turn gets [turnTimeout] from the moment it starts, so turns behind a
  /// hung one are released one at a time, and a hung reconcile frees the
  /// scheduler instead of holding it for the rest of the session.
  Future<void> _exclusively(Future<void> Function() body) {
    // ponytail: a bounded turn, not cancellation. A turn that hangs (a native
    // call that never answers) is left running in the background while the
    // queue moves on, so it can still land late. Cancel the transport call
    // instead if that ever shows up.
    final run = _turn.then((_) {
      _turnGeneration++;
      return body().timeout(
        turnTimeout,
        onTimeout: () {
          // The abandoned turn is no longer current: whatever it does when it
          // answers late is checked against this number and dropped.
          _turnGeneration++;
          _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: 'timeout'));
          appLogger.w('preference sync: a sync turn did not finish in time');
        },
      );
    });
    _turn = run.catchError((Object _) {});
    return run;
  }

  /// Bumped when a turn starts and when one times out. A turn that answers
  /// late sees a newer number and knows its snapshot is stale.
  int _turnGeneration = 0;

  /// How long one reconcile run or remote event may take before the queue
  /// moves on without it.
  @visibleForTesting
  Duration turnTimeout = const Duration(seconds: 30);

  /// Test-facing view of the scheduler, so "one run, not three" is measurable.
  @visibleForTesting
  PreferenceReconcileScheduler get scheduler => _scheduler;

  /// Ask for a reconciliation. Overlapping requests collapse; see
  /// [PreferenceReconcileScheduler].
  Future<void> requestReconcile(ReconcileTrigger trigger) => _scheduler.request(trigger);

  /// What each trigger actually needs doing.
  ///
  /// Only the first run after an upgrade has legacy values to import, and only
  /// a trigger that can have changed the store needs a pull before the push. An
  /// import or a reset changed *local* state, so pulling first would be a good
  /// way to undo what the user just did.
  /// An account change seen but not yet handled by a current turn.
  ///
  /// ponytail: in memory, so an app restart between the event and its turn
  /// loses it; persist it in prefs if that shows up.
  bool _accountChangePending = false;

  Future<void> _runReconcile(Set<ReconcileTrigger> triggers) async {
    // Still the current turn, and sync still on. Taken before the first await:
    // a turn that hangs in the availability check and answers after its
    // timeout must not clear stamps or act on a snapshot beside the next turn.
    final generation = _turnGeneration;
    bool current() => generation == _turnGeneration && _enabled();

    // One gate for every trigger. `disabled` means the toggle is off (no
    // channel call is made to find that out), `unavailable` means nobody is
    // signed in, and the store may have gone away while we were suspended. In
    // each case the status has to say so before this pass pretends to have
    // sent anything. The enable path writes the toggle first, and import and
    // reset only call in through `pushAllIfEnabled`.
    if (triggers.contains(ReconcileTrigger.accountChanged)) _accountChangePending = true;
    await refreshAvailability();
    if (status.value.availability != PreferenceSyncAvailability.ready || !current()) return;
    // Pending until a current turn has cleared the stamps: a turn that timed
    // out or stopped before this point leaves it set, and the next reconcile of
    // any kind runs the account change instead of keeping the old stamps.
    final storeWins = _accountChangePending;
    if (storeWins) {
      // Strict read-first (B9). The stamps describe this device's edits against
      // the previous account's history; against another account they mean
      // nothing, and keeping them would push the old account's values into the
      // new one as "newer". The engine has no account identity: a store holding
      // records this device wrote proves nothing (A, B, A would carry B's
      // stamps into A), so every account change reads first. Local values stay;
      // the store wins what it holds, per map entry too.
      await clearRevisions();
      await PreferenceLegacyBootstrap.reset(_prefs);
      if (!current()) return;
      _accountChangePending = false;
    }
    final needsBootstrap =
        triggers.contains(ReconcileTrigger.boot) || triggers.contains(ReconcileTrigger.enabled) || storeWins;
    final localIsTheSource = triggers.every((t) => t == ReconcileTrigger.imported || t == ReconcileTrigger.reset);

    if (needsBootstrap) await bootstrapFromLegacyV1(proceed: current);
    if (!localIsTheSource) await applyAllRemote(proceed: current, storeWins: storeWins);
    await _reconciler.reconcile(proceed: current);
  }

  // ---- Availability ---------------------------------------------------------

  /// Hold every send until [refreshAvailability] answers, without holding back
  /// the stamp. The default status reads `disabled`, which `starting()`
  /// promotes to `ready`, so a write in that window would report a send from a
  /// device that may be signed out; `unknown` makes [apply] stamp and stop,
  /// and unlike `unavailable` does not claim that iCloud is signed out.
  void markAvailabilityUnknown() => _setStatus(status.value.copyWith(availability: PreferenceSyncAvailability.unknown));

  /// Re-read whether the engine can run at all: the toggle, then the transport.
  ///
  /// Separate from health on purpose. "iCloud is signed out" is not a failure
  /// of the last sync, and showing it as one would send the user looking for a
  /// problem in the app.
  Future<void> refreshAvailability() async {
    if (!_enabled()) {
      _setStatus(status.value.switchedOff());
      return;
    }
    final available = await _transport?.isAvailable() ?? false;
    _setStatus(
      status.value.copyWith(
        availability: available ? PreferenceSyncAvailability.ready : PreferenceSyncAvailability.unavailable,
      ),
    );
  }

  // ---- Remote to local ------------------------------------------------------

  void listen() {
    final transport = _transport;
    if (transport == null) return;
    _changeSub ??= transport.changes.listen((change) => unawaited(_onRemoteChange(change)));
  }

  Future<void> _onRemoteChange(RemotePreferenceChange change) async {
    if (!_enabled()) return;
    // Every other event is evidence of a live store. An account change is not:
    // it fires on sign-out too, so it re-checks availability instead of
    // claiming it, and a send cannot slip through while the check runs.
    if (change.reason != RemoteChangeReason.accountChanged) {
      _setStatus(status.value.sawRemoteChange(DateTime.now()));
    }
    switch (change.reason) {
      case RemoteChangeReason.quotaExceeded:
        appLogger.w('preference sync: transport quota exceeded');
        _setStatus(status.value.raise(PreferenceSyncHealth.quota));
      case RemoteChangeReason.accountChanged:
        _accountChangePending = true;
        // The account under the store changed, or went away. Re-ask whether
        // there is a store to talk to at all before deciding this is a sync:
        // signing out is not an error, and reporting it as one sends the user
        // looking for a problem in the app.
        await refreshAvailability();
        if (status.value.availability == PreferenceSyncAvailability.ready) {
          await requestReconcile(ReconcileTrigger.accountChanged);
        }
      case RemoteChangeReason.serverChange:
        if (change.changedKeys.isNotEmpty) await applyRemoteKeys(change.changedKeys);
      case RemoteChangeReason.initialSync:
        if (change.changedKeys.isNotEmpty) await applyRemoteKeys(change.changedKeys);
        await requestReconcile(ReconcileTrigger.initialSync);
    }
  }

  /// Drive the remote-event path without a stream. Test-only.
  @visibleForTesting
  Future<void> handleRemoteChange(RemotePreferenceChange change) => _onRemoteChange(change);

  /// Apply everything in the store. [proceed] is asked after the read; see
  /// [PreferenceReconciler.reconcile].
  Future<void> applyAllRemote({bool Function()? proceed, bool storeWins = false}) async {
    final all = await _transport?.readAll();
    if (proceed != null && !proceed()) return;
    if (all != null && all.isNotEmpty) await _remoteApply.applyEntries(all, storeWins: storeWins);
  }

  /// Apply the keys a remote event named. Queued behind a running reconcile.
  Future<void> applyRemoteKeys(List<String> keys) => _exclusively(() async {
    final generation = _turnGeneration;
    final all = await _transport?.readAll();
    // Timed out and answered after a newer turn ran: applying this snapshot
    // now, a key it lacks would remove a value that turn just wrote.
    if (generation != _turnGeneration) return;
    // null means the read failed. Absence only means "removed remotely" when
    // the read succeeded; inferring removals from a broken channel wipes local
    // settings on a transient error.
    if (all == null) return;
    await applyEntries({for (final k in keys) k: all[k]});
  });

  late final PreferenceRemoteApply _remoteApply = PreferenceRemoteApply(
    prefs: _prefs,
    revisionStore: _revisionStore,
    keys: _keys,
    transport: () => _transport,
    status: status,
    onChanged: (stale) {
      onLocalStateChanged?.call();
      onRemoteChangesApplied?.call();
      if (stale.isNotEmpty) onRuntimeRefresh?.call(stale);
    },
  );

  /// Apply transport entries to local prefs. A null value is a removal. See
  /// [PreferenceRemoteApply.applyEntries].
  Future<void> applyEntries(Map<String, String?> entries) => _remoteApply.applyEntries(entries);

  /// See [PreferenceKeyMapper.ownsCloudKey].
  bool ownsCloudKey(String cloudKey) => _keys.ownsCloudKey(cloudKey);

  /// Import unambiguously global v1 cloud values into v2, once. See
  /// [PreferenceRemoteApply.bootstrapFromLegacyV1].
  Future<void> bootstrapFromLegacyV1({bool Function()? proceed}) =>
      _remoteApply.bootstrapFromLegacyV1(proceed: proceed);

  // ---- Reconcile ------------------------------------------------------------

  /// See [PreferenceReconciler.metaVersionKey].
  static const String metaVersionKey = PreferenceReconciler.metaVersionKey;
  static const int formatVersion = PreferenceReconciler.formatVersion;

  /// See [PreferenceReconciler.v2MetaVersionKey].
  static const String v2MetaVersionKey = PreferenceReconciler.v2MetaVersionKey;
  static const int v2FormatVersion = PreferenceReconciler.v2FormatVersion;

  late final PreferenceReconciler _reconciler = PreferenceReconciler(
    prefs: _prefs,
    revisionStore: _revisionStore,
    keys: _keys,
    transport: () => _transport,
    status: status,
  );

  /// Read the format version the store was last written with.
  Future<int?> readFormatVersion() => _reconciler.readFormatVersion();

  /// Push every syncable local key whose stamp is newer than the store's, or
  /// which the store lacks; re-send tombstones the store has been written over.
  /// See [PreferenceReconciler.reconcile].
  Future<void> reconcile() => _reconciler.reconcile();

  Future<void> dispose() async {
    await _changeSub?.cancel();
    _changeSub = null;
    await _transport?.dispose();
    _transport = null;
  }

  // ---- Logging safety -------------------------------------------------------

  void _setStatus(PreferenceSyncStatus next) => status.value = next;

  /// Never log a preference key verbatim: per-library and per-server keys carry
  /// identifiers. The registered prefix is enough to debug with.
  static String _category(String baseKey) => preferenceLogCategory(baseKey);

  static String _errorCategory(Object e) => e.runtimeType.toString();
}
