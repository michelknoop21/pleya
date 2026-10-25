/// The rows of Instellingen up to Profielen: one builder per destination,
/// shared by the phone page and the TV page.
///
/// A `part` of `settings_screen.dart`, like the two pages: each builder reads
/// the screen's focus memory and providers, so the phone and the TV page keep
/// one definition of every row.
part of '../settings_screen.dart';

extension _SettingsTiles on _SettingsScreenState {
  Widget _buildDonateTile() {
    return SettingNavigationTile(
      focusNode: _focusTracker.get(_SettingsScreenState._kDonate),
      icon: Symbols.favorite_rounded,
      title: t.settings.supportDeveloper,
      subtitle: t.settings.supportDeveloperDescription,
      trailingIcon: Symbols.open_in_new_rounded,
      onTap: _handleDonateTap,
    );
  }

  Widget _buildAppearanceTile() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => SettingValueBuilder<int>(
        pref: settings.SettingsService.libraryDensity,
        builder: (context, libraryDensity, _) {
          // A-24: the theme is the row's value, right-aligned; the density
          // stays on the line under the title, so the row still says both.
          final theme = switch (themeProvider.themeMode) {
            settings.ThemeMode.system => t.settings.systemTheme,
            settings.ThemeMode.light => t.settings.lightTheme,
            settings.ThemeMode.dark => t.settings.darkTheme,
            settings.ThemeMode.oled => t.settings.oledTheme,
          };
          return AutomationNode(
            id: AutomationIds.settingsTile,
            instance: 'appearance',
            role: 'list.item',
            child: SettingNavigationTile(
              focusNode: _focusTracker.get(_SettingsScreenState._kAppearance),
              icon: Symbols.palette_rounded,
              title: t.settings.appearance,
              subtitle: '${t.settings.libraryDensity} $libraryDensity',
              trailingLabel: theme,
              destinationBuilder: (context) => const AppearanceSettingsScreen(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocalLibraryTile() => AutomationNode(
    id: AutomationIds.settingsTile,
    instance: 'local_library',
    role: 'list.item',
    child: SettingNavigationTile(
      icon: Symbols.offline_bolt_rounded,
      title: t.localLibrary.title,
      subtitle: t.localLibrary.enable,
      destinationBuilder: (_) => const LocalLibrarySettingsScreen(),
    ),
  );

  Widget _buildLibraryVisibilityTile() {
    return SettingNavigationTile(
      focusNode: _focusTracker.get(_SettingsScreenState._kLibraryVisibility),
      icon: Symbols.video_library_rounded,
      title: t.settings.libraryVisibility,
      subtitle: t.settings.libraryVisibilityDescription,
      destinationBuilder: (context) => const LibraryVisibilityScreen(),
    );
  }

  Widget _buildHomeLayoutTile() {
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'home_layout',
      role: 'list.item',
      child: SettingNavigationTile(
        focusNode: _focusTracker.get(_SettingsScreenState._kHomeLayout),
        icon: Symbols.dashboard_customize_rounded,
        title: t.settings.homeLayout,
        subtitle: t.settings.homeLayoutDescription,
        destinationBuilder: (context) => const HomeLayoutScreen(),
      ),
    );
  }

  Widget _buildPlaybackTile() {
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'playback',
      role: 'list.item',
      child: SettingNavigationTile(
        focusNode: _focusTracker.get(_SettingsScreenState._kPlayback),
        icon: Symbols.play_circle_rounded,
        title: t.settings.videoPlayback,
        subtitle: t.settings.videoPlaybackDescription,
        destinationBuilder: (context) => const PlaybackSettingsScreen(),
      ),
    );
  }

  /// Taal en ondertitels — the single place a language preference is managed
  /// (DEC-109 lid 9), next to Afspelen because a viewer who wonders why a
  /// series starts in English looks under language rather than under playback.
  Widget _buildLanguageTile() {
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'language',
      role: 'list.item',
      child: SettingNavigationTile(
        focusNode: _focusTracker.get(_SettingsScreenState._kLanguage),
        icon: Symbols.translate_rounded,
        title: t.languageSettings.title,
        subtitle: t.languageSettings.description,
        destinationBuilder: (context) => const LanguageSettingsScreen(),
      ),
    );
  }

  /// Promoted out of "Video afspelen" (northstar 14): a top-level entry next
  /// to "Taal en ondertitels" instead of nested two levels down. Same
  /// destination and copy `PlaybackSettingsScreen` used, removed there so
  /// there is exactly one way in.
  Widget _buildSubtitleStylingTile() {
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'subtitle_styling',
      role: 'list.item',
      child: SettingNavigationTile(
        focusNode: _focusTracker.get(_SettingsScreenState._kSubtitleStyling),
        icon: Symbols.subtitles_rounded,
        title: t.settings.subtitleStyling,
        subtitle: t.settings.subtitleStylingDescription,
        destinationBuilder: (_) => const SubtitleStylingScreen(),
      ),
    );
  }

  /// Storage location, WiFi-only and auto-remove used to be three inline rows
  /// in their own unlabelled card; northstar 14 draws "Downloads" as one row
  /// with a summary, like every other entry in this group.
  Widget _buildDownloadsTile() {
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: 'downloads',
      role: 'list.item',
      child: SettingNavigationTile(
        focusNode: _focusTracker.get(_SettingsScreenState._kDownloadLocation),
        icon: Symbols.download_rounded,
        title: t.settings.downloads,
        subtitle: t.settings.downloadsDescription,
        destinationBuilder: (_) => const DownloadsSettingsScreen(),
      ),
    );
  }

