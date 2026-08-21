import 'dart:async';
import 'dart:convert';
import '../media/ids.dart';

import 'package:uuid/uuid.dart';

import '../profiles/profile.dart';
import '../utils/log_redaction_manager.dart';
import 'base_shared_preferences_service.dart';
import 'preferences/preference_mutation.dart';
import 'preferences/preference_sync_scope.dart';

class StorageService extends BaseSharedPreferencesService {
  static const String _keyPlexToken = 'plex_token';
  static const String _keyClientId = 'client_identifier';
  static const String _keySelectedLibraryKey = 'selected_library_key';
  static const String _keyLibraryFilters = 'library_filters';
  static const String _keyLibraryOrder = 'library_order';
  static const String _keyCurrentUserUUID = 'current_user_uuid';
  static const String _keyHiddenLibraries = 'hidden_libraries';
  static const String _keyServersList = 'servers_list';
  static const String _keyServerOrder = 'server_order';
  // One definition, in the layer that has to recognise a write to it.
  static const String _keyActiveProfileId = PreferenceSyncScope.activeProfileIdKey;
  static const String _keyHomeRowOrder = 'home_row_order';
  static const String _keyHiddenHomeRows = 'hidden_home_rows';

  // Key prefixes for per-id storage
  static const String _prefixServerEndpoint = 'server_endpoint_';
  static const String _prefixLibraryFilters = 'library_filters_';
  static const String _prefixLibrarySort = 'library_sort_';
  static const String _prefixLibraryGrouping = 'library_grouping_';
  static const String _prefixLibraryTab = 'library_tab_';
  static const String _prefixPlexHomeUsers = 'plex_home_users_';
  static const String _prefixProfileLastUsed = 'profile_last_used_';
  // Key groups for bulk clearing
  static const List<String> _credentialKeys = [_keyPlexToken, _keyClientId, _keyCurrentUserUUID];

  static const List<String> _libraryPreferenceKeys = [_keyLibraryFilters, _keyLibraryOrder, _keyHiddenLibraries];

  StorageService._();

  static Future<StorageService> getInstance() {
    return BaseSharedPreferencesService.initializeInstance(() => StorageService._());
  }

  @override
  Future<void> onInit() async {
    // Seed known values so logs can redact immediately on startup. Reading
    // the legacy plex_token slot here is acceptable: it's a one-shot
    // redaction-priming read for any tokens lingering from before the
    // migration ran (after migration the slot is empty so this is a no-op).
    // ignore: deprecated_member_use_from_same_package
    LogRedactionManager.registerToken(getPlexToken());
  }

  // User-scoped storage for per-profile library settings

  /// Returns the scope identifier for the active profile, or `null` if no
  /// profile is active.
  ///
  /// For Plex Home profiles (id format `plex-home-{connId}-{homeUserUuid}`)
  /// the scope is the home-user UUID — keeps per-user library prefs working
  /// the same way the legacy `currentUserUUID` did. For local profiles, the
  /// full profile id is the scope.
  String? activeUserScope() => _activeUserScope();

  String userScopeForProfileId(String profileId) => parsePlexHomeProfileId(profileId)?.homeUserUuid ?? profileId;

  String? _activeUserScope() {
    final id = getActiveProfileId();
    if (id == null) return null;
    return parsePlexHomeProfileId(id)?.homeUserUuid ?? id;
  }

  /// Returns `'user_{scope}_'` for the active profile, or `''` if no
  /// profile is active.
  String get _userPrefix {
    final scope = _activeUserScope();
    return scope != null ? 'user_${scope}_' : '';
  }

  String _userPrefixForProfileId(String profileId) => 'user_${userScopeForProfileId(profileId)}_';

