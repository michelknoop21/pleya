/// The rows of Weergave, shared by the phone list and the TV categories.
///
/// A `part` of `appearance_settings_screen.dart`, split off to keep both files
/// readable (A-24b). The TV order and controls are unchanged; the phone list
/// uses the same builders in the Studio series' order.
part of '../appearance_settings_screen.dart';

extension _AppearanceRows on AppearanceSettingsScreen {
  /// Thema off TV (series `ios/02`): a value row that opens the picker, with
  /// the four modes on the line under it, the one row on the page that keeps
  /// that line in the Studio rows.
  Widget _themeChoice() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final options = [
          DialogOption(value: settings.ThemeMode.system, title: t.settings.systemTheme),
          DialogOption(value: settings.ThemeMode.light, title: t.settings.lightTheme),
          DialogOption(value: settings.ThemeMode.dark, title: t.settings.darkTheme),
          DialogOption(value: settings.ThemeMode.oled, title: t.settings.oledTheme),
        ];
        return settingsIconStyleOverride(
          context,
          hideDescriptions: false,
          child: _choice<settings.ThemeMode>(
            pref: SettingsService.themeMode,
            icon: themeProvider.themeModeIcon,
            title: t.settings.theme,
            options: options,
            description: options.map((o) => o.title).join(' · '),
            onAfterWrite: themeProvider.setThemeMode,
          ),
        );
      },
    );
  }

  /// Dichtheid off TV (anchor `03`: "Dichtheid 3 van 5"): a value row with a
  /// picker of the five steps instead of the slider line under it.
  Widget _densityChoice() => SettingSelectionTile<int, int>(
    pref: SettingsService.libraryDensity,
    icon: Symbols.grid_view_rounded,
    title: t.settings.libraryDensity,
    subtitleBuilder: (v) => t.settingsStudio.densityValue(value: '$v'),
    options: [
      for (var v = 1; v <= 5; v++)
        DialogOption(
          value: v,
          title: switch (v) {
            1 => '1 · ${t.settings.compact}',
            5 => '5 · ${t.settings.comfortable}',
            _ => '$v',
          },
        ),
    ],
    decode: (v) => v,
    encode: (v) => v,
  );

  Widget _viewModeChoice() => _choice<ViewMode>(
    pref: SettingsService.viewMode,
    icon: Symbols.view_list_rounded,
    title: t.settings.viewMode,
    options: [
      DialogOption(value: ViewMode.grid, title: t.settings.gridView),
      DialogOption(value: ViewMode.list, title: t.settings.listView),
    ],
  );

  Widget _episodePosterModeChoice() => _choice<EpisodePosterMode>(
    pref: SettingsService.episodePosterMode,
    icon: Symbols.image_rounded,
    title: t.settings.episodePosterMode,
    options: [
      DialogOption(value: EpisodePosterMode.seriesPoster, title: t.settings.seriesPoster),
      DialogOption(value: EpisodePosterMode.seasonPoster, title: t.settings.seasonPoster),
      DialogOption(value: EpisodePosterMode.episodeThumbnail, title: t.settings.episodeThumbnail),
    ],
  );

  Widget _continueWatchingActionChoice() => _choice<ContinueWatchingAction>(
    pref: SettingsService.continueWatchingAction,
    icon: Symbols.play_circle_rounded,
    title: t.settings.continueWatchingAction,
    options: [
      DialogOption(value: ContinueWatchingAction.play, title: t.settings.continueWatchingPlay),
      DialogOption(value: ContinueWatchingAction.details, title: t.settings.continueWatchingDetails),
    ],
  );

  Widget _episodeActionChoice() => _choice<EpisodeAction>(
    pref: SettingsService.episodeAction,
    icon: Symbols.tv_rounded,
    title: t.settings.episodeAction,
    options: [
      DialogOption(value: EpisodeAction.play, title: t.settings.episodePlay),
      DialogOption(value: EpisodeAction.details, title: t.settings.episodeDetails),
    ],
  );

  Widget _forceTvModeTile(BuildContext context) => SettingSwitchTile(
    pref: SettingsService.forceTvMode,
    icon: Symbols.tv_rounded,
    title: t.settings.forceTvMode,
    subtitle: t.settings.forceTvModeDescription,
    onAfterWrite: (value) {
      TvDetectionService.setForceTVSync(value);
      _restartApp(context);
    },
  );

  /// The side-navigation pair where the app has a side bar, the label switch
  /// where it has a bottom bar.
  List<Widget> _navigationLayoutTiles(BuildContext context) => [
    if (PlatformDetector.shouldUseSideNavigation(context)) ...[
      SettingSwitchTile(
        pref: SettingsService.alwaysKeepSidebarOpen,
        icon: Symbols.dock_to_left_rounded,
        title: t.settings.alwaysKeepSidebarOpen,
        subtitle: t.settings.alwaysKeepSidebarOpenDescription,
      ),
      SettingSwitchTile(
        pref: SettingsService.groupLibrariesByServer,
        icon: Symbols.dns_rounded,
        title: t.settings.groupLibrariesByServer,
        subtitle: t.settings.groupLibrariesByServerDescription,
      ),
    ] else
      SettingSwitchTile(
        pref: SettingsService.showNavBarLabels,
        icon: Symbols.label_rounded,
        title: t.settings.showNavBarLabels,
        subtitle: t.settings.showNavBarLabelsDescription,
      ),
  ];

  List<Widget> _windowTiles() => [
    SettingSwitchTile(
      pref: SettingsService.startInFullscreen,
      icon: Symbols.fullscreen_rounded,
      title: t.settings.startInFullscreen,
      subtitle: t.settings.startInFullscreenDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.exitFullscreenOnPlayerClose,
      icon: Symbols.fullscreen_exit_rounded,
      title: t.settings.exitFullscreenOnPlayerClose,
      subtitle: t.settings.exitFullscreenOnPlayerCloseDescription,
    ),
  ];

  /// Thema on TV: the picker row without the line of modes.
  Widget _themeSelector() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => _choice<settings.ThemeMode>(
        pref: SettingsService.themeMode,
        icon: themeProvider.themeModeIcon,
        title: t.settings.theme,
        options: [
          DialogOption(value: settings.ThemeMode.system, title: t.settings.systemTheme),
          DialogOption(value: settings.ThemeMode.light, title: t.settings.lightTheme),
          DialogOption(value: settings.ThemeMode.dark, title: t.settings.darkTheme),
          DialogOption(value: settings.ThemeMode.oled, title: t.settings.oledTheme),
        ],
        onAfterWrite: themeProvider.setThemeMode,
      ),
    );
  }

  /// Bibliotheek dichtheid on TV: the slider between its two end labels.
  Widget _densitySelector() {
    return SettingValueBuilder<int>(
      pref: SettingsService.libraryDensity,
      builder: (context, density, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const AppIcon(Symbols.grid_view_rounded, fill: 1),
            const SizedBox(width: 16),
            Text(t.settings.libraryDensity),
            const SizedBox(width: 20),
            Text(t.settings.compact, style: _densityLabelStyle(context)),
            Expanded(
              child: FocusableSlider(
                value: density.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => SettingsService.instance.write(SettingsService.libraryDensity, v.round()),
              ),
            ),
            Text(t.settings.comfortable, style: _densityLabelStyle(context)),
          ],
        ),
      ),
    );
  }

  /// VIS-0925-C: the theme's muted ink rather than a fixed grey, and on TV the
  /// HIG minimum (Caption 2) instead of a phone size the wrapper blows up.
  TextStyle _densityLabelStyle(BuildContext context) =>
      TextStyle(fontSize: TvHig.caption2 * TvHig.of(context), color: tokens(context).textMuted);

  /// A value row that opens a picker: the TV rows, and off TV every choice
  /// of the Studio series. [description] is the line under the title off TV.
  Widget _choice<T>({
    required Pref<T> pref,
    required IconData icon,
    required String title,
    required List<DialogOption<T>> options,
    String? description,
    Future<void> Function(T)? onAfterWrite,
  }) => SettingSelectionTile<T, T>(
    pref: pref,
    icon: icon,
    title: title,
    subtitleBuilder: (value) => options.firstWhere((option) => option.value == value).title,
    descriptionBuilder: description == null ? null : (_) => description,
    options: options,
    decode: (value) => value,
    encode: (value) => value,
    onAfterWrite: onAfterWrite,
  );

  // Sections offered as a startup destination, in display order. Live TV is
  // always listed; if no server provides it, startup falls back to Home.
  static const _startupSectionOptions = [
    NavigationTabId.discover,
    NavigationTabId.libraries,
    NavigationTabId.liveTv,
    NavigationTabId.search,
  ];

  String _startupSectionLabel(NavigationTabId id) => allNavigationTabs.firstWhere((t) => t.id == id).getLabel();

  Widget _startupSectionSelector() => SettingSelectionTile<NavigationTabId, NavigationTabId>(
    pref: SettingsService.startupSection,
    icon: Symbols.start_rounded,
    title: t.settings.startupSection,
    subtitleBuilder: _startupSectionLabel,
    options: _startupSectionOptions.map((id) => DialogOption(value: id, title: _startupSectionLabel(id))).toList(),
    decode: (v) => v,
    encode: (v) => v,
  );

  String _visualEffectsLabel(VisualEffectsSetting value) => switch (value) {
    VisualEffectsSetting.auto => t.settings.visualEffectsAuto,
    VisualEffectsSetting.full => t.settings.visualEffectsFull,
    VisualEffectsSetting.reduced => t.settings.visualEffectsReduced,
  };

  Widget _visualEffectsSelector(BuildContext context) =>
      SettingSelectionTile<VisualEffectsSetting, VisualEffectsSetting>(
        pref: SettingsService.visualEffects,
        icon: Symbols.animation_rounded,
        title: t.settings.visualEffects,
        subtitleBuilder: _visualEffectsLabel,
        options: [
          DialogOption(
            value: VisualEffectsSetting.auto,
            title: t.settings.visualEffectsAuto,
            subtitle: t.settings.visualEffectsAutoDescription,
          ),
          DialogOption(value: VisualEffectsSetting.full, title: t.settings.visualEffectsFull),
          DialogOption(
            value: VisualEffectsSetting.reduced,
            title: t.settings.visualEffectsReduced,
            subtitle: t.settings.visualEffectsReducedDescription,
          ),
        ],
        decode: (v) => v,
        encode: (v) => v,
        onAfterWrite: (value) {
          DevicePerformance.setOverrideSync(value);
          _restartApp(context);
        },
      );

  Widget _requireProfileSelection() {
    return Consumer<ActiveProfileProvider>(
      builder: (context, activeProvider, _) {
        if (!activeProvider.hasMultipleProfiles) return const SizedBox.shrink();
        return SettingSwitchTile(
          pref: SettingsService.requireProfileSelectionOnOpen,
          icon: Symbols.person_rounded,
          title: t.settings.requireProfileSelectionOnOpen,
          subtitle: t.settings.requireProfileSelectionOnOpenDescription,
        );
      },
    );
  }

  void _restartApp(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
  }
}
