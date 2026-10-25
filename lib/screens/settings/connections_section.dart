import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection_cleanup.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/storage_service.dart';
import '../../utils/dialogs.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/setting_tile.dart';
import 'add_connection_screen.dart';
import 'pleya_share_host_screen.dart';

/// The "Servers en bronnen" page's content: the connections this device
/// already has, adding one, and hosting a Pleya Share.
///
/// Its own widget because it is the only part of that screen with real
/// behaviour behind it, and because a section nobody could pump is a section
/// nobody tested. The bug that produced it was exactly that: a Pleya Server
/// was filtered out of every list here and had no way to be removed, and no
/// test could have noticed.
class ConnectionsSection extends StatefulWidget {
  const ConnectionsSection({super.key});

  @override
  State<ConnectionsSection> createState() => _ConnectionsSectionState();
}

class _ConnectionsSectionState extends State<ConnectionsSection> {
  /// Subscribed once, not per build.
  ///
  /// `watchConnections()` returns a fresh stream on every call, so building it
  /// inside `build` handed each rebuild a stream that starts at "waiting" and
  /// then rebuilt on its first event, which starts another one. Two lists on
  /// the same registry made that a treadmill that never draws a row.
  /// One per list, and not shared: a single stream handed to two builders is
  /// a race over who is listening when it emits.
  Stream<List<Connection>>? _serverRows;
  Stream<List<Connection>>? _sourceRows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = context.read<ConnectionRegistry>();
    _serverRows ??= registry.watchConnections();
    _sourceRows ??= registry.watchConnections();
  }

  @override
  Widget build(BuildContext context) => _buildConnectionsSection();

  /// Series `ios/12` (A-24b): the sources this device already has first, in
  /// one card, then the two ways to add one. The card of existing sources is
  /// left out while there are none ([SettingsGroup] draws nothing empty).
  Widget _buildConnectionsSection() {
    final active = context.select<ActiveProfileProvider, Profile?>((p) => p.active);
    final subtitle = active == null
        ? t.connections.addConnectionSubtitleNoProfile
        : t.connections.addConnectionSubtitleScoped(displayName: active.displayName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildExistingSources(),
        SettingsGroup(
          title: t.connections.addConnection,
          children: [
            // Connections are managed per-profile (via the Profiles section
            // and each profile's detail screen). The shortcut here just opens
            // the picker scoped to the active profile so users can add a Plex
            // account, Jellyfin server, or borrow from another profile.
            SettingNavigationTile(
              icon: Symbols.add_link_rounded,
              title: t.connections.addConnection,
              subtitle: subtitle,
              onTap: () {
                final active = context.read<ActiveProfileProvider>().active;
                Navigator.push(
                  context,
                  settingsStudioRoute<void>(context, (_) => AddConnectionScreen(targetProfile: active)),
                );
              },
            ),
            SettingNavigationTile(
              icon: Symbols.share_rounded,
              title: t.pleyaShare.hostTitle,
              subtitle: t.pleyaShare.hostDescription,
              onTap: () {
                Navigator.push(context, settingsStudioRoute<void>(context, (_) => const PleyaShareHostScreen()));
              },
            ),
          ],
        ),
      ],
    );
  }

  /// The Pleya Servers this device is signed in to, then the device-bound
  /// sources (local folders, Pleya Share hosts), each removable here.
  ///
  /// A Pleya Server is not on this device but an account on a server
  /// somewhere; it used to appear in no list here, so the only way to
  /// disconnect one was two screens deep under Profiles. The device-bound
  /// sources are removable regardless of profile bindings: this is also the
  /// escape hatch for rows orphaned by a vanished (virtual Plex Home) profile
  /// or a profile-less add.
  Widget _buildExistingSources() {
    // `watch`, not `select`. A selector returning a collection compares it with
    // `==`, and a fresh Set is never equal to the previous one, so every build
    // looked like a change and the section rebuilt itself without end.
    final authErrorIds = context.watch<MultiServerProvider>().authErrorServerIds.toSet();
    return StreamBuilder<List<Connection>>(
      stream: _serverRows,
      builder: (context, serverSnapshot) => StreamBuilder<List<Connection>>(
        stream: _sourceRows,
        builder: (context, sourceSnapshot) {
          final servers = (serverSnapshot.data ?? const <Connection>[]).whereType<PleyaServerConnection>().toList();
          final sources = (sourceSnapshot.data ?? const <Connection>[])
              .where((c) => c is LocalFolderConnection || c is PleyaShareConnection)
              .toList();
          return SettingsGroup(
            title: t.settingsStudio.existingSources,
            children: [
              for (final server in servers)
                _connectionRow(
                  icon: Symbols.dns_rounded,
                  title: server.displayLabel,
                  // The durable place to see "this one needs a sign-in", so the
                  // top-of-app bar does not have to be the only carrier of it.
                  subtitle: authErrorIds.contains(server.serverId)
                      ? '${server.displaySubtitle} · ${t.connections.reauthRequired}'
                      : server.displaySubtitle,
                  kind: t.connections.pleyaServers,
                  removeTooltip: t.connections.disconnectServer,
                  onRemove: () => _disconnectPleyaServer(server),
                ),
              for (final source in sources)
                _connectionRow(
                  icon: source is PleyaShareConnection ? Symbols.devices_rounded : Symbols.folder_rounded,
                  title: source.displayLabel,
                  subtitle: source.displaySubtitle,
                  kind: t.connections.localSources,
                  removeTooltip: t.connections.removeSource,
                  onRemove: () => _removeLocalSource(source),
                ),
            ],
          );
        },
      ),
    );
  }

  /// One removable connection row. Both lists use it so the row stays a single
  /// focus target with the same shape, which is what a D-pad walks.
  ///
  /// [kind] says what the source is ("Pleya Servers", "Lokale bronnen") now
  /// that both kinds share one card: on the line under the title, before the
  /// address, and so also to VoiceOver.
  Widget _connectionRow({
    required IconData icon,
    required String title,
    required String? subtitle,
    required String kind,
    required String removeTooltip,
    required VoidCallback onRemove,
  }) {
    final theme = Theme.of(context);
    final line = subtitle == null ? kind : '$kind · $subtitle';
    return SettingRowFocus(
      onSelect: onRemove,
      child: ListTile(
        contentPadding: settingRowPadding(),
        leading: SettingsIconStyleScope.of(context) == SettingsIconStyle.none
            ? null
            : Icon(icon, fill: 1, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: removeTooltip,
          icon: Icon(Symbols.delete_outline_rounded, color: settingsDestructiveInk(context)),
          onPressed: onRemove,
        ),
      ),
    );
  }

  /// Disconnecting is a local action and stays available whatever the server
  /// is doing: offline, expired, or gone for good. Nothing here waits on it.
  Future<void> _disconnectPleyaServer(PleyaServerConnection server) =>
      ConnectionsRemoval.disconnectPleyaServer(context, server);

  Future<void> _removeLocalSource(Connection source) => ConnectionsRemoval.removeLocalSource(context, source);
}

