import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../settings_export_service.dart';
import '../track_preference_store.dart';
import 'preference_legacy_bootstrap.dart';
import 'preference_merge_strategies.dart';
import 'preference_mutation.dart';
import 'preference_quarantine.dart';
import 'preference_reconcile_scheduler.dart';
import 'preference_refresh.dart';
import 'preference_revision.dart';
import 'preference_revision_store.dart';
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
       _activeProfileId = activeProfileId,
       _enabled = enabled,
       _deviceId = deviceId,
       _isServerIdPortable = isServerIdPortable ?? noServerIdIsPortable,
       _useV2CloudFormat = useV2CloudFormat ?? v2CloudFormatEnabled,
       _transport = transport,
       onRemoteChangesApplied = onRemoteChangesApplied,
       onLocalStateChanged = onLocalStateChanged {
    _registerBuiltInMergeFamilies();
  }

  final SharedPreferencesWithCache _prefs;
  final String? Function() _activeProfileId;
  final bool Function() _enabled;
  final String _deviceId;

  /// Whether a server id identifies the same server on another device. Deny by
  /// default: without the connection layer wired in, nothing is portable.
  ///
  /// Late-bindable, because the answer comes from the connection registry and
  /// that only exists once the database is open, well after the engine starts.
  /// Until it is supplied nothing library-scoped travels, which is the right
  /// way round: a missing answer must not read as "yes".
  IsServerIdPortable _isServerIdPortable;

  set serverIdPortability(IsServerIdPortable predicate) => _isServerIdPortable = predicate;

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
  /// Off by design: the coordinator, the policy, the scope and the envelope all
  /// exist, but nothing writes a v2 record or deletes a v1 one until profile
  /// ownership and rolling-client safety have been signed off. Flipping this is
  /// the whole of that change.
  ///
  /// The two formats differ in more than the key shape, which is why the switch
  /// is readable per instance rather than only as a constant. Under v1 the
  /// cloud key carries no profile identity, so an incoming profile-scoped
  /// record cannot be applied at all: it goes to [PreferenceQuarantine] instead
  /// of being handed to whichever profile happens to be active. Under v2 the
  /// profile is in the key, so the same record applies normally.
  static const bool v2CloudFormatEnabled = true;

  final bool _useV2CloudFormat;

  /// This instance's format. Equals [v2CloudFormatEnabled] in the app; tests
  /// drive both sides.
  bool get usesV2CloudFormat => _useV2CloudFormat;

  // ---- Scope ----------------------------------------------------------------

  PreferenceSyncScope scopeFor(String baseKey) {
    final policy = PreferenceSyncPolicyRegistry.policyFor(baseKey);
    return switch (policy.scope) {
      PreferenceScopeKind.global => PreferenceSyncScope.global,
      PreferenceScopeKind.deviceLocal => PreferenceSyncScope.deviceLocal,
      PreferenceScopeKind.profile => PreferenceSyncScope.forProfile(_activeProfileId()),
    };
  }

  /// The active profile's scope identifier, the value `StorageService` uses for
  /// its `user_<scope>_` prefixes.
  String? get activeUserScope => PreferenceSyncScope.forProfile(_activeProfileId()).id;

  /// Full prefs key to the key it travels under, or null when it must not
  /// travel: unregistered, sensitive, device-local, another profile's, or a
  /// profile-scoped value with no portable profile behind it.
  String? cloudKeyFor(String fullKey) {
    final baseKey = baseKeyOf(fullKey);
    if (baseKey == null) return null;
    if (!PreferenceSyncPolicyRegistry.maySync(baseKey)) return null;
    if (!_keyIdentityIsPortable(baseKey)) return null;
    final scope = scopeFor(baseKey);
    if (!scope.portable) return null;
    return _useV2CloudFormat ? scope.cloudKey(baseKey) : baseKey;
  }

  /// Per-library families put the identity in the key
  /// (`library_sort_<serverId:libraryId>`), so there is nothing to filter out
  /// of the value: the key travels whole or not at all.
  bool _keyIdentityIsPortable(String baseKey) {
    for (final prefix in perLibraryKeyPrefixes) {
      if (baseKey.startsWith(prefix)) {
        return PreferenceValuePortability.isPortableScopedKey(baseKey, prefix, _isServerIdPortable);
      }
    }
    return true;
  }

  /// Families whose key carries a `serverId:libraryId`.
  static const List<String> perLibraryKeyPrefixes = [
    'library_filters_',
    'library_sort_',
    'library_grouping_',
    'library_tab_',
  ];

  /// The merge behaviour per family, looked up by the name in the policy.
  ///
  /// The coordinator never learns what a value means. It asks the registry
  /// whether this key's family has a merge and calls it. Before this there was
  /// one hardcoded `if` on a key list, which is why nothing else could ever
  /// need a merge.
  final PreferenceMergeRegistry _merges = PreferenceMergeRegistry();

  PreferenceMergeRegistry get mergeRegistry => _merges;

  void _registerBuiltInMergeFamilies() {
    // The closure reads the field rather than capturing it: the portability
    // predicate arrives from the connection registry after the engine starts.
    _merges.register(buildServerScopedListFamily((serverId) => _isServerIdPortable(serverId)));
    _merges.register(buildProgressMapFamily(watchedMap: false));
    _merges.register(buildProgressMapFamily(watchedMap: true));
    _merges.register(buildProfileKeyedMapFamily());
    _merges.register(TrackPreferenceStore.mergeFamily());
  }

  /// The value as it may leave the device, or null when nothing may.
  ///
  /// For a family with an outgoing merge this is where it runs. [remote] is the
  /// value currently in the store, when the caller could read it; null means
  /// "not available", and a family must then fall back to what it can decide on
  /// its own — for the server-scoped lists, dropping the entries whose server id
  /// is not portable. A device with one Plex server and one local folder still
  /// syncs its Plex choices; the folder's simply never leave.
  Object? portableValueFor(String baseKey, Object? value, {Object? remote}) {
    final outbound = _merges.familyFor(baseKey)?.outbound;
    if (outbound == null) return value;
    return outbound(value, remote);
  }

  /// Strip the active profile's prefix. Returns null for a key belonging to
  /// another profile, or for a reserved namespace.
  String? baseKeyOf(String fullKey) {
    for (final reserved in PreferenceSyncPolicyRegistry.reservedPrefixes) {
      if (fullKey.startsWith(reserved)) return null;
    }
    final scope = PreferenceSyncScope.forProfile(_activeProfileId());
    final prefix = scope.localPrefix;
    if (prefix.isNotEmpty && fullKey.startsWith(prefix)) return fullKey.substring(prefix.length);
    if (fullKey.startsWith(SettingsExportService.userPrefixRoot)) return null;
    return fullKey;
  }

  /// Inverse of [baseKeyOf] for a base key that arrived from a transport.
  String? localKeyFor(String baseKey) {
    if (!PreferenceSyncPolicyRegistry.isProfileScoped(baseKey)) return baseKey;
    final scope = PreferenceSyncScope.forProfile(_activeProfileId());
    if (scope.id == null) return null;
    return '${scope.localPrefix}$baseKey';
  }

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

    final baseKey = baseKeyOf(mutation.key);
    if (baseKey == null) return;

    // Stamped before any gate that holds the send back. An unstamped local
    // value loses to every stamped remote record (see [remoteStampWins]), so a
    // user's write that skipped the stamp would be overwritten by the next
    // remote batch, however old that batch is.
    if (mutation.stampsUserChange) {
      _revisionStore.stampUserChange(baseKey, removed: mutation.operation == PreferenceOperation.remove);
    }

    if (!_enabled()) return;
    final transport = _transport;
    if (transport == null) return;
    if (status.value.availability == PreferenceSyncAvailability.unavailable) {
      // Signed out. The change is stamped above, so the first reconcile after
      // signing back in carries it; writing now would only produce a "last
      // sent" time for a value that went nowhere.
      return;
    }

    final cloudKey = cloudKeyFor(mutation.key);
    if (cloudKey == null) return;

    _setStatus(status.value.starting(DateTime.now()));
    try {
      if (mutation.operation == PreferenceOperation.remove) {
        // A removal is a first-class change. v1 lost it here: the hook only had
        // a key, read `null` back, and stopped. Since DEC-131 it travels as a
        // tombstone rather than as an absent key, so the other device can tell
        // "deleted" from "never had it".
        await transport.write(cloudKey, encodeTombstone(_revisionStore.stampOf(baseKey)));
        _setStatus(status.value.writeSucceeded(DateTime.now()));
        return;
      }

      // A family with an outgoing merge needs to see what is in the store
      // before it decides what to send. A failed read is not an empty store, so
      // the write is held back rather than pushed over entries this device
      // cannot account for.
      Object? remoteValue;
      if (_merges.familyFor(baseKey)?.mergesOutgoing ?? false) {
        final all = await transport.readAll();
        if (all == null) {
          _setStatus(status.value.countingSkipped(1).raise(PreferenceSyncHealth.warning));
          appLogger.w('preference sync: held back ${_category(baseKey)}, the store could not be read');
          return;
        }
        final record = all[cloudKey];
        remoteValue = record == null ? null : _decodeTyped(record)?.$2;
      }

      final portableValue = portableValueFor(baseKey, mutation.value, remote: remoteValue);
      if (portableValue == null) {
        // Everything in this list belongs to a non-portable backend. Nothing to
        // send, and nothing to delete either: the cloud copy belongs to the
        // other devices' entries.
        _setStatus(status.value.countingSkipped(1));
        return;
      }
      final entry = SettingsExportService.encodeValue(portableValue);
      if (entry == null) {
        _setStatus(status.value.countingSkipped(1));
        return;
      }
      final encoded = encodeStampedRecord(entry, _revisionStore.stampOf(baseKey));
      final cap = transport.maxValueBytes;
      if (cap != null && encoded.length > cap) {
        // Oversize is reported, not swallowed. It also must not become a
        // removal: leaving the older cloud value in place is strictly better
        // than deleting it because the newer one did not fit.
        appLogger.w('preference sync: value for ${_category(baseKey)} exceeds the transport cap');
        _setStatus(status.value.copyWith(oversize: status.value.oversize + 1).raise(PreferenceSyncHealth.warning));
        return;
      }
      await transport.write(cloudKey, encoded);
      _setStatus(status.value.writeSucceeded(DateTime.now()));
    } catch (e) {
      _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: _errorCategory(e)));
      appLogger.w('preference sync: transport write failed for ${_category(baseKey)}');
    }
  }

  // ---- Conflict metadata ----------------------------------------------------

  /// See [PreferenceRevisionStore.storeKey].
  static const String revisionStoreKey = PreferenceRevisionStore.storeKey;

  /// See [PreferenceRevisionStore.legacyAt].
  static const int legacyRevisionAt = PreferenceRevisionStore.legacyAt;

  late final PreferenceRevisionStore _revisionStore = PreferenceRevisionStore(_prefs, _deviceId);

  /// Record a revision for a value that was already present, without pretending
  /// the user just chose it. Idempotent.
  Future<void> bootstrapLegacyRevision(String baseKey) => _revisionStore.bootstrapLegacy(baseKey);

  /// The last deliberate local change to [baseKey], or null when this device
  /// never made one. This is the half of [PreferenceRevision] that has to be
  /// kept locally so a remote snapshot has something to be compared against.
  PreferenceRevision? localRevision(String baseKey) {
    final entry = _revisionStore.all()[baseKey];
    if (entry is! Map) return null;
    final at = entry['t'];
    final device = entry['d'];
    if (at is! int || device is! String) return null;
    final deleted = entry['x'] == true;
    final localKey = localKeyFor(baseKey);
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
          _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: 'timeout'));
          appLogger.w('preference sync: a sync turn did not finish in time');
        },
      );
    });
    _turn = run.catchError((Object _) {});
    return run;
  }

  /// Bumped when a turn starts. A turn that timed out and answers late sees a
  /// newer number and knows its snapshot is stale.
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
  Future<void> _runReconcile(Set<ReconcileTrigger> triggers) async {
    // One gate for every trigger. `disabled` means the toggle is off (no
    // channel call is made to find that out), `unavailable` means nobody is
    // signed in, and the store may have gone away while we were suspended. In
    // each case the status has to say so before this pass pretends to have
    // sent anything. The enable path writes the toggle first, and import and
    // reset only call in through `pushAllIfEnabled`.
    await refreshAvailability();
    if (status.value.availability != PreferenceSyncAvailability.ready) return;
    if (triggers.contains(ReconcileTrigger.accountChanged)) {
      // The stamps describe this device's edits against the previous account's
      // history. Against another account they mean nothing, and keeping them
      // would push the old account's values into the new one as "newer".
      // Local values stay; the store is read first and wins what it holds.
      await clearRevisions();
      await PreferenceLegacyBootstrap.reset(_prefs);
    }
    final needsBootstrap =
        triggers.contains(ReconcileTrigger.boot) ||
        triggers.contains(ReconcileTrigger.enabled) ||
        triggers.contains(ReconcileTrigger.accountChanged);
    final localIsTheSource = triggers.every((t) => t == ReconcileTrigger.imported || t == ReconcileTrigger.reset);

    if (needsBootstrap) await bootstrapFromLegacyV1();
    if (!localIsTheSource) await applyAllRemote();
    await reconcile();
  }

  // ---- Availability ---------------------------------------------------------

  /// Hold every send until [refreshAvailability] answers, without holding back
  /// the stamp. The default status reads `disabled`, which `starting()`
  /// promotes to `ready`, so a write in that window would report a send from a
  /// device that may be signed out; `unavailable` makes [apply] stamp and stop.
  void markAvailabilityUnknown() =>
      _setStatus(status.value.copyWith(availability: PreferenceSyncAvailability.unavailable));

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

  Future<void> applyAllRemote() async {
    final all = await _transport?.readAll();
    if (all != null && all.isNotEmpty) await applyEntries(all);
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

  /// Apply transport entries to local prefs. A null value is a removal.
  Future<void> applyEntries(Map<String, String?> entries) async {
    var changed = 0;
    var skipped = 0;
    final stale = <PreferenceRefreshFamily>{};
    for (final entry in entries.entries) {
      final cloudKey = entry.key;
      if (cloudKey.startsWith('__') && !PreferenceSyncScope.ownsCloudKey(cloudKey)) {
        continue; // transport meta, another feature, or a format we do not read
      }
      if (_useV2CloudFormat && isLegacyV1Record(cloudKey)) {
        // A flat v1 key changing after the cutover means another device is
        // still writing that format. It is not merged into v2 under any
        // circumstances: v1 carries no revision, so there is no way to tell a
        // newer user action from an older snapshot of one. Surfaced, not
        // applied, and not deleted.
        _setStatus(status.value.sawLegacyPeer());
        // A profile-scoped one is also permanently unattributable, so it keeps
        // its quarantine record and the removal condition that goes with it.
        if (PreferenceSyncPolicyRegistry.isProfileScoped(cloudKey)) {
          await PreferenceQuarantine.quarantine(
            _prefs,
            cloudKey,
            reason: 'v1 cloud key carries no profile identity',
            seenAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          );
        }
        skipped++;
        continue;
      }
      final baseKey = _baseKeyFromCloudKey(cloudKey);
      if (baseKey == null) {
        skipped++;
        continue; // malformed, or a record for another profile
      }
      if (!PreferenceSyncPolicyRegistry.maySync(baseKey)) {
        skipped++;
        continue;
      }
      // A v1 record for a profile-scoped key carries no profile identity: the
      // format stripped it. Handing it to whichever profile is active would
      // make the existing collision permanent, so it is recorded and left.
      if (!_useV2CloudFormat && PreferenceSyncPolicyRegistry.isProfileScoped(baseKey)) {
        await PreferenceQuarantine.quarantine(
          _prefs,
          baseKey,
          reason: 'v1 cloud key carries no profile identity',
          seenAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        skipped++;
        continue;
      }

      final targetKey = localKeyFor(baseKey);
      if (targetKey == null) {
        skipped++;
        continue; // profile-scoped with no active profile to scope to
      }

      final refresh = PreferenceSyncPolicyRegistry.policyFor(baseKey).refresh;

      final raw = entry.value;
      if (raw == null) {
        // Named in the event, gone from the store: the previous build's
        // `transport.remove`. It carries no stamp, so it is honoured as it
        // always was. This build never removes; it writes a tombstone.
        await _prefs.remove(targetKey);
        // The stamp goes back to "unstamped, removed". Keeping the live stamp
        // would make this device skip every later record stamped below it
        // and leave the key empty for good.
        await _revisionStore.adopt(baseKey, (
          at: legacyRevisionAt,
          device: PreferenceRevisionStore.noDevice,
          deleted: true,
        ));
        changed++;
        if (refresh != null) stale.add(refresh);
        continue;
      }
      final record = decodeStampedRecord(raw);
      if (record == null) {
        skipped++;
        continue;
      }
      final family = _merges.familyFor(baseKey);
      final local = _revisionStore.stampOf(baseKey);
      // A value in a merge family is merged, whatever its stamp. A tombstone
      // on either side is not a value to merge: an incoming one has to be
      // newer than this device's change, and a live record has to be newer
      // than this device's own removal, or the two flip back and forth.
      final stampDecides = family == null || record.stamp.deleted || local.deleted;
      if (stampDecides && !remoteStampWins(record.stamp, local)) {
        skipped++;
        continue; // this device's change is newer, or the same
      }
      if (record.stamp.deleted) {
        final current = _prefs.get(targetKey);
        // The family keeps what the sender could never have removed, such as
        // this device's local-folder libraries.
        final kept = current == null ? null : family?.removed?.call(current);
        final typed = kept == null ? null : SettingsExportService.encodeValue(kept);
        if (typed != null && kept != current) {
          if (await SettingsExportService.writeTyped(_prefs, targetKey, typed['type'] as String, typed['value'])) {
            changed++;
            if (refresh != null) stale.add(refresh);
          }
        } else if (typed == null && current != null) {
          await _prefs.remove(targetKey);
          changed++;
          if (refresh != null) stale.add(refresh);
        }
        await _revisionStore.adopt(baseKey, record.stamp);
        continue;
      }
      var value = record.value;
      final inbound = family?.inbound;
      if (inbound != null) {
        // Not a replacement. What the family does with the two sides is the
        // family's business; for the server-scoped lists it keeps what the
        // sender never saw, because treating that absence as a removal would
        // wipe this device's local-folder libraries on every remote change.
        value = inbound(_prefs.get(targetKey), value);
      }
      final ok = await SettingsExportService.writeTyped(_prefs, targetKey, record.type, value);
      if (ok) {
        changed++;
        if (refresh != null) stale.add(refresh);
        if (stampDecides) await _revisionStore.adopt(baseKey, record.stamp);
      } else {
        skipped++;
      }
    }
    _setStatus(status.value.appliedRemote(DateTime.now(), changed: changed, skippedCount: skipped));
    if (changed > 0) {
      onLocalStateChanged?.call();
      onRemoteChangesApplied?.call();
      if (stale.isNotEmpty) onRuntimeRefresh?.call(stale);
    }
  }

  /// The base key a transport record maps to, or null when it is not this
  /// device's business.
  ///
  /// Under v2 that includes the profile check: a record under another profile's
  /// namespace is not "unknown", it belongs to somebody else and is skipped.
  String? _baseKeyFromCloudKey(String cloudKey) {
    if (!_useV2CloudFormat) return cloudKey;
    final parsed = PreferenceSyncScope.parseCloudKey(cloudKey);
    if (parsed == null) return null;
    if (parsed.kind == PreferenceScopeKind.profile) {
      final active = PreferenceSyncScope.forProfile(_activeProfileId());
      if (active.id == null || active.id != parsed.id) return null;
    }
    return parsed.baseKey;
  }

  (String, Object?)? _decodeTyped(String raw) {
    try {
      final m = json.decode(raw);
      if (m is! Map) return null;
      final type = m['type'];
      if (type is! String) return null;
      return (type, m['value']);
    } catch (_) {
      return null;
    }
  }

  /// Whether [cloudKey] is a v1 preference record: a flat key, outside every
  /// `__` namespace, that the registry recognises as a preference.
  ///
  /// The registry check matters. Without it any unknown flat key would be read
  /// as "an old Pleya is running", and the warning would fire on somebody
  /// else's data.
  static bool isLegacyV1Record(String cloudKey) {
    if (cloudKey.startsWith('__')) return false;
    return PreferenceSyncPolicyRegistry.isRegistered(cloudKey);
  }

  /// Whether a transport key is a record this coordinator, in its current
  /// format, is entitled to delete.
  ///
  /// Under v2 the answer is always no. A removal travels as a tombstone since
  /// DEC-131, so a record this device does not hold is one it has not seen
  /// yet, never one it deleted. The v1 path keeps a prune for the
  /// rolling-upgrade test. That path is not the released v1 algorithm any
  /// more: it writes stamped records and compares before it writes.
  bool ownsCloudKey(String cloudKey) {
    if (_useV2CloudFormat) return false;
    if (cloudKey.startsWith('__')) return false;
    return PreferenceSyncPolicyRegistry.maySync(cloudKey);
  }

  /// Import unambiguously global v1 cloud values into v2, once.
  ///
  /// Only global ones. A profile-scoped v1 record has had its profile stripped
  /// by the format, so nobody can say whose it is; those are quarantined by
  /// [applyEntries] and stay there.
  ///
  /// Imported values carry [legacyRevisionAt], not the moment the import ran.
  /// A v1 value has no real change time, and stamping it with `now` would make
  /// whichever device upgraded last look like the most recent editor of every
  /// setting it touched. At zero, the first genuine change anywhere wins.
  ///
  /// Runs at most once per installation, and writes nothing back to v1.
  Future<void> bootstrapFromLegacyV1() async {
    if (!_useV2CloudFormat) return;
    final transport = _transport;
    if (transport == null) return;
    if (PreferenceLegacyBootstrap.hasRun(_prefs)) return;

    final all = await transport.readAll();
    // A failed read is not an empty store. Leaving the marker unset means the
    // import simply tries again next time, which is the safe direction.
    if (all == null) return;

    var imported = 0;
    for (final entry in all.entries) {
      final key = entry.key;
      if (!isLegacyV1Record(key)) continue;
      final policy = PreferenceSyncPolicyRegistry.policyFor(key);
      if (!policy.maySync) continue;
      if (policy.scope != PreferenceScopeKind.global) continue; // ambiguous, stays quarantined

      final decoded = _decodeTyped(entry.value);
      if (decoded == null) continue;
      // Local value wins if there is one: this device already has an opinion.
      if (_prefs.get(key) == null) {
        final ok = await SettingsExportService.writeTyped(_prefs, key, decoded.$1, decoded.$2);
        if (!ok) continue;
      }
      await bootstrapLegacyRevision(key);
      imported++;
    }

    await PreferenceLegacyBootstrap.markComplete(_prefs);
    appLogger.i('preference sync: imported $imported legacy global values at the v2 cutover');
  }

  // ---- Reconcile ------------------------------------------------------------

  /// The v1 meta key. Read, never written after the cutover: it belongs to the
  /// frozen v1 state, and older clients still maintain it among themselves.
  static const String metaVersionKey = '__syncFormatVersion';
  static const int formatVersion = 1;

  /// The v2 marker, inside the namespace this coordinator owns.
  static const String v2MetaVersionKey = '${PreferenceSyncScope.cloudNamespacePrefix}__meta/formatVersion';
  static const int v2FormatVersion = 2;

  String get _activeMetaKey => _useV2CloudFormat ? v2MetaVersionKey : metaVersionKey;
  int get _activeFormatVersion => _useV2CloudFormat ? v2FormatVersion : formatVersion;

  /// Read the format version the store was last written with. v1 wrote this and
  /// never read it, which left no way to recognise a store from a newer client.
  Future<int?> readFormatVersion() async {
    final all = await _transport?.readAll();
    if (all == null) return null;
    final raw = all[_activeMetaKey];
    if (raw == null) return null;
    final decoded = _decodeTyped(raw);
    final value = decoded?.$2;
    return value is int ? value : null;
  }

  /// Push every syncable local key whose stamp is newer than the store's, or
  /// which the store lacks; re-send tombstones the store has been written over.
  Future<void> reconcile() async {
    final transport = _transport;
    if (transport == null) return;
    _setStatus(status.value.starting(DateTime.now()));

    try {
      // The store is read before anything is written. A failed read is not an
      // empty store, and without it nothing can be compared: pushing blind
      // could put an older value over a newer one whose author is no longer
      // around to put it back. Nothing is sent; the next trigger tries again.
      final remote = await transport.readAll();
      if (remote == null) {
        _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: 'readFailed'));
        appLogger.w('preference sync: reconcile held back, the store could not be read');
        return;
      }

      var pushed = 0;
      var skipped = 0;
      var oversize = 0;
      final known = <String>{};
      for (final fullKey in _prefs.keys) {
        final baseKey = baseKeyOf(fullKey);
        if (baseKey != null) known.add(baseKey);
        final cloudKey = cloudKeyFor(fullKey);
        if (cloudKey == null || baseKey == null) continue;
        final local = _revisionStore.stampOf(baseKey);
        // A value held under a removal stamp (a family's local-only entries)
        // is not a change of its own; sending it would carry the tombstone's
        // stamp on a live record. A legacy removal (the old build's bare
        // remove, stamp 0) orders nothing, so a value under it counts as
        // unstamped and travels like one.
        if (local.deleted && local.at != legacyRevisionAt) continue;
        final family = _merges.familyFor(baseKey);
        final raw = remote[cloudKey];
        final record = raw == null ? null : decodeStampedRecord(raw);
        final portableValue = portableValueFor(baseKey, _prefs.get(fullKey), remote: record?.value);
        if (portableValue == null) {
          skipped++;
          continue;
        }
        final entry = SettingsExportService.encodeValue(portableValue);
        if (entry == null) {
          skipped++;
          continue;
        }
        final encoded = encodeStampedRecord(entry, local);
        final cap = transport.maxValueBytes;
        if (cap != null && encoded.length > cap) {
          oversize++;
          continue;
        }
        if (record != null) {
          if (family == null) {
            // Last-writer-wins: only a strictly newer local change travels. An
            // equal stamp means the same value; an older one lost already.
            if (remoteStampWins(record.stamp, local) || sameStamp(record.stamp, local)) continue;
          } else if (json.encode(record.value) == json.encode(entry['value'])) {
            continue; // the merged value is already what the store holds
          }
        }
        await transport.write(cloudKey, encoded);
        pushed++;
      }

      // Tombstones this device holds, re-sent where the store still carries an
      // older live record: the previous build writes its values back over them.
      for (final e in _revisionStore.all().entries) {
        final meta = e.value;
        if (meta is! Map || meta['x'] != true) continue;
        final localKey = localKeyFor(e.key);
        if (localKey == null) continue;
        final cloudKey = cloudKeyFor(localKey);
        if (cloudKey == null) continue;
        final raw = remote[cloudKey];
        if (raw == null) continue;
        final record = decodeStampedRecord(raw);
        if (record == null || record.stamp.deleted) continue;
        final local = _revisionStore.stampOf(e.key);
        if (remoteStampWins(record.stamp, local)) continue;
        await transport.write(cloudKey, encodeTombstone(local));
        pushed++;
      }

      final metaRecord = json.encode({'type': 'int', 'value': _activeFormatVersion});
      if (remote[_activeMetaKey] != metaRecord) {
        await transport.write(_activeMetaKey, metaRecord);
      }

      if (!_useV2CloudFormat) {
        // The v1 prune, kept for the rolling-upgrade test only. It deletes what
        // is genuinely gone locally and leaves what is present but no longer
        // eligible, so an older client that still syncs the key keeps it.
        final scope = PreferenceSyncScope.forProfile(_activeProfileId());
        for (final k in remote.keys) {
          if (!ownsCloudKey(k)) continue;
          if (known.contains(k)) continue;
          if (scope.id == null && PreferenceSyncPolicyRegistry.isProfileScoped(k)) continue;
          await transport.remove(k);
        }
      }
      await transport.flush();
      _setStatus(
        status.value.reconcileSucceeded(
          DateTime.now(),
          pushedCount: pushed,
          skippedCount: skipped,
          oversizeCount: oversize,
        ),
      );
    } catch (e) {
      _setStatus(status.value.raise(PreferenceSyncHealth.error, errorCategory: _errorCategory(e)));
      appLogger.w('preference sync: reconcile failed (${_errorCategory(e)})');
    }
  }

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
  static String _category(String baseKey) {
    for (final prefix in PreferenceSyncPolicyRegistry.registeredPrefixes) {
      if (baseKey.startsWith(prefix)) return '$prefix*';
    }
    return PreferenceSyncPolicyRegistry.isRegistered(baseKey) ? baseKey : 'unregistered';
  }

  static String _errorCategory(Object e) => e.runtimeType.toString();
}
