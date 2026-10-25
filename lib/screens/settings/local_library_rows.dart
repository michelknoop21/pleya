/// The rows of the local library (A-24b, series `ios/03-bibliotheek-home-01`,
/// group Lokale bibliotheek): its own page and Bibliotheek & Home draw the
/// same rows from here, so the switches, the sync and the confirmed clear have
/// one definition.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../providers/local_library_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/dialogs.dart';
import '../../utils/formatters.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings/setting_value_label.dart';
import '../../widgets/settings_section.dart';

/// Gives a page the local library's rows and the state of a clear in progress.
mixin LocalLibraryRowsHost<T extends StatefulWidget> on State<T> {
  bool _clearing = false;

  String _status(LocalLibraryProvider provider) {
    final labels = t.localLibrary;
    return switch (provider.state) {
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
  }

  /// Offline index, wifi only, the storage used, the last sync with the
  /// state of the index, sync now and the confirmed clear, in the series'
  /// order.
  List<Widget> buildLocalLibraryRows(LocalLibraryProvider provider) {
    final labels = t.localLibrary;
    final status = _status(provider);
    // The state only needs a line of its own when it is not the everyday one.
    final showStatus = provider.state != LocalLibraryState.ready && provider.state != LocalLibraryState.disabled;
    final lastSync = provider.lastSync == null ? labels.never : DateFormat.yMd().add_Hm().format(provider.lastSync!);
    return [
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
      _ValueRow(title: labels.usage, value: ByteFormatter.formatBytes(provider.bytes)),
      AutomationNode(
        id: AutomationIds.localLibraryStatus,
        role: 'status',
        state: () => {
          'status': provider.state.name,
          'processed': provider.done,
          'items': provider.items.length,
          'bytes': provider.bytes,
        },
        child: _ValueRow(title: labels.lastSync, value: lastSync, line: showStatus ? status : null),
      ),
      AutomationNode(
        id: AutomationIds.localLibrarySync,
        role: 'button',
        child: FocusableListTile(
          enabled: provider.enabled && provider.state != LocalLibraryState.syncing && !_clearing,
          contentPadding: settingRowPadding(),
          leading: settingsRowLeading(context, Symbols.sync_rounded),
          title: Text(labels.syncNow),
          subtitle: provider.state != LocalLibraryState.syncing
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(labels.progress(count: provider.done)),
                    Text(provider.currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
          onTap: () => unawaited(provider.synchronize()),
        ),
      ),
      AutomationNode(
        id: AutomationIds.localLibraryClear,
        role: 'button',
        child: FocusableListTile(
          enabled: provider.initialized && !_clearing,
          contentPadding: settingRowPadding(),
          leading: settingsRowLeading(context, Symbols.delete_outline_rounded),
          title: Text(labels.clear, style: TextStyle(color: settingsDestructiveInk(context))),
          onTap: () => unawaited(_clear(provider)),
        ),
      ),
    ];
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

/// A row that only reports a value: no focus stop, nothing to open.
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.title, required this.value, this.line});

  final String title;
  final String value;

  /// A line under the title, for a state worth reading (syncing, an error).
  final String? line;

  @override
  Widget build(BuildContext context) {
    final line = this.line;
    return ListTile(
      contentPadding: settingRowPadding(),
      title: Text(title),
      subtitle: line == null ? null : Text(line, style: TextStyle(color: tokens(context).textMuted)),
      trailing: SettingValueLabel(value, title: title),
    );
  }
}