/// The confirm-then-remove flows behind a connection row, as functions rather
/// than private methods on one screen's State.
///
/// `TvServersPage` draws the same connections as tiles. Copying these two
/// dialogs and the five-step teardown behind them would be two places to keep
/// a destructive path in agreement; this is one, and both presentations call
/// it with their own context.
class ConnectionsRemoval {
  const ConnectionsRemoval._();

  static Future<void> disconnectPleyaServer(BuildContext context, PleyaServerConnection server) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.connections.disconnectServer,
      message: t.connections.disconnectServerConfirm(name: server.displayLabel),
      confirmText: t.connections.disconnectServer,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await removeLocally(context, server);
  }

  static Future<void> removeLocalSource(BuildContext context, Connection source) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.connections.removeSource,
      message: t.connections.removeSourceConfirm(name: source.displayLabel),
      confirmText: t.common.delete,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await removeLocally(context, source);
  }

  static Future<void> removeLocally(BuildContext context, Connection connection) async {
    final profileConnections = context.read<ProfileConnectionRegistry>();
    final connections = context.read<ConnectionRegistry>();
    final serverManager = context.read<MultiServerProvider>().serverManager;
    final storage = await StorageService.getInstance();
    await removeConnectionCompletely(
      connection: connection,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
    if (!context.mounted) return;
    await context.read<HiddenLibrariesProvider?>()?.refresh();
    if (!context.mounted) return;
    final activeId = context.read<ActiveProfileProvider>().active?.id;
    if (activeId != null) {
      final rebind = context.read<ActiveProfileBinder?>()?.rebindIfActive(activeId);
      if (rebind != null) unawaited(rebind);
    }
  }
}
