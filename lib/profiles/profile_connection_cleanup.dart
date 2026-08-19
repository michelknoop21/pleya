import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../media/ids.dart';
import '../services/multi_server_manager.dart';
import '../services/storage_service.dart';
import 'profile_connection_registry.dart';

Future<void> removeProfileConnectionAndCleanup({
  required String profileId,
  required Connection connection,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  final removedServerIds = _serverIdsForConnection(connection);
  await profileConnections.remove(profileId, connection.id);
  await _clearProfileServerPrefsNoLongerReferenced(
    profileId: profileId,
    removedServerIds: removedServerIds,
    profileConnections: profileConnections,
    connections: connections,
    storage: storage,
    clearEverywhereWhenUnreferenced: connection is JellyfinConnection,
  );

  if (connection is JellyfinConnection) {
    await _removeUnreferencedJellyfinConnection(
      connection,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
  }

  // Een lokale map heeft geen account achter zich: zodra geen enkel profiel er
  // nog naar verwijst, verwijderen we de bron zelf én de runtime-client, anders
  // blijft hij in content opduiken.
  if (connection is LocalFolderConnection && (await profileConnections.listForConnection(connection.id)).isEmpty) {
    await connections.remove(connection.id);
    serverManager?.removeLocalSource(connection);
    final serverId = ServerId.tryParse(connection.id);
    if (serverId != null) {
      await storage.clearLibraryPreferencesForServerEverywhere(serverId);
    }
  }

  // Zelfde verhaal voor een Pleya Share-koppeling: ongerefereerd = unpair.
  if (connection is PleyaShareConnection && (await profileConnections.listForConnection(connection.id)).isEmpty) {
    await connections.remove(connection.id);
    serverManager?.removePleyaShareSource(connection);
    final serverId = ServerId.tryParse(connection.id);
    if (serverId != null) {
      await storage.clearLibraryPreferencesForServerEverywhere(serverId);
    }
  }
}

/// Remove [connection] from the device entirely: every profile binding plus —
/// for device-bound sources (local folders, Pleya Share) — the connection row,
/// runtime client, and library prefs. Also handles orphan rows that were never
/// bound to a profile (added without an active profile, or bound to a
/// since-vanished virtual Plex Home profile).
Future<void> removeConnectionCompletely({
  required Connection connection,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  for (final row in await profileConnections.listForConnection(connection.id)) {
    await removeProfileConnectionAndCleanup(
      profileId: row.profileId,
      connection: connection,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
  }
  // Orphan (no bindings) — the per-profile path never ran; clean up directly.
  if (await connections.get(connection.id) != null &&
      (connection is LocalFolderConnection || connection is PleyaShareConnection)) {
    await connections.remove(connection.id);
    if (connection is LocalFolderConnection) serverManager?.removeLocalSource(connection);
    if (connection is PleyaShareConnection) serverManager?.removePleyaShareSource(connection);
    final serverId = ServerId.tryParse(connection.id);
    if (serverId != null) {
      await storage.clearLibraryPreferencesForServerEverywhere(serverId);
    }
  }
}

Future<void> removeAllProfileConnectionsAndCleanup({
  required String profileId,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  final rows = await profileConnections.listForProfile(profileId);
  if (rows.isEmpty) return;

  final all = await connections.list();
  final byId = {for (final connection in all) connection.id: connection};
  for (final row in rows) {
    final connection = byId[row.connectionId];
    if (connection == null) {
      await profileConnections.remove(profileId, row.connectionId);
      continue;
    }
    await removeProfileConnectionAndCleanup(
      profileId: profileId,
      connection: connection,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
  }
}

Future<int> pruneUnreferencedJellyfinConnections({
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  final all = await connections.list();
  final referencedConnectionIds = (await profileConnections.listAll()).map((row) => row.connectionId).toSet();
  var removed = 0;

  for (final connection in all.whereType<JellyfinConnection>()) {
    if (referencedConnectionIds.contains(connection.id)) continue;
    await _removeJellyfinConnection(
      connection,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
    removed++;
  }

  return removed;
}

Future<void> _removeUnreferencedJellyfinConnection(
  JellyfinConnection connection, {
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  if ((await profileConnections.listForConnection(connection.id)).isNotEmpty) return;
  await _removeJellyfinConnection(
    connection,
    profileConnections: profileConnections,
    connections: connections,
    storage: storage,
    serverManager: serverManager,
  );
}

Future<void> _removeJellyfinConnection(
  JellyfinConnection connection, {
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  await connections.remove(connection.id);
  serverManager?.removeJellyfinConnection(connection);
  final serverId = ServerId.tryParse(connection.serverMachineId);
  if (serverId != null &&
      !await _isServerReferenced(serverId, profileConnections: profileConnections, connections: connections)) {
    await storage.clearLibraryPreferencesForServerEverywhere(serverId);
  }
}

Future<void> _clearProfileServerPrefsNoLongerReferenced({
  required String profileId,
  required Set<ServerId> removedServerIds,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  required bool clearEverywhereWhenUnreferenced,
}) async {
  if (removedServerIds.isEmpty) return;
  final remainingProfileServerIds = await _serverIdsForProfile(
    profileId,
    profileConnections: profileConnections,
    connections: connections,
  );
  final activeProfileId = storage.getActiveProfileId();

  for (final serverId in removedServerIds) {
    if (remainingProfileServerIds.contains(serverId)) continue;
    final serverStillReferenced = await _isServerReferenced(
      serverId,
      profileConnections: profileConnections,
      connections: connections,
    );
    if (serverStillReferenced || !clearEverywhereWhenUnreferenced) {
      await storage.clearLibraryPreferencesForServer(
        serverId,
        profileId: profileId,
        includeLegacy: activeProfileId == profileId,
      );
    } else {
      await storage.clearLibraryPreferencesForServerEverywhere(serverId);
    }
  }
}

Future<Set<ServerId>> _serverIdsForProfile(
  String profileId, {
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
}) async {
  final rows = await profileConnections.listForProfile(profileId);
  if (rows.isEmpty) return const {};

  final all = await connections.list();
  final byId = {for (final connection in all) connection.id: connection};
  return {
    for (final row in rows)
      if (byId[row.connectionId] case final connection?) ..._serverIdsForConnection(connection),
  };
}

Future<bool> _isServerReferenced(
  ServerId serverId, {
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
}) async {
  final rows = await profileConnections.listAll();
  if (rows.isEmpty) return false;

  final all = await connections.list();
  final byId = {for (final connection in all) connection.id: connection};
  for (final row in rows) {
    final connection = byId[row.connectionId];
    if (connection != null && _serverIdsForConnection(connection).contains(serverId)) return true;
  }
  return false;
}

Set<ServerId> _serverIdsForConnection(Connection connection) {
  return switch (connection) {
    PlexAccountConnection(:final servers) => {
      for (final server in servers) ?ServerId.tryParse(server.clientIdentifier),
    },
    JellyfinConnection(:final serverMachineId) => {?ServerId.tryParse(serverMachineId)},
    LocalFolderConnection(:final id) => {?ServerId.tryParse(id)},
    PleyaShareConnection(:final id) => {?ServerId.tryParse(id)},
    PleyaServerConnection(:final serverId) => {?ServerId.tryParse(serverId)},
  };
}
