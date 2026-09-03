/// The profile's default server for duplicate content.
///
/// **This is the one preference that may choose for the user.** It supersedes,
/// for this preference only, the earlier fase-4 rule that every source
/// preference sets picker focus and nothing more. Two preferences now exist and
/// they carry different authority:
///
/// | | scope | key | may auto-select |
/// | --- | --- | --- | --- |
/// | preferred server (here) | profile | stable `serverId` | **yes** |
/// | last-used source (`SourcePreferenceStore`) | profile + canonical title | `bucketKey` | no — focus only |
///
/// The reason for the split is the experience, not the storage: someone who
/// runs one main server should not be asked the same question at every
/// duplicated title, while "the last one I happened to pick for *this* film"
/// is far too weak a signal to skip a question with.
///
/// Two things this store deliberately cannot do:
///
/// * **Override an explicit choice.** "Wijzigen" on a detail page and
///   "Andere bron kiezen" after a failed start are explicit source-selection
///   intents; both open the picker, and neither consults this preference —
///   otherwise the app would answer the user's question with its own default.
/// * **Name a server by name.** Server names are user-editable and can collide
///   (edge case A7), so the value is always a stable `serverId`. A preference
///   that followed a rename would quietly point at a different machine.
///
/// Storage shape follows `SourcePreferenceStore` and `TrackPreferenceStore`: a
/// `SettingsService` `JsonPref` map keyed by `StorageService.activeUserScope()`,
/// serialised through one write lock. No LRU cap is needed — there is exactly
/// one entry per profile, not one per title.
library;

import 'dart:async';

import '../../utils/app_logger.dart';
import '../settings_service.dart';
import '../storage_service.dart';

class PreferredServerStore {
  PreferredServerStore._();

  static Future<void> _writeLock = Future<void>.value();

  /// `whenComplete`, not `then`: a failing write must still release the queue.
  static Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _writeLock;
    final completer = Completer<void>();
    _writeLock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// An empty scope (no active profile) is a namespace of its own, so a
  /// signed-out session never reads or writes a signed-in profile's entry.
  static Future<String> _scope() async {
    final storage = await StorageService.getInstance();
    return storage.activeUserScope() ?? '';
  }

  /// The active profile's preferred `serverId`, or null when it has none.
  ///
  /// The caller still has to check that the returned id names a server that is
  /// currently visible and usable: this store has no view of live servers, and
  /// a preference for a server that was removed, hidden or is offline must
  /// fall through to the ordinary activation rules rather than block them.
  static Future<String?> read() async {
    try {
      final settings = await SettingsService.getInstance();
      final value = settings.read(SettingsService.preferredUnifiedServer)[await _scope()];
      return (value == null || value.isEmpty) ? null : value;
    } catch (e) {
      appLogger.w('Failed to read preferred server', error: e);
      return null;
    }
  }

  /// Makes [serverId] the active profile's default for duplicate content.
  static Future<void> remember(String serverId) {
    return _locked(() async {
      try {
        if (serverId.isEmpty) return;
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.preferredUnifiedServer);
        await settings.write(SettingsService.preferredUnifiedServer, {...stored, await _scope(): serverId});
      } catch (e) {
        appLogger.w('Failed to remember preferred server', error: e);
      }
    });
  }

  /// Drops the active profile's preference, restoring "ask me" behaviour.
  static Future<void> clear() async => clearForProfileScope(await _scope());

  /// Drops [profileScope]'s entry. Called when a profile is deleted, for the
  /// same privacy reason `SourcePreferenceStore.clearForProfileScope` exists
  /// (hoofdstuk 22): which server someone watches from is theirs, and it goes
  /// with the profile rather than ageing out.
  static Future<void> clearForProfileScope(String profileScope) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.preferredUnifiedServer);
        if (!stored.containsKey(profileScope)) return;
        await settings.write(SettingsService.preferredUnifiedServer, {...stored}..remove(profileScope));
      } catch (e) {
        appLogger.w('Failed to clear preferred server for profile', error: e);
      }
    });
  }
}
