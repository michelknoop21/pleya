import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/mono_tokens.dart';
import '../../widgets/settings_section.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/pleya_share/pleya_share_device_name.dart';
import '../../services/pleya_share/pleya_share_host_service.dart';
import '../../services/pleya_share/pleya_share_uri.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import 'add_local_folder_screen.dart';

/// Host side of Pleya Share: toggle sharing, show the pairing code, and
/// manage paired guest devices. The service holds the wakelock while
/// sharing is on.
class PleyaShareHostScreen extends StatefulWidget {
  const PleyaShareHostScreen({super.key});

  /// Hotspot-facing addresses first: when this host runs a personal hotspot
  /// (iOS: 172.20.10.1) that is the IP a scanning guest can actually reach.
  /// Link-local (direct-cable fallback) goes last so the common paths race
  /// first — pairAny probes all of them anyway.
  static List<String> orderIpsForPairing(List<String> ips) {
    final ordered = [...ips];
    ordered.sort((a, b) {
      int rank(String ip) => ip.startsWith('172.20.10.')
          ? 0
          : ip.startsWith('169.254.')
          ? 2
          : 1;
      return rank(a).compareTo(rank(b));
    });
    return ordered;
  }

  @override
  State<PleyaShareHostScreen> createState() => _PleyaShareHostScreenState();
}

class _PleyaShareHostScreenState extends State<PleyaShareHostScreen> {
  final _service = PleyaShareHostService.instance;
  bool _busy = false;
  Timer? _ipRefresh;

  @override
  void initState() {
    super.initState();
    // Interfaces change while this screen is open (hotspot toggled on, Wi-Fi
    // joined) — re-resolve so the QR always carries current, reachable IPs.
    _ipRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _service.isRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _ipRefresh?.cancel();
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
      } else {
        await _service.stop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Compact in-app explainer so the server/client model is clear before
  /// the user flips the toggle.
  Widget _howItWorks(ThemeData theme) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    shape: const Border(),
    title: Text(t.pleyaShare.howItWorksTitle, style: theme.textTheme.titleSmall),
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          t.pleyaShare.howItWorksBody,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.75)),
        ),
      ),
    ],
  );

  Future<void> _addFolder() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddLocalFolderScreen()));
    if (mounted) setState(() {});
  }

  /// QR encoding the pair deep link (host IPs + port + code + salt) so a guest
  /// can join by scanning instead of typing. Hidden until IPs resolve.
  Widget _pairQr(String code) {
    final salt = _service.pairSaltB64;
    if (salt == null) return const SizedBox.shrink();
    return FutureBuilder<List<String>>(
      future: _service.localIps(),
      builder: (context, snapshot) {
        final ips = PleyaShareHostScreen.orderIpsForPairing(snapshot.data ?? const []);
        if (ips.isEmpty) return const SizedBox.shrink();
        final data = PleyaSharePairUri(
          ips: ips,
          port: _service.port,
          code: code,
          saltB64: salt,
          relayHostId: _service.relayHostId,
        ).build();
        return Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(data: data, size: 200, backgroundColor: Colors.white),
          ),
        );
      },
    );
  }

  /// Card surface shared by the blocks on this screen, matching the grouped
  /// look of the settings list.
  Widget _card(BuildContext context, {required Widget child, EdgeInsets? padding}) {
    final tk = tokens(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(tk.radiusMd),
        border: Border.all(color: settingsOutlineColor(context)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // watch: re-enables the toggle the moment a local folder source appears.
    final hasFolders = context.watch<MultiServerProvider>().serverManager.localFolderClients.isNotEmpty;
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
                return SettingsWidthLimit(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SettingsIconBadge(Symbols.cast_rounded),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    Platform.isAndroid
                                        ? t.pleyaShare.hostDescriptionAndroid
                                        : Platform.isIOS
                                        ? t.pleyaShare.hostDescriptionIos
                                        : t.pleyaShare.hostDescription,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            _howItWorks(theme),
                          ],
                        ),
                      ),
                      _card(
                        context,
                        padding: EdgeInsets.zero,
                        child: FocusableWrapper(
                          disableScale: true,
                          borderRadius: 12,
                          onSelect: hasFolders && !_busy ? () => _toggle(!running) : null,
                          child: SwitchListTile(
                            contentPadding: kSettingRowPadding,
                            secondary: const SettingsIconBadge(Symbols.share_rounded),
                            title: Text(t.pleyaShare.hostToggle),
                            value: running,
                            onChanged: hasFolders && !_busy ? _toggle : null,
                          ),
                        ),
                      ),
                      if (!hasFolders)
                        _card(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.pleyaShare.noLocalFolders,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                              ),
                              const SizedBox(height: 12),
                              FocusableWrapper(
                                disableScale: true,
                                borderRadius: 20,
                                onSelect: _addFolder,
                                child: OutlinedButton.icon(
                                  onPressed: _addFolder,
                                  icon: const Icon(Symbols.create_new_folder_rounded, fill: 1),
                                  label: Text(t.pleyaShare.addFolder),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (running && code != null)
                        _card(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.pleyaShare.pairCodeLabel, style: theme.textTheme.titleSmall),
                              const SizedBox(height: 12),
                              // Code and QR sit side by side when there is room:
                              // a guest either types the digits or scans, and
                              // stacking them pushed the QR off a laptop screen.
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 24,
                                runSpacing: 16,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${code.substring(0, 3)} ${code.substring(3)}',
                                        style: theme.textTheme.displayMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 6,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 320),
                                        child: Text(
                                          t.pleyaShare.pairCodeHint,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      FocusableWrapper(
                                        disableScale: true,
                                        borderRadius: 20,
                                        onSelect: _service.regeneratePairCode,
                                        child: TextButton.icon(
                                          onPressed: _service.regeneratePairCode,
                                          icon: const Icon(Symbols.refresh_rounded),
                                          label: Text(t.pleyaShare.regenerateCode),
                                        ),
                                      ),
                                    ],
                                  ),
                                  _pairQr(code),
                                ],
                              ),
                            ],
                          ),
                        ),
                      _card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                FocusableWrapper(
                                  disableScale: true,
                                  borderRadius: 12,
                                  onSelect: () => _service.revokeGuest(guest.pairId),
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const SettingsIconBadge(Symbols.devices_rounded),
                                    title: Text(guest.deviceName),
                                    trailing: IconButton(
                                      tooltip: t.pleyaShare.revokeGuest,
                                      icon: Icon(Symbols.link_off_rounded, color: theme.colorScheme.error),
                                      onPressed: () => _service.revokeGuest(guest.pairId),
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
