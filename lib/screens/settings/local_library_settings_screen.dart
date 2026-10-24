import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../providers/local_library_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/formatters.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';

class LocalLibrarySettingsScreen extends StatefulWidget {
  const LocalLibrarySettingsScreen({super.key});
  @override
  State<LocalLibrarySettingsScreen> createState() => _LocalLibrarySettingsScreenState();
}

class _LocalLibrarySettingsScreenState extends State<LocalLibrarySettingsScreen> {
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalLibraryProvider>();
    final labels = t.localLibrary;
    final status = switch (provider.state) {
      LocalLibraryState.disabled => labels.disabled,
      LocalLibraryState.syncing => labels.syncing,
      LocalLibraryState.ready => labels.ready,
      LocalLibraryState.wifi => labels.wifi,
      LocalLibraryState.offline => labels.offline,
      LocalLibraryState.storage => labels.storage,
      LocalLibraryState.storageUnavailable => labels.storageUnavailable,
      LocalLibraryState.paused => labels.paused,
      LocalLibraryState.error => labels.error,
    };
    return AutomationScreen(
      id: AutomationIds.screenLocalLibrary,
      readiness: () => provider.initialized ? const AutomationReadiness.ready() : const AutomationReadiness.loading(),
      child: SettingsPage(
        title: Text(labels.title),
        children: [
          AutomationNode(
            id: AutomationIds.localLibraryEnable,
            role: 'switch',
            state: () => {'value': provider.enabled},
            child: SettingSwitchRow(
              value: provider.enabled,
              enabled: provider.initialized && !_clearing,
              onChanged: (v) => unawaited(_action(() => provider.setEnabled(v))),
              icon: Symbols.offline_bolt_rounded,
              title: labels.enable,
              subtitle: labels.description,
            ),
          ),
          AutomationNode(
            id: AutomationIds.localLibraryWifi,
            role: 'switch',
            state: () => {'value': provider.wifiOnly},
            child: SettingSwitchRow(
              value: provider.wifiOnly,
              enabled: provider.initialized && !_clearing,
              onChanged: (v) => unawaited(_action(() => provider.setWifiOnly(v))),
              icon: Symbols.wifi_rounded,
              title: labels.wifiOnly,
              subtitle: labels.wifiDescription,
            ),
          ),
          AutomationNode(
            id: AutomationIds.localLibraryStatus,
            role: 'status',
            state: () => {
              'status': provider.state.name,
              'processed': provider.done,
              'items': provider.items.length,
              'bytes': provider.bytes,
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: Theme.of(context).textTheme.bodyLarge),
                  if (provider.state == LocalLibraryState.syncing) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(labels.progress(count: provider.done)),
                    Text(provider.currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ),
          ListTile(title: Text(labels.usage), trailing: Text(ByteFormatter.formatBytes(provider.bytes))),
          ListTile(
            title: Text(labels.lastSync),
            subtitle: Text(
              provider.lastSync == null ? labels.never : DateFormat.yMd().add_Hm().format(provider.lastSync!),
            ),
          ),
          AutomationNode(
            id: AutomationIds.localLibrarySync,
            role: 'button',
            child: FocusableListTile(
              enabled: provider.enabled && provider.state != LocalLibraryState.syncing && !_clearing,
              leading: const Icon(Symbols.sync_rounded),
              title: Text(labels.syncNow),
              onTap: () => unawaited(provider.synchronize()),
            ),
          ),
          AutomationNode(
            id: AutomationIds.localLibraryClear,
            role: 'button',
            child: FocusableListTile(
              enabled: provider.initialized && !_clearing,
              leading: const Icon(Symbols.delete_outline_rounded),
              title: Text(labels.clear),
              onTap: () => unawaited(_clear(provider)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) showErrorSnackBar(context, t.common.error);
    }
  }

  Future<void> _clear(LocalLibraryProvider provider) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.localLibrary.clear,
      message: t.localLibrary.clearMessage,
      confirmText: t.localLibrary.clear,
      isDestructive: true,
      confirmAutomationId: '${AutomationIds.localLibraryAction}[confirm_clear]',
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    try {
      await provider.clear();
      if (!mounted) return;
      final refill = await showScopedDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.localLibrary.afterClear),
          content: Text(t.localLibrary.chooseAfterClear),
          actions: [
            AutomationNode(
              id: AutomationIds.localLibraryAction,
              instance: 'keep_off',
              role: 'button',
              child: DialogActionButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                label: t.localLibrary.keepOff,
              ),
            ),
            AutomationNode(
              id: AutomationIds.localLibraryAction,
              instance: 'refill',
              role: 'button',
              child: DialogActionButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                label: t.localLibrary.refill,
                isPrimary: true,
              ),
            ),
          ],
        ),
      );
      if (refill == true && mounted) await provider.setEnabled(true);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, t.common.error);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }
}
