import 'dart:async';

import 'package:flutter/foundation.dart';

import 'base_shared_preferences_service.dart';

enum IntegrationCredentialChangeSource { edit, migration, refresh }

/// Serializes integration writes with cloud imports. Network calls never hold
/// this lock. Values remain in the device's existing encrypted stores.
class IntegrationCredentialChanges {
  static Future<void>? _turn;
  static Future<void> Function(String key, IntegrationCredentialChangeSource source)? onLocalChange;
  static bool Function(String key, IntegrationCredentialChangeSource source)? mayWrite;
  static final _remoteChanges = StreamController<Set<String>>.broadcast();

  static Stream<Set<String>> get remoteChanges => _remoteChanges.stream;

  /// Fresh test fixtures have a new fake-async zone. Reset only between tests,
  /// after the previous fixture's providers and writes have finished.
  @visibleForTesting
  static void resetForTesting() {
    _turn = null;
  }

  static Future<T> exclusively<T>(Future<T> Function() body) {
    final run = (_turn ?? Future<void>.value()).then((_) => body());
    _turn = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  static Future<void> write(
    String key,
    String? value, {
    IntegrationCredentialChangeSource source = IntegrationCredentialChangeSource.edit,
    Map<String, String?> expected = const {},
  }) => exclusively(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    if (expected.entries.any((entry) => prefs.getString(entry.key) != entry.value) ||
        !(mayWrite?.call(key, source) ?? true)) {
      appliedRemote({key}); // Reload the binding that won the race.
      return;
    }
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    await onLocalChange?.call(key, source);
  });

  static void appliedRemote(Set<String> keys) {
    if (keys.isNotEmpty) _remoteChanges.add(Set.unmodifiable(keys));
  }

  /// Changes fields of an existing binding while holding the same lock as
  /// remote imports. A policy edit can never recreate a removed credential.
  static Future<void> update(
    String key,
    Future<String> Function(String current) transform, {
    required IntegrationCredentialChangeSource source,
  }) => exclusively(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final current = prefs.getString(key);
    if (current == null || !(mayWrite?.call(key, source) ?? true)) return;
    await prefs.setString(key, await transform(current));
    await onLocalChange?.call(key, source);
  });
}
