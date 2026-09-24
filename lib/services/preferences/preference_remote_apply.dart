import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../settings_export_service.dart';
import 'preference_legacy_bootstrap.dart';
import 'preference_key_mapper.dart';
import 'preference_quarantine.dart';
import 'preference_refresh.dart';
import 'preference_revision_store.dart';
import 'preference_sync_policy.dart';
import 'preference_sync_scope.dart';
import 'preference_sync_status.dart';
import 'preference_transport.dart';

/// Remote to local: applies transport records to local prefs, and runs the
/// one-time v1 import. Knows nothing about scheduling; the coordinator decides
/// when a batch runs.
class PreferenceRemoteApply {
  PreferenceRemoteApply({
    required SharedPreferencesWithCache prefs,
    required PreferenceRevisionStore revisionStore,
    required PreferenceKeyMapper keys,
    required PreferenceTransport? Function() transport,
    required ValueNotifier<PreferenceSyncStatus> status,
    required void Function(Set<PreferenceRefreshFamily> stale) onChanged,
  }) : _prefs = prefs,
       _revisionStore = revisionStore,
       _keys = keys,
       _transport = transport,
       _status = status,
       _onChanged = onChanged;

  final SharedPreferencesWithCache _prefs;
  final PreferenceRevisionStore _revisionStore;
  final PreferenceKeyMapper _keys;
  final PreferenceTransport? Function() _transport;
  final ValueNotifier<PreferenceSyncStatus> _status;

  /// Called once a batch changed at least one value, with the runtime families
  /// it invalidated.
  final void Function(Set<PreferenceRefreshFamily> stale) _onChanged;

  void _setStatus(PreferenceSyncStatus next) => _status.value = next;

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
      if (_keys.v2Format && isLegacyV1Record(cloudKey)) {
        // A flat v1 key changing after the cutover means another device is
        // still writing that format. It is not merged into v2 under any
        // circumstances: v1 carries no revision, so there is no way to tell a
        // newer user action from an older snapshot of one. Surfaced, not
        // applied, and not deleted.
        _setStatus(_status.value.sawLegacyPeer());
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
      if (!_keys.v2Format && PreferenceSyncPolicyRegistry.isProfileScoped(baseKey)) {
        await PreferenceQuarantine.quarantine(
          _prefs,
          baseKey,
          reason: 'v1 cloud key carries no profile identity',
          seenAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        skipped++;
        continue;
      }

      final targetKey = _keys.localKeyFor(baseKey);
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
          at: PreferenceRevisionStore.legacyAt,
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
      final family = _keys.merges.familyFor(baseKey);
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
    _setStatus(_status.value.appliedRemote(DateTime.now(), changed: changed, skippedCount: skipped));
    if (changed > 0) _onChanged(stale);
  }

  /// The base key a transport record maps to, or null when it is not this
  /// device's business.
  ///
  /// Under v2 that includes the profile check: a record under another profile's
  /// namespace is not "unknown", it belongs to somebody else and is skipped.
  String? _baseKeyFromCloudKey(String cloudKey) {
    if (!_keys.v2Format) return cloudKey;
    final parsed = PreferenceSyncScope.parseCloudKey(cloudKey);
    if (parsed == null) return null;
    if (parsed.kind == PreferenceScopeKind.profile) {
      final active = _keys.activeProfileScope;
      if (active.id == null || active.id != parsed.id) return null;
    }
    return parsed.baseKey;
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

  /// Import unambiguously global v1 cloud values into v2, once.
  ///
  /// Only global ones. A profile-scoped v1 record has had its profile stripped
  /// by the format, so nobody can say whose it is; those are quarantined by
  /// [applyEntries] and stay there.
  ///
  /// Imported values carry [PreferenceRevisionStore.legacyAt], not the moment
  /// the import ran. A v1 value has no real change time, and stamping it with
  /// `now` would make whichever device upgraded last look like the most recent
  /// editor of every setting it touched. At zero, the first genuine change
  /// anywhere wins.
  ///
  /// Runs at most once per installation, and writes nothing back to v1.
  Future<void> bootstrapFromLegacyV1() async {
    if (!_keys.v2Format) return;
    final transport = _transport();
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

      final decoded = decodeTypedRecord(entry.value);
      if (decoded == null) continue;
      // Local value wins if there is one: this device already has an opinion.
      if (_prefs.get(key) == null) {
        final ok = await SettingsExportService.writeTyped(_prefs, key, decoded.$1, decoded.$2);
        if (!ok) continue;
      }
      await _revisionStore.bootstrapLegacy(key);
      imported++;
    }

    await PreferenceLegacyBootstrap.markComplete(_prefs);
    appLogger.i('preference sync: imported $imported legacy global values at the v2 cutover');
  }
}

/// A `{"type","value"}` record as `(type, value)`, or null when [raw] is not
/// one. Ignores any stamp.
(String, Object?)? decodeTypedRecord(String raw) {
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
