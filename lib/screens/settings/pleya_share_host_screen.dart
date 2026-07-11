import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../i18n/strings.g.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/pleya_share/pleya_share_device_name.dart';
import '../../services/pleya_share/pleya_share_host_service.dart';
import '../../widgets/focused_scroll_scaffold.dart';

/// Host side of Pleya Share: toggle sharing, show the pairing code + QR,
/// and manage paired guest devices.
class PleyaShareHostScreen extends StatefulWidget {
  const PleyaShareHostScreen({super.key});

  @override
  State<PleyaShareHostScreen> createState() => _PleyaShareHostScreenState();
}

class _PleyaShareHostScreenState extends State<PleyaShareHostScreen> {
  final _service = PleyaShareHostService.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_service.isRunning) WakelockPlus.enable();
  }

  @override
  void dispose() {
    // The server keeps running when the user navigates away, but without the
    // wakelock iOS/Android will eventually suspend it; the screen tells the
    // user to keep it open.
    if (!_service.isRunning) WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _toggle(bool enable) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (enable) {
        final manager = context.read<MultiServerProvider>().serverManager;
        final name = await pleyaShareDeviceName();
        await _service.start(clients: () => manager.localFolderClients, deviceName: name);
        await WakelockPlus.enable();
      } else {
        await _service.stop();
        await WakelockPlus.disable();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFolders = context.read<MultiServerProvider>().serverManager.localFolderClients.isNotEmpty;
    return FocusedScrollScaffold(
      title: Text(t.pleyaShare.hostTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: _service,
              builder: (context, _) {
                final running = _service.isRunning;
                final code = _service.pairCode;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.pleyaShare.hostDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: Text(t.pleyaShare.hostToggle),
                      value: running,
                      onChanged: hasFolders && !_busy ? _toggle : null,
                    ),
                    if (!hasFolders) ...[
                      const SizedBox(height: 8),
                      Text(
                        t.pleyaShare.noLocalFolders,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    if (running && code != null) ...[
                      const SizedBox(height: 24),
                      Text(t.pleyaShare.pairCodeLabel, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          '${code.substring(0, 3)} ${code.substring(3)}',
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: QrImageView(
                            data: 'pleya-share://pair?v=1&code=$code&port=${_service.port}',
                            size: 160,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.pleyaShare.pairCodeHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: _service.regeneratePairCode,
                          icon: const Icon(Symbols.refresh_rounded),
                          label: Text(t.pleyaShare.regenerateCode),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(t.pleyaShare.pairedDevices, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (_service.pairedGuests.isEmpty)
                      Text(
                        t.pleyaShare.noGuests,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      )
                    else
                      for (final guest in _service.pairedGuests)
                        Card(
                          child: ListTile(
                            leading: const Icon(Symbols.devices_rounded, fill: 1),
                            title: Text(guest.deviceName),
                            trailing: IconButton(
                              tooltip: t.pleyaShare.revokeGuest,
                              icon: Icon(Symbols.link_off_rounded, color: theme.colorScheme.error),
                              onPressed: () => _service.revokeGuest(guest.pairId),
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
