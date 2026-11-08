import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'integration_credential_changes.dart';
import 'integration_credential_codec.dart';
import 'integration_credential_transport.dart';
import 'preferences/preference_device_id.dart';
import 'settings_service.dart';
import 'tautulli/tautulli_integration_store.dart';

enum IntegrationCredentialSyncStatus { idle, syncing, error, accountChanged }

/// A small outbox for the two integration stores. CloudKit encrypts the cloud
/// payload; each receiving device re-encrypts credentials with its own vault.
/// A pending import is journaled with device-encrypted bytes so a crash between
/// the credential write and metadata write cannot turn an import into an edit.
/// Neither plaintext credentials nor vault keys enter the metadata.
class IntegrationCredentialSyncService {
  IntegrationCredentialSyncService({
    required this.prefs,
    required this.transport,
    required this.deviceId,
    required this.enabled,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static IntegrationCredentialSyncService? instance;
  static const metadataKey = 'pleya_integration_credential_sync_v1';
  static const maxPayloadBytes = 256 * 1024;

  final SharedPreferencesWithCache prefs;
  final IntegrationCredentialTransport transport;
  final String deviceId;
  final bool Function() enabled;
  final DateTime Function() _now;
  final status = ValueNotifier(IntegrationCredentialSyncStatus.idle);
  final Map<String, _LocalRevision> _local = {};
  final Map<String, Map<String, dynamic>> _pending = {};
  String? _account;
  int _generation = 0;
  Future<void>? _flight;
  bool _again = false;
  bool _foreground = true;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;

  static Future<void> start(SettingsService settings) async {
    if ((!Platform.isIOS && !Platform.isMacOS) || instance != null) return;
    final service = IntegrationCredentialSyncService(
      prefs: settings.prefs,
      transport: CloudKitIntegrationCredentialTransport(),
      deviceId: await PreferenceDeviceId.getOrCreate(settings.prefs),
      enabled: () => settings.read(SettingsService.icloudSyncEnabled),
    );
    instance = service;
    try {
      await service.initialize();
      IntegrationCredentialChanges.onLocalChange = service.localChanged;
      IntegrationCredentialChanges.mayWrite = service.mayWrite;
      settings.listenable(SettingsService.icloudSyncEnabled).addListener(() => unawaited(service.sync()));
      service._lifecycle = AppLifecycleListener(
        onStateChange: (state) {
          service._foreground = state == AppLifecycleState.resumed;
          if (service._foreground) unawaited(service.sync());
        },
      );
      service._poll = Timer.periodic(const Duration(minutes: 1), (_) {
        if (service._foreground) unawaited(service.sync());
      });
      unawaited(service.sync());
    } catch (_) {
      service.status.value = IntegrationCredentialSyncStatus.error;
      appLogger.w('integration credential sync: local metadata unavailable');
    }
  }

  Future<void> initialize() async {
    final raw = prefs.getString(metadataKey);
    if (raw == null) return;
    final state = jsonDecode(raw) as Map<String, dynamic>;
    if (state['v'] != 1) throw const FormatException('Unsupported credential metadata');
    _account = state['account'] as String?;
    final entries = state['entries'] as Map<String, dynamic>;
    for (final entry in entries.entries) {
      if (!IntegrationCredentialCodec.isSupportedKey(entry.key)) continue;
      final value = entry.value as Map<String, dynamic>;
      _local[entry.key] = _LocalRevision(_CloudRevision.fromJson(value), value['fingerprint'] as String?);
    }
    final pending = state['pending'] as Map<String, dynamic>? ?? {};
    for (final entry in pending.entries) {
      if (!IntegrationCredentialCodec.isSupportedKey(entry.key)) continue;
      final value = Map<String, dynamic>.from(entry.value as Map);
      final revision = _CloudRevision.fromJson(value);
      final desired = value['raw'] as String?;
      final current = _fingerprint(prefs.getString(entry.key));
      if (current == value['before'] || current == _fingerprint(desired)) {
        if (desired == null) {
          await prefs.remove(entry.key);
        } else {
          await prefs.setString(entry.key, desired);
        }
        _local[entry.key] = _LocalRevision(revision, _fingerprint(desired));
      } else {
        _scanKey(entry.key, migration: false); // A newer local edit survives.
      }
    }
    if (pending.isNotEmpty) await _saveMetadata();
  }

  String? _fingerprint(String? value) => value == null ? null : sha256.convert(utf8.encode(value)).toString();

  Future<void> _saveMetadata() => prefs.setString(
    metadataKey,
    jsonEncode({
      'v': 1,
      'account': _account,
      'entries': {
        for (final e in _local.entries) e.key: {...e.value.revision.toJson(), 'fingerprint': e.value.fingerprint},
      },
      'pending': _pending,
    }),
  );

  void _scanKey(String key, {required bool migration}) {
    if (!IntegrationCredentialCodec.isSupportedKey(key)) return;
    final raw = prefs.getString(key);
    final fingerprint = _fingerprint(raw);
    final previous = _local[key];
    if (previous != null && previous.fingerprint == fingerprint) return;
    if (migration && previous != null) {
      _local[key] = _LocalRevision(previous.revision, fingerprint);
      _generation++;
      return; // Legacy discovery is not a new administrative decision.
    }
    final at = migration && previous == null ? 0 : _now().millisecondsSinceEpoch;
    final stamp = previous == null || at > previous.revision.at ? at : previous.revision.at + 1;
    _local[key] = _LocalRevision(_CloudRevision(stamp, deviceId, raw == null), fingerprint);
    _generation++;
  }

  void _scanAll() {
    for (final key in {...prefs.keys.where(IntegrationCredentialCodec.isSupportedKey), ..._local.keys}) {
      _scanKey(key, migration: !_local.containsKey(key));
    }
  }

  /// Called inside the store write lock, including while cloud sync is off.
  /// The durable stamp is written before the settings screen reports success.
  bool mayWrite(String key, IntegrationCredentialChangeSource source) =>
      source == IntegrationCredentialChangeSource.edit || _local[key]?.revision.deleted != true;

  Future<void> localChanged(String key, IntegrationCredentialChangeSource source) async {
    if (!IntegrationCredentialCodec.isSupportedKey(key)) return;
    _scanKey(key, migration: source != IntegrationCredentialChangeSource.edit);
    _pending.remove(key);
    await _saveMetadata();
    unawaited(sync());
  }

  Future<void> sync() {
    _again = true;
    return _flight ??= _drain().whenComplete(() => _flight = null);
  }

  Future<void> _drain() async {
    try {
      for (var attempt = 0; attempt < 3 && _again; attempt++) {
        _again = false;
        if (!enabled()) {
          status.value = IntegrationCredentialSyncStatus.idle;
          return;
        }
        status.value = IntegrationCredentialSyncStatus.syncing;
        try {
          await _pass();
        } on PlatformException catch (e) {
          if (e.code != 'CREDENTIAL_CONFLICT') rethrow;
          _again = true; // CAS failed; read the competing update before retrying.
        }
        if (status.value == IntegrationCredentialSyncStatus.accountChanged) return;
      }
      status.value = _again ? IntegrationCredentialSyncStatus.error : IntegrationCredentialSyncStatus.idle;
    } catch (e) {
      status.value = IntegrationCredentialSyncStatus.error;
      // Native errors and payloads can contain personal data: log category only.
      appLogger.w('integration credential sync: failed (${e.runtimeType})');
    }
  }

  Future<void> _pass() async {
    final snapshot = await transport.read().timeout(const Duration(seconds: 30));
    if (!enabled()) return;
    if (_account != null && _account != snapshot.account) {
      status.value = IntegrationCredentialSyncStatus.accountChanged;
      return; // Never seed another Apple account with this account's secrets.
    }
    if (snapshot.account.isEmpty || (snapshot.tag != null && snapshot.payload == null)) {
      throw const FormatException('Invalid credential snapshot');
    }
    final Map<String, dynamic> remote;
    if (snapshot.payload == null) {
      remote = {};
    } else {
      final decoded = jsonDecode(snapshot.payload!) as Map<String, dynamic>;
      if (decoded['v'] != 1) throw const FormatException('Unsupported credential snapshot');
      remote = Map<String, dynamic>.from(decoded['entries'] as Map);
    }
    final changed = <String>{};
    int? generation;
    await IntegrationCredentialChanges.exclusively(() async {
      if (!enabled()) return;
      _account ??= snapshot.account;
      _scanAll();
      for (final key in {...remote.keys, ..._local.keys}) {
        if (!IntegrationCredentialCodec.isSupportedKey(key)) continue;
        final incoming = remote[key] == null ? null : _CloudRevision.fromJson(remote[key] as Map<String, dynamic>);
        final local = _local[key];
        final localWins = local != null && (incoming == null || local.revision.winsOver(incoming));
        final selected = localWins ? local.revision : incoming!;
        final localRaw = prefs.getString(key);
        final cloudValue = (remote[key] as Map?)?['value'];
        final Map<String, dynamic>? value = selected.deleted
            ? null
            : localWins
            ? await IntegrationCredentialCodec.toCloud(key, localRaw!)
            : Map<String, dynamic>.from(cloudValue as Map);
        var policyChanged = false;
        if (value != null && key.startsWith(TautulliIntegrationStore.keyPrefix)) {
          final localValue = localRaw == null ? null : jsonDecode(localRaw) as Map;
          _mergeTautulliPolicy(value, localValue, cloudValue is Map ? cloudValue : null);
          policyChanged =
              localValue != null &&
              (localValue['use_history_for_recommendations'] != value['use_history_for_recommendations'] ||
                  localValue['policy_changed_at_ms'] != value['policy_changed_at_ms']);
        }
        remote[key] = {...?remote[key] as Map?, ...selected.toJson(), 'value': value};
        if (local == null || !selected.sameStamp(local.revision) || policyChanged) {
          String? encoded;
          if (!selected.deleted) encoded = await IntegrationCredentialCodec.fromCloud(key, value!);
          if (!enabled()) return;
          _pending[key] = {...selected.toJson(), 'raw': encoded, 'before': _fingerprint(prefs.getString(key))};
          await _saveMetadata();
          if (key.startsWith(TautulliIntegrationStore.keyPrefix)) {
            await TautulliIntegrationStore.instance.clearLegacySessionsForServer(
              key.substring(TautulliIntegrationStore.keyPrefix.length),
            );
          }
          if (encoded == null) {
            await prefs.remove(key);
          } else {
            await prefs.setString(key, encoded);
          }
          _local[key] = _LocalRevision(selected, _fingerprint(encoded));
          _pending.remove(key);
          changed.add(key);
        }
      }
      await _saveMetadata();
      generation = _generation;
    });
    IntegrationCredentialChanges.appliedRemote(changed);
    if (!enabled() || generation == null) return;
    if (generation != _generation) {
      _again = true;
      return;
    }
    if (remote.isEmpty && snapshot.payload == null) return;
    final payload = jsonEncode({'v': 1, 'entries': remote});
    if (utf8.encode(payload).length > maxPayloadBytes) throw const FormatException('Credential snapshot too large');
    if (payload != snapshot.payload) await transport.write(snapshot, payload).timeout(const Duration(seconds: 30));
  }

  void _mergeTautulliPolicy(Map<String, dynamic> value, Map? local, Map? cloud) {
    final localTime = local?['policy_changed_at_ms'] as int? ?? 0;
    final cloudTime = cloud?['policy_changed_at_ms'] as int? ?? 0;
    final localWins =
        localTime > cloudTime || (localTime == cloudTime && local?['use_history_for_recommendations'] == false);
    final policy = localWins ? local : cloud;
    if (policy == null) return;
    value['use_history_for_recommendations'] = policy['use_history_for_recommendations'];
    value['policy_changed_at_ms'] = policy['policy_changed_at_ms'];
  }

  void dispose() {
    _poll?.cancel();
    _lifecycle?.dispose();
    status.dispose();
  }
}

class _LocalRevision {
  const _LocalRevision(this.revision, this.fingerprint);
  final _CloudRevision revision;
  final String? fingerprint;
}

class _CloudRevision {
  const _CloudRevision(this.at, this.device, this.deleted);
  final int at;
  final String device;
  final bool deleted;

  factory _CloudRevision.fromJson(Map<String, dynamic> value) {
    final at = value['t'];
    final device = value['d'];
    final deleted = value['x'];
    if (at is! int || at < 0 || device is! String || device.isEmpty || deleted is! bool) {
      throw const FormatException('Invalid credential revision');
    }
    return _CloudRevision(at, device, deleted);
  }

  bool sameStamp(_CloudRevision other) => at == other.at && device == other.device && deleted == other.deleted;
  bool winsOver(_CloudRevision other) =>
      at > other.at || (at != 0 && at == other.at && device.compareTo(other.device) > 0);
  Map<String, dynamic> toJson() => {'t': at, 'd': device, 'x': deleted};
}
