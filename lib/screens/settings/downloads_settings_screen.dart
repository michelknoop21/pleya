/// Instellingen ▸ Downloads, northstar 14. Storage location, WiFi-only and
/// auto-remove-watched used to be inline rows directly on the settings list
/// (its own unlabelled card); the mockup draws "Downloads" as one row with a
/// summary inside "App en afspelen", like every other entry there. Promoted
/// to its own destination rather than adding a summary line to an inline
/// block, so the shape matches its siblings instead of being the one card
/// that behaves differently.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/download_storage_service.dart';
import '../../services/settings_service.dart' as settings;
import '../../widgets/app_icon.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import 'download_location_dialog.dart';

class DownloadsSettingsScreen extends StatefulWidget {
  const DownloadsSettingsScreen({super.key});

  @override
  State<DownloadsSettingsScreen> createState() => _DownloadsSettingsScreenState();
}

class _DownloadsSettingsScreenState extends State<DownloadsSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final storageService = DownloadStorageService.instance;
    final isCustom = storageService.isUsingCustomPath();

    return SettingsPage(
      title: Text(t.settings.downloads),
      children: [
        if (!Platform.isIOS)
          FutureBuilder<String>(
            future: storageService.getCurrentDownloadPathDisplay(),
            builder: (context, snapshot) {
              final currentPath = snapshot.data ?? '...';
              return ListTile(
                leading: const AppIcon(Symbols.folder_rounded, fill: 1),
                title: Text(isCustom ? t.settings.downloadLocationCustom : t.settings.downloadLocationDefault),
                subtitle: Text(currentPath, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                // `setState` on the change/reset callback: the FutureBuilder
                // above needs a rebuild to pick up the new path, and
                // `isUsingCustomPath()` above it to know whether to offer
                // "reset" next time.
                onTap: () => showDownloadLocationDialog(context, onChanged: () => setState(() {})),
              );
            },
          ),
        SettingSwitchTile(
          pref: settings.SettingsService.downloadOnWifiOnly,
          icon: Symbols.wifi_rounded,
          title: t.settings.downloadOnWifiOnly,
          subtitle: t.settings.downloadOnWifiOnlyDescription,
        ),
        SettingSwitchTile(
          pref: settings.SettingsService.autoRemoveWatchedDownloads,
          icon: Symbols.delete_sweep_rounded,
          title: t.settings.autoRemoveWatchedDownloads,
          subtitle: t.settings.autoRemoveWatchedDownloadsDescription,
        ),
      ],
    );
  }
}
