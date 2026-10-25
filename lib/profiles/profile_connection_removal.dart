/// Removing a connection from a profile, confirmed first: the one flow
/// behind the remove action on a profile's page and on Instellingen ▸ Servers
/// en bronnen (A-24b), so the downloads release, the cleanup and the rebind
/// cannot drift apart between the two.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../i18n/strings.g.dart';
import '../providers/download_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../services/storage_service.dart';
import '../utils/dialogs.dart';
import 'active_profile_binder.dart';
import 'profile.dart';
import 'profile_connection_cleanup.dart';
import 'profile_connection_registry.dart';

/// The server ids a connection's downloads belong to.
Set<String> serverIdsForConnection(Connection conn) {
  return switch (conn) {
    PlexAccountConnection(:final servers) => servers.map((s) => s.clientIdentifier).toSet(),
    JellyfinConnection(:final serverMachineId) => {serverMachineId},
    LocalFolderConnection(:final id) => {id},
    PleyaShareConnection(:final id) => {id},
    PleyaServerConnection(:final serverId) => {serverId},
  };
}

/// Asks, then releases the profile's downloads for [connection], removes the
/// binding with its cleanup and rebinds the profile when it is the active one.
Future<void> confirmAndRemoveProfileConnection(
  BuildContext context, {
  required Profile profile,
  required Connection connection,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: t.profiles.removeConnectionTitle,
    message: t.profiles.removeConnectionMessage(
      displayName: profile.displayName,
      connectionLabel: connection.displayLabel,
    ),
    confirmText: t.profiles.removeConnection,
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await context.read<DownloadProvider>().releaseDownloadsForProfileServers(
    profile.id,
    serverIdsForConnection(connection),
  );
  if (!context.mounted) return;
  await removeProfileConnectionAndCleanup(
    profileId: profile.id,
    connection: connection,
    profileConnections: context.read<ProfileConnectionRegistry>(),
    connections: context.read<ConnectionRegistry>(),
    storage: context.read<StorageService>(),
    serverManager: context.read<MultiServerProvider>().serverManager,
  );
  if (!context.mounted) return;
  await context.read<HiddenLibrariesProvider?>()?.refresh();
  if (!context.mounted) return;
  unawaited(context.read<ActiveProfileBinder>().rebindIfActive(profile.id));
}
