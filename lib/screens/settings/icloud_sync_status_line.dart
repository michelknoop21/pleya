import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/preferences/preference_sync_status.dart';

/// One line under the iCloud toggle saying what the sync is doing.
///
/// Two rules it exists to keep. It never claims anything about the user's other
/// devices: a key-value store accepts a write, it does not report delivery, so
/// "all devices in sync" would be a guess dressed up as a fact. And it never
/// shows a key, a value or a count that carries an identity — the point is
/// health, not a dump of what synced.
class ICloudSyncStatusLine extends StatelessWidget {
  const ICloudSyncStatusLine({super.key, required this.status});

  final ValueListenable<PreferenceSyncStatus> status;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PreferenceSyncStatus>(
      valueListenable: status,
      builder: (context, value, _) {
        final lines = messagesFor(value, context);
        if (lines.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Text(
                  line.text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: line.attention ? scheme.tertiary : scheme.onSurfaceVariant),
                ),
            ],
          ),
        );
      },
    );
  }

  /// What the line says, as data, so a test can read it without a golden.
  ///
  /// The compatibility warning is its own line rather than a state: it is a
  /// fact about the account, and it is true whether or not the last write went
  /// well.
  static List<SyncStatusMessage> messagesFor(PreferenceSyncStatus status, BuildContext? context) {
    final lines = <SyncStatusMessage>[];
    switch (status.state) {
      case PreferenceSyncState.disabled:
      case PreferenceSyncState.unavailable:
      case PreferenceSyncState.idle:
        // The toggle and its subtitle already say this.
        break;
      case PreferenceSyncState.syncing:
        lines.add(SyncStatusMessage(t.settings.icloudSyncStatusSyncing, attention: false));
      case PreferenceSyncState.success:
        final at = status.lastSuccess;
        if (at != null) {
          lines.add(
            SyncStatusMessage(t.settings.icloudSyncStatusLastSent(time: _clock(at, context)), attention: false),
          );
        }
      case PreferenceSyncState.warning:
        if (status.oversize > 0) lines.add(SyncStatusMessage(t.settings.icloudSyncStatusOversize, attention: true));
      case PreferenceSyncState.error:
        lines.add(SyncStatusMessage(t.settings.icloudSyncStatusError, attention: true));
      case PreferenceSyncState.quota:
        lines.add(SyncStatusMessage(t.settings.icloudSyncStatusQuota, attention: true));
    }
    if (status.legacyPeerDetected) {
      lines.add(SyncStatusMessage(t.settings.icloudSyncLegacyPeer, attention: true));
    }
    return lines;
  }

  static String _clock(DateTime at, BuildContext? context) {
    final local = at.toLocal();
    if (context != null) return TimeOfDay.fromDateTime(local).format(context);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class SyncStatusMessage {
  const SyncStatusMessage(this.text, {required this.attention});

  final String text;

  /// Whether this is something the user may want to act on.
  final bool attention;
}
