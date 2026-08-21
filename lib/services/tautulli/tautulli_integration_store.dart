import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import 'tautulli_account_store.dart';
import 'tautulli_server_integration.dart';
import 'tautulli_session.dart';

/// Device-wide persistence for Tautulli integrations, one record per monitored
/// Plex server, keyed `tautulli_integration_{machineIdentifier}`.
///
/// Deliberately not scoped to a profile. The admin pairs a *server* once and
/// every local profile that has that server benefits; scoping the key to a
/// profile would force each household member to hold the admin credential.
/// The blob is protected exactly as the old per-profile session was, by the
/// same device-local [CredentialVault] key, and `tautulli_integration_` is a
/// deny prefix in `SettingsExportService`, so it never reaches an export or an
/// iCloud payload.
class TautulliIntegrationStore {
  TautulliIntegrationStore._();
  static final TautulliIntegrationStore instance = TautulliIntegrationStore._();

  static const String keyPrefix = 'tautulli_integration_';

  static String keyFor(String machineIdentifier) => '$keyPrefix$machineIdentifier';

  /// Every stored integration, keyed by machine identifier.
  ///
  /// A record that cannot be parsed at all is skipped with a log line rather
  /// than taking the rest down with it; the remaining servers keep working.
  Future<Map<String, TautulliServerIntegration>> loadAll() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final out = <String, TautulliServerIntegration>{};
    for (final key in prefs.keys.where((k) => k.startsWith(keyPrefix))) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final integration = await TautulliServerIntegration.decode(raw);
        out[integration.machineIdentifier] = integration;
      } catch (e) {
        appLogger.w('TautulliIntegrationStore: unreadable record, skipping', error: e);
      }
    }
    return out;
  }

  Future<void> save(TautulliServerIntegration integration) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(keyFor(integration.machineIdentifier), await integration.encode());
  }

  /// Removes a record outright. Disconnecting does *not* use this: it clears
  /// the credential and keeps the admin's policy, because deleting a credential
  /// is not the same act as revoking a decision.
  Future<void> remove(String machineIdentifier) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(keyFor(machineIdentifier));
  }

  /// Moves a legacy per-profile session into the server-scoped store.
  ///
  /// Returns the resulting record for [userUuid], or null when there is nothing
  /// to migrate. Two cases are deliberately different:
  ///
  ///  * With a `pms_identifier` the session becomes a normal integration and
  ///    the legacy key is removed. The policy starts unset, so an existing
  ///    working pairing keeps working and lands on the default (on).
  ///  * Without one there is no server to key it under. The legacy key stays
  ///    put and keeps serving the presence surfaces exactly as before; import
  ///    refuses anyway, because it demands an exact identifier match. Re-pairing
  ///    fetches the identifier and migrates it then.
  ///
  /// Several profiles can each hold a legacy session for the *same* server, and
  /// then there is no defensible way to pick one: prefs keys carry no recency,
  /// so "newest wins" does not exist, and choosing by profile order would make
  /// the household's Tautulli URL and credential depend on who signed in first.
  /// So:
  ///
  ///  * Identical pairings (same URL, auth mode and token) are a duplicate, not
  ///    a conflict. The legacy blob is dropped and nothing changes.
  ///  * Differing pairings mark the surviving record
  ///    [TautulliServerIntegration.hasUnresolvedConflict], which switches import
  ///    off until an admin re-pairs. Credentials are never merged and the
  ///    existing record's token is left exactly as it was. The legacy blob is
  ///    cleared so the same conflict is not rediscovered on every launch.
  ///
  /// The log line names the category only, never a URL, a token or a profile.
  Future<TautulliServerIntegration?> migrateLegacySession(String userUuid) async {
    final legacy = await TautulliAccountStore.instance.load(userUuid);
    if (legacy == null) return null;

    final identifier = legacy.machineIdentifier?.trim() ?? '';
    if (identifier.isEmpty) {
      appLogger.i('TautulliIntegrationStore: legacy session has no server identifier, leaving it profile-scoped');
      return null;
    }

    final candidate = TautulliServerIntegration.fromSession(
      legacy,
      machineIdentifier: identifier,
      configuredByProfileId: userUuid.isEmpty ? null : userUuid,
    );

    final existing = (await loadAll())[identifier];
    if (existing != null) {
      await TautulliAccountStore.instance.clear(userUuid);
      if (existing.describesSamePairing(candidate)) {
        appLogger.i('TautulliIntegrationStore: duplicate legacy session for a known server, discarded');
        return existing;
      }
      if (existing.hasUnresolvedConflict) return existing;
      final flagged = existing.copyWith(hasUnresolvedConflict: true);
      await save(flagged);
      appLogger.w(
        'TautulliIntegrationStore: conflicting legacy pairings for one server, '
        'import disabled until an admin re-pairs',
      );
      return flagged;
    }

    await save(candidate);
    await TautulliAccountStore.instance.clear(userUuid);
    appLogger.i('TautulliIntegrationStore: migrated a legacy session to the server-scoped store');
    return candidate;
  }

  /// The legacy per-profile session, for the presence surfaces of a profile
  /// whose pairing predates `pms_identifier` and therefore cannot be migrated.
  Future<TautulliSession?> loadLegacySession(String userUuid) => TautulliAccountStore.instance.load(userUuid);

  /// Stores a pairing that reported no server identifier. It stays
  /// profile-scoped and can never feed an import, which needs an exact match.
  Future<void> saveLegacySession(String userUuid, TautulliSession session) =>
      TautulliAccountStore.instance.save(userUuid, session);

  Future<void> clearLegacySession(String userUuid) => TautulliAccountStore.instance.clear(userUuid);
}
