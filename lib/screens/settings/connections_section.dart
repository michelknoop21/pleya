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
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../profile/borrow_connection_screen.dart';
import 'add_jellyfin_screen.dart';
import 'add_local_folder_screen.dart';
import 'add_plex_account_screen.dart';
import 'add_pleya_server_screen.dart';
import 'connection_sources_screen.dart';
import 'pleya_share_host_screen.dart';
import 'pleya_share_join_screen.dart';

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
  /// the same registry made that a treadmill that never draws a row. Since
  /// A-24b one builder reads it, for which kinds of source exist.
  Stream<List<Connection>>? _serverRows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = context.read<ConnectionRegistry>();
    _serverRows ??= registry.watchConnections();
  }

  @override
  Widget build(BuildContext context) => _buildConnectionsSection();

  /// Series `ios/12` (A-24b): Bestaande bronnen, one row per kind this
  /// device has (each opens its own list with the remove it always had) and
  /// the removal of a source in the destructive ink; then Verbinding
  /// toevoegen, one row per way to add a connection, the add flows the
  /// picker opens, and hosting a Pleya Share.
  Widget _buildConnectionsSection() {
    final active = context.select<ActiveProfileProvider, Profile?>((p) => p.active);
    return StreamBuilder<List<Connection>>(
      stream: _serverRows,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Connection>[];
        bool has(ConnectionSourceKind kind) => all.any((c) => connectionSourceMatches(kind, c));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroup(
              title: t.settingsStudio.existingSources,
              children: [
                for (final kind in const [
                  ConnectionSourceKind.plex,
                  ConnectionSourceKind.jellyfin,
                  ConnectionSourceKind.emby,
                  ConnectionSourceKind.pleyaServer,
                ])
                  if (has(kind)) _sourcesRow(kind),
                if (has(ConnectionSourceKind.removable)) _sourcesRow(ConnectionSourceKind.removable, destructive: true),
              ],
            ),
            SettingsGroup(
              title: t.connections.addConnection,
              children: [
                _addRow(
                  'plex',
                  Symbols.link_rounded,
                  t.settingsStudio.linkPlex,
                  (_) => AddPlexAccountScreen(targetProfile: active),
                ),
                _addRow(
                  'jellyfin',
                  Symbols.add_rounded,
                  t.settingsStudio.addJellyfin,
                  (_) => AddJellyfinScreen(targetProfile: active),
                ),
                _addRow(
                  'emby',
                  Symbols.add_rounded,
                  t.settingsStudio.addEmby,
                  (_) => AddJellyfinScreen(targetProfile: active, emby: true),
                ),
                _addRow(
                  'pleya_server',
                  Symbols.add_rounded,
                  t.settingsStudio.addPleyaServer,
                  (_) => AddPleyaServerScreen(targetProfile: active),
                ),
                _addRow(
                  'local_folder',
                  Symbols.folder_rounded,
                  t.addLocalFolder.cardTitle,
                  (_) => AddLocalFolderScreen(targetProfile: active),
                ),
                _addRow(
                  'pleya_share',
                  Symbols.devices_rounded,
                  t.pleyaShare.cardTitle,
                  (_) => PleyaShareJoinScreen(targetProfile: active),
                ),
                if (active != null)
                  _addRow(
                    'borrow',
                    Symbols.group_rounded,
                    t.addServer.borrowFromAnotherProfile,
                    (_) => BorrowConnectionScreen(targetProfile: active),
                  ),
                SettingNavigationTile(
                  icon: Symbols.share_rounded,
                  title: t.pleyaShare.hostTitle,
                  subtitle: t.pleyaShare.hostDescription,
                  automationInstance: 'settings.settings_pleya_share',
                  onTap: () => pushSettingsPage(context, (_) => const PleyaShareHostScreen(), id: 'pleyaShareHost'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _sourcesRow(ConnectionSourceKind kind, {bool destructive = false}) => AutomationNode(
    id: AutomationIds.settingsTile,
    instance: 'sources.${kind.name}',
    role: 'list.item',
    child: SettingNavigationTile(
      icon: destructive ? Symbols.delete_outline_rounded : Symbols.dns_rounded,
      title: connectionSourceTitle(kind),
      destructive: destructive,
      automationInstance: 'settings.sources.${kind.name}',
      destinationBuilder: (_) => ConnectionSourcesScreen(kind: kind),
    ),
  );

  /// A way to add a connection: the flow the picker opens for it.
  Widget _addRow(String instance, IconData icon, String title, WidgetBuilder builder) => AutomationNode(
    id: AutomationIds.settingsTile,
    instance: 'add.$instance',
    role: 'list.item',
    child: SettingNavigationTile(
      icon: icon,
      title: title,
      automationInstance: 'settings.add.$instance',
      onTap: () => pushSettingsPage(context, builder, id: 'add.$instance'),
    ),
  );
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
