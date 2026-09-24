import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../settings_export_service.dart';
import 'preference_key_mapper.dart';
import 'preference_remote_apply.dart';
import 'preference_revision_store.dart';
import 'preference_sync_policy.dart';
import 'preference_sync_scope.dart';
import 'preference_sync_status.dart';
import 'preference_transport.dart';

/// Local to remote in bulk: compares every syncable local key against one
/// snapshot of the store and pushes what is newer. Knows nothing about
/// scheduling; the coordinator decides when a pass runs.
class PreferenceReconciler {
  PreferenceReconciler({
    required SharedPreferencesWithCache prefs,
    required PreferenceRevisionStore revisionStore,
    required PreferenceKeyMapper keys,
    required PreferenceTransport? Function() transport,
    required ValueNotifier<PreferenceSyncStatus> status,
  }) : _prefs = prefs,
       _revisionStore = revisionStore,
       _keys = keys,
       _transport = transport,
       _status = status;

  final SharedPreferencesWithCache _prefs;
  final PreferenceRevisionStore _revisionStore;
  final PreferenceKeyMapper _keys;
  final PreferenceTransport? Function() _transport;
  final ValueNotifier<PreferenceSyncStatus> _status;

  void _setStatus(PreferenceSyncStatus next) => _status.value = next;

  /// The v1 meta key. Read, never written after the cutover: it belongs to the
  /// frozen v1 state, and older clients still maintain it among themselves.
  static const String metaVersionKey = '__syncFormatVersion';
  static const int formatVersion = 1;

  /// The v2 marker, inside the namespace this coordinator owns.
  static const String v2MetaVersionKey = '${PreferenceSyncScope.cloudNamespacePrefix}__meta/formatVersion';
  static const int v2FormatVersion = 2;

  String get _activeMetaKey => _keys.v2Format ? v2MetaVersionKey : metaVersionKey;
  int get _activeFormatVersion => _keys.v2Format ? v2FormatVersion : formatVersion;

  /// Read the format version the store was last written with. v1 wrote this and
  /// never read it, which left no way to recognise a store from a newer client.
  Future<int?> readFormatVersion() async {
    final all = await _transport()?.readAll();
    if (all == null) return null;
    final raw = all[_activeMetaKey];
    if (raw == null) return null;
    final decoded = decodeTypedRecord(raw);
    final value = decoded?.$2;
    return value is int ? value : null;
  }

  /// Push every syncable local key whose stamp is newer than the store's, or
  /// which the store lacks; re-send tombstones the store has been written over.
  Future<void> reconcile() async {
    final transport = _transport();
    if (transport == null) return;
    _setStatus(_status.value.starting(DateTime.now()));

    try {
      // The store is read before anything is written. A failed read is not an
      // empty store, and without it nothing can be compared: pushing blind
      // could put an older value over a newer one whose author is no longer
      // around to put it back. Nothing is sent; the next trigger tries again.
      final remote = await transport.readAll();
      if (remote == null) {
        _setStatus(_status.value.raise(PreferenceSyncHealth.error, errorCategory: 'readFailed'));
        appLogger.w('preference sync: reconcile held back, the store could not be read');
        return;
      }

      var pushed = 0;
      var skipped = 0;
      var oversize = 0;
      final known = <String>{};
      for (final fullKey in _prefs.keys) {
        final baseKey = _keys.baseKeyOf(fullKey);
        if (baseKey != null) known.add(baseKey);
        final cloudKey = _keys.cloudKeyFor(fullKey);
        if (cloudKey == null || baseKey == null) continue;
        final local = _revisionStore.stampOf(baseKey);
        // A value held under a removal stamp (a family's local-only entries)
        // is not a change of its own; sending it would carry the tombstone's
        // stamp on a live record. A legacy removal (the old build's bare
        // remove, stamp 0) orders nothing, so a value under it counts as
        // unstamped and travels like one.
        if (local.deleted && local.at != PreferenceRevisionStore.legacyAt) continue;
        final family = _keys.merges.familyFor(baseKey);
        final raw = remote[cloudKey];
        final record = raw == null ? null : decodeStampedRecord(raw);
        final portableValue = _keys.portableValueFor(baseKey, _prefs.get(fullKey), remote: record?.value);
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
        if (cap != null && utf8.encode(encoded).length > cap) {
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
        final localKey = _keys.localKeyFor(e.key);
        if (localKey == null) continue;
        final cloudKey = _keys.cloudKeyFor(localKey);
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

      if (!_keys.v2Format) {
        // The v1 prune, kept for the rolling-upgrade test only. It deletes what
        // is genuinely gone locally and leaves what is present but no longer
        // eligible, so an older client that still syncs the key keeps it.
        final scope = _keys.activeProfileScope;
        for (final k in remote.keys) {
          if (!_keys.ownsCloudKey(k)) continue;
          if (known.contains(k)) continue;
          if (scope.id == null && PreferenceSyncPolicyRegistry.isProfileScoped(k)) continue;
          await transport.remove(k);
        }
      }
      await transport.flush();
      _setStatus(
        _status.value.reconcileSucceeded(
          DateTime.now(),
          pushedCount: pushed,
          skippedCount: skipped,
          oversizeCount: oversize,
        ),
      );
    } catch (e) {
      final category = e.runtimeType.toString();
      _setStatus(_status.value.raise(PreferenceSyncHealth.error, errorCategory: category));
      appLogger.w('preference sync: reconcile failed ($category)');
    }
  }
}
