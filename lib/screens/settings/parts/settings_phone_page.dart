/// Instellingen on phones, tablets and desktop: the scaffold with its search
/// field, the list of groups and the search results.
///
/// A `part` for the same reason as `settings_tv_page.dart`: every row and
/// every dialog below is a method of the one settings screen, so the phone and
/// the TV page cannot drift into two definitions of the same action.
part of '../settings_screen.dart';

extension _SettingsPhonePage on _SettingsScreenState {
  Widget _buildSettingsScaffold(BuildContext context) {
    // A-24: the Studio header and the filled search bar on an iPhone;
    // everywhere else the plain bar and outlined field from before.
    final studio = settingsStudioHeaderApplies(context);
    final list = _searchQuery.isNotEmpty ? _buildSearchResults() : _buildGroups(context);
    if (!studio) {
      return Scaffold(
        body: Focus(
          onKeyEvent: _handleKeyEvent,
          child: ScrollCrown(
            child: CustomScrollView(
              primary: false,
              slivers: [
                ExcludeFocus(child: CustomAppBar(title: Text(t.settings.title), pinned: true)),
                if (_searchEnabled)
                  SliverToBoxAdapter(child: SettingsWidthLimit(child: _buildSearchField(studio: false))),
                list,
              ],
            ),
          ),
        ),
      );
    }
    // A-24b, anchor `01`: no bar above the header. The page scrolls from the
    // top of the screen and the compact bar is laid over it once the large
    // title has gone under the status bar ([SettingsStudioFrame]).
    return Scaffold(
      body: Focus(
        onKeyEvent: _handleKeyEvent,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => settingsStudioTrackScroll(_studioCollapsed, n),
          child: SettingsStudioFrame(
            collapsed: _studioCollapsed,
            title: Text(t.settings.title),
            child: ScrollCrown(
              child: CustomScrollView(
                primary: false,
                slivers: [
                  SliverToBoxAdapter(
                    child: ExcludeFocus(
                      child: SettingsWidthLimit(
                        child: SettingsStudioHeader(
                          title: t.settings.title,
                          section: t.settingsStudio.personal,
                          tagline: t.settingsStudio.mainTagline,
                        ),
                      ),
                    ),
                  ),
                  if (_searchEnabled)
                    SliverToBoxAdapter(child: SettingsWidthLimit(child: _buildSearchField(studio: true))),
                  list,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The groups of anchor `01` and series `ios/01`: VOOR JOU, VERBINDINGEN EN
  /// PROFIELEN and SYSTEEM, one row per page. Steun Pleya stays on top where
  /// the build offers it. Every row of the old groups is on the page its row
  /// opens; the old-to-new mapping is in the A-24b parity matrix.
  Widget _buildGroups(BuildContext context) {
    final groups = <Widget>[
      if (DonationService.isEnabled) SettingsGroup(children: [_buildDonateTile()]),
      SettingsGroup(
        title: t.settingsStudio.forYou,
        children: [
          _buildAppearanceTile(),
          _buildPlaybackTile(),
          _buildLanguageTile(),
          _buildSubtitleStylingTile(),
          _buildLibraryHomeTile(),
        ],
      ),
      SettingsGroup(
        title: t.settingsStudio.connectionsAndProfiles,
        children: [
          _buildIntegrationsTile(),
          ?assistantSettingsTile(context),
          _buildProfilesTile(),
          _buildServersTile(),
        ],
      ),
      SettingsGroup(
        title: t.settingsStudio.system,
        children: [
          _buildAdvancedTile(),
          _buildBackupTile(),
          if (UpdateService.isUpdateCheckEnabled) _buildUpdatesTile(),
          _buildAboutTile(),
        ],
      ),
      // Plus the bottom inset: with Liquid Glass the tab bar floats over this
      // list and the main Scaffold reports its height here.
      SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
    ];
    final sliver = SliverList(
      // Every card gets the same maximum width so the column stays centred
      // on a wide window instead of stretching across it.
      delegate: SliverChildListDelegate([for (final group in groups) SettingsWidthLimit(child: group)]),
    );
    // The page always wears the Studio palette off TV ([SettingsScreen.build]
    // wraps it below this State's context): line icons and titles only, the
    // description is the row's VoiceOver hint (A-24b).
    return SettingsIconStyleScope(style: SettingsIconStyle.line, hideDescriptions: true, child: sliver);
  }

  Widget _buildSearchField({required bool studio}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, studio ? 0 : 8, 16, 8),
      // A-24 on an iPhone: a filled, rounded bar without an outline. The
      // theme's input decoration already supplies the fill and the 12 pt
      // radius. Elsewhere the outlined field from before.
      child: FocusableTextField(
        controller: _searchController,
        // A-24b: the series' 40 pt search bar with 14 pt text on an iPhone.
        style: studio ? const TextStyle(fontSize: 14) : null,
        decoration: InputDecoration(
          hintText: t.settings.searchHint,
          hintStyle: studio
              ? (Theme.of(context).inputDecorationTheme.hintStyle ?? const TextStyle()).copyWith(fontSize: 14)
              : null,
          prefixIcon: studio ? const AppIcon(Symbols.search_rounded, size: 20) : const AppIcon(Symbols.search_rounded),
          prefixIconConstraints: studio ? const BoxConstraints(minWidth: 40, minHeight: 40) : null,
          contentPadding: studio ? const EdgeInsets.symmetric(vertical: 11) : null,
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const AppIcon(Symbols.close_rounded),
                  onPressed: () {
                    _searchController.clear();
                    _searchQuery = '';
                    _rebuild();
                  },
                ),
          border: studio ? null : const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) {
          _searchQuery = value.trim();
          _rebuild();
        },
      ),
    );
  }

  /// Static index of navigable settings sub-screens, filtered by the search
  /// query. Grouped (A-24b) or not, every row of every settings page that has
  /// one destination is here, by its own title or by its page's. Titles/subtitles reuse the same [t] strings as the tiles; tapping a
  /// result navigates to the same destination screen. Platform gating mirrors
  /// the tile list so hidden destinations never surface in search.
  List<_SettingsSearchEntry> _buildSearchIndex() {
    return [
      _SettingsSearchEntry(
        icon: Symbols.light_mode_rounded,
        title: t.settings.appearance,
        keywords: const ['theme', 'dark', 'light', 'density', 'thema', 'kleur', 'uiterlijk', 'appearance', 'dichtheid'],
        destinationBuilder: (_) => const AppearanceSettingsScreen(),
      ),
      // A-24b: the pages the main page's rows open are found by their own
      // name too, not only by the rows inside them.
      _SettingsSearchEntry(
        icon: Symbols.grid_view_rounded,
        title: t.settingsStudio.libraryAndHome,
        keywords: const ['libraries', 'bibliotheken', 'home', 'downloads'],
        destinationBuilder: (_) => const LibraryHomeSettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.offline_bolt_rounded,
        title: t.localLibrary.title,
        subtitle: t.localLibrary.enable,
        keywords: const ['offline', 'local', 'lokaal', 'sync', 'synchroniseren', 'index'],
        destinationBuilder: (_) => const LocalLibrarySettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.cloud_rounded,
        title: t.settingsStudio.integrations,
        keywords: const ['integrations', 'trakt', 'seerr', 'tautulli', 'koppelen'],
        destinationBuilder: (_) => const IntegrationsSettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.tune_rounded,
        title: t.settings.advanced,
        keywords: const ['advanced', 'crash', 'debug', 'logging', 'relay', 'cache', 'reset', 'onderhoud'],
        destinationBuilder: (_) => const _SettingsSystemPage(_SystemPageKind.advanced),
      ),
      _SettingsSearchEntry(
        icon: Symbols.cloud_upload_rounded,
        title: t.settings.backup,
        keywords: const ['backup', 'icloud', 'sync', 'export', 'import'],
        destinationBuilder: (_) => const _SettingsSystemPage(_SystemPageKind.backup),
      ),
      _SettingsSearchEntry(
        icon: Symbols.video_library_rounded,
        title: t.settings.libraryVisibility,
        subtitle: t.settings.libraryVisibilityDescription,
        destinationBuilder: (_) => const LibraryVisibilityScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.dashboard_customize_rounded,
        title: t.settings.homeLayout,
        subtitle: t.settings.homeLayoutDescription,
        keywords: const ['home', 'rows', 'order', 'reorder', 'hide', 'rijen', 'volgorde', 'verbergen', 'indeling'],
        destinationBuilder: (_) => const HomeLayoutScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.play_arrow_rounded,
        title: t.settings.videoPlayback,
        subtitle: t.settings.videoPlaybackDescription,
        keywords: const [
          'subtitle',
          'audio',
          'skip intro',
          'ondertitel',
          'afspelen',
          // The audio-output setting lives on this screen; these are what
          // people actually type when they go looking for it.
          'atmos',
          'dolby',
          'passthrough',
          'spatial',
          'surround',
          'doorvoer',
        ],
        destinationBuilder: (_) => const PlaybackSettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.translate_rounded,
        title: t.languageSettings.title,
        subtitle: t.languageSettings.description,
        keywords: const [
          'language',
          'subtitle',
          'audio',
          'taal',
          'ondertitel',
          'ondertiteling',
          'sprache',
          'untertitel',
          'series preference',
          'serievoorkeur',
          'app language',
          'app-taal',
          'interface',
          'locale',
        ],
        destinationBuilder: (_) => const LanguageSettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.sync_rounded,
        title: t.settings.trackers,
        subtitle: t.settings.trackersDescription,
        keywords: const ['trakt', 'mal', 'anilist', 'simkl'],
        destinationBuilder: (_) => const TrackersSettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.playlist_add_rounded,
        title: t.settings.requests,
        subtitle: t.settings.requestsDescription,
        keywords: const ['jellyseerr', 'overseerr', 'seerr'],
        destinationBuilder: (_) => const SeerrSettingsScreen(),
      ),
      // Same gate as the tile itself: searching for "tautulli" must not be a
      // back door into a screen the profile is not allowed to have.
      if (_SettingsScreenState._managesAPlexServer(context.read<MultiServerProvider>()))
        _SettingsSearchEntry(
          icon: Symbols.insights_rounded,
          title: t.tautulli.title,
          subtitle: t.tautulli.subtitle,
          keywords: const ['tautulli', 'statistics', 'statistieken', 'watched by'],
          destinationBuilder: (_) => const TautulliSettingsScreen(),
        ),
      if (_keyboardShortcutsSupported && _keyboardService != null)
        _SettingsSearchEntry(
          icon: Symbols.keyboard_rounded,
          title: t.settings.keyboardShortcuts,
          keywords: const ['hotkey', 'shortcut', 'sneltoets'],
          onTap: (context) => Navigator.push(
            context,
            settingsStudioRoute<void>(context, (_) => KeyboardShortcutsScreen(keyboardService: _keyboardService!)),
          ),
        ),
      _SettingsSearchEntry(
        icon: Symbols.info_rounded,
        title: t.settings.about,
        subtitle: t.settings.aboutDescription,
        keywords: const ['version', 'license', 'versie', 'licentie'],
        destinationBuilder: (_) => const AboutScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.add_link_rounded,
        title: t.connections.addConnection,
        keywords: const ['server', 'plex', 'jellyfin', 'connection', 'verbinding', 'share', 'pair', 'koppelen'],
        onTap: (context) {
          final active = context.read<ActiveProfileProvider>().active;
          Navigator.push(
            context,
            settingsStudioRoute<void>(context, (_) => AddConnectionScreen(targetProfile: active)),
          );
        },
      ),
      _SettingsSearchEntry(
        icon: Symbols.share_rounded,
        title: t.pleyaShare.hostTitle,
        subtitle: t.pleyaShare.hostToggle,
        keywords: const ['share', 'delen', 'pair', 'koppelen', 'host', 'pleya share'],
        destinationBuilder: (_) => const PleyaShareHostScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.group_rounded,
        title: t.profiles.sectionTitle,
        keywords: const ['profile', 'user', 'pin', 'gebruiker', 'profiel'],
        onTap: (context) => Navigator.of(
          context,
          rootNavigator: true,
        ).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
      ),
      _SettingsSearchEntry(
        icon: Symbols.article_rounded,
        title: t.settings.viewLogs,
        subtitle: t.settings.viewLogsDescription,
        keywords: const ['log', 'logs', 'debug', 'diagnostiek'],
        destinationBuilder: (_) => const LogsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.download_rounded,
        title: t.settings.downloads,
        subtitle: t.settings.downloadsDescription,
        keywords: const ['download', 'offline', 'storage', 'wifi', 'opslag', 'locatie'],
        destinationBuilder: (_) => const DownloadsSettingsScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.subtitles_rounded,
        title: t.settings.subtitleStyling,
        subtitle: t.settings.subtitleStylingDescription,
        keywords: const ['subtitle', 'caption', 'font', 'ondertitel', 'lettertype'],
        destinationBuilder: (_) => const SubtitleStylingScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.dns_rounded,
        title: t.settingsStudio.serversAndSources,
        keywords: const ['server', 'plex', 'jellyfin', 'nas', 'servers', 'bronnen', 'sources'],
        destinationBuilder: (_) => const ServersScreen(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.dns_rounded,
        title: t.settings.watchTogetherRelay,
        subtitle: t.settings.watchTogetherRelayDescription,
        keywords: const ['relay', 'watch together', 'url', 'server'],
        onTap: (_) => _showRelayUrlDialog(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.cleaning_services_rounded,
        title: t.settings.clearCache,
        subtitle: t.settings.clearCacheDescription,
        keywords: const ['cache', 'clear', 'wissen', 'opschonen'],
        onTap: (_) => _showClearCacheDialog(),
      ),
      _SettingsSearchEntry(
        icon: Symbols.restore_rounded,
        title: t.settings.resetSettings,
        subtitle: t.settings.resetSettingsDescription,
        keywords: const ['reset', 'restore', 'herstel', 'standaard'],
        onTap: (_) => _showResetSettingsDialog(),
      ),
      if (!PlatformDetector.isTV()) ...[
        _SettingsSearchEntry(
          icon: Symbols.upload_rounded,
          title: t.settings.exportSettings,
          subtitle: t.settings.exportSettingsDescription,
          keywords: const ['backup', 'export', 'settings', 'instellingen'],
          onTap: (_) => _handleExportSettings(),
        ),
        _SettingsSearchEntry(
          icon: Symbols.download_rounded,
          title: t.settings.importSettings,
          subtitle: t.settings.importSettingsDescription,
          keywords: const ['backup', 'import', 'restore', 'instellingen'],
          onTap: (_) => _showImportSettingsDialog(),
        ),
      ],
      if (UpdateService.isUpdateCheckEnabled) ...[
        _SettingsSearchEntry(
          icon: Symbols.system_update_rounded,
          title: t.settings.checkForUpdates,
          keywords: const ['update', 'upgrade', 'versie', 'bijwerken'],
          onTap: (_) => _handleCheckForUpdatesTap(),
        ),
        _SettingsSearchEntry(
          icon: Symbols.system_update_rounded,
          title: t.settings.updates,
          keywords: const ['update', 'automatic', 'automatisch', 'opstarten'],
          destinationBuilder: (_) => const _SettingsSystemPage(_SystemPageKind.updates),
        ),
      ],
    ];
  }

  Widget _buildSearchResults() {
    final query = _searchQuery.toLowerCase();
    final results = _buildSearchIndex().where((e) => e.matches(query)).toList();
    if (results.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(t.messages.noResultsFound)),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = results[index];
        return SettingNavigationTile(
          icon: entry.icon,
          title: entry.title,
          subtitle: entry.subtitle,
          destinationBuilder: entry.destinationBuilder,
          onTap: entry.onTap == null ? null : () => entry.onTap!(context),
        );
      }, childCount: results.length),
    );
  }
}

/// Pure predicate for the settings search: does an entry with this [title],
/// [subtitle] and [keywords] match [lowerQuery] (already lower-cased)? Extracted
/// as a top-level function so it can be unit-tested without pumping the screen.
@visibleForTesting
bool settingsSearchMatches({
  required String title,
  String? subtitle,
  List<String> keywords = const [],
  required String lowerQuery,
}) {
  if (lowerQuery.isEmpty) return false;
  return title.toLowerCase().contains(lowerQuery) ||
      (subtitle?.toLowerCase().contains(lowerQuery) ?? false) ||
      keywords.any((k) => k.toLowerCase().contains(lowerQuery));
}

/// One searchable settings destination. Exactly one of [destinationBuilder] /
/// [onTap] is set — the tile navigates the same way the original tile did.
class _SettingsSearchEntry {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<String> keywords;
  final WidgetBuilder? destinationBuilder;
  final void Function(BuildContext)? onTap;

  const _SettingsSearchEntry({
    required this.icon,
    required this.title,
    this.subtitle,
    this.keywords = const [],
    this.destinationBuilder,
    this.onTap,
  }) : assert(destinationBuilder != null || onTap != null);

  bool matches(String lowerQuery) =>
      settingsSearchMatches(title: title, subtitle: subtitle, keywords: keywords, lowerQuery: lowerQuery);
}