  Widget _buildTrackersTile() {
    return Consumer2<TraktAccountProvider, TrackersProvider>(
      builder: (context, trakt, trackers, _) {
        final connectedNames = <String>[
          if (trakt.isConnected) t.trakt.title,
          if (trackers.isMalConnected) t.trackers.services.mal,
          if (trackers.isAnilistConnected) t.trackers.services.anilist,
          if (trackers.isSimklConnected) t.trackers.services.simkl,
        ];
        // A-24: what is connected is the row's value; the description stays.
        final connected = connectedNames.isEmpty ? null : connectedNames.join(' · ');
        return AutomationNode(
          id: AutomationIds.settingsTile,
          instance: 'trackers',
          role: 'list.item',
          child: SettingNavigationTile(
            focusNode: _focusTracker.get(_SettingsScreenState._kTrackers),
            icon: Symbols.sync_rounded,
            title: t.settings.trackers,
            subtitle: t.settings.trackersDescription,
            trailingLabel: connected,
            destinationBuilder: (_) => const TrackersSettingsScreen(),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTile() {
    return Consumer<SeerrProvider>(
      builder: (context, seerr, _) {
        return AutomationNode(
          id: AutomationIds.settingsTile,
          instance: 'requests',
          role: 'list.item',
          child: SettingNavigationTile(
            focusNode: _focusTracker.get(_SettingsScreenState._kRequests),
            icon: Symbols.playlist_add_rounded,
            title: t.settings.requests,
            subtitle: t.settings.requestsDescription,
            trailingLabel: seerr.isConfigured ? (seerr.host ?? t.settings.requests) : null,
            destinationBuilder: (_) => const SeerrSettingsScreen(),
          ),
        );
      },
    );
  }

  /// Tautulli reports on the whole Plex server, and its single API key opens
  /// the entire admin surface, so the tile only appears for someone with owner
  /// rights on a Plex server here. Everyone else never learns the integration exists, which
  /// is the right outcome: they could not use it anyway.
  Widget _buildTautulliTile() {
    if (!context.select<MultiServerProvider, bool>(_SettingsScreenState._managesAPlexServer)) {
      return const SizedBox.shrink();
    }

    return Consumer<TautulliProvider>(
      builder: (context, tautulli, _) {
        return SettingNavigationTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kTautulli),
          icon: Symbols.insights_rounded,
          title: t.tautulli.title,
          subtitle: t.tautulli.subtitle,
          trailingLabel: tautulli.isConfigured ? (tautulli.serverName ?? tautulli.host ?? t.tautulli.connected) : null,
          destinationBuilder: (_) => const TautulliSettingsScreen(),
        );
      },
    );
  }

  /// The full `ConnectionsSection` (add connection, host Pleya Share, every
  /// server and local source with its own removable row) moved behind one
  /// summary tile, northstar 14's single "Servers" row. [ServersScreen] is
  /// the exact wrap My Pleya's own Servers card already uses (DEC-113) — the
  /// same destination, reached from a second place, not a second copy of
  /// server management.
  Widget _buildServersSection() {
    return Consumer<MultiServerProvider>(
      builder: (context, servers, _) {
        final manager = servers.serverManager;
        final names = [for (final id in servers.serverIds) manager.serverDisplayName(ServerId(id))];
        final serverNames = names.isEmpty ? t.tvMyPleya.noServers : names.join(', ');
        return SettingsGroup(
          title: t.connections.sectionTitle,
          children: [
            AutomationNode(
              id: AutomationIds.settingsTile,
              instance: 'servers',
              role: 'list.item',
              child: SettingNavigationTile(
                focusNode: _focusTracker.get(_SettingsScreenState._kServers),
                icon: Symbols.dns_rounded,
                title: t.tvMyPleya.servers,
                trailingLabel: serverNames,
                needsAttention: servers.hasAuthErrorServers,
                destinationBuilder: (_) => const ServersScreen(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfilesTile() {
    return StreamBuilder<List<Profile>>(
      stream: context.read<ProfileRegistry>().watchProfiles(),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        // `context.select` so this StreamBuilder doesn't rebuild on every
        // ActiveProfileProvider notification — only when the active
        // profile's display name actually changes.
        final activeName = context.select<ActiveProfileProvider, String?>((p) => p.active?.displayName);
        // A-24: with several profiles the active one is the row's value and
        // the count stays under the title; a single profile keeps its hint.
        final subtitle = count <= 1 ? t.profiles.summarySingle : t.profiles.summaryMultiple(count: count);
        final trailing = count <= 1 ? null : activeName;
        return AutomationNode(
          id: AutomationIds.settingsTile,
          instance: 'profiles',
          role: 'list.item',
          child: SettingNavigationTile(
            icon: Symbols.group_rounded,
            title: t.profiles.sectionTitle,
            subtitle: subtitle,
            trailingLabel: trailing,
            onTap: () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
          ),
        );
      },
    );
  }
}
