/// Instellingen ▸ Bibliotheken (A-24b, series `ios/03` "Bibliotheek & Home").
///
/// Which libraries show, the local library's own rows inline, the Home
/// aanpassen actions inline, and off Apple TV a row to Downloads. It adds no
/// preference of its own: every row is a preference or action that already
/// exists, under the automation id it had before.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../providers/local_library_provider.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'downloads_settings_screen.dart';
import 'library_home_rows.dart';
import 'library_visibility_screen.dart';
import 'local_library_rows.dart';

class LibraryHomeSettingsScreen extends StatefulWidget {
  const LibraryHomeSettingsScreen({super.key, this.includeHomeLayout = true});

  /// False on the TV Instellingen page, where Home aanpassen is a category of
  /// its own on the rail (A-24b, anchor `02`).
  final bool includeHomeLayout;

  @override
  State<LibraryHomeSettingsScreen> createState() => _LibraryHomeSettingsScreenState();
}

class _LibraryHomeSettingsScreenState extends State<LibraryHomeSettingsScreen>
    with LocalLibraryRowsHost<LibraryHomeSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final localLibrary = context.watch<LocalLibraryProvider?>();
    return SettingsPage(
      title: Text(t.settingsStudio.libraryAndHome),
      children: [
        SettingsSectionHeader(t.settingsStudio.libraries),
        _row(
          'library_visibility',
          SettingNavigationTile(
            icon: Symbols.video_library_rounded,
            title: t.settings.libraryVisibility,
            subtitle: t.settings.libraryVisibilityDescription,
            automationInstance: 'settings.library_visibility',
            destinationBuilder: (_) => const LibraryVisibilityScreen(),
          ),
        ),
        // The local library's own rows, inline as the series draws them.
        if (localLibrary != null) ...[
          SettingsSectionHeader(t.localLibrary.title),
          ...buildLocalLibraryRows(localLibrary),
        ],
        if (widget.includeHomeLayout) ...[
          SettingsSectionHeader(t.settings.homeLayout),
          ...buildHomeLayoutRows(context),
        ],
        // Apple TV keeps no downloads; everywhere else Downloads is its own
        // page (series `ios/07`).
        if (!PlatformDetector.isAppleTV()) ...[
          SettingsSectionHeader(t.settings.downloads),
          _row(
            'downloads',
            SettingNavigationTile(
              icon: Symbols.download_rounded,
              title: t.settings.downloads,
              subtitle: t.settings.downloadsDescription,
              destinationBuilder: (_) => const DownloadsSettingsScreen(),
            ),
          ),
        ],
      ],
    );
  }

  /// The row under its `settings.tile[...]` id, the one it had on the main page.
  static Widget _row(String instance, Widget child) =>
      AutomationNode(id: AutomationIds.settingsTile, instance: instance, role: 'list.item', child: child);
}
