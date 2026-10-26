import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../widgets/focused_scroll_scaffold.dart';
import '../widgets/settings_page.dart';
import '../widgets/settings_section.dart';
import 'settings/connections_section.dart';

/// Mijn Pleya ▸ Servers on mobile, per northstar 18, and Instellingen ▸
/// Servers en bronnen (A-24b, series `ios/12`).
///
/// Same registry, same actions as the settings screen's own connections
/// block ([ConnectionsSection]) and the same wrap TV already did in
/// `TvServersPage` — a screen just mounts the one existing section, so
/// server management stays in one place instead of growing a second copy.
/// Opened from Instellingen it is a Studio settings page; from Mijn Pleya it
/// keeps its plain bar and title.
class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  static const _section = SliverPadding(
    padding: EdgeInsets.only(top: 8),
    sliver: SliverToBoxAdapter(child: ConnectionsSection()),
  );

  @override
  Widget build(BuildContext context) {
    if (SettingsStudioTheme.isActive(context)) {
      return SettingsPage.slivers(
        title: Text(t.settingsStudio.serversAndSources),
        hideDescriptions: true,
        slivers: const [_section],
      );
    }
    return FocusedScrollScaffold(title: Text(t.tvMyPleya.servers), slivers: const [_section]);
  }
}
