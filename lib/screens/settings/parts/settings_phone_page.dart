/// Instellingen on phones, tablets and desktop: the scaffold with its search
/// field, the list of groups and the search results.
///
/// A `part` for the same reason as `settings_tv_page.dart`: every row and
/// every dialog below is a method of the one settings screen, so the phone and
/// the TV page cannot drift into two definitions of the same action.
part of '../settings_screen.dart';

extension _SettingsPhonePage on _SettingsScreenState {
  Widget _buildSettingsScaffold(BuildContext context) {
    // A-24: the Studio header, its bar and the filled search bar on an iPhone;
    // everywhere else the plain bar and outlined field from before.
    final studio = settingsStudioHeaderApplies(context);
    // The eyebrow names whose settings these are, when there is a profile.
    final profileName = context.select<ActiveProfileProvider?, String?>((p) => p?.active?.displayName);
    return Scaffold(
      body: Focus(
        onKeyEvent: _handleKeyEvent,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => studio && settingsStudioTrackScroll(_studioCollapsed, n),
          child: ScrollCrown(
            child: CustomScrollView(
              primary: false,
              slivers: [
                ExcludeFocus(
                  child: studio
                      ? SettingsStudioBar(collapsed: _studioCollapsed, title: Text(t.settings.title))
                      : CustomAppBar(title: Text(t.settings.title), pinned: true),
                ),
                if (studio)
                  SliverToBoxAdapter(
                    child: ExcludeFocus(
                      child: SettingsWidthLimit(
                        child: SettingsStudioHeader(title: t.settings.title, section: profileName),
                      ),
                    ),
                  ),
                if (_searchEnabled)
                  SliverToBoxAdapter(
                    child: SettingsWidthLimit(child: _buildSearchField(studio: studio)),
                  ),
                if (_searchQuery.isNotEmpty)
                  _buildSearchResults()
                else
                  SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        if (DonationService.isEnabled) SettingsGroup(children: [_buildDonateTile()]),

                        SettingsGroup(
                          title: t.settings.sectionLibrary,
                          children: [
                            _buildAppearanceTile(),
                            _buildLibraryVisibilityTile(),
                            _buildLocalLibraryTile(),
                            _buildHomeLayoutTile(),
                            _buildPlaybackTile(),
                            _buildLanguageTile(),
                            _buildSubtitleStylingTile(),
                            if (!PlatformDetector.isAppleTV()) _buildDownloadsTile(),
                          ],
                        ),

                        SettingsGroup(
                          title: t.settings.sectionIntegrations,
                          children: [
                            _buildTrackersTile(),
                            _buildRequestsTile(),
                            _buildTautulliTile(),
                            ?assistantSettingsTile(context),
                            _buildProfilesTile(),
                          ],
                        ),

                        _buildServersSection(),

                        if (_keyboardShortcutsSupported) ...[_buildKeyboardShortcutsSection()],

                        _buildAdvancedSection(),

                        if (UpdateService.isUpdateCheckEnabled) ...[_buildUpdateSection()],

                        if (!PlatformDetector.isTV() || _SettingsScreenState._icloudSyncPlatform) _buildBackupSection(),

                        if (kDebugMode) _buildDebugSection(),

                        SettingsGroup(
                          children: [
                            SettingNavigationTile(
                              focusNode: _focusTracker.get(_SettingsScreenState._kAbout),
                              icon: Symbols.info_rounded,
                              title: t.settings.about,
                              subtitle: t.settings.aboutDescription,
                              destinationBuilder: (context) => const AboutScreen(),
                            ),
                          ],
                        ),
                        // Plus the bottom inset: with Liquid Glass the tab bar floats
                        // over this list and the main Scaffold reports its height here.
                        SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
                        // Every card gets the same maximum width so the column stays
                        // centred on a wide window instead of stretching across it.
                      ].map((w) => SettingsWidthLimit(child: w)).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField({required bool studio}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, studio ? 0 : 8, 16, 8),
      // A-24 on an iPhone: a filled, rounded bar without an outline. The
      // theme's input decoration already supplies the fill and the 12 pt
      // radius. Elsewhere the outlined field from before.
      child: FocusableTextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: t.settings.searchHint,
          prefixIcon: const AppIcon(Symbols.search_rounded),
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
  /// query. Titles/subtitles reuse the same [t] strings as the tiles; tapping a
  /// result navigates to the same destination screen. Platform gating mirrors
  /// the tile list so hidden destinations never surface in search.
  List<_SettingsSearchEntry> _buildSearchIndex() {
    return [
      _SettingsSearchEntry(
        icon: Symbols.palette_rounded,
        title: t.settings.appearance,
        keywords: const ['theme', 'dark', 'light', 'density', 'thema', 'kleur'],
        destinationBuilder: (_) => const AppearanceSettingsScreen(),
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
        icon: Symbols.play_circle_rounded,
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
            MaterialPageRoute(builder: (_) => KeyboardShortcutsScreen(keyboardService: _keyboardService!)),
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
          Navigator.push(context, MaterialPageRoute(builder: (_) => AddConnectionScreen(targetProfile: active)));
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
        title: t.tvMyPleya.servers,
        keywords: const ['server', 'plex', 'jellyfin', 'nas', 'servers'],
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
      if (UpdateService.isUpdateCheckEnabled)
        _SettingsSearchEntry(
          icon: Symbols.system_update_rounded,
          title: t.settings.checkForUpdates,
          keywords: const ['update', 'upgrade', 'versie', 'bijwerken'],
          onTap: (_) => _handleCheckForUpdatesTap(),
        ),
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
