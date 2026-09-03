/// How one profile last left Films and Series set up: the sort it chose and
/// the filters it applied (hoofdstuk 27 fase 5 of
/// docs/tvos-unified-experience.md — "persisted queryvoorkeuren").
///
/// The third member of the storage family fase 4 established, not a new one.
/// Shape, scoping and write discipline are `PreferredServerStore`'s, line for
/// line: a `SettingsService` `JsonPref` map, keys carrying the profile scope
/// from `StorageService.activeUserScope()`, every write serialised through one
/// lock, every failure logged and swallowed so a corrupt entry cannot stop a
/// page from opening.
///
/// Two entries per profile at most — one for Films, one for Series — so, like
/// `PreferredServerStore` and unlike `SourcePreferenceStore`, there is no LRU
/// cap to maintain: this map cannot grow with the size of anyone's library.
///
/// ## What this is not
///
/// Not the **preferred server**. That is a profile-wide *activation*
/// preference: it decides which concrete source opens when a title exists on
/// several, and it lives in `PreferredServerStore` with its own authority
/// rules. This store holds *view* settings, which decide what a page shows and
/// in what order, and which may never select a source for anybody.
///
/// Not a place for anything a backend cannot execute either. The stored
/// selection is the user's full intent and is deliberately kept whole — a
/// genre choice survives a Pleya Server library joining the catalog and
/// suppressing it — while
/// `UnifiedCatalogFilterSelection.constrainedTo` decides what is applied right
/// now. Writing the constrained value back here would delete a choice the user
/// can still get back by narrowing their sources.
library;

import 'dart:async';

import '../../media/media_kind.dart';
import '../../utils/app_logger.dart';
import '../settings_service.dart';
import '../storage_service.dart';
import 'unified_catalog_filters.dart';

class UnifiedCatalogQueryStore {
  UnifiedCatalogQueryStore._();

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

  /// Films and Series are two catalogs with two independent setups, so the
  /// kind is part of the key rather than a field inside one shared entry.
  static Future<String> _key(MediaKind kind) async => '${await _scope()}|${kind.id}';

  /// What [kind]'s catalog was last left as, or the defaults.
  ///
  /// Falls back to [UnifiedCatalogPreferences.defaults] for a missing entry and
  /// for an unreadable one alike: the difference between "never set" and
  /// "corrupt" changes nothing a user can act on, and a page that refuses to
  /// open because a stored sort name no longer exists would be worse than one
  /// that opens on Title A–Z.
  static Future<UnifiedCatalogPreferences> read(MediaKind kind) async {
    try {
      final settings = await SettingsService.getInstance();
      final stored = settings.read(SettingsService.unifiedCatalogPreferences)[await _key(kind)];
      return stored ?? UnifiedCatalogPreferences.defaults;
    } catch (e) {
      appLogger.w('Failed to read unified catalog preferences', error: e);
      return UnifiedCatalogPreferences.defaults;
    }
  }

  /// Stores [preferences] for [kind] under the active profile.
  static Future<void> write(MediaKind kind, UnifiedCatalogPreferences preferences) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.unifiedCatalogPreferences);
        await settings.write(SettingsService.unifiedCatalogPreferences, {...stored, await _key(kind): preferences});
      } catch (e) {
        appLogger.w('Failed to write unified catalog preferences', error: e);
      }
    });
  }

  /// Drops every catalog setup belonging to [profileScope].
  ///
  /// Called from the profile delete flow beside the other two unified stores,
  /// for the same hoofdstuk-22 reason: which genres someone browses is theirs,
  /// and it leaves with the profile rather than ageing out.
  static Future<void> clearForProfileScope(String profileScope) {
    return _locked(() async {
      try {
        final settings = await SettingsService.getInstance();
        final stored = settings.read(SettingsService.unifiedCatalogPreferences);
        final remaining = {
          for (final entry in stored.entries)
            if (!_belongsToScope(entry.key, profileScope)) entry.key: entry.value,
        };
        if (remaining.length == stored.length) return;
        await settings.write(SettingsService.unifiedCatalogPreferences, remaining);
      } catch (e) {
        appLogger.w('Failed to clear unified catalog preferences for profile', error: e);
      }
    });
  }

  /// Whether [key] is `{profileScope}|{kind}`.
  ///
  /// Matched on the separator rather than with `startsWith`, or the empty
  /// (signed-out) scope would match every key and deleting one profile would
  /// clear them all.
  static bool _belongsToScope(String key, String profileScope) {
    final separator = key.lastIndexOf('|');
    if (separator < 0) return false;
    return key.substring(0, separator) == profileScope;
  }
}