  /// Read a string with user-scoped key, migrating from legacy key if needed.
  String? _getScopedString(String baseKey) {
    final scopedKey = '$_userPrefix$baseKey';
    final value = prefs.getString(scopedKey);
    if (value != null || _userPrefix.isEmpty) return value;
    // One-time migration from legacy global key
    final legacy = prefs.getString(baseKey);
    if (legacy != null) {
      // A read that promotes a legacy key is bookkeeping, not a choice. It must
      // not push, and it must not stamp a user timestamp, or the device that
      // upgrades last would look like the most recent editor of everything.
      unawaited(_writePreference(scopedKey, legacy, source: PreferenceSource.migration));
      unawaited(_removePreference(baseKey, source: PreferenceSource.migration));
    }
    return legacy;
  }

  // Per-Server Endpoint URL (for multi-server connection caching)
  Future<void> saveServerEndpoint(ServerId serverId, String url) async {
    await prefs.setString('$_prefixServerEndpoint$serverId', url);
    LogRedactionManager.registerServerUrl(url);
  }

  String? getServerEndpoint(ServerId serverId) {
    return prefs.getString('$_prefixServerEndpoint$serverId');
  }

  Future<void> clearServerEndpoint(ServerId serverId) async {
    await prefs.remove('$_prefixServerEndpoint$serverId');
  }

  // Plex.tv Token — read once by [ConnectionBootstrap.migrateLegacyPlexAccount]
  // on the upgrade run. The new pipeline stores Plex account tokens on
  // [PlexAccountConnection.accountToken] in [ConnectionRegistry].
  @Deprecated(
    'Read PlexAccountConnection.accountToken from ConnectionRegistry instead. '
    'Only ConnectionBootstrap.migrateLegacyPlexAccount may use this.',
  )
  String? getPlexToken() {
    return prefs.getString(_keyPlexToken);
  }

  /// Drop the legacy `plex_token` slot. Called by
  /// [ConnectionBootstrap.migrateLegacyPlexAccount] after the token has
  /// been moved into a [PlexAccountConnection] row, so a later sign-out
  /// doesn't get resurrected on next launch (the migration would
  /// otherwise see the orphaned token and re-create the connection).
  Future<void> clearLegacyPlexToken() async {
    await prefs.remove(_keyPlexToken);
  }

