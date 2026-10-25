import 'local_library_settings_screen.dart';
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
import '../../media/ids.dart';
import '../../focus/focusable_text_field.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../main_screen.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../mixins/refreshable.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../services/donation_service.dart';
import '../../services/download_storage_service.dart';
import '../../services/icloud_sync_service.dart';
import 'icloud_sync_status_line.dart';
import '../../services/preferences/preference_sync_coordinator.dart';
import '../../services/settings_export_service.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/tautulli_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/trackers_provider.dart';
import '../../providers/trakt_account_provider.dart';
import '../../services/keyboard_shortcuts_service.dart';
import '../../services/settings_service.dart' as settings;
import '../../services/update_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/platform_detector.dart';
import '../../utils/update_dialog.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings/settings_studio_header.dart';
import '../../widgets/settings_section.dart';
import '../../providers/multi_server_provider.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_registry.dart';
import 'about_screen.dart';
import 'add_connection_screen.dart';
import 'pleya_share_host_screen.dart';
import 'appearance_settings_screen.dart';
import 'assistant_settings_screen.dart';
import 'downloads_settings_screen.dart';
import 'keyboard_shortcuts_screen.dart';
import 'home_layout_screen.dart';
import 'library_visibility_screen.dart';
import 'logs_screen.dart';
import 'language_settings_screen.dart';
import 'playback_settings_screen.dart';
import '../profile/profile_switch_screen.dart';
import '../servers_screen.dart';
import 'download_location_dialog.dart';
import 'seerr_settings_screen.dart';
import 'subtitle_styling_screen.dart';
import 'tautulli_settings_screen.dart';
import 'trackers_settings_screen.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_settings_categories.dart';
import '../../widgets/tv/tv_settings_library_preview.dart';
import '../../widgets/tv/tv_settings_rows.dart';
import '../tv/sections/tv_about_screen.dart';
import '../../navigation/tv/tv_content_route_registry.dart';
import '../../widgets/scroll_crown/scroll_crown.dart';

part 'parts/settings_actions.dart';
part 'parts/settings_phone_page.dart';
part 'parts/settings_system_tiles.dart';
part 'parts/settings_tiles.dart';
part 'parts/settings_tv_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with FocusableTab, MountedSetStateMixin {
  late final FocusMemoryTracker _focusTracker;

  /// The TV page's categories, which own which rows are mounted (A-24).
  final _tvCategories = GlobalKey<TvSettingsCategoriesState>();

  // Focus tracking keys
  static const _kDonate = 'donate';
  static const _kAppearance = 'appearance';
  static const _kPlayback = 'playback';
  static const _kLanguage = 'language';
  static const _kSubtitleStyling = 'subtitle_styling';
  static const _kTrackers = 'trackers';
  static const _kLibraryVisibility = 'library_visibility';
  static const _kHomeLayout = 'home_layout';
  static const _kRequests = 'requests';
  static const _kTautulli = 'tautulli';
  static const _kDownloadLocation = 'download_location';
  static const _kDownloadOnWifiOnly = 'download_on_wifi_only';
  static const _kAutoRemoveWatchedDownloads = 'auto_remove_watched_downloads';
  static const _kVideoPlayerControls = 'video_player_controls';
  static const _kVideoPlayerNavigation = 'video_player_navigation';
  static const _kCrashReporting = 'crash_reporting';
  static const _kDebugLogging = 'debug_logging';
  static const _kViewLogs = 'view_logs';
  static const _kClearCache = 'clear_cache';
  static const _kResetSettings = 'reset_settings';
  static const _kCheckForUpdates = 'check_for_updates';
  static const _kAutoCheckUpdatesOnStartup = 'auto_check_updates_on_startup';
  static const _kAbout = 'about';
  static const _kWatchTogetherRelay = 'watch_together_relay';
  static const _kServers = 'servers';
  static const _kExportSettings = 'export_settings';
  static const _kImportSettings = 'import_settings';
  static const _kIcloudSync = 'icloud_sync';

  /// iCloud settings-sync tile is Apple-only (tvOS reports as iOS).
  static bool get _icloudSyncPlatform => Platform.isIOS || Platform.isMacOS;

  /// Whether iCloud is signed in. null = not yet resolved (tile stays enabled
  /// optimistically until the check returns).
  bool? _icloudAvailable;

  KeyboardShortcutsService? _keyboardService;
  late final bool _keyboardShortcutsSupported = KeyboardShortcutsService.isPlatformSupported();

  // Settings search (desktop/mobile only; TV OSK-search is a separate track).
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool get _searchEnabled => !PlatformDetector.isTV();

  // Update checking state
  bool _isCheckingForUpdate = false;
  Map<String, dynamic>? _updateInfo;

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
    if (_keyboardShortcutsSupported) {
      KeyboardShortcutsService.getInstance().then((s) {
        setStateIfMounted(() => _keyboardService = s);
      });
    }
    if (_icloudSyncPlatform) {
      ICloudSyncService.instance?.isAvailable().then((available) {
        setStateIfMounted(() => _icloudAvailable = available);
      });
    }
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
      if (_restoreTvFocus(fallbackKey)) return;
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

  settings.SettingsService get _settingsService => settings.SettingsService.instance;

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
    if (PlatformDetector.isTV()) return _buildTvSettings(context);

    return AutomationScreen(
      id: AutomationIds.screenSettings,
      readiness: () => const AutomationReadiness.ready(),
      child: _buildSettingsScaffold(context),
    );
  }

  /// Whether this profile may administer any Plex server here. Used by both
  /// the tile and the search entry, so the two can never disagree about who is
  /// allowed to reach the Tautulli screen. A borrowed connection or a
  /// Jellyfin-only administrator does not count.
  static bool _managesAPlexServer(MultiServerProvider multiServer) => multiServer.serverManager.managesAPlexServer;

  /// Stays on the state class: it calls `setState`, which the part files'
  /// extensions may not.
  Future<void> _checkForUpdates() async {
    setState(() => _isCheckingForUpdate = true);

    try {
      final updateInfo = await UpdateService.checkForUpdates();

      if (mounted) {
        setState(() {
          _updateInfo = updateInfo;
          _isCheckingForUpdate = false;
        });

        if (updateInfo == null || updateInfo['hasUpdate'] != true) {
          showAppSnackBar(context, t.update.latestVersion);
        } else if (_searchQuery.isNotEmpty) {
          // The update-available tile is hidden while search results are
          // shown, so surface the found update directly.
          _showUpdateDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingForUpdate = false);
        showErrorSnackBar(context, t.update.checkFailed);
      }
    }
  }
}
