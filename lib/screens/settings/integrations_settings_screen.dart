/// Instellingen ▸ Koppelingen (A-24b, anchor `01` and series `ios/08`-`09`).
///
/// A hub of the three rows the main page used to carry in its Koppelingen
/// group: Trackers, Aanvragen and, for someone who owns a Plex server here,
/// Tautulli. Each row keeps its value (what is connected) and opens the page
/// it opened before, under the same automation id.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/tautulli_provider.dart';
import '../../providers/trackers_provider.dart';
import '../../providers/trakt_account_provider.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'seerr_settings_screen.dart';
import 'tautulli_settings_screen.dart';
import 'trackers_settings_screen.dart';

class IntegrationsSettingsScreen extends StatelessWidget {
  const IntegrationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Tautulli's single API key opens the whole Plex server's admin surface,
    // so the row only exists for someone with owner rights on a Plex server
    // here, the same gate the main page and its search apply.
    final managesPlex = context.select<MultiServerProvider, bool>((s) => s.serverManager.managesAPlexServer);
    return SettingsPage(
      title: Text(t.settingsStudio.integrations),
      hideDescriptions: true,
      children: [
        SettingsSectionHeader(t.settings.trackers),
        const _TrackersRow(),
        SettingsSectionHeader(t.settings.requests),
        const _RequestsRow(),
        if (managesPlex) ...[SettingsSectionHeader(t.tautulli.title), const _TautulliRow()],
      ],
    );
  }
}

class _TrackersRow extends StatelessWidget {
  const _TrackersRow();

  @override
  Widget build(BuildContext context) {
    final trakt = context.watch<TraktAccountProvider>();
    final trackers = context.watch<TrackersProvider>();
    final connected = [
      if (trakt.isConnected) t.trakt.title,
      if (trackers.isMalConnected) t.trackers.services.mal,
      if (trackers.isAnilistConnected) t.trackers.services.anilist,
      if (trackers.isSimklConnected) t.trackers.services.simkl,
    ];
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'trackers',
      role: 'list.item',
      child: SettingNavigationTile(
        icon: Symbols.sync_rounded,
        title: t.settings.trackers,
        subtitle: t.settings.trackersDescription,
        trailingLabel: connected.isEmpty ? null : connected.join(' · '),
        destinationBuilder: (_) => const TrackersSettingsScreen(),
      ),
    );
  }
}

class _RequestsRow extends StatelessWidget {
  const _RequestsRow();

  @override
  Widget build(BuildContext context) {
    final seerr = context.watch<SeerrProvider>();
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'requests',
      role: 'list.item',
      child: SettingNavigationTile(
        icon: Symbols.playlist_add_rounded,
        title: t.settings.requests,
        subtitle: t.settings.requestsDescription,
        trailingLabel: seerr.isConfigured ? (seerr.host ?? t.settings.requests) : null,
        destinationBuilder: (_) => const SeerrSettingsScreen(),
      ),
    );
  }
}

class _TautulliRow extends StatelessWidget {
  const _TautulliRow();

  @override
  Widget build(BuildContext context) {
    final tautulli = context.watch<TautulliProvider>();
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'tautulli',
      role: 'list.item',
      child: SettingNavigationTile(
        icon: Symbols.insights_rounded,
        title: t.tautulli.title,
        subtitle: t.tautulli.subtitle,
        trailingLabel: tautulli.isConfigured ? (tautulli.serverName ?? tautulli.host ?? t.tautulli.connected) : null,
        destinationBuilder: (_) => const TautulliSettingsScreen(),
      ),
    );
  }
}
