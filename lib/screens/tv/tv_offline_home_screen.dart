/// MOC-23 (PB-12): the TV offline Home.
///
/// Hoofdstuk 21.2's discovery snapshot (a persisted "last known Home" with an
/// age stamp, so "Verder kijken" survives offline) does not exist anywhere in
/// the codebase yet, on any platform — building it is a separate, larger
/// round Michel deliberately did not fold into this one. So this is the
/// scoped-down candidate: a reconnect affordance, the servers this device
/// knows about with a status line each, and a way into Settings. My Pleya and
/// Settings stay reachable through the shell regardless (hoofdstuk 18.3).
///
/// Single-column focus order (title/body, then the two actions, then the
/// server rows) rather than the mockup's two-column layout: [TvMenuGrid] has
/// no exit-left hook, so a left/right split would leave LEFT off the first
/// server row with nowhere defined to go. Vertical order needs only
/// exitUp/exitDown, which the grid already gives for free.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../providers/multi_server_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_panel_primitives.dart';
import '../../widgets/tv/tv_unified_layout.dart';

class TvOfflineHomeScreen extends StatefulWidget {
  const TvOfflineHomeScreen({
    super.key,
    required this.isReconnecting,
    required this.onReconnect,
    required this.onManageServers,
  });

  final bool isReconnecting;
  final VoidCallback onReconnect;
  final VoidCallback onManageServers;

  @override
  State<TvOfflineHomeScreen> createState() => _TvOfflineHomeScreenState();
}

class _TvOfflineHomeScreenState extends State<TvOfflineHomeScreen> {
  static const String _reconnectKey = 'offlineHome_reconnect';
  static const String _manageServersKey = 'offlineHome_manageServers';

  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvOfflineHome');

  /// Subscribed once, not per build — see `ConnectionsSection`'s comment on
  /// the same pattern: `watchConnections()` hands back a fresh stream on
  /// every call, and building one inside `build` never settles.
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

  void _focusButtons() {
    final node = _nodes.nodeFor(_reconnectKey) ?? _nodes.nodeFor(_manageServersKey);
    if (node != null && node.canRequestFocus) node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final authErrorIds = context.watch<MultiServerProvider>().authErrorServerIds.toSet();

    return StreamBuilder<List<Connection>>(
      stream: _rows,
      builder: (context, snapshot) {
        final servers = (snapshot.data ?? const <Connection>[])
            .where((c) => c is! LocalFolderConnection && c is! PleyaShareConnection)
            .toList();
        void focusFirstServer() {
          if (servers.isEmpty) return;
          _nodes.get('offlineHome_server_${servers.first.id}').requestFocus();
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              TvDiscoveryLayout.pageInset * scale,
              TvCatalogLayout.topSafeInset * scale,
              TvDiscoveryLayout.pageInset * scale,
              TvCatalogLayout.bottomSafeInset * scale,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 640 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.tvOfflineHome.title,
                    style: TextStyle(fontSize: 32 * scale, fontWeight: FontWeight.w700, color: tk.text),
                  ),
                  SizedBox(height: 12 * scale),
                  Text(
                    t.tvOfflineHome.body,
                    style: TextStyle(fontSize: 15 * scale, height: 1.4, color: tk.text.withValues(alpha: 0.72)),
                  ),
                  SizedBox(height: 28 * scale),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TvPanelButton(
                        scale: scale,
                        label: t.common.reconnect,
                        icon: Symbols.wifi_rounded,
                        primary: true,
                        autofocus: true,
                        focusNode: _nodes.get(_reconnectKey, debugLabel: _reconnectKey),
                        onPressed: widget.isReconnecting ? () {} : widget.onReconnect,
                        onNavigateRight: () => _nodes.get(_manageServersKey).requestFocus(),
                        onNavigateDown: servers.isEmpty ? null : focusFirstServer,
                      ),
                      SizedBox(width: 12 * scale),
                      TvPanelButton(
                        scale: scale,
                        label: t.tvOfflineHome.manageServers,
                        icon: Symbols.dns_rounded,
                        primary: false,
                        focusNode: _nodes.get(_manageServersKey, debugLabel: _manageServersKey),
                        onPressed: widget.onManageServers,
                        onNavigateLeft: () => _nodes.get(_reconnectKey).requestFocus(),
                        onNavigateDown: servers.isEmpty ? null : focusFirstServer,
                      ),
                    ],
                  ),
                  if (servers.isNotEmpty) ...[
                    SizedBox(height: 28 * scale),
                    Text(
                      t.tvMyPleya.servers,
                      style: TextStyle(
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w600,
                        color: tk.text.withValues(alpha: 0.6),
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    TvMenuGrid(
                      nodes: _nodes,
                      columns: 1,
                      automationInstance: 'offline_home.servers',
                      onExitUp: _focusButtons,
                      sections: [
                        TvMenuSection(
                          items: [
                            for (final server in servers)
                              TvMenuItem(
                                key: 'offlineHome_server_${server.id}',
                                icon: Symbols.dns_rounded,
                                title: server.displayLabel,
                                value: _statusLine(server: server, authErrorIds: authErrorIds),
                                onSelect: widget.onManageServers,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// A connection is only rendered on this screen while the whole shell is
  /// offline (`shouldRenderMainScreenOffline`), which is true precisely
  /// because nothing answered — so every row's default is "Offline", not a
  /// fresh reachability check this screen has no server to make. The one
  /// exception mirrors `ConnectionsSection`/`TvServersPage`: a Pleya Server
  /// already known to need a sign-in keeps saying so instead of just
  /// "Offline", because "sign in again" is a different fix than "reconnect".
  String _statusLine({required Connection server, required Set<String> authErrorIds}) {
    final needsReauth = server is PleyaServerConnection && authErrorIds.contains(server.serverId);
    final status = needsReauth ? t.connections.reauthRequired : t.common.offline;
    return [status, server.displaySubtitle].whereType<String>().join(' · ');
  }
}
