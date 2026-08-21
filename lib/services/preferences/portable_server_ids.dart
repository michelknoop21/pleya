import '../../connection/connection.dart';
import 'preference_value_portability.dart';

/// The set of server ids that identify the same server on any device.
///
/// Built from the connection rows rather than guessed from the id string,
/// because only the connection knows where its id came from. Deny by default:
/// a backend is portable when it can be shown to be, never because nothing
/// said otherwise.
///
/// | kind | server id | portable |
/// |---|---|---|
/// | plex | `PlexServer.clientIdentifier` from plex.tv `/resources` | yes |
/// | jellyfin | `serverMachineId` from the server's own `machineId` | yes |
/// | local | the local `connection.id` row key | no |
/// | pleyaShare | the local `connection.id` row key | no |
///
/// A local folder is device-bound by nature, so excluding it costs nothing:
/// there is no second device where "hide this folder's library" would mean
/// anything. Pleya Share is excluded because its identity is the pairing row,
/// which is per-installation as well.
class PortableServerIds {
  const PortableServerIds(this._ids);

  const PortableServerIds.empty() : _ids = const <String>{};

  final Set<String> _ids;

  /// Collect the portable server ids from [connections].
  factory PortableServerIds.fromConnections(Iterable<Connection> connections) {
    final ids = <String>{};
    for (final connection in connections) {
      switch (connection) {
        case PlexAccountConnection(:final servers):
          // One account can front several servers; each carries plex.tv's own
          // identifier for that server.
          for (final server in servers) {
            if (server.clientIdentifier.isNotEmpty) ids.add(server.clientIdentifier);
          }
        case JellyfinConnection(:final serverMachineId):
          if (serverMachineId.isNotEmpty) ids.add(serverMachineId);
        case LocalFolderConnection():
        case PleyaShareConnection():
          // Identified by a locally generated row id. Never portable.
          break;
      }
    }
    return PortableServerIds(ids);
  }

  bool contains(String serverId) => _ids.contains(serverId);

  IsServerIdPortable get predicate => contains;

  int get length => _ids.length;

  @override
  String toString() => 'PortableServerIds(${_ids.length})';
}
