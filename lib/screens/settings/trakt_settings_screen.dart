import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../models/trackers/device_code.dart';
import '../../providers/trakt_account_provider.dart';
import '../../services/settings_service.dart';
import '../../services/trackers/tracker_constants.dart';
import '../../services/trakt/trakt_scrobble_service.dart';
import '../../services/trakt/trakt_sync_service.dart';
import '../../utils/dialogs.dart';
import '../../widgets/device_code_dialog.dart';
import '../../widgets/settings_page.dart';
import 'tracker_account_settings_body.dart';
import 'tracker_connect_launcher.dart';

/// The answer to "send your watching to Trakt?" applies to both write-backs
/// at once; the two toggles stay available under Trakt in Settings.
Future<void> applyTraktSendConsent(bool allow) async {
  final settings = await SettingsService.getInstance();
  await settings.write(SettingsService.enableTraktScrobble, allow);
  await settings.write(SettingsService.enableTraktWatchedSync, allow);
  await TraktScrobbleService.instance.setEnabled(allow);
  await TraktSyncService.instance.setEnabled(allow);
}

Future<void> startTraktConnection(BuildContext context) async {
  final account = context.read<TraktAccountProvider>();
  final wasConnected = account.isConnected;
  final name = t.trakt.title;
  await launchTrackerConnect<DeviceCode>(
    context,
    isBusyOrConnected: account.isConnecting || account.isConnected,
    serviceName: name,
    connect: (cb) => account.connect(onCodeReady: cb),
    onCancel: account.cancelConnect,
    buildDialog: (code, cancel) => DeviceCodeDialog(code: code, serviceName: name, onCancel: cancel),
    urlFor: (code) => code.verificationUrlComplete ?? code.verificationUrl,
  );
  // Linking Trakt never sends anything back by itself: it is asked once here.
  if (!context.mounted || wasConnected || !account.isConnected) return;
  final allow = await showConfirmDialog(
    context,
    title: t.trakt.sendTitle,
    message: t.trakt.sendBody,
    confirmText: t.trakt.sendAllow,
    cancelText: t.trakt.sendDecline,
  );
  await applyTraktSendConsent(allow);
}

class TraktSettingsScreen extends StatelessWidget {
  const TraktSettingsScreen({super.key});

  Future<void> _disconnect(BuildContext context, TraktAccountProvider account) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.trakt.disconnectConfirm,
      message: t.trakt.disconnectConfirmBody,
      confirmText: t.common.disconnect,
      isDestructive: true,
    );
    if (!confirmed) return;
    await account.disconnect();
    // build()'s post-frame handler pops the screen once the provider rebuilds
    // with isConnected == false — don't pop here too.
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TraktAccountProvider>(
      builder: (context, account, _) {
        // Safety net: if we end up here while not connected (e.g. refresh failed
        // in the background and cleared the session), bail out. The settings
        // tile is the only supported entry point for the unauthed flow.
        if (!account.isConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return SettingsPage.slivers(
            title: Text(t.trakt.title),
            slivers: const [SliverFillRemaining(child: SizedBox.shrink())],
          );
        }

        final username = account.username;
        return TrackerAccountSettingsBody(
          title: Text(t.trakt.title),
          accountTitle: username != null ? t.trakt.connectedAs(username: username) : t.trakt.connected,
          accountSubtitle: t.trakt.connected,
          service: TrackerService.trakt,
          toggles: [
            TrackerSettingsToggle(
              pref: SettingsService.enableTraktScrobble,
              icon: Symbols.auto_timer,
              title: t.trakt.scrobble,
              subtitle: t.trakt.scrobbleDescription,
              onAfterWrite: TraktScrobbleService.instance.setEnabled,
            ),
            TrackerSettingsToggle(
              pref: SettingsService.enableTraktWatchedSync,
              icon: Symbols.check_circle_rounded,
              title: t.trakt.watchedSync,
              subtitle: t.trakt.watchedSyncDescription,
              onAfterWrite: TraktSyncService.instance.setEnabled,
            ),
          ],
          onDisconnect: () => _disconnect(context, account),
        );
      },
    );
  }
}