  /// Return the persisted device identifier, generating and saving a UUID on
  /// first call. Used by Plex's `X-Plex-Client-Identifier` header so plex.tv
  /// sees the same device across launches; not Plex-specific in itself —
  /// Jellyfin's `DeviceId` header reuses the same value too.
  Future<String> getOrCreateClientIdentifier() async {
    final existing = prefs.getString(_keyClientId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = const Uuid().v4();
    await prefs.setString(_keyClientId, generated);
    return generated;
  }

  // Clear all credentials
  Future<void> clearCredentials() async {
    await Future.wait([..._credentialKeys.map((k) => prefs.remove(k)), clearMultiServerData()]);
    LogRedactionManager.clearTrackedValues();
  }

  // Selected Library Key (replaces index-based selection)
  Future<void> saveSelectedLibraryKey(String key) async {
    await _writePreference('$_userPrefix$_keySelectedLibraryKey', key);
  }

  String? getSelectedLibraryKey() {
    return _getScopedString(_keySelectedLibraryKey);
  }

  // Library Filters (stored as JSON string)
  Future<void> saveLibraryFilters(Map<String, String> filters, {String? sectionId}) async {
    final baseKey = sectionId != null ? '$_prefixLibraryFilters$sectionId' : _keyLibraryFilters;
    // Note: using Map<String, String> which json.encode handles correctly
    final jsonString = json.encode(filters);
    await _writePreference('$_userPrefix$baseKey', jsonString);
  }

  Map<String, String> getLibraryFilters({String? sectionId}) {
    final baseKey = sectionId != null ? '$_prefixLibraryFilters$sectionId' : _keyLibraryFilters;

    // Prefer per-library filters when available
    var jsonString = _getScopedString(baseKey);
    if (jsonString == null && sectionId != null) {
      // Legacy support: fall back to global filters if present
      jsonString = _getScopedString(_keyLibraryFilters);
    }
    if (jsonString == null) return {};

    final decoded = decodeJsonStringToMap(jsonString);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  // Library Sort (per-library, stored individually with descending flag)
  Future<void> saveLibrarySort(String sectionId, String sortKey, {bool descending = false}) async {
    final sortData = {'key': sortKey, 'descending': descending};
    await _setJsonMap('$_userPrefix$_prefixLibrarySort$sectionId', sortData);
  }

  Map<String, dynamic>? getLibrarySort(String sectionId) {
    final baseKey = '$_prefixLibrarySort$sectionId';
    final scopedKey = '$_userPrefix$baseKey';
    var result = _readJsonMap(scopedKey, legacyStringOk: true);
    if (result != null || _userPrefix.isEmpty) return result;
    // One-time migration from legacy key
    result = _readJsonMap(baseKey, legacyStringOk: true);
    if (result != null) {
      unawaited(_setJsonMap(scopedKey, result, source: PreferenceSource.migration));
      unawaited(_removePreference(baseKey, source: PreferenceSource.migration));
    }
    return result;
  }

  // Library Grouping (per-library, e.g., 'movies', 'shows', 'seasons', 'episodes')
  Future<void> saveLibraryGrouping(String sectionId, String grouping) async {
    await _writePreference('$_userPrefix$_prefixLibraryGrouping$sectionId', grouping);
  }

  String? getLibraryGrouping(String sectionId) {
    return _getScopedString('$_prefixLibraryGrouping$sectionId');
  }

  // Library Tab (per-library, saves last selected tab name)
  Future<void> saveLibraryTab(String sectionId, String tabName) async {
    await _writePreference('$_userPrefix$_prefixLibraryTab$sectionId', tabName);
  }

  String? getLibraryTab(String sectionId) {
    final key = '$_userPrefix$_prefixLibraryTab$sectionId';
    // Handle migration from old int storage: try string first, fall back to removing stale int
    try {
      return prefs.getString(key);
    } catch (_) {
      unawaited(_removePreference(key, source: PreferenceSource.migration));
      return null;
    }
  }

  // Hidden Libraries (stored as JSON array of library section IDs)
  Future<void> saveHiddenLibraries(Set<String> libraryKeys) async {
    await _setStringList('$_userPrefix$_keyHiddenLibraries', libraryKeys.toList());
  }

  Future<void> saveHiddenLibrariesForProfile(String profileId, Set<String> libraryKeys) async {
    await _setStringList('${_userPrefixForProfileId(profileId)}$_keyHiddenLibraries', libraryKeys.toList());
  }

  Set<String> getHiddenLibraries() {
    final jsonString = _getScopedString(_keyHiddenLibraries);
    return _decodeStringSet(jsonString);
  }

  Set<String> getHiddenLibrariesForProfile(String profileId) {
    final scopedKey = '${_userPrefixForProfileId(profileId)}$_keyHiddenLibraries';
    var jsonString = prefs.getString(scopedKey);
    if (jsonString == null && getActiveProfileId() == profileId) {
      // One-time migration from the legacy unscoped key, but only for the
      // currently active profile. Otherwise merely opening another profile's
      // scoped provider could steal legacy preferences into the wrong scope.
      final legacy = prefs.getString(_keyHiddenLibraries);
      if (legacy != null) {
        unawaited(_writePreference(scopedKey, legacy, source: PreferenceSource.migration));
        unawaited(_removePreference(_keyHiddenLibraries, source: PreferenceSource.migration));
        jsonString = legacy;
      }
    }
    return _decodeStringSet(jsonString);
  }

  Set<String> _decodeStringSet(String? jsonString) {
    if (jsonString == null) return {};

    try {
      final list = json.decode(jsonString) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (e) {
      return {};
    }
  }

  // Clear library preferences (scoped to current user)
  Future<void> clearLibraryPreferences() async {
    final prefix = _userPrefix;
    await Future.wait([
      ..._libraryPreferenceKeys.map((k) => _removePreference('$prefix$k', source: PreferenceSource.reset)),
      _removePreference('$prefix$_keySelectedLibraryKey', source: PreferenceSource.reset),
      _clearKeysWithPrefix('$prefix$_prefixLibrarySort'),
      _clearKeysWithPrefix('$prefix$_prefixLibraryFilters'),
      _clearKeysWithPrefix('$prefix$_prefixLibraryGrouping'),
      _clearKeysWithPrefix('$prefix$_prefixLibraryTab'),
      if (prefix.isNotEmpty) ...[
        ..._libraryPreferenceKeys.map((k) => _removePreference(k, source: PreferenceSource.reset)),
        _removePreference(_keySelectedLibraryKey, source: PreferenceSource.reset),
        _clearKeysWithPrefix(_prefixLibrarySort),
        _clearKeysWithPrefix(_prefixLibraryFilters),
        _clearKeysWithPrefix(_prefixLibraryGrouping),
        _clearKeysWithPrefix(_prefixLibraryTab),
      ],
    ]);
  }

  /// Clear library preferences for [serverId] within [profileId]'s user scope.
  ///
  /// Library-specific preferences are keyed by `serverId:libraryId`, so when a
  /// profile loses access to a server those entries must go too. Otherwise a
  /// later re-add of the same physical server revives old hidden/order/filter
  /// choices.
  Future<void> clearLibraryPreferencesForServer(
    ServerId serverId, {
    required String profileId,
    bool includeLegacy = false,
  }) async {
    final prefixes = <String>{_userPrefixForProfileId(profileId), if (includeLegacy) ''};
    await Future.wait(prefixes.map((prefix) => _clearLibraryPreferencesForServerPrefix(prefix, serverId)));
  }

  /// Clear [serverId] library preferences from every user scope and legacy
  /// unscoped storage. Used when no remaining profile has access to the server.
  Future<void> clearLibraryPreferencesForServerEverywhere(ServerId serverId) async {
    await Future.wait([
      _clearLibraryPreferencesForServerPrefix('', serverId),
      _filterServerEntriesFromAllStringListKeys(_keyLibraryOrder, serverId),
      _filterServerEntriesFromAllStringListKeys(_keyHiddenLibraries, serverId),
      _clearServerSelectedLibraryKeysEverywhere(serverId),
      _clearServerPerLibraryKeysEverywhere(_prefixLibrarySort, serverId),
      _clearServerPerLibraryKeysEverywhere(_prefixLibraryFilters, serverId),
      _clearServerPerLibraryKeysEverywhere(_prefixLibraryGrouping, serverId),
      _clearServerPerLibraryKeysEverywhere(_prefixLibraryTab, serverId),
    ]);
  }

  Future<void> _clearLibraryPreferencesForServerPrefix(String prefix, ServerId serverId) async {
    await Future.wait([
      _filterServerEntriesFromStringList('$prefix$_keyLibraryOrder', serverId),
      _filterServerEntriesFromStringList('$prefix$_keyHiddenLibraries', serverId),
      _clearSelectedLibraryForServer('$prefix$_keySelectedLibraryKey', serverId),
      _clearKeysWithPrefixForServer('$prefix$_prefixLibrarySort', serverId),
      _clearKeysWithPrefixForServer('$prefix$_prefixLibraryFilters', serverId),
      _clearKeysWithPrefixForServer('$prefix$_prefixLibraryGrouping', serverId),
      _clearKeysWithPrefixForServer('$prefix$_prefixLibraryTab', serverId),
    ]);
  }

  // Library Order (stored as JSON list of library keys)
  Future<void> saveLibraryOrder(List<String> libraryKeys) async {
    await _setStringList('$_userPrefix$_keyLibraryOrder', libraryKeys);
  }

  List<String>? getLibraryOrder() {
    final baseKey = _keyLibraryOrder;
    final scopedKey = '$_userPrefix$baseKey';
    final value = _getStringList(scopedKey);
    if (value != null || _userPrefix.isEmpty) return value;
    // One-time migration from legacy key
    final legacy = _getStringList(baseKey);
    if (legacy != null) {
      unawaited(_setStringList(scopedKey, legacy, source: PreferenceSource.migration));
      unawaited(_removePreference(baseKey, source: PreferenceSource.migration));
    }
    return legacy;
  }

  // Home row layout (order + hidden rows on the discover/home screen).
  // Keys are hub identities ('serverId:identifier'); see DiscoverScreen.
  // ponytail: no legacy-key migration — these keys are new, empty = default order.
  Future<void> saveHomeRowOrder(String? profileId, List<String> rowIds) async {
    await _setStringList('${_homePrefix(profileId)}$_keyHomeRowOrder', rowIds);
  }

  List<String> getHomeRowOrder(String? profileId) {
    return _getStringList('${_homePrefix(profileId)}$_keyHomeRowOrder') ?? const [];
  }

  Future<void> saveHiddenHomeRows(String? profileId, Set<String> rowIds) async {
    await _setStringList('${_homePrefix(profileId)}$_keyHiddenHomeRows', rowIds.toList());
  }

  Set<String> getHiddenHomeRows(String? profileId) {
    return (_getStringList('${_homePrefix(profileId)}$_keyHiddenHomeRows') ?? const []).toSet();
  }

  String _homePrefix(String? profileId) => profileId == null ? _userPrefix : _userPrefixForProfileId(profileId);

  // Current User UUID — read once by [ConnectionBootstrap._promoteActiveProfileFromLegacy]
  // on the upgrade run, then cleared. Replaced by
  // [getActiveProfileId] / [setActiveProfileId].
  @Deprecated(
    'Use setActiveProfileId / getActiveProfileId. '
    'Only ConnectionBootstrap._promoteActiveProfileFromLegacy may read this.',
  )
  String? getCurrentUserUUID() {
    return prefs.getString(_keyCurrentUserUUID);
  }

  /// Clears the legacy `currentUserUUID` slot. Used by the upgrade migration.
  Future<void> clearCurrentUserUUID() async {
    await prefs.remove(_keyCurrentUserUUID);
  }

  // Clear all user-related data (for logout)
  Future<void> clearUserData() async {
    await Future.wait([clearCredentials(), clearLibraryPreferences()]);
  }

  // Multi-Server Support Methods
  //
  // Servers now live on [PlexAccountConnection.servers] in
  // [ConnectionRegistry]. The legacy `servers_list` JSON slot is read once
  // by [ConnectionBootstrap.migrateLegacyPlexAccount] and then dropped.

  /// Get legacy servers list as JSON string. Use [ConnectionRegistry] for
  /// fresh data; this exists only for the boot-time migration.
  @Deprecated(
    'Read PlexAccountConnection.servers from ConnectionRegistry. '
    'Only ConnectionBootstrap.migrateLegacyPlexAccount may use this.',
  )
  String? getServersListJson() {
    return prefs.getString(_keyServersList);
  }

  /// Clear the legacy servers list.
  Future<void> clearServersList() async {
    await prefs.remove(_keyServersList);
  }

  /// Clear all multi-server data
  Future<void> clearMultiServerData() async {
    await Future.wait([
      clearServersList(),
      clearServerOrder(),
      _clearKeysWithPrefix(_prefixServerEndpoint, source: PreferenceSource.migration),
    ]);
  }

  /// Clear legacy server order.
  Future<void> clearServerOrder() async {
    await prefs.remove(_keyServerOrder);
  }

  // Active app-level profile (kids mode / multi-user gating)

  String? getActiveProfileId() => prefs.getString(_keyActiveProfileId);

  /// Both of these report the mutation even though the key never syncs.
  ///
  /// The engine listens for exactly this write: which profile is active decides
  /// which cloud namespace applies, so switching profiles has to reconcile.
  /// Writing straight to `prefs` here would have left every path that switches
  /// profiles — activation, bootstrap, cleanup — silently unreconciled.
  Future<void> setActiveProfileId(String id) => _writePreference(_keyActiveProfileId, id);

  Future<void> clearActiveProfileId() => _removePreference(_keyActiveProfileId);

  // Per-connection Plex Home users cache. Plex Home profiles are not
  // persisted as Profile rows — they're fetched live by [PlexHomeService]
  // and cached here so the picker can paint immediately on cold start.
  // Stored as a JSON list of [PlexHomeUser] payloads, no TTL — the service
  // refreshes in the background via stale-while-revalidate.
  Future<void> savePlexHomeUsersCache(String connectionId, List<Map<String, dynamic>> users) async {
    await prefs.setString('$_prefixPlexHomeUsers$connectionId', json.encode(users));
  }

  String? getPlexHomeUsersCacheJson(String connectionId) {
    return prefs.getString('$_prefixPlexHomeUsers$connectionId');
  }

  Future<void> clearPlexHomeUsersCache(String connectionId) async {
    await prefs.remove('$_prefixPlexHomeUsers$connectionId');
  }

  Future<void> clearAllPlexHomeUsersCache() async {
    await _clearKeysWithPrefix(_prefixPlexHomeUsers, source: PreferenceSource.migration);
  }

  // `lastUsedAt` for ordering and future filtering of profiles by recency
  // (currently surfaced via `Profile.lastUsedAt`). Stored separately so it
  // works for both DB-backed local profiles and virtual Plex Home profiles
  // (which don't have a Profile row to update).
  Future<void> markProfileUsed(String profileId, DateTime at) async {
    await prefs.setInt('$_prefixProfileLastUsed$profileId', at.millisecondsSinceEpoch);
  }

  DateTime? getProfileLastUsed(String profileId) {
    final ms = prefs.getInt('$_prefixProfileLastUsed$profileId');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> clearAllProfileLastUsed() async {
    await _clearKeysWithPrefix(_prefixProfileLastUsed, source: PreferenceSource.migration);
  }

  // Private helper methods

  /// Helper to read and decode JSON `List<String>` from preferences
  List<String>? _getStringList(String key) {
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;

    try {
      final decoded = json.decode(jsonString) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      return null;
    }
  }

  /// Helper to read and decode JSON Map from preferences
  ///
  /// [key] - The preference key to read
  /// [legacyStringOk] - If true, returns {'key': value, 'descending': false}
  ///                    when value is a plain string (for legacy library sort)
  Map<String, dynamic>? _readJsonMap(String key, {bool legacyStringOk = false}) {
    final jsonString = prefs.getString(key);
    if (jsonString == null) return null;

    return decodeJsonStringToMap(jsonString, legacyStringOk: legacyStringOk);
  }

  /// Remove all keys matching a prefix.
  ///
  /// [source] is `reset` for the library and home families, which the sync
  /// engine owns, and `migration` for the runtime caches it does not: server
  /// endpoints, the Plex Home user cache, per-profile last-used stamps.
  Future<void> _clearKeysWithPrefix(String prefix, {PreferenceSource source = PreferenceSource.reset}) async {
    final keys = prefs.keys.where((k) => k.startsWith(prefix)).toList(growable: false);
    await Future.wait(keys.map((k) => _removePreference(k, source: source)));
  }

  bool _belongsToServer(String value, ServerId serverId) => value.startsWith('$serverId:');

  Future<void> _filterServerEntriesFromStringList(String key, ServerId serverId) async {
    final values = _getStringList(key);
    if (values == null || values.isEmpty) return;
    final filtered = values.where((value) => !_belongsToServer(value, serverId)).toList(growable: false);
    if (filtered.length == values.length) return;
    if (filtered.isEmpty) {
      await _removePreference(key, source: PreferenceSource.reset);
    } else {
      await _setStringList(key, filtered);
    }
  }

  Future<void> _filterServerEntriesFromAllStringListKeys(String baseKey, ServerId serverId) async {
    final keys = prefs.keys
        .where((key) => key == baseKey || (key.startsWith('user_') && key.endsWith('_$baseKey')))
        .toList(growable: false);
    await Future.wait(keys.map((key) => _filterServerEntriesFromStringList(key, serverId)));
  }

  Future<void> _clearSelectedLibraryForServer(String key, ServerId serverId) async {
    final selected = prefs.getString(key);
    if (selected != null && _belongsToServer(selected, serverId)) {
      await _removePreference(key, source: PreferenceSource.reset);
    }
  }

  Future<void> _clearServerSelectedLibraryKeysEverywhere(ServerId serverId) async {
    final keys = prefs.keys
        .where(
          (key) =>
              key == _keySelectedLibraryKey || (key.startsWith('user_') && key.endsWith('_$_keySelectedLibraryKey')),
        )
        .toList(growable: false);
    await Future.wait(keys.map((key) => _clearSelectedLibraryForServer(key, serverId)));
  }

  Future<void> _clearKeysWithPrefixForServer(String keyPrefix, ServerId serverId) async {
    final serverPrefix = '$serverId:';
    final keys = prefs.keys
        .where((key) => key.startsWith(keyPrefix) && key.substring(keyPrefix.length).startsWith(serverPrefix))
        .toList(growable: false);
    await Future.wait(keys.map((key) => _removePreference(key, source: PreferenceSource.reset)));
  }

  Future<void> _clearServerPerLibraryKeysEverywhere(String basePrefix, ServerId serverId) async {
    final serverPrefix = '$serverId:';
    final scopedMarker = '_$basePrefix';
    final keys = prefs.keys
        .where((key) {
          if (key.startsWith(basePrefix)) {
            return key.substring(basePrefix.length).startsWith(serverPrefix);
          }
          if (!key.startsWith('user_')) return false;
          final markerIndex = key.lastIndexOf(scopedMarker);
          if (markerIndex == -1) return false;
          final suffix = key.substring(markerIndex + scopedMarker.length);
          return suffix.startsWith(serverPrefix);
        })
        .toList(growable: false);
    await Future.wait(keys.map((key) => _removePreference(key, source: PreferenceSource.reset)));
  }

  // Public JSON helpers for reducing boilerplate

  // Preference-pipeline helpers.
  //
  // Library and home preferences are not `Pref<T>` objects, so they never went
  // through `write<T>`. Half of them fired the old write hook by hand and half
  // did not, and none of the *removals* fired it at all: iCloud saw the set and
  // never the delete. These three helpers put every one of them on the same
  // path, with the source spelled out at the call site.

  Future<void> _writePreference(String key, String value, {PreferenceSource source = PreferenceSource.local}) async {
    await prefs.setString(key, value);
    await BaseSharedPreferencesService.notifyMutation(PreferenceMutation.set(key, value, source: source));
  }

  Future<void> _removePreference(String key, {PreferenceSource source = PreferenceSource.local}) async {
    await prefs.remove(key);
    await BaseSharedPreferencesService.notifyMutation(PreferenceMutation.remove(key, source: source));
  }

  /// Save a JSON-encodable map to storage
  Future<void> _setJsonMap(String key, Map<String, dynamic> data, {PreferenceSource source = PreferenceSource.local}) {
    return _writePreference(key, json.encode(data), source: source);
  }

  /// Save a string list as JSON array.
  Future<void> _setStringList(String key, List<String> list, {PreferenceSource source = PreferenceSource.local}) {
    return _writePreference(key, json.encode(list), source: source);
  }
}
