/// Mijn Pleya ▸ Instellingen on TV, per the approved `settings-a` layout.
///
/// A `part` rather than a widget of its own because this is the same screen:
/// every destination, dialog and preference write below is the method the
/// mobile row already calls. Copying them into a second screen would give the
/// product two definitions of "reset settings", and one of those is
/// destructive.
///
/// What the audit of 2 September 2026 measured here was three content edges on
/// one page — a heading at 1.67%, a group label at 9.64%, a card at 9.14% that
/// stopped at 81.69% of the screen because `kSettingsMaxWidth` caps a desktop
/// column at 880 logical pixels — with unscaled 36px badges, 20px glyphs, a
/// 3px bar marking the focused row, and 5.3 rows visible with the sixth cut in
/// half by the pinned app bar.
///
/// This is an index of settings sections, which is functionally the same thing
/// as the Mijn Pleya hub, so it gets the hub's tile language instead of a
/// second idiom. Two columns rather than four: a settings row carries its
/// current value as well as its title, and four of those on one line is
/// unreadable at ten feet.
///
/// **Same rows, same order, same conditions.** The platform gates are the ones
/// the mobile list already applies, read from the same expressions, so a tile
/// cannot appear on TV that the phone hides — Downloads is still absent on an
/// Apple TV, Backup still narrows to the one iCloud toggle, Tautulli still
/// only exists for someone who owns a Plex server here.
///
/// **Connections is the one deliberate difference.** The mobile page mounts
/// [ConnectionsSection], which lists every server. On TV that list is a whole
/// section of its own at Mijn Pleya ▸ Servers, and putting it here as well
/// would be the third place in the product answering "which servers do I
/// have". So this group keeps the two actions and leaves the inventory where
/// it lives.
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
    final trakt = context.watch<TraktAccountProvider>();
    final trackers = context.watch<TrackersProvider>();
    final seerr = context.watch<SeerrProvider>();
    final tautulli = context.watch<TautulliProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final ownsAPlexServer = context.select<MultiServerProvider, bool>(_SettingsScreenState._ownsAPlexServer);

    final connectedTrackers = <String>[
      if (trakt.isConnected) t.trakt.title,
      if (trackers.isMalConnected) t.trackers.services.mal,
      if (trackers.isAnilistConnected) t.trackers.services.anilist,
      if (trackers.isSimklConnected) t.trackers.services.simkl,
    ];

    // PB-1: a settings subpage keeps the top bar. `SettingsScreen` is itself a
    // nested route already (`tvMyPleyaNestedRoute`), so pushing its own
    // subpages on the profile navigator meant the child escaped a shell the
    // parent had stayed inside — the bar was on screen right up until you
    // opened Uiterlijk. Falls back to the ordinary push when no TV shell is
    // listening, which is every other platform and every test that mounts this
    // page on its own.
    void open(String id, WidgetBuilder builder) {
      if (openTvContentRoute(id: 'tvSettings_$id', builder: builder) != null) return;
      Navigator.push(context, MaterialPageRoute<void>(builder: builder));
    }

    // Rebuilds when any preference a tile shows the state of changes. Without
    // this the tile would keep drawing the value it was built with, because
    // nothing here listens the way `SettingSwitchTile` does per row.
    return SettingsBuilder(
      prefs: [
        settings.SettingsService.libraryDensity,
        settings.SettingsService.crashReporting,
        settings.SettingsService.enableDebugLogging,
        settings.SettingsService.downloadOnWifiOnly,
        settings.SettingsService.autoRemoveWatchedDownloads,
        settings.SettingsService.videoPlayerNavigationEnabled,
        settings.SettingsService.autoCheckUpdatesOnStartup,
        settings.SettingsService.icloudSyncEnabled,
      ],
      builder: (context) => TvPageSurface(
        title: t.settings.title,
        automationInstance: 'settings',
        children: [
          TvMenuGrid(
            nodes: _focusTracker,
            columns: 2,
            automationInstance: 'settings',
            sections: [
              if (DonationService.isEnabled)
                TvMenuSection(
                  items: [
                    TvMenuItem(
                      key: _SettingsScreenState._kDonate,
                      icon: Symbols.favorite_rounded,
                      title: t.settings.supportDeveloper,
                      subtitle: t.settings.supportDeveloperDescription,
                      onSelect: _handleDonateTap,
                    ),
                  ],
                ),
              TvMenuSection(
                label: t.settings.sectionLibrary,
                items: [
                  TvMenuItem(
                    key: _SettingsScreenState._kAppearance,
                    icon: Symbols.palette_rounded,
                    title: t.settings.appearance,
                    value:
                        '${themeProvider.themeModeDisplayName} · '
                        '${t.settings.libraryDensity} ${_settingsService.read(settings.SettingsService.libraryDensity)}',
                    onSelect: () => open('appearance', (_) => const AppearanceSettingsScreen()),
                  ),
                  TvMenuItem(
                    key: _SettingsScreenState._kLibraryVisibility,
                    icon: Symbols.video_library_rounded,
                    title: t.settings.libraryVisibility,
                    subtitle: t.settings.libraryVisibilityDescription,
                    onSelect: () => open('libraryVisibility', (_) => const LibraryVisibilityScreen()),
                  ),
                  TvMenuItem(
                    key: _SettingsScreenState._kHomeLayout,
                    icon: Symbols.dashboard_customize_rounded,
                    title: t.settings.homeLayout,
                    subtitle: t.settings.homeLayoutDescription,
                    onSelect: () => open('homeLayout', (_) => const HomeLayoutScreen()),
                  ),
                  TvMenuItem(
                    key: _SettingsScreenState._kPlayback,
                    icon: Symbols.play_circle_rounded,
                    title: t.settings.videoPlayback,
                    subtitle: t.settings.videoPlaybackDescription,
                    onSelect: () => open('playback', (_) => const PlaybackSettingsScreen()),
                  ),
                  TvMenuItem(
                    key: _SettingsScreenState._kTrackers,
                    icon: Symbols.sync_alt_rounded,
                    title: t.settings.trackers,
                    value: connectedTrackers.isEmpty ? null : connectedTrackers.join(' · '),
                    subtitle: connectedTrackers.isEmpty ? t.settings.trackersDescription : null,
                    onSelect: () => open('trackers', (_) => const TrackersSettingsScreen()),
                  ),
                  TvMenuItem(
                    key: _SettingsScreenState._kRequests,
                    icon: Symbols.playlist_add_rounded,
                    title: t.settings.requests,
                    value: seerr.isConfigured ? (seerr.host ?? t.settings.requests) : null,
                    subtitle: seerr.isConfigured ? null : t.settings.requestsDescription,
                    onSelect: () => open('requests', (_) => const SeerrSettingsScreen()),
                  ),
                  if (ownsAPlexServer)
                    TvMenuItem(
                      key: _SettingsScreenState._kTautulli,
                      icon: Symbols.insights_rounded,
                      title: t.tautulli.title,
                      value: tautulli.isConfigured
                          ? (tautulli.serverName ?? tautulli.host ?? t.tautulli.connected)
                          : null,
                      subtitle: tautulli.isConfigured ? null : t.tautulli.subtitle,
                      onSelect: () => open('tautulli', (_) => const TautulliSettingsScreen()),
                    ),
                ],
              ),
              TvMenuSection(
                label: t.connections.sectionTitle,
                items: [
                  TvMenuItem(
                    key: 'settings_add_connection',
                    icon: Symbols.add_link_rounded,
                    title: t.connections.addConnection,
                    subtitle: context.read<ActiveProfileProvider>().active == null
                        ? t.connections.addConnectionSubtitleNoProfile
                        : t.connections.addConnectionSubtitleScoped(
                            displayName: context.read<ActiveProfileProvider>().active!.displayName,
                          ),
                    onSelect: () => open(
                      'addConnection',
                      (_) => AddConnectionScreen(targetProfile: context.read<ActiveProfileProvider>().active),
                    ),
                  ),
                  TvMenuItem(
                    key: 'settings_pleya_share',
                    icon: Symbols.share_rounded,
                    title: t.pleyaShare.hostTitle,
                    subtitle: t.pleyaShare.hostToggle,
                    onSelect: () => open('pleyaShareHost', (_) => const PleyaShareHostScreen()),
                  ),
                  TvMenuItem(
                    key: 'settings_profiles',
                    icon: Symbols.group_rounded,
                    title: t.profiles.sectionTitle,
                    subtitle: t.profiles.summarySingle,
                    onSelect: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(MaterialPageRoute<void>(builder: (_) => const ProfileSwitchScreen())),
                  ),
                ],
              ),
              if (!PlatformDetector.isAppleTV())
                TvMenuSection(
                  label: t.settings.downloads,
                  items: [
                    if (!Platform.isIOS)
                      TvMenuItem(
                        key: _SettingsScreenState._kDownloadLocation,
                        icon: Symbols.folder_rounded,
                        title: DownloadStorageService.instance.isUsingCustomPath()
                            ? t.settings.downloadLocationCustom
                            : t.settings.downloadLocationDefault,
                        subtitle: t.settings.downloads,
                        onSelect: _showDownloadLocationDialog,
                      ),
                    _tvToggle(
                      key: _SettingsScreenState._kDownloadOnWifiOnly,
                      icon: Symbols.wifi_rounded,
                      title: t.settings.downloadOnWifiOnly,
                      pref: settings.SettingsService.downloadOnWifiOnly,
                    ),
                    _tvToggle(
                      key: _SettingsScreenState._kAutoRemoveWatchedDownloads,
                      icon: Symbols.delete_sweep_rounded,
                      title: t.settings.autoRemoveWatchedDownloads,
                      pref: settings.SettingsService.autoRemoveWatchedDownloads,
                    ),
                  ],
                ),
              if (_keyboardShortcutsSupported && _keyboardService != null)
                TvMenuSection(
                  label: t.settings.keyboardShortcuts,
                  items: [
                    TvMenuItem(
                      key: _SettingsScreenState._kVideoPlayerControls,
                      icon: Symbols.keyboard_rounded,
                      title: t.settings.videoPlayerControls,
                      subtitle: t.settings.keyboardShortcutsDescription,
                      onSelect: () =>
                          open('keyboardShortcuts', (_) => KeyboardShortcutsScreen(keyboardService: _keyboardService!)),
                    ),
                    _tvToggle(
                      key: _SettingsScreenState._kVideoPlayerNavigation,
                      icon: Symbols.gamepad_rounded,
                      title: t.settings.videoPlayerNavigation,
                      pref: settings.SettingsService.videoPlayerNavigationEnabled,
                    ),
                  ],
                ),
              TvMenuSection(
                label: t.settings.advanced,
                items: [
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
                ],
              ),
              if (UpdateService.isUpdateCheckEnabled)
                TvMenuSection(
                  label: t.settings.updates,
                  items: [
                    TvMenuItem(
                      key: _SettingsScreenState._kCheckForUpdates,
                      icon: Symbols.system_update_rounded,
                      title: _hasPendingUpdate ? t.settings.updateAvailable : t.settings.checkForUpdates,
                      value: _hasPendingUpdate
                          ? t.update.versionAvailable(version: _updateInfo!['latestVersion'])
                          : null,
                      onSelect: _isCheckingForUpdate ? null : _handleCheckForUpdatesTap,
                    ),
                    _tvToggle(
                      key: _SettingsScreenState._kAutoCheckUpdatesOnStartup,
                      icon: Symbols.notifications_active_rounded,
                      title: t.settings.autoCheckUpdatesOnStartup,
                      pref: settings.SettingsService.autoCheckUpdatesOnStartup,
                    ),
                  ],
                ),
              // Export and import hand a file to a file picker, which a TV has
              // no sensible surface for, so on TV this group is the iCloud
              // toggle or it is nothing — the same rule `_buildBackupSection`
              // applies.
              if (_SettingsScreenState._icloudSyncPlatform)
                TvMenuSection(
                  label: t.settings.backup,
                  items: [
                    _tvToggle(
                      key: _SettingsScreenState._kIcloudSync,
                      icon: Symbols.cloud_sync_rounded,
                      title: t.settings.icloudSync,
                      pref: settings.SettingsService.icloudSyncEnabled,
                      enabled: _icloudAvailable != false,
                      subtitle: _icloudAvailable == false ? t.settings.icloudSyncUnavailable : null,
                      onAfterWrite: _handleIcloudSyncToggle,
                    ),
                  ],
                ),
              TvMenuSection(
                items: [
                  TvMenuItem(
                    key: _SettingsScreenState._kAbout,
                    icon: Symbols.info_rounded,
                    title: t.settings.about,
                    subtitle: t.settings.aboutDescription,
                    onSelect: () => open('about', (_) => const TvAboutScreen()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasPendingUpdate => _updateInfo != null && _updateInfo!['hasUpdate'] == true;
}
