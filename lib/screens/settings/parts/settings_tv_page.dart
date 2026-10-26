/// Mijn Pleya ▸ Instellingen on TV, per the A-24b Studio anchor `02` and the
/// series `tvos/01`-`12`.
///
/// A `part` rather than a widget of its own because this is the same screen:
/// every destination, dialog and preference write below is the method the
/// mobile row already calls. Copying them into a second screen would give the
/// product two definitions of "reset settings", and one of those is
/// destructive.
///
/// The rail carries the series' categories, each with its glyph: Weergave,
/// Afspelen, Taal en ondertitels, Bibliotheken, Home aanpassen, Koppelingen,
/// Big P where the build has it, and Geavanceerd. Where the series shows a
/// category's settings in place, the category mounts the settings page that
/// owns them under [SettingsInlineScope]: the same rows, the same conditions
/// and the same automation ids as that page opened on its own, and the same
/// building blocks the iPhone pages use (Bibliotheek & Home, Koppelingen,
/// Servers en bronnen, Home aanpassen). Nothing is defined twice.
///
/// **Same conditions.** Downloads is still absent on an Apple TV (the
/// Bibliotheek & Home page's own gate), Backup still narrows to the one iCloud
/// toggle, Tautulli still only exists for someone who owns a Plex server here,
/// Big P only where the build carries it.
part of '../settings_screen.dart';

extension _SettingsTvPage on _SettingsScreenState {
  /// A preference as a tile: the state on the value line, the state in the
  /// glyph, and SELECT toggles it. There is no switch to reach separately —
  /// on a remote the row *is* the control.
  TvMenuItem _tvToggle({
    required String key,
    required IconData icon,
    required String title,
    required settings.Pref<bool> pref,
    bool enabled = true,
    String? subtitle,
    FutureOr<void> Function(bool)? onAfterWrite,
  }) {
    final value = _settingsService.read(pref);
    return TvMenuItem(
      key: key,
      icon: icon,
      title: title,
      // The value line says the state; the subtitle only survives where it
      // explains something the state cannot, such as iCloud being unreachable.
      value: subtitle ?? (value ? t.common.on : t.common.off),
      toggled: value,
      onSelect: !enabled
          ? null
          : () async {
              await _settingsService.write(pref, !value);
              if (onAfterWrite != null) await onAfterWrite(!value);
            },
    );
  }

