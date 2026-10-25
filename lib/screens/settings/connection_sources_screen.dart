/// Instellingen ▸ Servers en bronnen ▸ one kind of source (A-24b, series
/// `ios/12`): Plex-servers beheren, Jellyfin- and Emby-bronnen beheren,
/// Pleya Server-bronnen beheren, and Bron ontkoppelen / verwijderen.
///
/// No new management: a Plex, Jellyfin or Emby row is the active profile's
/// connection with the profile page's own confirmed remove
/// ([confirmAndRemoveProfileConnection]) and Jellyfin's edit; a Pleya Server
/// or a source on this device keeps the device-wide disconnect this page
/// always had ([ConnectionsRemoval]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../profiles/profile_connection_removal.dart';
import '../../profiles/profiles_view.dart';
import '../../providers/multi_server_provider.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'connections_section.dart';
import 'edit_jellyfin_connection_screen.dart';

/// What a [ConnectionSourcesScreen] lists.
enum ConnectionSourceKind { plex, jellyfin, emby, pleyaServer, removable }

/// Whether [connection] belongs on the page for [kind].
bool connectionSourceMatches(ConnectionSourceKind kind, Connection connection) => switch (kind) {
  ConnectionSourceKind.plex => connection is PlexAccountConnection,
  ConnectionSourceKind.jellyfin => connection is JellyfinConnection && !connection.isEmby,
  ConnectionSourceKind.emby => connection is JellyfinConnection && connection.isEmby,
  ConnectionSourceKind.pleyaServer => connection is PleyaServerConnection,
  ConnectionSourceKind.removable =>
    connection is PleyaServerConnection || connection is LocalFolderConnection || connection is PleyaShareConnection,
};

/// The row label that opens the page for [kind].
String connectionSourceTitle(ConnectionSourceKind kind) {
  final s = t.settingsStudio;
  return switch (kind) {
    ConnectionSourceKind.plex => s.managePlex,
    ConnectionSourceKind.jellyfin => s.manageJellyfin,
    ConnectionSourceKind.emby => s.manageEmby,
    ConnectionSourceKind.pleyaServer => s.managePleyaServer,
    ConnectionSourceKind.removable => s.removeSource,
  };
}

class ConnectionSourcesScreen extends StatefulWidget {
  const ConnectionSourcesScreen({super.key, required this.kind});

  final ConnectionSourceKind kind;

  @override
  State<ConnectionSourcesScreen> createState() => _ConnectionSourcesScreenState();
}

class _ConnectionSourcesScreenState extends State<ConnectionSourcesScreen> {
  // Subscribed once, not per build (see ConnectionsSection).
  Stream<List<Connection>>? _connections;
  Stream<List<ProfileConnection>>? _bindings;
  String? _boundProfileId;

  /// Profile-scoped kinds: the active profile's own connections.
  bool get _scoped => switch (widget.kind) {
    ConnectionSourceKind.plex || ConnectionSourceKind.jellyfin || ConnectionSourceKind.emby => true,
    _ => false,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connections ??= context.read<ConnectionRegistry>().watchConnections();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.select<ActiveProfileProvider, Profile?>((p) => p.active);
    if (_scoped && profile != null && profile.id != _boundProfileId) {
      _boundProfileId = profile.id;
      _bindings = context.read<ProfileConnectionRegistry>().watchForProfile(profile.id);
    }
    return SettingsPage(
      title: Text(connectionSourceTitle(widget.kind)),
      children: [
        StreamBuilder<List<Connection>>(
          stream: _connections,
          builder: (context, all) => !_scoped
              ? _deviceList(all.data ?? const [])
              : StreamBuilder<List<ProfileConnection>>(
                  stream: _bindings,
                  builder: (context, pcs) => _profileList(profile, all.data ?? const [], pcs.data ?? const []),
                ),
        ),
      ],
    );
  }

  /// Pleya Servers and the sources on this device, removed device-wide.
  Widget _deviceList(List<Connection> all) {
    final authErrorIds = context.watch<MultiServerProvider>().authErrorServerIds.toSet();
    final rows = [
      for (final connection in all)
        if (connectionSourceMatches(widget.kind, connection))
          ConnectionSourceRow(
            title: connection.displayLabel,
            subtitle: connection is PleyaServerConnection && authErrorIds.contains(connection.serverId)
                ? '${connection.displaySubtitle} · ${t.connections.reauthRequired}'
                : connection.displaySubtitle,
            removeTooltip: connection is PleyaServerConnection
                ? t.connections.disconnectServer
                : t.connections.removeSource,
            onRemove: () => unawaited(
              connection is PleyaServerConnection
                  ? ConnectionsRemoval.disconnectPleyaServer(context, connection)
                  : ConnectionsRemoval.removeLocalSource(context, connection),
            ),
          ),
    ];
    return _card(rows);
  }

  /// The active profile's connections of this kind, with the profile page's
  /// own remove; a Plex Home profile's parent account is shown and kept.
  Widget _profileList(Profile? profile, List<Connection> all, List<ProfileConnection> pcs) {
    if (profile == null) return _card(const []);
    final byId = {for (final c in all) c.id: c};
    final parent = profile.isPlexHome ? byId[profile.parentConnectionId] : null;
    final rows = <Widget>[
      if (parent != null && connectionSourceMatches(widget.kind, parent))
        ConnectionSourceRow(title: parent.displayLabel, subtitle: t.profiles.plexHomeAccount),
      for (final pc in visibleProfileConnections(profile, pcs))
        if (byId[pc.connectionId] case final connection? when connectionSourceMatches(widget.kind, connection))
          ConnectionSourceRow(
            title: connection.displayLabel,
            subtitle: connection.displaySubtitle,
            onEdit: connection is JellyfinConnection
                ? () => unawaited(
                    Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => EditJellyfinConnectionScreen(connection: connection)),
                    ),
                  )
                : null,
            removeTooltip: t.profiles.removeConnection,
            onRemove: () =>
                unawaited(confirmAndRemoveProfileConnection(context, profile: profile, connection: connection)),
          ),
    ];
    return _card(rows);
  }

  Widget _card(List<Widget> rows) {
    if (rows.isEmpty) return SettingsFootnote(t.profiles.noConnectionsHint);
    return SettingsGroup(children: rows);
  }
}

/// One source: its name, what and where it is, and the remove in the
/// destructive ink (and Jellyfin's edit). A single focus stop whose SELECT is
/// the remove, as the D-pad walked it before.
class ConnectionSourceRow extends StatelessWidget {
  const ConnectionSourceRow({
    super.key,
    required this.title,
    this.subtitle,
    this.removeTooltip,
    this.onRemove,
    this.onEdit,
  });

  final String title;
  final String? subtitle;
  final String? removeTooltip;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final onRemove = this.onRemove;
    final onEdit = this.onEdit;
    return SettingRowFocus(
      enabled: onRemove != null,
      onSelect: onRemove,
      child: ListTile(
        contentPadding: settingRowPadding(),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(tooltip: t.common.edit, icon: const AppIcon(Symbols.edit_rounded), onPressed: onEdit),
            if (onRemove != null)
              IconButton(
                tooltip: removeTooltip,
                icon: Icon(Symbols.delete_outline_rounded, color: settingsDestructiveInk(context)),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
