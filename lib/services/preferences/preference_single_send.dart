import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../settings_export_service.dart';
import 'preference_key_mapper.dart';
import 'preference_remote_apply.dart';
import 'preference_revision_store.dart';
import 'preference_sync_policy.dart';
import 'preference_sync_status.dart';
import 'preference_transport.dart';

/// Sends one local change to the store, outside a reconcile pass. The
/// coordinator decides whether it may travel and under which turn.
class PreferenceSingleSend {
  PreferenceSingleSend({
    required PreferenceKeyMapper keys,
    required PreferenceRevisionStore revisionStore,
    required ValueNotifier<PreferenceSyncStatus> status,
  }) : _keys = keys,
       _revisionStore = revisionStore,
       _status = status;

  final PreferenceKeyMapper _keys;
  final PreferenceRevisionStore _revisionStore;
  final ValueNotifier<PreferenceSyncStatus> _status;

  PreferenceSyncStatus get _current => _status.value;
  void _setStatus(PreferenceSyncStatus next) => _status.value = next;

  /// One value to the store, merged with what the store holds when the family
  /// asks for it ([readFirst]).
  Future<void> send(
    PreferenceTransport transport,
    String baseKey,
    String cloudKey,
    String stampKey,
    Object? value, {
    required bool readFirst,
  }) async {
    // A failed read is not an empty store, so the write is held back rather
    // than pushed over entries this device cannot account for.
    Object? remoteValue;
    if (readFirst) {
      final all = await transport.readAll();
      if (all == null) {
        _setStatus(_current.countingSkipped(1).raise(PreferenceSyncHealth.warning));
        appLogger.w('preference sync: held back ${_category(baseKey)}, the store could not be read');
        return;
      }
      final record = all[cloudKey];
      remoteValue = record == null ? null : decodeTypedRecord(record)?.$2;
    }

    final portableValue = _keys.portableValueFor(baseKey, value, remote: remoteValue);
    if (portableValue == null) {
      // Everything in this list belongs to a non-portable backend. Nothing to
      // send, and nothing to delete either: the cloud copy belongs to the
      // other devices' entries.
      _setStatus(_current.countingSkipped(1));
      return;
    }
    final entry = SettingsExportService.encodeValue(portableValue);
    if (entry == null) {
      _setStatus(_current.countingSkipped(1));
      return;
    }
    final encoded = encodeStampedRecord(entry, _revisionStore.stampOf(stampKey), key: _keys.keyTagFor(baseKey));
    if (exceedsTransportLimits(transport, cloudKey, encoded)) {
      // Oversize is reported, not swallowed. It also must not become a
      // removal: leaving the older cloud value in place is strictly better
      // than deleting it because the newer one did not fit.
      appLogger.w('preference sync: value for ${_category(baseKey)} exceeds the transport limits');
      _setStatus(_current.copyWith(oversize: _current.oversize + 1).raise(PreferenceSyncHealth.warning));
      return;
    }
    await transport.write(cloudKey, encoded);
    _setStatus(_current.writeSucceeded(DateTime.now()));
  }
}

/// Never log a preference key verbatim: per-library and per-server keys carry
/// identifiers. The registered prefix is enough to debug with.
String preferenceLogCategory(String baseKey) {
  for (final prefix in PreferenceSyncPolicyRegistry.registeredPrefixes) {
    if (baseKey.startsWith(prefix)) return '$prefix*';
  }
  return PreferenceSyncPolicyRegistry.isRegistered(baseKey) ? baseKey : 'unregistered';
}

String _category(String baseKey) => preferenceLogCategory(baseKey);
