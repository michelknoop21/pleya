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
import '../../services/device_performance.dart';
import '../../theme/glass/glass_settings.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/settings/settings_live_preview_card.dart';
import 'settings_utils.dart';

part 'parts/appearance_rows.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isTV()) {
      return SettingsPage(title: Text(t.settings.appearance), hideDescriptions: true, children: _phoneRows(context));
    }
    // A-24b: on TV Weergave is a category of Instellingen, its rows in place
    // (`SettingsInlineScope`); the page's own rail is gone with it.
    return SettingsPage(title: Text(t.settings.appearance), children: _tvRows(context));
  }

  /// Weergave off TV in the Studio series' order (`ios/02-weergave-01..03`,
  /// anchors `01`/`03`): the live preview, then Scherm, Home, Navigatie and
  /// Inhoud en venster. Every row the page had stays, under the same
  /// conditions; the four with two to four short options open a picker from
  /// a value row, as the series draws them. Dichtheid follows Raster of lijst as
  /// anchor `03` places it; App-taal has no slot in the series and closes
  /// Scherm.
  List<Widget> _phoneRows(BuildContext context) => [
    const SettingsLivePreviewCard(),
    SettingsSectionHeader(t.settings.display),
    _themeChoice(),
    if (glassAppliesTo(context))
      SettingSwitchTile(
        pref: SettingsService.liquidGlass,
        icon: Symbols.blur_on_rounded,
        title: t.settings.liquidGlass,
        subtitle: t.settings.liquidGlassDescription,
      ),
    if (Platform.isAndroid) _visualEffectsSelector(context),
    _viewModeChoice(),
    // Anchor 03 puts Dichtheid right after Raster of lijst.
    _densityChoice(),
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

  /// Weergave on TV in the series' order (`tvos/02-weergave-01..05`, anchors
  /// `02`/`04`): Scherm, Home, Navigatie and Inhoud. Every row the TV page had
  /// stays under its own condition; Dichtheid is the value row of anchor `04`
  /// ("3 van 5") instead of the slider. App-taal lives in Taal en ondertitels.
  List<Widget> _tvRows(BuildContext context) => [
    SettingsSectionHeader(t.settings.display),
    _themeSelector(),
    if (Platform.isAndroid) _visualEffectsSelector(context),
    if (glassAppliesTo(context))
      SettingSwitchTile(
        pref: SettingsService.liquidGlass,
        icon: Symbols.blur_on_rounded,
        title: t.settings.liquidGlass,
        subtitle: t.settings.liquidGlassDescription,
      ),
    _viewModeChoice(),
    _densityChoice(),
    _episodePosterModeChoice(),
    SettingSwitchTile(
      pref: SettingsService.tvFullCardLayout,
      icon: Symbols.image_rounded,
      title: t.settings.tvFullCardLayout,
      subtitle: t.settings.tvFullCardLayoutDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.focusGlow,
      icon: Symbols.lightbulb_rounded,
      title: t.settings.focusGlow,
      subtitle: t.settings.focusGlowDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.tvReduceMotion,
      icon: Symbols.motion_photos_off_rounded,
      title: t.settings.tvReduceMotion,
      subtitle: t.settings.tvReduceMotionDescription,
      // App-wide: `reduceMotion()` (lib/theme/mono_tokens.dart) has a dozen
      // call sites across every screen, so a restart is what guarantees every
      // one of them picks it up, the same reason `visualEffects` restarts too.
      onAfterWrite: (value) => _restartApp(context),
    ),
    SettingSwitchTile(
      pref: SettingsService.tvShowTitlesUnderPosters,
      icon: Symbols.title_rounded,
      title: t.settings.tvShowTitlesUnderPosters,
      subtitle: t.settings.tvShowTitlesUnderPostersDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.showEpisodeNumberOnCards,
      icon: Symbols.tag_rounded,
      title: t.settings.showEpisodeNumberOnCards,
      subtitle: t.settings.showEpisodeNumberOnCardsDescription,
    ),

    SettingsSectionHeader(t.settings.homeScreen),
    SettingSwitchTile(
      pref: SettingsService.tvHeroClearLogo,
      icon: Symbols.branding_watermark_rounded,
      title: t.settings.tvHeroClearLogo,
      subtitle: t.settings.tvHeroClearLogoDescription,
    ),
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
    _continueWatchingActionChoice(),
    SettingSwitchTile(
      pref: SettingsService.showServerNameOnHubs,
      icon: Symbols.dns_rounded,
      title: t.settings.showServerNameOnHubs,
      subtitle: t.settings.showServerNameOnHubsDescription,
    ),
    SettingSwitchTile(
      pref: SettingsService.useGlobalHubs,
      icon: Symbols.home_rounded,
      title: t.settings.useGlobalHubs,
      subtitle: t.settings.useGlobalHubsDescription,
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

    SettingsSectionHeader(t.settings.content),
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
  ];
}
