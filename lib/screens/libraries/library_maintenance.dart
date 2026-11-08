/// Library maintenance (scan, analyze, refresh metadata, empty trash) as the
/// library's own server offers it. Shared by the libraries menu and the TV
/// action sheet so both offer exactly what the client implements.
library;

import '../../media/ids.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../media/server_administration.dart';
import '../../services/multi_server_manager.dart';
import '../../services/plex_client.dart';

enum LibraryMaintenance { scan, analyze, refreshMetadata, emptyTrash }

/// The client that maintains [library]: its own server's, never another
/// server's, and only while the active profile may administer that server
/// (`canAdministerServer`: the owner on Plex, an administrator on Jellyfin and
/// Emby, owner or admin on Pleya Server) and the server exposes
/// administration. Null means no maintenance.
MediaServerClient? libraryMaintenanceClient(MultiServerManager servers, MediaLibrary library) {
  final serverId = serverIdOrNull(library.serverId);
  if (serverId == null || !servers.canAdministerServer(serverId)) return null;
  final client = servers.getClient(serverId);
  if (client case final ServerAdministrationClient admin when !admin.supportsServerAdministration) return null;
  return client;
}

/// What [client] can do for a library, in menu order. Analyze and empty
/// trash have no equivalent outside Plex.
List<LibraryMaintenance> libraryMaintenanceFor(MediaServerClient? client) => [
  // False alarm: the linter only sees the static type. Concrete clients
  // implement this capability contract, so the check is not always false.
  // ignore: avoid-unrelated-type-assertions
  if (client is LibraryScanClient) LibraryMaintenance.scan,
  if (client is PlexClient) LibraryMaintenance.analyze,
  if (client != null) LibraryMaintenance.refreshMetadata,
  if (client is PlexClient) LibraryMaintenance.emptyTrash,
];

/// Runs [action] on [client]. Only call with an action [libraryMaintenanceFor]
/// offered for that client.
Future<void> runLibraryMaintenance(MediaServerClient client, LibraryMaintenance action, String libraryId) =>
    switch (action) {
      LibraryMaintenance.scan => (client as LibraryScanClient).scanLibrary(libraryId),
      LibraryMaintenance.analyze => (client as PlexClient).analyzeLibrary(libraryId),
      LibraryMaintenance.refreshMetadata => client.refreshLibraryMetadata(libraryId),
      LibraryMaintenance.emptyTrash => (client as PlexClient).emptyLibraryTrash(libraryId),
    };
