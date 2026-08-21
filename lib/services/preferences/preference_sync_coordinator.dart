import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../settings_export_service.dart';
import 'preference_legacy_bootstrap.dart';
import 'preference_merge_strategies.dart';
import 'preference_mutation.dart';
import 'preference_quarantine.dart';
import 'preference_reconcile_scheduler.dart';
import 'preference_refresh.dart';
import 'preference_revision.dart';
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
/// The wire format is still v1 while the cloud-content migration waits for its
/// own checkpoint: cloud keys are export base keys and values are the bare
/// typed markers. [PreferenceRevision] and [PreferenceSyncScope.cloudKey] are
/// built and tested, and go live together in A6, under the `__` namespace an
/// older client provably leaves alone.
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

  /// Guards the remote-apply window. Remote writes go straight to `prefs`, so
  /// they cannot echo by construction; this is the second lock on the door.
  bool _applyingRemote = false;

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
    if (_applyingRemote && mutation.source == PreferenceSource.local) {
      // A local write landing inside a remote-apply window is not an echo, but
      // ordering it against the batch we are mid-way through is not worth the
      // complexity: let the reconcile that follows pick it up.
      return;
    }
    if (!mutation.mayTravel) return;

    final baseKey = baseKeyOf(mutation.key);
    if (baseKey == null) return;

    if (mutation.stampsUserChange) _stampRevision(baseKey, mutation);

    if (!_enabled()) return;
    final transport = _transport;
    if (transport == null) return;

    final cloudKey = cloudKeyFor(mutation.key);
    if (cloudKey == null) return;

    _setStatus(status.value.starting(DateTime.now()));
    try {
      if (mutation.operation == PreferenceOperation.remove) {
        // A removal is a first-class change. v1 lost it here: the hook only had
        // a key, read `null` back, and stopped.
        await transport.remove(cloudKey);
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
      final encoded = json.encode(entry);
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

  /// Key holding this device's per-preference revision metadata. Registered as
  /// runtime cache, so it never syncs: it describes this device's edits.
  static const String revisionStoreKey = 'pleya_pref_revisions_v1';

  Map<String, dynamic> _revisions() {
    final raw = _prefs.getString(revisionStoreKey);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  /// The revision a value carries when it was not written by a user but found
  /// already there: a v1 cloud value adopted at upgrade, or a local value that
  /// predates the revision store.
  ///
  /// Zero, not `now()`. A migrated value has no real change time, and stamping
  /// it with the moment the migration happened to run would make the last
  /// device to upgrade look like the most recent editor of every setting it
  /// touched. At zero, the first genuine change on any device wins.
  static const int legacyRevisionAt = 0;

  void _stampRevision(String baseKey, PreferenceMutation mutation) {
    if (!PreferenceSyncPolicyRegistry.maySync(baseKey)) return;
    final revisions = _revisions();
    revisions[baseKey] = {
      't': _nextRevisionTimestamp(baseKey, revisions),
      'd': _deviceId,
      if (mutation.operation == PreferenceOperation.remove) 'x': true,
    };
    unawaited(_prefs.setString(revisionStoreKey, json.encode(revisions)));
  }

  /// A timestamp that never goes backwards on this device.
  ///
  /// Cross-device clock skew is a real limit of client-side last-writer-wins
  /// and this does not fix it. What it does fix is the local case: set the
  /// clock back an hour, change a setting, and without this the new value would
  /// carry a revision below its own predecessor, so the *older* value would win
  /// on the very device that just replaced it. One millisecond past the last
  /// revision is enough to keep the local sequence honest.
  int _nextRevisionTimestamp(String baseKey, Map<String, dynamic> revisions) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final previous = revisions[baseKey];
    final previousAt = previous is Map ? previous['t'] : null;
    if (previousAt is! int) return now;
    return now > previousAt ? now : previousAt + 1;
  }

  /// Record a revision for a value that was already present, without pretending
  /// the user just chose it. Idempotent: an existing revision is never
  /// downgraded to the legacy one.
  Future<void> bootstrapLegacyRevision(String baseKey) async {
    if (!PreferenceSyncPolicyRegistry.maySync(baseKey)) return;
    final revisions = _revisions();
    if (revisions.containsKey(baseKey)) return;
    revisions[baseKey] = {'t': legacyRevisionAt, 'd': _deviceId};
    await _prefs.setString(revisionStoreKey, json.encode(revisions));
  }

  /// The last deliberate local change to [baseKey], or null when this device
  /// never made one. This is the half of [PreferenceRevision] that has to be
  /// kept locally so a remote snapshot has something to be compared against.
  PreferenceRevision? localRevision(String baseKey) {
    final entry = _revisions()[baseKey];
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

  @visibleForTesting
  void debugClearRevisions() => unawaited(_prefs.remove(revisionStoreKey));

  // ---- Reconciliation lifecycle ---------------------------------------------

  late final PreferenceReconcileScheduler _scheduler = PreferenceReconcileScheduler(
    run: _runReconcile,
    onError: (e) => appLogger.w('preference sync: reconcile failed (${_errorCategory(e)})'),
  );

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
    // An ambient trigger fires whether or not anybody asked for sync, so it is
    // gated here. The explicit ones come from a caller that already decided:
    // the enable path is what turns the toggle on, and import and reset are
    // deliberate bulk acts.
    const ambient = {ReconcileTrigger.foreground, ReconcileTrigger.accountChanged, ReconcileTrigger.profileChanged};
    if (triggers.every(ambient.contains) && !_enabled()) return;
    final needsBootstrap = triggers.contains(ReconcileTrigger.boot) || triggers.contains(ReconcileTrigger.enabled);
    final localIsTheSource = triggers.every((t) => t == ReconcileTrigger.imported || t == ReconcileTrigger.reset);

    if (needsBootstrap) await bootstrapFromLegacyV1();
    if (!localIsTheSource) await applyAllRemote();
    await reconcile();
  }

  // ---- Availability ---------------------------------------------------------

  /// Re-read whether the engine can run at all: the toggle, then the transport.
  ///
  /// Separate from health on purpose. "iCloud is signed out" is not a failure
  /// of the last sync, and showing it as one would send the user looking for a
  /// problem in the app.
  Future<void> refreshAvailability() async {
    if (!_enabled()) {
      _setStatus(status.value.copyWith(availability: PreferenceSyncAvailability.disabled));
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
    _setStatus(status.value.sawRemoteChange(DateTime.now()));
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
      case RemoteChangeReason.initialSync:
        if (change.changedKeys.isNotEmpty) await applyRemoteKeys(change.changedKeys);
    }
  }

  Future<void> applyAllRemote() async {
    final all = await _transport?.readAll();
    if (all != null && all.isNotEmpty) await applyEntries(all);
  }

  Future<void> applyRemoteKeys(List<String> keys) async {
    final all = await _transport?.readAll();
    // null means the read failed. Absence only means "removed remotely" when
    // the read succeeded; inferring removals from a broken channel wipes local
    // settings on a transient error.
    if (all == null) return;
    await applyEntries({for (final k in keys) k: all[k]});
  }

  /// Apply transport entries to local prefs. A null value is a removal.
  Future<void> applyEntries(Map<String, String?> entries) async {
    _applyingRemote = true;
    var changed = 0;
    var skipped = 0;
    final stale = <PreferenceRefreshFamily>{};
    try {
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

        final family = PreferenceSyncPolicyRegistry.policyFor(baseKey).refresh;

        final raw = entry.value;
        if (raw == null) {
          await _prefs.remove(targetKey);
          changed++;
          if (family != null) stale.add(family);
          continue;
        }
        final decoded = _decodeTyped(raw);
        if (decoded == null) {
          skipped++;
          continue;
        }
        var value = decoded.$2;
        final inbound = _merges.familyFor(baseKey)?.inbound;
        if (inbound != null) {
          // Not a replacement. What the family does with the two sides is the
          // family's business; for the server-scoped lists it keeps what the
          // sender never saw, because treating that absence as a removal would
          // wipe this device's local-folder libraries on every remote change.
          value = inbound(_prefs.get(targetKey), value);
        }
        final ok = await SettingsExportService.writeTyped(_prefs, targetKey, decoded.$1, value);
        if (ok) {
          changed++;
          if (family != null) stale.add(family);
        } else {
          skipped++;
        }
      }
    } finally {
      _applyingRemote = false;
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
  /// Deliberately narrower than "not obviously somebody else's". The prune is
  /// the only destructive operation in the engine, so it works from a positive
  /// claim of ownership: in v2 that is the coordinator's own namespace, and in
  /// v1 it is a flat key the registry recognises as a syncable preference. A
  /// key from another feature, a future format, an older Pleya, or simply one
  /// nobody registered is left alone. Cloud junk is cheaper than deleting
  /// somebody's data.
  bool ownsCloudKey(String cloudKey) {
    if (_useV2CloudFormat) {
      // Namespace alone is not ownership: another profile's record lives in the
      // same namespace and is emphatically not ours to delete. The scope has to
      // match too, which is what `_baseKeyFromCloudKey` checks.
      return _baseKeyFromCloudKey(cloudKey) != null;
    }
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

  /// Push every syncable local key and drop transport keys that no longer exist
  /// locally, so removals and a settings reset propagate.
  Future<void> reconcile() async {
    final transport = _transport;
    if (transport == null) return;
    _setStatus(status.value.starting(DateTime.now()));

    try {
      // The store is read before anything is written. A family with an outgoing
      // merge cannot decide what to send without seeing what is already there,
      // and the prune works from the same snapshot. A failed read is not an
      // empty store: everything that can decide on its own is still pushed, and
      // nothing is deleted.
      final remote = await transport.readAll();

      final eligible = <String, String>{};
      final oversize = <String>{};
      // Every base key this device holds, syncable or not. The prune deletes
      // what is genuinely gone locally, never what merely stopped being
      // eligible. Without that distinction, tightening the policy (or simply
      // forgetting to register a preference) would delete other devices' copies
      // instead of leaving them alone, and an older client that still syncs the
      // key would lose it outright.
      final known = <String>{};
      var skipped = 0;
      for (final fullKey in _prefs.keys) {
        final baseKey = baseKeyOf(fullKey);
        if (baseKey != null) known.add(baseKey);
        final cloudKey = cloudKeyFor(fullKey);
        if (cloudKey == null || baseKey == null) continue;
        if ((_merges.familyFor(baseKey)?.mergesOutgoing ?? false) && remote == null) {
          // Merging blind would push over entries this device cannot account
          // for. Held back from the push, and from the prune with it.
          skipped++;
          continue;
        }
        final record = remote?[cloudKey];
        final portableValue = portableValueFor(
          baseKey,
          _prefs.get(fullKey),
          remote: record == null ? null : _decodeTyped(record)?.$2,
        );
        if (portableValue == null) {
          skipped++;
          continue;
        }
        final entry = SettingsExportService.encodeValue(portableValue);
        if (entry == null) {
          skipped++;
          continue;
        }
        final encoded = json.encode(entry);
        final cap = transport.maxValueBytes;
        if (cap != null && encoded.length > cap) {
          // Oversize keys are held back from the push AND from the prune. v1
          // pruned on absence from this map, so a value that grew past the cap
          // was deleted from the cloud rather than skipped.
          oversize.add(cloudKey);
          continue;
        }
        eligible[cloudKey] = encoded;
      }

      await transport.write(_activeMetaKey, json.encode({'type': 'int', 'value': _activeFormatVersion}));
      for (final e in eligible.entries) {
        await transport.write(e.key, e.value);
      }

      if (remote != null) {
        final scope = PreferenceSyncScope.forProfile(_activeProfileId());
        for (final k in remote.keys) {
          if (!ownsCloudKey(k)) continue; // another format, another feature, or unknown
          if (eligible.containsKey(k)) continue;
          if (oversize.contains(k)) continue;
          // The comparison is on base keys. Under v2 a cloud key is namespaced
          // and a local key is not, so comparing the two directly never matched
          // and the "present locally, just not eligible" protection quietly did
          // nothing: a list that held only local-folder entries was pushed by
          // nobody and deleted from the store on the next reconcile.
          final baseKey = _baseKeyFromCloudKey(k);
          if (baseKey == null) continue;
          if (known.contains(baseKey)) continue;
          // With no profile behind it, a profile-scoped cloud key belongs to
          // somebody else. Absent locally means "not mine", not "deleted".
          if (scope.id == null && PreferenceSyncPolicyRegistry.isProfileScoped(baseKey)) continue;
          await transport.remove(k);
        }
      }
      await transport.flush();
      _setStatus(
        status.value.reconcileSucceeded(
          DateTime.now(),
          pushedCount: eligible.length,
          skippedCount: skipped,
          oversizeCount: oversize.length,
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
