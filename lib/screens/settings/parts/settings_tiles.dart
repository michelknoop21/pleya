/// The rows of the main Instellingen page on phones, tablets and desktop
/// (A-24b, anchor `01` and series `ios/01`): one row per page, a line icon,
/// the title and a chevron. What a row used to say in its value or under its
/// title is on the page it opens.
///
/// A `part` of `settings_screen.dart`: each builder reads the screen's focus
/// memory, so keyboard focus comes back to the row a page was opened from.
part of '../settings_screen.dart';

extension _SettingsTiles on _SettingsScreenState {
  /// A main-page row: [instance] is its `settings.tile[...]` automation id and
  /// [focusKey] its place in the focus memory.
  Widget _mainRow({
    required String instance,
    required String focusKey,
    required IconData icon,
    required String title,
    String? subtitle,
    WidgetBuilder? destinationBuilder,
    VoidCallback? onTap,
    bool needsAttention = false,
  }) {
    return AutomationNode(
      id: AutomationIds.settingsTile,
      instance: instance,
      role: 'list.item',
      child: SettingNavigationTile(
        focusNode: _focusTracker.get(focusKey),
        icon: icon,
        title: title,
        subtitle: subtitle,
        needsAttention: needsAttention,
        destinationBuilder: destinationBuilder,
        onTap: onTap,
      ),
    );
  }

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

  Widget _buildAppearanceTile() => _mainRow(
    instance: 'appearance',
    focusKey: _SettingsScreenState._kAppearance,
    icon: Symbols.light_mode_rounded,
    title: t.settings.appearance,
    destinationBuilder: (_) => const AppearanceSettingsScreen(),
  );

  Widget _buildPlaybackTile() => _mainRow(
    instance: 'playback',
    focusKey: _SettingsScreenState._kPlayback,
    icon: Symbols.play_arrow_rounded,
    title: t.settings.videoPlayback,
    subtitle: t.settings.videoPlaybackDescription,
    destinationBuilder: (_) => const PlaybackSettingsScreen(),
  );

  /// Taal en ondertitels: the single place a language preference is managed
  /// (DEC-109 lid 9), next to Afspelen.
  Widget _buildLanguageTile() => _mainRow(
    instance: 'language',
    focusKey: _SettingsScreenState._kLanguage,
    icon: Symbols.subtitles_rounded,
    title: t.languageSettings.title,
    subtitle: t.languageSettings.description,
    destinationBuilder: (_) => const LanguageSettingsScreen(),
  );

  Widget _buildSubtitleStylingTile() => _mainRow(
    instance: 'subtitle_styling',
    focusKey: _SettingsScreenState._kSubtitleStyling,
    icon: Symbols.closed_caption_rounded,
    title: t.settings.subtitleStyling,
    subtitle: t.settings.subtitleStylingDescription,
    destinationBuilder: (_) => const SubtitleStylingScreen(),
  );

  /// Bibliotheken: the page with library visibility, the local library, the
  /// Home layout and, off Apple TV, Downloads (series `ios/03`).
  Widget _buildLibraryHomeTile() => _mainRow(
    instance: 'library_home',
    focusKey: _SettingsScreenState._kLibraryHome,
    icon: Symbols.grid_view_rounded,
    title: t.settingsStudio.libraries,
    destinationBuilder: (_) => const LibraryHomeSettingsScreen(),
  );

  /// Koppelingen: Trackers, Aanvragen and, for a Plex owner, Tautulli.
  Widget _buildIntegrationsTile() => _mainRow(
    instance: 'integrations',
    focusKey: _SettingsScreenState._kIntegrations,
    icon: Symbols.cloud_rounded,
    title: t.settingsStudio.integrations,
    destinationBuilder: (_) => const IntegrationsSettingsScreen(),
  );

  /// Servers en bronnen: the existing [ServersScreen], the same destination
  /// Mijn Pleya's own Servers card opens (DEC-113). The amber dot still says
  /// that a server needs a new sign-in.
  Widget _buildServersTile() => Selector<MultiServerProvider, bool>(
    selector: (_, servers) => servers.hasAuthErrorServers,
    builder: (context, needsAttention, _) => _mainRow(
      instance: 'servers',
      focusKey: _SettingsScreenState._kServers,
      icon: Symbols.dns_rounded,
      title: t.settingsStudio.serversAndSources,
      needsAttention: needsAttention,
      destinationBuilder: (_) => const ServersScreen(),
    ),
  );

  Widget _buildProfilesTile() => _mainRow(
    instance: 'profiles',
    focusKey: _SettingsScreenState._kProfiles,
    icon: Symbols.person_rounded,
    title: t.profiles.sectionTitle,
    onTap: () =>
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
  );

  Widget _buildAdvancedTile() => _mainRow(
    instance: 'advanced',
    focusKey: _SettingsScreenState._kAdvanced,
    icon: Symbols.tune_rounded,
    title: t.settings.advanced,
    destinationBuilder: (_) => const _SettingsSystemPage(_SystemPageKind.advanced),
  );

  Widget _buildBackupTile() => _mainRow(
    instance: 'backup',
    focusKey: _SettingsScreenState._kBackup,
    icon: Symbols.cloud_upload_rounded,
    title: t.settings.backup,
    destinationBuilder: (_) => const _SettingsSystemPage(_SystemPageKind.backup),
  );

  Widget _buildUpdatesTile() => _mainRow(
    instance: 'updates',
    focusKey: _SettingsScreenState._kUpdates,
    icon: Symbols.system_update_rounded,
    title: t.settings.updates,
    destinationBuilder: (_) => const _SettingsSystemPage(_SystemPageKind.updates),
  );

  Widget _buildAboutTile() => _mainRow(
    instance: 'about',
    focusKey: _SettingsScreenState._kAbout,
    icon: Symbols.info_rounded,
    title: t.settings.about,
    subtitle: t.settings.aboutDescription,
    destinationBuilder: (_) => const AboutScreen(),
  );
}
