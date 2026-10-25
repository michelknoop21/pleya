/// Instellingen ▸ Bibliotheken (A-24b, series `ios/03` "Bibliotheek & Home").
///
/// A hub of rows the main page used to carry itself: which libraries show,
/// the local library, the Home layout and, off Apple TV, Downloads. It adds
/// no preference of its own; every row opens the page it opened before, with
/// the same automation id.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'downloads_settings_screen.dart';
import 'home_layout_screen.dart';
import 'library_visibility_screen.dart';
import 'local_library_settings_screen.dart';

class LibraryHomeSettingsScreen extends StatelessWidget {
  const LibraryHomeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: Text(t.settingsStudio.libraryAndHome),
      hideDescriptions: true,
      children: [
        SettingsSectionHeader(t.settingsStudio.libraries),
        _row(
          'library_visibility',
          SettingNavigationTile(
            icon: Symbols.video_library_rounded,
            title: t.settings.libraryVisibility,
            subtitle: t.settings.libraryVisibilityDescription,
            destinationBuilder: (_) => const LibraryVisibilityScreen(),
          ),
        ),
        _row(
          'local_library',
          SettingNavigationTile(
            icon: Symbols.offline_bolt_rounded,
            title: t.localLibrary.title,
            subtitle: t.localLibrary.enable,
            destinationBuilder: (_) => const LocalLibrarySettingsScreen(),
          ),
        ),
        SettingsSectionHeader(t.settings.homeScreen),
        _row(
          'home_layout',
          SettingNavigationTile(
            icon: Symbols.dashboard_customize_rounded,
            title: t.settings.homeLayout,
            subtitle: t.settings.homeLayoutDescription,
            destinationBuilder: (_) => const HomeLayoutScreen(),
          ),
        ),
        // Apple TV keeps no downloads; everywhere else the page is unchanged.
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
