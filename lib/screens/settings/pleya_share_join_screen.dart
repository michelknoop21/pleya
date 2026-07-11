import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/pleya_share/pleya_share_channel.dart';
import '../../services/pleya_share/pleya_share_device_name.dart';
import '../../services/pleya_share/pleya_share_protocol.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import 'connection_persistence.dart';

/// Guest side of Pleya Share: discover hosts on the LAN (or enter an IP),
/// enter the 6-digit code, pair, and register the host as a media source.
class PleyaShareJoinScreen extends StatefulWidget {
  final Profile? targetProfile;

  const PleyaShareJoinScreen({super.key, this.targetProfile});

  @override
  State<PleyaShareJoinScreen> createState() => _PleyaShareJoinScreenState();
}

class _PleyaShareJoinScreenState extends State<PleyaShareJoinScreen> {
  final _hostController = TextEditingController();
  final _codeController = TextEditingController();
  Future<List<DiscoveredShareHost>>? _discovery;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _discovery = PleyaShareChannel.discoverHosts());
  }

  bool get _canConnect =>
      !_busy && _hostController.text.trim().isNotEmpty && RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim());

  Future<void> _connect() async {
    if (!_canConnect) return;
    setState(() => _busy = true);
    try {
      final deviceName = await pleyaShareDeviceName();
      final connection = await PleyaShareChannel.pair(
        ip: _hostController.text.trim(),
        port: PleyaShareProtocol.sharePort,
        code: _codeController.text.trim(),
        deviceName: deviceName,
      );
      if (!mounted) return;

      final profile = widget.targetProfile ?? context.read<ActiveProfileProvider>().active;
      final bindToProfile = profile != null
          ? ProfileConnection(profileId: profile.id, connectionId: connection.id, userIdentifier: connection.id)
          : null;
      final added = await persistAndBindConnection(
        context: context,
        connection: connection,
        bindToProfile: bindToProfile,
        addToManager: () async {
          final manager = context.read<MultiServerProvider>().serverManager;
          return manager.addPleyaShareSource(connection);
        },
        visibleServerId: connection.id,
      );
      if (!mounted) return;
      if (added) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.pleyaShare.paired(name: connection.hostName))));
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.pleyaShare.pairFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.pleyaShare.joinTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                t.pleyaShare.joinDescription,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(child: Text(t.pleyaShare.hostsFound, style: theme.textTheme.titleSmall)),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Symbols.refresh_rounded, size: 18),
                    label: Text(t.pleyaShare.refresh),
                  ),
                ],
              ),
              FutureBuilder<List<DiscoveredShareHost>>(
                future: _discovery,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text(t.pleyaShare.searching, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    );
                  }
                  final hosts = snap.data ?? const [];
                  if (hosts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        t.pleyaShare.noHostsFound,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final host in hosts)
                        Card(
                          child: ListTile(
                            leading: const Icon(Symbols.share_rounded, fill: 1),
                            title: Text(host.name),
                            subtitle: Text('${host.ip}:${host.port}'),
                            selected: _hostController.text.trim() == host.ip,
                            onTap: () => setState(() => _hostController.text = host.ip),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              Text(t.pleyaShare.manualHost, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _hostController,
                decoration: InputDecoration(hintText: '192.168.1.23', border: const OutlineInputBorder()),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              Text(t.pleyaShare.codeLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(hintText: '123456', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                maxLength: 6,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _canConnect ? _connect : null,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Symbols.link_rounded, fill: 1),
                label: Text(t.pleyaShare.connect),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
