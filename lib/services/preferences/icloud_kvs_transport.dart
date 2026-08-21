import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/app_logger.dart';
import 'preference_transport.dart';

/// `NSUbiquitousKeyValueStore` behind the [PreferenceTransport] port.
///
/// This class is deliberately thin: channel calls, event translation, and
/// nothing else. Eligibility, scoping, conflict resolution and status live in
/// the coordinator, so a second transport does not have to reimplement them.
///
/// No-op off Apple platforms, where the native plugin does not exist. tvOS
/// reports itself as iOS.
class ICloudKvsTransport implements PreferenceTransport {
  ICloudKvsTransport({MethodChannel? channel, EventChannel? events})
    : _channel = channel ?? const MethodChannel('com.pleya/icloud_kvs'),
      _events = events ?? const EventChannel('com.pleya/icloud_kvs/events');

  final MethodChannel _channel;
  final EventChannel _events;

  StreamSubscription<dynamic>? _eventSub;
  final StreamController<RemotePreferenceChange> _changes = StreamController<RemotePreferenceChange>.broadcast();

  // NSUbiquitousKeyValueStoreChangeReason values.
  static const int _reasonServerChange = 0;
  static const int _reasonInitialSync = 1;
  static const int _reasonQuotaViolation = 2;
  static const int _reasonAccountChange = 3;

  /// Only Apple platforms ship the native plugin. Test-only override; nothing
  /// in the app sets this.
  static bool debugForceSupported = false;

  static bool get supported => debugForceSupported || Platform.isIOS || Platform.isMacOS;

  @override
  String get name => 'icloud-kvs';

  /// KVS totals 1MB across all keys, so one oversized value must not be
  /// allowed to starve every other setting.
  @override
  int? get maxValueBytes => 100 * 1024;

  @override
  Future<bool> isAvailable() async {
    if (!supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('isAvailable')) ?? false;
    } catch (e) {
      appLogger.w('iCloud isAvailable failed', error: e);
      return false;
    }
  }

  @override
  Stream<RemotePreferenceChange> get changes {
    _eventSub ??= _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object e) => appLogger.w('iCloud KVS event error', error: e),
    );
    return _changes.stream;
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final change = translateEvent(Map<String, dynamic>.from(event));
    if (change != null) _changes.add(change);
  }

  /// Native payload to a transport-level change. Pure, so the event path can be
  /// exercised without a live EventChannel.
  static RemotePreferenceChange? translateEvent(Map<String, dynamic> event) {
    final reason = event['reason'] as int? ?? -1;
    final keys = (event['changedKeys'] as List?)?.cast<String>() ?? const <String>[];
    return switch (reason) {
      _reasonQuotaViolation => const RemotePreferenceChange(reason: RemoteChangeReason.quotaExceeded),
      _reasonAccountChange => const RemotePreferenceChange(reason: RemoteChangeReason.accountChanged),
      _reasonInitialSync => RemotePreferenceChange(reason: RemoteChangeReason.initialSync, changedKeys: keys),
      _reasonServerChange => RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: keys),
      // An unknown reason is treated as a server change: re-reading is cheap
      // and safe, ignoring a real change is not.
      _ => RemotePreferenceChange(reason: RemoteChangeReason.serverChange, changedKeys: keys),
    };
  }

  /// Feed a native event straight into the stream. Test-only.
  @visibleForTesting
  void debugEmit(Map<String, dynamic> event) => _onNativeEvent(event);

  @override
  Future<Map<String, String>?> readAll() async {
    try {
      return (await _channel.invokeMapMethod<String, String>('getAll')) ?? const {};
    } catch (e) {
      appLogger.w('iCloud getAll failed', error: e);
      return null;
    }
  }

  @override
  Future<void> write(String key, String encoded) async {
    try {
      await _channel.invokeMethod('set', {'key': key, 'value': encoded});
    } catch (e) {
      appLogger.w('iCloud set failed', error: e);
      rethrow;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await _channel.invokeMethod('remove', {'key': key});
    } catch (e) {
      appLogger.w('iCloud remove failed', error: e);
      rethrow;
    }
  }

  @override
  Future<void> flush() async {
    try {
      await _channel.invokeMethod('synchronize');
    } catch (_) {
      // Best-effort: the OS coalesces uploads anyway.
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _changes.close();
  }
}
