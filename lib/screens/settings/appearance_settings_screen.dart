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
import '../../widgets/settings/settings_live_preview_card.dart';
import 'parts/app_language_row.dart';
import 'settings_utils.dart';

part 'parts/appearance_rows.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isTV()) {
      return SettingsPage(title: Text(t.settings.appearance), hideDescriptions: true, children: _phoneRows(context));
    }
    return TvAppearanceCategories(title: t.settings.appearance, children: _tvRows(context));
  }

  /// Weergave off TV in the Studio series' order (`ios/02-weergave-01..03`,
  /// anchors `01`/`03`): the live preview, then Scherm, Home, Navigatie and
  /// Inhoud en venster. Every row the page had stays, under the same
  /// conditions; the four with two to four short options open a picker from
  /// a value row, as the series draws them. App-taal and Dichtheid are not on
  /// the series and sit in Scherm (anchor `03` shows Dichtheid there).
  List<Widget> _phoneRows(BuildContext context) => [
    const SettingsLivePreviewCard(),
    SettingsSectionHeader(t.settings.display),
    _themeChoice(),
    AppLanguageRow(onRestart: () => _restartApp(context)),
    _densityChoice(),
    if (glassAppliesTo(context))
      SettingSwitchTile(
        pref: SettingsService.liquidGlass,
        icon: Symbols.blur_on_rounded,
        title: t.settings.liquidGlass,
        subtitle: t.settings.liquidGlassDescription,
      ),
    if (Platform.isAndroid) _visualEffectsSelector(context),
    _viewModeChoice(),
    _episodePosterModeChoice(),
    SettingSwitchTile(
      pref: SettingsService.showEpisodeNumberOnCards,
      icon: Symbols.tag_rounded,
      title: t.settings.showEpisodeNumberOnCards,
      subtitle: t.settings.showEpisodeNumberOnCardsDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.showSeasonPostersOnTabs,
      icon: Symbols.image_rounded,
      title: t.settings.showSeasonPostersOnTabs,
      subtitle: t.settings.showSeasonPostersOnTabsDescription,
    ),

    SettingsSectionHeader(t.settings.homeScreen),
    SettingSwitchTile(
      pref: SettingsService.showHeroSection,
      icon: Symbols.featured_play_list_rounded,
      title: t.settings.showHeroSection,
      subtitle: t.settings.showHeroSectionDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.personalizedRecommendations,
      icon: Symbols.recommend_rounded,
      title: t.settings.personalizedRecommendations,
      subtitle: t.settings.personalizedRecommendationsDescription,
    ),
    if (PlatformDetector.isDesktop(context))
      SettingSwitchTile(
        pref: SettingsService.hoverExpandCards,
        icon: Symbols.pageview_rounded,
        title: t.settings.hoverExpandCards,
        subtitle: t.settings.hoverExpandCardsDescription,
      ),
    _continueWatchingActionChoice(),
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
    if (Platform.isAndroid) _forceTvModeTile(context),
    _requireProfileSelection(),
    ..._navigationLayoutTiles(context),
    SettingSwitchTile(
      pref: SettingsService.showUnwatchedCount,
      icon: Symbols.counter_1_rounded,
      title: t.settings.showUnwatchedCount,
      subtitle: t.settings.showUnwatchedCountDescription,
    ),

    SettingsSectionHeader(t.settingsStudio.contentAndWindow),
    SettingSwitchTile(
      pref: SettingsService.hideSpoilers,
      icon: Symbols.visibility_off_rounded,
      title: t.settings.hideSpoilers,
      subtitle: t.settings.hideSpoilersDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.liveTvDefaultFavorites,
      icon: Symbols.star_rounded,
      title: t.settings.liveTvDefaultFavorites,
      subtitle: t.settings.liveTvDefaultFavoritesDescription,
    ),
    _episodeActionChoice(),
    SettingSwitchTile(
      pref: SettingsService.autoHidePerformanceOverlay,
      icon: Symbols.speed_rounded,
      title: t.settings.autoHidePerformanceOverlay,
      subtitle: t.settings.autoHidePerformanceOverlayDescription,
    ),
    if (PlatformDetector.isDesktopOS()) ..._windowTiles(),
  ];

  /// Weergave on TV: unchanged by A-24b phase 2 (the TV page is phase 3).
  List<Widget> _tvRows(BuildContext context) {
    final children = <Widget>[
      SettingsSectionHeader(t.settings.display),
      _themeSelector(),
      AppLanguageRow(onRestart: () => _restartApp(context)),
      _densitySelector(),
      _viewModeChoice(),
      _episodePosterModeChoice(),
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
      _continueWatchingActionChoice(),
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
      if (Platform.isAndroid) _forceTvModeTile(context),
      ..._navigationLayoutTiles(context),
      SettingSwitchTile(
        pref: SettingsService.showUnwatchedCount,
        icon: Symbols.counter_1_rounded,
        title: t.settings.showUnwatchedCount,
        subtitle: t.settings.showUnwatchedCountDescription,
      ),

      if (PlatformDetector.isDesktopOS()) ...[SettingsSectionHeader(t.settings.window), ..._windowTiles()],

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
      _episodeActionChoice(),
      _requireProfileSelection(),
      SettingSwitchTile(
        pref: SettingsService.autoHidePerformanceOverlay,
        icon: Symbols.speed_rounded,
        title: t.settings.autoHidePerformanceOverlay,
        subtitle: t.settings.autoHidePerformanceOverlayDescription,
      ),
    ];
    return children;
  }
}