  Widget _buildTvSettings(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final active = context.watch<ActiveProfileProvider>().active;

    // A settings subpage opens inside the shell. `SettingsScreen` is itself a
    // nested route already (`tvMyPleyaNestedRoute`), so pushing its own
    // subpages on the profile navigator meant the child escaped a shell the
    // parent had stayed inside. A-24 (DEC-XXX): under the same collapsible
    // bar as this page ([kTvSettingsTopNav]). Falls back to the ordinary push
    // when no TV shell is listening, which is every test that mounts this page
    // on its own.
    void open(String id, WidgetBuilder builder) {
      // Every page opened from here is a settings page: it keeps the Studio
      // palette (A-24b). [context] is the State's, above the page's wrapper.
      Widget studio(BuildContext context) => SettingsStudioTheme(child: builder(context));
      if (openTvContentRoute(id: 'tvSettings_$id', builder: studio, topNav: kTvSettingsTopNav) != null) return;
      Navigator.push(context, MaterialPageRoute<void>(builder: studio));
    }

    TvSettingsRowList rows(List<TvMenuItem> items) =>
        TvSettingsRowList(items: items, nodes: _focusTracker, automationInstance: 'settings');

    // Rebuilds when any preference a row or a preview shows changes. Without
    // this the row would keep drawing the value it was built with, because
    // nothing here listens the way `SettingSwitchTile` does per row.
    return SettingsBuilder(
      prefs: [
        settings.SettingsService.viewMode,
        settings.SettingsService.defaultQualityPreset,
        settings.SettingsService.crashReporting,
        settings.SettingsService.enableDebugLogging,
        settings.SettingsService.videoPlayerNavigationEnabled,
        settings.SettingsService.autoCheckUpdatesOnStartup,
        settings.SettingsService.icloudSyncEnabled,
      ],
      builder: (context) {
        final libraryPreview = TvSettingsLibraryPreview(
          modeLine: settingsPreviewModeLine(
            themeProvider.themeMode,
            _settingsService.read(settings.SettingsService.viewMode),
          ),
          // "Bekijk voorbeeld" opens Bibliotheken; RIGHT from a row reaches
          // it, LEFT goes back to the rows.
          action: settingsViewPreviewAction(context),
        );
        final assistant = assistantSettingsTvItem(
          onSelect: () => open('assistant', (_) => const AssistantSettingsScreen()),
        );
        final categories = <TvSettingsCategory>[
          if (DonationService.isEnabled)
            TvSettingsCategory(
              id: 'support',
              title: t.settings.supportDeveloper,
              icon: Symbols.favorite_rounded,
              body: rows([
                TvMenuItem(
                  key: _SettingsScreenState._kDonate,
                  icon: Symbols.favorite_rounded,
                  title: t.settings.supportDeveloper,
                  subtitle: t.settings.supportDeveloperDescription,
                  onSelect: _handleDonateTap,
                ),
              ]),
            ),
          TvSettingsCategory(
            id: 'appearance',
            title: t.settings.appearance,
            icon: Symbols.light_mode_rounded,
            heading: t.settingsStudio.appearanceHeadline,
            body: const SettingsInlineScope(child: AppearanceSettingsScreen()),
            preview: libraryPreview,
          ),
          TvSettingsCategory(
            id: 'playback',
            title: t.settings.videoPlayback,
            icon: Symbols.play_arrow_rounded,
            body: const SettingsInlineScope(child: PlaybackSettingsScreen()),
            preview: TvSettingsPlaybackPreview(
              qualityLine:
                  '${t.settings.defaultQualityTitle} · '
                  '${qualityPresetLabel(_settingsService.read(settings.SettingsService.defaultQualityPreset))}',
            ),
          ),
          TvSettingsCategory(
            id: 'language',
            title: t.languageSettings.title,
            icon: Symbols.subtitles_rounded,
            // The series' last group here is Ondertekststijl.
            body: const SettingsInlineScope(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [LanguageSettingsScreen(), SubtitleStylingScreen()],
              ),
            ),
            preview: libraryPreview,
          ),
          TvSettingsCategory(
            id: 'libraries',
            title: t.settingsStudio.libraries,
            icon: Symbols.grid_view_rounded,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsInlineScope(child: LibraryHomeSettingsScreen(includeHomeLayout: false)),
                SettingsSectionHeader(t.profiles.sectionTitle),
                rows([
                  TvMenuItem(
                    key: 'settings_profiles',
                    icon: Symbols.group_rounded,
                    title: t.settingsStudio.activeProfile,
                    value: active?.displayName,
                    subtitle: t.profiles.summarySingle,
                    onSelect: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(MaterialPageRoute<void>(builder: (_) => const ProfileSwitchScreen())),
                  ),
                ]),
              ],
            ),
            preview: libraryPreview,
          ),
          TvSettingsCategory(
            id: 'home',
            title: t.settings.homeLayout,
            icon: Symbols.stacks_rounded,
            body: SettingsGroup(children: buildHomeLayoutRows(context)),
          ),
          TvSettingsCategory(
            id: 'integrations',
            title: t.settingsStudio.integrations,
            icon: Symbols.cloud_rounded,
            // Trackers, Aanvragen and Tautulli as on the iPhone's Koppelingen
            // page, then Servers en bronnen (series `tvos/10`).
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsInlineScope(child: IntegrationsSettingsScreen()),
                // The series' second page here has its own large title.
                Padding(
                  padding: EdgeInsets.only(top: 28 * TvHig.of(context)),
                  child: TvStudioHeading(t.settingsStudio.serversAndSources),
                ),
                const ConnectionsSection(),
              ],
            ),
          ),
          if (assistant != null)
            TvSettingsCategory(
              id: 'assistant',
              title: assistant.title,
              icon: assistant.icon,
              body: const SettingsInlineScope(child: AssistantSettingsScreen()),
              preview: TvSettingsLibraryPreview(
                eyebrow: t.assistant.tileTitle,
                title: t.assistant.examples.tonight.first,
                modeLine: t.assistant.tileSubtitle,
              ),
            ),
          TvSettingsCategory(
            id: 'advanced',
            title: t.settings.advanced,
            icon: Symbols.settings_rounded,
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _tvAdvancedGroups(open, rows)),
          ),
        ];
        return SettingsIconStyleScope(
          style: SettingsIconStyle.none,
          hideDescriptions: true,
          child: TvSettingsCategories(
            key: _tvCategories,
            title: t.settings.title,
            subtitle: t.settingsStudio.tvTagline,
            automationInstance: 'settings',
            categoryAutomationId: AutomationIds.settingsCategory,
            autofocusFirstCategory: false,
            maxBodyWidthPt: 1100,
            categories: categories,
          ),
        );
      },
    );
  }

  /// Geavanceerd (series `tvos/11`-`12`): Diagnose, Onderhoud, the keyboard
  /// where it exists, Updates in a build that checks, Back-up (iCloud) and
  /// Over Pleya. Export and import hand a file to a file picker, which a TV
  /// has no sensible surface for, so Back-up is the iCloud toggle or nothing,
  /// the same rule `_buildBackupSection` applies.
  List<Widget> _tvAdvancedGroups(
    void Function(String id, WidgetBuilder builder) open,
    TvSettingsRowList Function(List<TvMenuItem>) rows,
  ) => [
    SettingsSectionHeader(t.settingsStudio.diagnostics),
    rows([
      TvMenuItem(
        key: _SettingsScreenState._kWatchTogetherRelay,
        icon: Symbols.dns_rounded,
        title: t.settings.watchTogetherRelay,
        subtitle: t.settings.watchTogetherRelayDescription,
        onSelect: _showRelayUrlDialog,
      ),
      _tvToggle(
        key: _SettingsScreenState._kCrashReporting,
        icon: Symbols.monitoring_rounded,
        title: t.settings.crashReporting,
        pref: settings.SettingsService.crashReporting,
      ),
      _tvToggle(
        key: _SettingsScreenState._kDebugLogging,
        icon: Symbols.bug_report_rounded,
        title: t.settings.debugLogging,
        pref: settings.SettingsService.enableDebugLogging,
      ),
      TvMenuItem(
        key: _SettingsScreenState._kViewLogs,
        icon: Symbols.article_rounded,
        title: t.settings.viewLogs,
        subtitle: t.settings.viewLogsDescription,
        onSelect: () => open('logs', (_) => const LogsScreen()),
      ),
    ]),
    SettingsSectionHeader(t.settingsStudio.maintenance),
    rows([
      TvMenuItem(
        key: _SettingsScreenState._kClearCache,
        icon: Symbols.cleaning_services_rounded,
        title: t.settings.clearCache,
        subtitle: t.settings.clearCacheDescription,
        onSelect: _showClearCacheDialog,
      ),
      TvMenuItem(
        key: _SettingsScreenState._kResetSettings,
        icon: Symbols.restore_rounded,
        title: t.settings.resetSettings,
        subtitle: t.settings.resetSettingsDescription,
        onSelect: _showResetSettingsDialog,
      ),
    ]),
    if (_keyboardShortcutsSupported && _keyboardService != null) ...[
      SettingsSectionHeader(t.settings.keyboardShortcuts),
      rows([
        TvMenuItem(
          key: _SettingsScreenState._kVideoPlayerControls,
          icon: Symbols.keyboard_rounded,
          title: t.settings.videoPlayerControls,
          subtitle: t.settings.keyboardShortcutsDescription,
          onSelect: () => open('keyboardShortcuts', (_) => KeyboardShortcutsScreen(keyboardService: _keyboardService!)),
        ),
        _tvToggle(
          key: _SettingsScreenState._kVideoPlayerNavigation,
          icon: Symbols.gamepad_rounded,
          title: t.settings.videoPlayerNavigation,
          pref: settings.SettingsService.videoPlayerNavigationEnabled,
        ),
      ]),
    ],
    if (UpdateService.isUpdateCheckEnabled) ...[
      SettingsSectionHeader(t.settings.updates),
      rows([
        TvMenuItem(
          key: _SettingsScreenState._kCheckForUpdates,
          icon: Symbols.system_update_rounded,
          title: _hasPendingUpdate ? t.settings.updateAvailable : t.settings.checkForUpdates,
          value: _hasPendingUpdate ? t.update.versionAvailable(version: _updateInfo!['latestVersion']) : null,
          onSelect: _isCheckingForUpdate ? null : _handleCheckForUpdatesTap,
        ),
        _tvToggle(
          key: _SettingsScreenState._kAutoCheckUpdatesOnStartup,
          icon: Symbols.notifications_active_rounded,
          title: t.settings.autoCheckUpdatesOnStartup,
          pref: settings.SettingsService.autoCheckUpdatesOnStartup,
        ),
      ]),
    ],
    if (_SettingsScreenState._icloudSyncPlatform) ...[
      SettingsSectionHeader(t.settings.backup),
      rows([
        _tvToggle(
          key: _SettingsScreenState._kIcloudSync,
          icon: Symbols.cloud_sync_rounded,
          title: t.settings.icloudSync,
          pref: settings.SettingsService.icloudSyncEnabled,
          enabled: _icloudAvailable != false,
          subtitle: _icloudAvailable == false ? t.settings.icloudSyncUnavailable : null,
          onAfterWrite: _handleIcloudSyncToggle,
        ),
      ]),
    ],
    SettingsSectionHeader(t.settings.about),
    rows([
      TvMenuItem(
        key: _SettingsScreenState._kAbout,
        icon: Symbols.info_rounded,
        title: t.settings.about,
        subtitle: t.settings.aboutDescription,
        onSelect: () => open('about', (_) => const TvAboutScreen()),
      ),
    ]),
  ];

  /// A-24b focus restore on the TV page: the categories remember whether the
  /// remote last stood on the rail or on a row, and return it there. False
  /// off TV, where every row is mounted and the tracker restores alone.
  bool _restoreTvFocus() {
    final categories = _tvCategories.currentState;
    if (categories == null) return false;
    categories.restoreFocus();
    return true;
  }

  bool get _hasPendingUpdate => _updateInfo != null && _updateInfo!['hasUpdate'] == true;
}
