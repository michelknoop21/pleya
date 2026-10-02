import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/theme_provider.dart';
import '../../profiles/active_profile_provider.dart';
import '../../navigation/navigation_tabs.dart';
import '../../services/settings_service.dart' hide ThemeMode;
import '../../services/settings_service.dart' as settings show ThemeMode;
import '../../focus/focusable_slider.dart';
import '../../services/device_performance.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import '../../utils/tv_hig.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/tv/tv_appearance_categories.dart';
import 'parts/app_language_row.dart';
import 'settings_utils.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      SettingsSectionHeader(t.settings.display),
      _themeSelector(),
      AppLanguageRow(onRestart: () => _restartApp(context)),
      _densitySelector(),
      _viewModeSelector(),
      _episodePosterModeSelector(),
      if (glassAppliesTo(context))
        SettingSwitchTile(
          pref: SettingsService.liquidGlass,
          icon: Symbols.blur_on_rounded,
          title: t.settings.liquidGlass,
          subtitle: t.settings.liquidGlassDescription,
        ),
      if (PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.tvFullCardLayout,
          icon: Symbols.image_rounded,
          title: t.settings.tvFullCardLayout,
          subtitle: t.settings.tvFullCardLayoutDescription,
        ),
      if (PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.focusGlow,
          icon: Symbols.lightbulb_rounded,
          title: t.settings.focusGlow,
          subtitle: t.settings.focusGlowDescription,
        ),
      if (PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.tvShowTitlesUnderPosters,
          icon: Symbols.title_rounded,
          title: t.settings.tvShowTitlesUnderPosters,
          subtitle: t.settings.tvShowTitlesUnderPostersDescription,
        ),
      if (PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.tvReduceMotion,
          icon: Symbols.motion_photos_off_rounded,
          title: t.settings.tvReduceMotion,
          subtitle: t.settings.tvReduceMotionDescription,
          // App-wide: `reduceMotion()` (lib/theme/mono_tokens.dart) has a
          // dozen call sites across every screen, not just this one, so a
          // restart is what guarantees every one of them picks it up,
          // the same reason `visualEffects` below restarts too.
          onAfterWrite: (value) => _restartApp(context),
        ),
      if (Platform.isAndroid) _visualEffectsSelector(context),
      SettingSwitchTile(
        pref: SettingsService.showEpisodeNumberOnCards,
        icon: Symbols.tag_rounded,
        title: t.settings.showEpisodeNumberOnCards,
        subtitle: t.settings.showEpisodeNumberOnCardsDescription,
      ),
      if (!PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.showSeasonPostersOnTabs,
          icon: Symbols.image_rounded,
          title: t.settings.showSeasonPostersOnTabs,
          subtitle: t.settings.showSeasonPostersOnTabsDescription,
        ),

      SettingsSectionHeader(t.settings.homeScreen),
      if (!PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.showHeroSection,
          icon: Symbols.featured_play_list_rounded,
          title: t.settings.showHeroSection,
          subtitle: t.settings.showHeroSectionDescription,
        ),
      if (PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.tvHeroClearLogo,
          icon: Symbols.branding_watermark_rounded,
          title: t.settings.tvHeroClearLogo,
          subtitle: t.settings.tvHeroClearLogoDescription,
        ),
      if (PlatformDetector.isTV())
        SettingSwitchTile(
          pref: SettingsService.tvHeroAutoAdvance,
          icon: Symbols.slideshow_rounded,
          title: t.settings.tvHeroAutoAdvance,
          subtitle: t.settings.tvHeroAutoAdvanceDescription,
        ),
      SettingSwitchTile(
        pref: SettingsService.personalizedRecommendations,
        icon: Symbols.recommend_rounded,
        title: t.settings.personalizedRecommendations,
        subtitle: t.settings.personalizedRecommendationsDescription,
      ),
      if (!PlatformDetector.isTV() && PlatformDetector.isDesktop(context))
        SettingSwitchTile(
          pref: SettingsService.hoverExpandCards,
          icon: Symbols.pageview_rounded,
          title: t.settings.hoverExpandCards,
          subtitle: t.settings.hoverExpandCardsDescription,
        ),
      _continueWatchingActionSelector(),
      SettingSwitchTile(
        pref: SettingsService.useGlobalHubs,
        icon: Symbols.home_rounded,
        title: t.settings.useGlobalHubs,
        subtitle: t.settings.useGlobalHubsDescription,
      ),
      SettingSwitchTile(
        pref: SettingsService.showServerNameOnHubs,
        icon: Symbols.dns_rounded,
        title: t.settings.showServerNameOnHubs,
        subtitle: t.settings.showServerNameOnHubsDescription,
      ),

      SettingsSectionHeader(t.settings.navigation),
      _startupSectionSelector(),
      if (Platform.isAndroid)
        SettingSwitchTile(
          pref: SettingsService.forceTvMode,
          icon: Symbols.tv_rounded,
          title: t.settings.forceTvMode,
          subtitle: t.settings.forceTvModeDescription,
          onAfterWrite: (value) {
            TvDetectionService.setForceTVSync(value);
            _restartApp(context);
          },
        ),
      if (PlatformDetector.shouldUseSideNavigation(context))
        SettingSwitchTile(
          pref: SettingsService.alwaysKeepSidebarOpen,
          icon: Symbols.dock_to_left_rounded,
          title: t.settings.alwaysKeepSidebarOpen,
          subtitle: t.settings.alwaysKeepSidebarOpenDescription,
        ),
      if (PlatformDetector.shouldUseSideNavigation(context))
        SettingSwitchTile(
          pref: SettingsService.groupLibrariesByServer,
          icon: Symbols.dns_rounded,
          title: t.settings.groupLibrariesByServer,
          subtitle: t.settings.groupLibrariesByServerDescription,
        ),
      if (!PlatformDetector.shouldUseSideNavigation(context))
        SettingSwitchTile(
          pref: SettingsService.showNavBarLabels,
          icon: Symbols.label_rounded,
          title: t.settings.showNavBarLabels,
          subtitle: t.settings.showNavBarLabelsDescription,
        ),
      SettingSwitchTile(
        pref: SettingsService.showUnwatchedCount,
        icon: Symbols.counter_1_rounded,
        title: t.settings.showUnwatchedCount,
        subtitle: t.settings.showUnwatchedCountDescription,
      ),

      if (PlatformDetector.isDesktopOS()) ...[
        SettingsSectionHeader(t.settings.window),
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
      ],

      SettingsSectionHeader(t.settings.content),
      SettingSwitchTile(
        pref: SettingsService.liveTvDefaultFavorites,
        icon: Symbols.star_rounded,
        title: t.settings.liveTvDefaultFavorites,
        subtitle: t.settings.liveTvDefaultFavoritesDescription,
      ),
      SettingSwitchTile(
        pref: SettingsService.hideSpoilers,
        icon: Symbols.visibility_off_rounded,
        title: t.settings.hideSpoilers,
        subtitle: t.settings.hideSpoilersDescription,
      ),
      _episodeActionSelector(),
      _requireProfileSelection(),
      SettingSwitchTile(
        pref: SettingsService.autoHidePerformanceOverlay,
        icon: Symbols.speed_rounded,
        title: t.settings.autoHidePerformanceOverlay,
        subtitle: t.settings.autoHidePerformanceOverlayDescription,
      ),
    ];
    if (PlatformDetector.isTV()) {
      return TvAppearanceCategories(title: t.settings.appearance, children: children);
    }
    return SettingsPage(title: Text(t.settings.appearance), children: children);
  }

  Widget _themeSelector() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        if (PlatformDetector.isTV()) {
          return _tvChoice<settings.ThemeMode>(
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
          );
        }
        return SegmentedSetting<settings.ThemeMode>(
          icon: themeProvider.themeModeIcon,
          title: t.settings.theme,
          segments: [
            ButtonSegment(value: settings.ThemeMode.system, label: Text(t.settings.systemTheme)),
            ButtonSegment(value: settings.ThemeMode.light, label: Text(t.settings.lightTheme)),
            ButtonSegment(value: settings.ThemeMode.dark, label: Text(t.settings.darkTheme)),
            ButtonSegment(value: settings.ThemeMode.oled, label: Text(t.settings.oledTheme)),
          ],
          selected: themeProvider.themeMode,
          onChanged: themeProvider.setThemeMode,
        );
      },
    );
  }

  Widget _densitySelector() {
    return SettingValueBuilder<int>(
      pref: SettingsService.libraryDensity,
      builder: (context, density, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const AppIcon(Symbols.grid_view_rounded, fill: 1),
            const SizedBox(width: 16),
            if (PlatformDetector.isTV()) ...[Text(t.settings.libraryDensity), const SizedBox(width: 20)],
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
  TextStyle _densityLabelStyle(BuildContext context) => TextStyle(
    fontSize: PlatformDetector.isTV() ? TvHig.caption2 * TvHig.of(context) : 12,
    color: tokens(context).textMuted,
  );

  Widget _viewModeSelector() => PlatformDetector.isTV()
      ? _tvChoice<ViewMode>(
          pref: SettingsService.viewMode,
          icon: Symbols.view_list_rounded,
          title: t.settings.viewMode,
          options: [
            DialogOption(value: ViewMode.grid, title: t.settings.gridView),
            DialogOption(value: ViewMode.list, title: t.settings.listView),
          ],
        )
      : SettingSegmentedTile<ViewMode, ViewMode>(
          pref: SettingsService.viewMode,
          icon: Symbols.view_list_rounded,
          title: t.settings.viewMode,
          segments: [
            ButtonSegment(value: ViewMode.grid, label: Text(t.settings.gridView)),
            ButtonSegment(value: ViewMode.list, label: Text(t.settings.listView)),
          ],
          decode: (v) => v,
          encode: (v) => v,
        );

  Widget _episodePosterModeSelector() => PlatformDetector.isTV()
      ? _tvChoice<EpisodePosterMode>(
          pref: SettingsService.episodePosterMode,
          icon: Symbols.image_rounded,
          title: t.settings.episodePosterMode,
          options: [
            DialogOption(value: EpisodePosterMode.seriesPoster, title: t.settings.seriesPoster),
            DialogOption(value: EpisodePosterMode.seasonPoster, title: t.settings.seasonPoster),
            DialogOption(value: EpisodePosterMode.episodeThumbnail, title: t.settings.episodeThumbnail),
          ],
        )
      : SettingSegmentedTile<EpisodePosterMode, EpisodePosterMode>(
          pref: SettingsService.episodePosterMode,
          icon: Symbols.image_rounded,
          title: t.settings.episodePosterMode,
          segments: [
            ButtonSegment(value: EpisodePosterMode.seriesPoster, label: Text(t.settings.seriesPoster)),
            ButtonSegment(value: EpisodePosterMode.seasonPoster, label: Text(t.settings.seasonPoster)),
            ButtonSegment(value: EpisodePosterMode.episodeThumbnail, label: Text(t.settings.episodeThumbnail)),
          ],
          decode: (v) => v,
          encode: (v) => v,
        );

  Widget _continueWatchingActionSelector() => PlatformDetector.isTV()
      ? _tvChoice<ContinueWatchingAction>(
          pref: SettingsService.continueWatchingAction,
          icon: Symbols.play_circle_rounded,
          title: t.settings.continueWatchingAction,
          options: [
            DialogOption(value: ContinueWatchingAction.play, title: t.settings.continueWatchingPlay),
            DialogOption(value: ContinueWatchingAction.details, title: t.settings.continueWatchingDetails),
          ],
        )
      : SettingSegmentedTile<ContinueWatchingAction, ContinueWatchingAction>(
          pref: SettingsService.continueWatchingAction,
          icon: Symbols.play_circle_rounded,
          title: t.settings.continueWatchingAction,
          segments: [
            ButtonSegment(value: ContinueWatchingAction.play, label: Text(t.settings.continueWatchingPlay)),
            ButtonSegment(value: ContinueWatchingAction.details, label: Text(t.settings.continueWatchingDetails)),
          ],
          decode: (v) => v,
          encode: (v) => v,
        );

  Widget _episodeActionSelector() => PlatformDetector.isTV()
      ? _tvChoice<EpisodeAction>(
          pref: SettingsService.episodeAction,
          icon: Symbols.tv_rounded,
          title: t.settings.episodeAction,
          options: [
            DialogOption(value: EpisodeAction.play, title: t.settings.episodePlay),
            DialogOption(value: EpisodeAction.details, title: t.settings.episodeDetails),
          ],
        )
      : SettingSegmentedTile<EpisodeAction, EpisodeAction>(
          pref: SettingsService.episodeAction,
          icon: Symbols.tv_rounded,
          title: t.settings.episodeAction,
          segments: [
            ButtonSegment(value: EpisodeAction.play, label: Text(t.settings.episodePlay)),
            ButtonSegment(value: EpisodeAction.details, label: Text(t.settings.episodeDetails)),
          ],
          decode: (v) => v,
          encode: (v) => v,
        );

  Widget _tvChoice<T>({
    required Pref<T> pref,
    required IconData icon,
    required String title,
    required List<DialogOption<T>> options,
    Future<void> Function(T)? onAfterWrite,
  }) => SettingSelectionTile<T, T>(
    pref: pref,
    icon: icon,
    title: title,
    subtitleBuilder: (value) => options.firstWhere((option) => option.value == value).title,
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
