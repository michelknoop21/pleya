import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../focus/focusable_text_field.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../main_screen.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../mixins/refreshable.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../services/donation_service.dart';
import '../../services/icloud_sync_service.dart';
import 'icloud_sync_status_line.dart';
import '../../services/preferences/preference_sync_coordinator.dart';
import '../../services/settings_export_service.dart';
import '../../providers/theme_provider.dart';
import '../../services/keyboard_shortcuts_service.dart';
import '../../services/settings_service.dart' as settings;
import '../../services/update_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/platform_detector.dart';
import '../../utils/update_dialog.dart';
import '../../utils/quality_preset_labels.dart';
import '../../utils/tv_hig.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings/settings_studio_header.dart';
import '../../widgets/settings_section.dart';
import '../../media/media_server_client.dart' show HouseholdActivityClient;
import '../../providers/multi_server_provider.dart';
import '../../profiles/active_profile_provider.dart';
import 'about_screen.dart';
import 'add_connection_screen.dart';
import 'pleya_share_host_screen.dart';
import 'appearance_settings_screen.dart';
import 'assistant_settings_screen.dart';
import 'downloads_settings_screen.dart';
import 'integrations_settings_screen.dart';
import 'library_home_rows.dart';
import 'library_home_settings_screen.dart';
import 'connections_section.dart';
import 'local_library_settings_screen.dart';
import 'keyboard_shortcuts_screen.dart';
import 'home_layout_screen.dart';
import 'library_visibility_screen.dart';
import 'logs_screen.dart';
import 'language_settings_screen.dart';
import 'playback_settings_screen.dart';
import '../profile/profile_switch_screen.dart';
import '../servers_screen.dart';
import 'seerr_settings_screen.dart';
import 'subtitle_styling_screen.dart';
import 'activity_sharing_controller.dart';
import 'tautulli_settings_screen.dart';
import 'trackers_settings_screen.dart';
import '../../providers/trakt_account_provider.dart';
import '../../services/trakt/trakt_comments_client.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_settings_categories.dart';
import '../../widgets/tv/tv_settings_library_preview.dart';
import '../../widgets/tv/tv_settings_rows.dart';
import '../tv/sections/tv_about_screen.dart';
import '../tv/sections/tv_servers_page.dart';
import '../../navigation/tv/tv_content_route_registry.dart';
import '../../widgets/scroll_crown/scroll_crown.dart';

part 'parts/settings_actions.dart';
part 'parts/settings_activity_sharing.dart';
part 'parts/settings_phone_page.dart';
part 'parts/settings_system_tiles.dart';
part 'parts/settings_tiles.dart';
part 'parts/settings_tv_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// The way the TV shell opens Instellingen > Koppelingen > Servers for
/// "Servers beheren" (A-24c): along the viewer's own route, so Menu from the
/// Servers page returns to the Servers row (review 557-I5).
abstract interface class TvSettingsServersEntry {
  void openTvServers();
}

class _SettingsScreenState extends State<SettingsScreen>
    with FocusableTab, MountedSetStateMixin, _SettingsActions<SettingsScreen>, _SettingsActivitySharing<SettingsScreen>
    implements TvSettingsServersEntry {
  @override
  void openTvServers() => _openTvServersFromShell();

  late final FocusMemoryTracker _focusTracker;

  /// The TV page's categories, which own which rows are mounted (A-24).
  final _tvCategories = GlobalKey<TvSettingsCategoriesState>();

  // Focus tracking keys
  static const _kDonate = 'donate';
  static const _kAppearance = 'appearance';
  static const _kPlayback = 'playback';
  static const _kLanguage = 'language';
  static const _kSubtitleStyling = 'subtitle_styling';
  static const _kVideoPlayerControls = 'video_player_controls';
  static const _kVideoPlayerNavigation = 'video_player_navigation';
  static const _kCrashReporting = 'crash_reporting';
  static const _kTraktDiscussions = 'trakt_discussions';
  static const _kDebugLogging = 'debug_logging';
  static const _kViewLogs = 'view_logs';
  static const _kClearCache = 'clear_cache';
  static const _kResetSettings = 'reset_settings';
  static const _kCheckForUpdates = 'check_for_updates';
  static const _kAutoCheckUpdatesOnStartup = 'auto_check_updates_on_startup';
  static const _kAbout = 'about';
  static const _kWatchTogetherRelay = 'watch_together_relay';
  static const _kServers = 'servers';
  static const _kIcloudSync = 'icloud_sync';
  // The main page's rows on phones and desktop (A-24b).
  static const _kLibraryHome = 'library_home';
  static const _kIntegrations = 'integrations';
  static const _kProfiles = 'profiles';
  static const _kAdvanced = 'advanced';
  static const _kBackup = 'backup';
  static const _kUpdates = 'updates';

  /// iCloud settings-sync tile is Apple-only (tvOS reports as iOS).
  static bool get _icloudSyncPlatform => Platform.isIOS || Platform.isMacOS;

  // Settings search (desktop/mobile only; TV OSK-search is a separate track).
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool get _searchEnabled => !PlatformDetector.isTV();

  /// The TV page has an update row; the phone's main page reaches the check
  /// only from search since A-24b moved Updates to its own page.
  @override
  bool get _showsUpdateTile => PlatformDetector.isTV();

  @override
  void initState() {
    super.initState();
    _focusTracker = FocusMemoryTracker(
      onFocusChanged: () {
        // ignore: no-empty-block - setState triggers rebuild to update focus styling
        setStateIfMounted(() {});
      },
      debugLabelPrefix: 'settings',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _studioCollapsed.dispose();
    _focusTracker.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    if (InputModeTracker.isKeyboardMode(context)) {
      final fallbackKey = DonationService.isEnabled ? _kDonate : _kAppearance;
      if (_restoreTvFocus()) return;
      _focusTracker.restoreFocus(fallbackKey: fallbackKey);
    }
  }

  void _navigateToSidebar() {
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _navigateToSidebar();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// `setState` is `@protected`, so `_SettingsTvPage` (an extension, not a
  /// `State` subclass method) cannot call it directly — this thin wrapper is
  /// what it passes as `showDownloadLocationDialog`'s `onChanged`.
  /// `_SettingsPhonePage` calls it after updating the search query.
  void _rebuild() => setState(() {});

  /// Whether the A-24 Studio header has scrolled under the pinned bar, which
  /// then shows its own title (phone page only).
  final ValueNotifier<bool> _studioCollapsed = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    // `settings-a`. The whole page, not a wrapper around the desktop cards:
    // see `parts/settings_tv_page.dart` for what the audit measured and why
    // the rows become tiles.
    //
    // A-24b: both pages wear the Studio palette, and every page they open
    // keeps it ([settingsStudioRoute]); nothing outside Instellingen does.
    // Built here, not in a Builder: the tiles call `context.select` on this
    // State's context, which is only legal while this build runs.
    if (PlatformDetector.isTV()) return SettingsStudioTheme(child: _buildTvSettings(context));

    return AutomationScreen(
      id: AutomationIds.screenSettings,
      readiness: () => const AutomationReadiness.ready(),
      child: SettingsStudioTheme(child: _buildSettingsScaffold(context)),
    );
  }

  /// Whether this profile may administer any Plex server here. Used by both
  /// the tile and the search entry, so the two can never disagree about who is
  /// allowed to reach the Tautulli screen. A borrowed connection or a
  /// Jellyfin-only administrator does not count.
  static bool _managesAPlexServer(MultiServerProvider multiServer) => multiServer.serverManager.managesAPlexServer;
}
