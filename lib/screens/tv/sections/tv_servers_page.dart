/// Mijn Pleya ▸ Servers on TV, per the approved `servers-a` layout.
///
/// The section this replaces mounted `ConnectionsSection` — the desktop
/// settings card — inside a TV page. The heading sat on the canonical inset
/// but the card 1.5% further in and its group label 2% further still, three
/// edges on one page, and the focused row was marked by
/// `kSettingsFocusBarWidth`'s 3px bar rather than the white ring the rest of
/// the product uses.
///
/// Same registry, same actions, same confirmations. What changes is that a
/// connection is a tile, and that a server tile says what the audit found
/// missing at a glance: which backend it is, whether it answered, and how much
/// it is carrying.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../connection/connection.dart';
import '../../../connection/connection_registry.dart';
import '../../../focus/focus_memory_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../profiles/profile.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../widgets/tv/tv_menu_grid.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import '../../settings/add_connection_screen.dart';
import '../../settings/connections_section.dart';
import '../../settings/pleya_share_host_screen.dart';

class TvServersPage extends StatefulWidget {
  const TvServersPage({super.key});

  @override
  State<TvServersPage> createState() => _TvServersPageState();
}

class _TvServersPageState extends State<TvServersPage> {
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvServers');

  /// Subscribed once, not per build: `watchConnections()` hands back a fresh
  /// stream each call, and building one inside `build` is the treadmill
  /// `ConnectionsSection` carries a comment about.
  Stream<List<Connection>>? _rows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rows ??= context.read<ConnectionRegistry>().watchConnections();
  }

  @override
  void dispose() {
    _nodes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = context.select<ActiveProfileProvider, Profile?>((p) => p.active);
    final servers = context.watch<MultiServerProvider>();
    final libraries = context.watch<LibrariesProvider?>();
    final online = servers.onlineServerIds.toSet();
    final authErrors = servers.authErrorServerIds.toSet();

    return StreamBuilder<List<Connection>>(
      stream: _rows,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Connection>[];
        final pleyaServers = all.whereType<PleyaServerConnection>().toList();
        final localSources = all.where((c) => c is LocalFolderConnection || c is PleyaShareConnection).toList();

        return TvPageSurface(
          title: t.tvMyPleya.servers,
          automationInstance: 'servers',
          children: [
            TvMenuGrid(
              nodes: _nodes,
              columns: 2,
              automationInstance: 'servers',
              sections: [
                TvMenuSection(
                  label: t.connections.sectionTitle,
                  items: [
                    TvMenuItem(
                      key: 'servers_add',
                      icon: Symbols.add_link_rounded,
                      title: t.connections.addConnection,
                      subtitle: active == null
                          ? t.connections.addConnectionSubtitleNoProfile
                          : t.connections.addConnectionSubtitleScoped(displayName: active.displayName),
                      onSelect: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AddConnectionScreen(targetProfile: context.read<ActiveProfileProvider>().active),
                        ),
                      ),
                    ),
                    TvMenuItem(
                      key: 'servers_share',
                      icon: Symbols.share_rounded,
                      title: t.pleyaShare.hostTitle,
                      subtitle: t.pleyaShare.hostDescription,
                      onSelect: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const PleyaShareHostScreen()),
                      ),
                    ),
                  ],
                ),
                if (pleyaServers.isNotEmpty)
                  TvMenuSection(
                    label: t.connections.pleyaServers,
                    items: [
                      for (final server in pleyaServers)
                        TvMenuItem(
                          key: 'servers_server_${server.serverId}',
                          icon: Symbols.dns_rounded,
                          title: server.displayLabel,
                          // Backend identity, reachability and how much this
                          // one is carrying, on the line the audit found
                          // occupied by a host:port and nothing else.
                          value: _serverStatus(
                            server: server,
                            online: online.contains(server.serverId),
                            needsReauth: authErrors.contains(server.serverId),
                            libraryCount: libraries?.libraries.where((l) => l.serverId == server.serverId).length,
                          ),
                          onSelect: () => _disconnect(server),
                        ),
                    ],
                  ),
                if (localSources.isNotEmpty)
                  TvMenuSection(
                    label: t.connections.localSources,
                    items: [
                      for (final source in localSources)
                        TvMenuItem(
                          key: 'servers_source_${source.id}',
                          icon: Symbols.folder_rounded,
                          title: source.displayLabel,
                          value: source.displaySubtitle,
                          onSelect: () => _removeSource(source),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// "Pleya-server · Online · 2 bibliotheken", trimmed of whatever this
  /// connection cannot answer for.
  String _serverStatus({
    required PleyaServerConnection server,
    required bool online,
    required bool needsReauth,
    required int? libraryCount,
  }) => [
    t.connections.pleyaServers,
    if (needsReauth) t.connections.reauthRequired else if (online) t.common.online else t.common.offline,
    if (libraryCount != null && libraryCount > 0) t.tvMyPleya.libraryCount(count: libraryCount),
    server.userName,
  ].join(' · ');

  Future<void> _disconnect(PleyaServerConnection server) => ConnectionsRemoval.disconnectPleyaServer(context, server);

  Future<void> _removeSource(Connection source) => ConnectionsRemoval.removeLocalSource(context, source);
}
