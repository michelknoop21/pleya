import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../../services/download_storage_service.dart';
import '../../services/file_picker_service.dart';
import '../../services/icloud_sync_service.dart';
import '../../services/saf_storage_service.dart';
import '../../services/settings_export_service.dart';
import '../../providers/seerr_provider.dart';
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
import '../../widgets/settings_section.dart';
import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../profiles/profile_connection_cleanup.dart';
import '../../profiles/profile_connection_registry.dart';
import '../../profiles/active_profile_binder.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/storage_service.dart';
import '../../focus/focusable_wrapper.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_registry.dart';
import 'about_screen.dart';
import 'add_connection_screen.dart';
import 'pleya_share_host_screen.dart';
import 'appearance_settings_screen.dart';
import 'keyboard_shortcuts_screen.dart';
import 'library_visibility_screen.dart';
import 'logs_screen.dart';
import 'playback_settings_screen.dart';
import '../profile/profile_switch_screen.dart';
import 'seerr_settings_screen.dart';
import 'trackers_settings_screen.dart';
import '../../widgets/loading_indicator_box.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with FocusableTab, MountedSetStateMixin {
  late final FocusMemoryTracker _focusTracker;

  // Focus tracking keys
  static const _kDonate = 'donate';
  static const _kAppearance = 'appearance';
  static const _kPlayback = 'playback';
  static const _kTrackers = 'trackers';
  static const _kLibraryVisibility = 'library_visibility';
  static const _kRequests = 'requests';
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
    _focusTracker.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    if (InputModeTracker.isKeyboardMode(context)) {
      _focusTracker.restoreFocus(fallbackKey: DonationService.isEnabled ? _kDonate : _kAppearance);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        onKeyEvent: _handleKeyEvent,
        child: CustomScrollView(
          primary: false,
          slivers: [
            ExcludeFocus(child: CustomAppBar(title: Text(t.settings.title), pinned: true)),
            if (_searchEnabled) SliverToBoxAdapter(child: _buildSearchField()),
            if (_searchQuery.isNotEmpty)
              _buildSearchResults()
            else
              SliverList(
                delegate: SliverChildListDelegate([
                  if (DonationService.isEnabled) _buildDonateTile(),

                  _buildAppearanceTile(),

                  _buildLibraryVisibilityTile(),

                  _buildPlaybackTile(),

                  _buildTrackersTile(),

                  _buildRequestsTile(),

                  _buildConnectionsSection(),

                  _buildProfilesSection(),

                  if (!PlatformDetector.isAppleTV()) _buildDownloadsSection(),

                  if (_keyboardShortcutsSupported) ...[_buildKeyboardShortcutsSection()],

                  _buildAdvancedSection(),

                  if (UpdateService.isUpdateCheckEnabled) ...[_buildUpdateSection()],

                  if (!PlatformDetector.isTV()) _buildBackupSection(),

                  if (kDebugMode) _buildDebugSection(),

                  SettingNavigationTile(
                    focusNode: _focusTracker.get(_kAbout),
                    icon: Symbols.info_rounded,
                    title: t.settings.about,
                    subtitle: t.settings.aboutDescription,
                    destinationBuilder: (context) => const AboutScreen(),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                    setState(() => _searchQuery = '');
                  },
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
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
        icon: Symbols.play_circle_rounded,
        title: t.settings.videoPlayback,
        subtitle: t.settings.videoPlaybackDescription,
        keywords: const ['subtitle', 'audio', 'skip intro', 'ondertitel', 'afspelen'],
        destinationBuilder: (_) => const PlaybackSettingsScreen(),
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
      if (!Platform.isIOS)
        _SettingsSearchEntry(
          icon: Symbols.folder_rounded,
          title: t.settings.downloads,
          keywords: const ['download', 'offline', 'storage', 'opslag', 'locatie'],
          onTap: (_) => _showDownloadLocationDialog(),
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

  Widget _buildDonateTile() {
    return SettingNavigationTile(
      focusNode: _focusTracker.get(_kDonate),
      icon: Symbols.favorite_rounded,
      title: t.settings.supportDeveloper,
      subtitle: t.settings.supportDeveloperDescription,
      trailingIcon: Symbols.open_in_new_rounded,
      onTap: () async {
        final url = Uri.parse(DonationService.donationUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  Widget _buildAppearanceTile() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => SettingValueBuilder<int>(
        pref: settings.SettingsService.libraryDensity,
        builder: (context, libraryDensity, _) {
          final summary = '${themeProvider.themeModeDisplayName} · ${t.settings.libraryDensity} $libraryDensity';
          return SettingNavigationTile(
            focusNode: _focusTracker.get(_kAppearance),
            icon: Symbols.palette_rounded,
            title: t.settings.appearance,
            subtitle: summary,
            destinationBuilder: (context) => const AppearanceSettingsScreen(),
          );
        },
      ),
    );
  }

  Widget _buildLibraryVisibilityTile() {
    return SettingNavigationTile(
      focusNode: _focusTracker.get(_kLibraryVisibility),
      icon: Symbols.video_library_rounded,
      title: t.settings.libraryVisibility,
      subtitle: t.settings.libraryVisibilityDescription,
      destinationBuilder: (context) => const LibraryVisibilityScreen(),
    );
  }

  Widget _buildPlaybackTile() {
    return SettingNavigationTile(
      focusNode: _focusTracker.get(_kPlayback),
      icon: Symbols.play_circle_rounded,
      title: t.settings.videoPlayback,
      subtitle: t.settings.videoPlaybackDescription,
      destinationBuilder: (context) => const PlaybackSettingsScreen(),
    );
  }

  Widget _buildTrackersTile() {
    return Consumer2<TraktAccountProvider, TrackersProvider>(
      builder: (context, trakt, trackers, _) {
        final connectedNames = <String>[
          if (trakt.isConnected) t.trakt.title,
          if (trackers.isMalConnected) t.trackers.services.mal,
          if (trackers.isAnilistConnected) t.trackers.services.anilist,
          if (trackers.isSimklConnected) t.trackers.services.simkl,
        ];
        final subtitle = connectedNames.isEmpty ? t.settings.trackersDescription : connectedNames.join(' · ');
        return SettingNavigationTile(
          focusNode: _focusTracker.get(_kTrackers),
          icon: Symbols.sync_rounded,
          title: t.settings.trackers,
          subtitle: subtitle,
          destinationBuilder: (_) => const TrackersSettingsScreen(),
        );
      },
    );
  }

  Widget _buildRequestsTile() {
    return Consumer<SeerrProvider>(
      builder: (context, seerr, _) {
        return SettingNavigationTile(
          focusNode: _focusTracker.get(_kRequests),
          icon: Symbols.playlist_add_rounded,
          title: t.settings.requests,
          subtitle: seerr.isConfigured ? (seerr.host ?? t.settings.requests) : t.settings.requestsDescription,
          destinationBuilder: (_) => const SeerrSettingsScreen(),
        );
      },
    );
  }

  Widget _buildConnectionsSection() {
    final active = context.select<ActiveProfileProvider, Profile?>((p) => p.active);
    final subtitle = active == null
        ? t.connections.addConnectionSubtitleNoProfile
        : t.connections.addConnectionSubtitleScoped(displayName: active.displayName);

    return Column(
      crossAxisAlignment: .start,
      children: [
        SettingsSectionHeader(t.connections.sectionTitle),
        // Connections are managed per-profile (via the Profiles section
        // and each profile's detail screen). The shortcut here just opens
        // the picker scoped to the active profile so users can add a Plex
        // account, Jellyfin server, or borrow from another profile.
        SettingNavigationTile(
          icon: Symbols.add_link_rounded,
          title: t.connections.addConnection,
          subtitle: subtitle,
          onTap: () {
            final active = context.read<ActiveProfileProvider>().active;
            Navigator.push(context, MaterialPageRoute(builder: (_) => AddConnectionScreen(targetProfile: active)));
          },
        ),
        SettingNavigationTile(
          icon: Symbols.share_rounded,
          title: t.pleyaShare.hostTitle,
          subtitle: t.pleyaShare.hostDescription,
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PleyaShareHostScreen()));
          },
        ),
        _buildLocalSourcesList(),
      ],
    );
  }

  /// Device-bound sources (local folders, Pleya Share hosts), removable here
  /// regardless of profile bindings — this is also the escape hatch for rows
  /// orphaned by a vanished (virtual Plex Home) profile or a profile-less add.
  Widget _buildLocalSourcesList() {
    return StreamBuilder<List<Connection>>(
      stream: context.read<ConnectionRegistry>().watchConnections(),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final sources = (snapshot.data ?? const <Connection>[])
            .where((c) => c is LocalFolderConnection || c is PleyaShareConnection)
            .toList();
        if (sources.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(t.connections.localSources, style: theme.textTheme.titleSmall),
            ),
            for (final source in sources)
              FocusableWrapper(
                disableScale: true,
                borderRadius: 12,
                onSelect: () => _removeLocalSource(source),
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      source is PleyaShareConnection ? Symbols.devices_rounded : Symbols.folder_rounded,
                      fill: 1,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(source.displayLabel),
                    subtitle: source.displaySubtitle == null
                        ? null
                        : Text(source.displaySubtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: t.connections.removeSource,
                      icon: Icon(Symbols.delete_outline_rounded, color: theme.colorScheme.error),
                      onPressed: () => _removeLocalSource(source),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _removeLocalSource(Connection source) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.connections.removeSource,
      message: t.connections.removeSourceConfirm(name: source.displayLabel),
      confirmText: t.common.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final profileConnections = context.read<ProfileConnectionRegistry>();
    final connections = context.read<ConnectionRegistry>();
    final serverManager = context.read<MultiServerProvider>().serverManager;
    final storage = await StorageService.getInstance();
    await removeConnectionCompletely(
      connection: source,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      serverManager: serverManager,
    );
    if (!mounted) return;
    await context.read<HiddenLibrariesProvider?>()?.refresh();
    if (!mounted) return;
    final activeId = context.read<ActiveProfileProvider>().active?.id;
    if (activeId != null) {
      unawaited(context.read<ActiveProfileBinder>().rebindIfActive(activeId));
    }
  }

  Widget _buildProfilesSection() {
    return StreamBuilder<List<Profile>>(
      stream: context.read<ProfileRegistry>().watchProfiles(),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        // `context.select` so this StreamBuilder doesn't rebuild on every
        // ActiveProfileProvider notification — only when the active
        // profile's display name actually changes.
        final activeName = context.select<ActiveProfileProvider, String?>((p) => p.active?.displayName);
        final subtitle = count <= 1
            ? t.profiles.summarySingle
            : (activeName != null
                  ? t.profiles.summaryMultipleWithActive(count: count, activeName: activeName)
                  : t.profiles.summaryMultiple(count: count));
        return SettingNavigationTile(
          icon: Symbols.group_rounded,
          title: t.profiles.sectionTitle,
          subtitle: subtitle,
          onTap: () => Navigator.of(
            context,
            rootNavigator: true,
          ).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
        );
      },
    );
  }

  Widget _buildDownloadsSection() {
    final storageService = DownloadStorageService.instance;
    final isCustom = storageService.isUsingCustomPath();

    return Column(
      crossAxisAlignment: .start,
      children: [
        SettingsSectionHeader(t.settings.downloads),
        if (!Platform.isIOS)
          FutureBuilder<String>(
            future: storageService.getCurrentDownloadPathDisplay(),
            builder: (context, snapshot) {
              final currentPath = snapshot.data ?? '...';
              return ListTile(
                focusNode: _focusTracker.get(_kDownloadLocation),
                leading: const AppIcon(Symbols.folder_rounded, fill: 1),
                title: Text(isCustom ? t.settings.downloadLocationCustom : t.settings.downloadLocationDefault),
                subtitle: Text(currentPath, maxLines: 2, overflow: .ellipsis),
                trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                onTap: () => _showDownloadLocationDialog(),
              );
            },
          ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_kDownloadOnWifiOnly),
          pref: settings.SettingsService.downloadOnWifiOnly,
          icon: Symbols.wifi_rounded,
          title: t.settings.downloadOnWifiOnly,
          subtitle: t.settings.downloadOnWifiOnlyDescription,
        ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_kAutoRemoveWatchedDownloads),
          pref: settings.SettingsService.autoRemoveWatchedDownloads,
          icon: Symbols.delete_sweep_rounded,
          title: t.settings.autoRemoveWatchedDownloads,
          subtitle: t.settings.autoRemoveWatchedDownloadsDescription,
        ),
      ],
    );
  }

  Widget _buildKeyboardShortcutsSection() {
    if (_keyboardService == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: .start,
      children: [
        SettingsSectionHeader(t.settings.keyboardShortcuts),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kVideoPlayerControls),
          icon: Symbols.keyboard_rounded,
          title: t.settings.videoPlayerControls,
          subtitle: t.settings.keyboardShortcutsDescription,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => KeyboardShortcutsScreen(keyboardService: _keyboardService!)),
            );
          },
        ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_kVideoPlayerNavigation),
          pref: settings.SettingsService.videoPlayerNavigationEnabled,
          icon: Symbols.gamepad_rounded,
          title: t.settings.videoPlayerNavigation,
          subtitle: t.settings.videoPlayerNavigationDescription,
        ),
      ],
    );
  }

  Widget _buildAdvancedSection() {
    return Column(
      crossAxisAlignment: .start,
      children: [
        SettingsSectionHeader(t.settings.advanced),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kWatchTogetherRelay),
          icon: Symbols.dns_rounded,
          title: t.settings.watchTogetherRelay,
          subtitle: t.settings.watchTogetherRelayDescription,
          onTap: () => _showRelayUrlDialog(),
        ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_kCrashReporting),
          pref: settings.SettingsService.crashReporting,
          icon: Symbols.monitoring_rounded,
          title: t.settings.crashReporting,
          subtitle: t.settings.crashReportingDescription,
        ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_kDebugLogging),
          pref: settings.SettingsService.enableDebugLogging,
          icon: Symbols.bug_report_rounded,
          title: t.settings.debugLogging,
          subtitle: t.settings.debugLoggingDescription,
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kViewLogs),
          icon: Symbols.article_rounded,
          title: t.settings.viewLogs,
          subtitle: t.settings.viewLogsDescription,
          destinationBuilder: (context) => const LogsScreen(),
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kClearCache),
          icon: Symbols.cleaning_services_rounded,
          title: t.settings.clearCache,
          subtitle: t.settings.clearCacheDescription,
          onTap: () => _showClearCacheDialog(),
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kResetSettings),
          icon: Symbols.restore_rounded,
          title: t.settings.resetSettings,
          subtitle: t.settings.resetSettingsDescription,
          onTap: () => _showResetSettingsDialog(),
        ),
      ],
    );
  }

  /// Debug-only tools, shown as a separate section at the bottom of the list.
  Widget _buildDebugSection() {
    return Column(
      crossAxisAlignment: .start,
      children: [
        const SettingsSectionHeader('Debug'),
        SettingNavigationTile(
          icon: Symbols.error_rounded,
          title: 'Test Sentry',
          subtitle: 'Send a test error',
          onTap: () {
            throw Exception("Example exception");
          },
        ),
        SettingNavigationTile(
          icon: Symbols.timer_rounded,
          title: 'Test ANR',
          subtitle: 'Block the main thread for 10 seconds',
          onTap: () {
            showSnackBar(context, 'Blocking main thread...');
            final end = DateTime.now().add(const Duration(seconds: 10));
            while (DateTime.now().isBefore(end)) {}
          },
        ),
      ],
    );
  }

  Widget _buildBackupSection() {
    return Column(
      crossAxisAlignment: .start,
      children: [
        SettingsSectionHeader(t.settings.backup),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kExportSettings),
          icon: Symbols.upload_rounded,
          title: t.settings.exportSettings,
          subtitle: t.settings.exportSettingsDescription,
          onTap: _handleExportSettings,
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_kImportSettings),
          icon: Symbols.download_rounded,
          title: t.settings.importSettings,
          subtitle: t.settings.importSettingsDescription,
          onTap: _showImportSettingsDialog,
        ),
        if (_icloudSyncPlatform) _buildIcloudSyncTile(),
      ],
    );
  }

  Widget _buildIcloudSyncTile() {
    final unavailable = _icloudAvailable == false;
    return SettingSwitchTile(
      focusNode: _focusTracker.get(_kIcloudSync),
      pref: settings.SettingsService.icloudSyncEnabled,
      icon: Symbols.cloud_sync_rounded,
      title: t.settings.icloudSync,
      subtitle: unavailable ? t.settings.icloudSyncUnavailable : t.settings.icloudSyncDescription,
      enabled: !unavailable,
      onAfterWrite: _handleIcloudSyncToggle,
    );
  }

  Future<void> _handleIcloudSyncToggle(bool enabled) async {
    final svc = ICloudSyncService.instance;
    if (svc == null) return;
    try {
      if (enabled) {
        await svc.enable();
      } else {
        await svc.disable();
      }
    } catch (_) {
      // Revert the toggle and surface the failure — the write already landed,
      // so undo it so the UI matches the actual (off) state.
      await _settingsService.write(settings.SettingsService.icloudSyncEnabled, false);
      if (mounted) showErrorSnackBar(context, t.settings.icloudSyncEnableFailed);
    }
  }

  Widget _buildAutoCheckUpdatesOnStartupTile() => SettingSwitchTile(
    focusNode: _focusTracker.get(_kAutoCheckUpdatesOnStartup),
    pref: settings.SettingsService.autoCheckUpdatesOnStartup,
    icon: Symbols.notifications_active_rounded,
    title: t.settings.autoCheckUpdatesOnStartup,
    subtitle: t.settings.autoCheckUpdatesOnStartupDescription,
  );

  Widget _buildUpdateSection() {
    if (UpdateService.useNativeUpdater) {
      return Column(
        crossAxisAlignment: .start,
        children: [
          SettingsSectionHeader(t.settings.updates),
          SettingNavigationTile(
            focusNode: _focusTracker.get(_kCheckForUpdates),
            icon: Symbols.system_update_rounded,
            title: t.settings.checkForUpdates,
            onTap: _handleCheckForUpdatesTap,
          ),
          _buildAutoCheckUpdatesOnStartupTile(),
        ],
      );
    }

    final hasUpdate = _updateInfo != null && _updateInfo!['hasUpdate'] == true;

    return Column(
      crossAxisAlignment: .start,
      children: [
        SettingsSectionHeader(t.settings.updates),
        ListTile(
          focusNode: _focusTracker.get(_kCheckForUpdates),
          leading: AppIcon(
            hasUpdate ? Symbols.system_update_rounded : Symbols.check_circle_rounded,
            fill: 1,
            color: hasUpdate ? Colors.orange : null,
          ),
          title: Text(hasUpdate ? t.settings.updateAvailable : t.settings.checkForUpdates),
          subtitle: hasUpdate ? Text(t.update.versionAvailable(version: _updateInfo!['latestVersion'])) : null,
          trailing: _isCheckingForUpdate
              ? const LoadingIndicatorBox(size: 24)
              : const AppIcon(Symbols.chevron_right_rounded, fill: 1),
          onTap: _isCheckingForUpdate ? null : _handleCheckForUpdatesTap,
        ),
        _buildAutoCheckUpdatesOnStartupTile(),
      ],
    );
  }

  Future<void> _showDownloadLocationDialog() async {
    final storageService = DownloadStorageService.instance;
    final isCustom = storageService.isUsingCustomPath();

    await showScopedDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.settings.downloads),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(t.settings.downloadLocationDescription),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: storageService.getCurrentDownloadPathDisplay(),
              builder: (context, snapshot) {
                return Text(
                  t.settings.currentPath(path: snapshot.data ?? '...'),
                  style: Theme.of(context).textTheme.bodySmall,
                );
              },
            ),
          ],
        ),
        actions: [
          if (isCustom)
            DialogActionButton(
              onPressed: () async {
                // Run the async work first, then pop — popping first leaves
                // setState inside _resetDownloadLocation racing against the
                // already-dismissed dialog (and any re-opened instance).
                await _resetDownloadLocation();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              label: t.settings.resetToDefault,
            ),
          DialogActionButton(onPressed: () => Navigator.pop(dialogContext), label: t.common.cancel),
          DialogActionButton(
            onPressed: () async {
              await _selectDownloadLocation();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            label: t.settings.selectFolder,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  Future<void> _selectDownloadLocation() async {
    try {
      String? selectedPath;
      String pathType = 'file';

      if (Platform.isAndroid) {
        final safService = SafStorageService.instance;
        selectedPath = await safService.pickDirectory();
        if (selectedPath != null) {
          pathType = 'saf';
        } else if (PlatformDetector.isTV()) {
          if (mounted) {
            showErrorSnackBar(context, t.settings.downloadLocationSelectError);
          }
          return;
        }
      } else {
        final result = await FilePickerService.instance.getDirectoryPath(dialogTitle: t.settings.selectFolder);
        selectedPath = result;
      }

      if (selectedPath != null) {
        if (pathType == 'file') {
          final dir = Directory(selectedPath);
          final isWritable = await DownloadStorageService.instance.isDirectoryWritable(dir);
          if (!isWritable) {
            if (mounted) {
              showErrorSnackBar(context, t.settings.downloadLocationInvalid);
            }
            return;
          }
        }

        await _settingsService.write(settings.SettingsService.customDownloadPath, selectedPath);
        await _settingsService.write(settings.SettingsService.customDownloadPathType, pathType);
        await DownloadStorageService.instance.refreshCustomPath();

        if (mounted) {
          // ignore: no-empty-block - setState triggers rebuild to reflect new download path
          setState(() {});
          showSuccessSnackBar(context, t.settings.downloadLocationChanged);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, t.settings.downloadLocationSelectError);
      }
    }
  }

  Future<void> _resetDownloadLocation() async {
    await _settingsService.write(settings.SettingsService.customDownloadPath, null);
    await _settingsService.write(settings.SettingsService.customDownloadPathType, null);
    await DownloadStorageService.instance.refreshCustomPath();

    if (mounted) {
      // ignore: no-empty-block - setState triggers rebuild to reflect reset path
      setState(() {});
      showAppSnackBar(context, t.settings.downloadLocationReset);
    }
  }

  Future<void> _showRelayUrlDialog() async {
    await showScopedDialog<void>(
      context: context,
      builder: (_) => _RelayUrlDialog(settingsService: _settingsService),
    );
  }

  Future<void> _showClearCacheDialog() async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.clearCache,
      message: t.settings.clearCacheDescription,
      confirmText: t.common.clear,
    );
    if (!confirmed) return;
    await _settingsService.clearCache();
    if (mounted) showSuccessSnackBar(context, t.settings.clearCacheSuccess);
  }

  Future<void> _showResetSettingsDialog() async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.resetSettings,
      message: t.settings.resetSettingsDescription,
      confirmText: t.common.reset,
      isDestructive: true,
    );
    if (!confirmed) return;
    await _settingsService.resetAllSettings();
    await _keyboardService?.resetToDefaults();
    if (mounted) showSuccessSnackBar(context, t.settings.resetSettingsSuccess);
  }

  Future<void> _handleExportSettings() async {
    try {
      final path = await SettingsExportService.exportToFile();
      if (!mounted) return;
      if (path == null) return; // user cancelled
      showSuccessSnackBar(context, t.settings.exportSettingsSuccess);
    } on SettingsExportException {
      if (mounted) showErrorSnackBar(context, t.settings.exportSettingsFailed);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, t.settings.exportSettingsFailed);
    }
  }

  Future<void> _showImportSettingsDialog() async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.importSettings,
      message: t.settings.importSettingsConfirm,
      confirmText: t.settings.importSettings,
    );
    if (!confirmed) return;
    await _handleImportSettings();
  }

  Future<void> _handleImportSettings() async {
    // Capture providers before any awaits so we don't reach through `context`
    // after the widget may have been unmounted.
    final themeProvider = context.read<ThemeProvider>();
    final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
    final librariesProvider = context.read<LibrariesProvider>();

    try {
      final result = await SettingsExportService.importFromFile();
      if (!mounted) return;
      if (result == null) return; // user cancelled file picker

      // Import wrote directly to SharedPreferences, bypassing `write`. Push
      // fresh values into active listenables before providers re-read settings.
      _settingsService.refreshListenables();
      unawaited(LocaleSettings.setLocale(_settingsService.read(settings.SettingsService.appLocale)));
      await Future.wait([
        themeProvider.reload(),
        hiddenLibrariesProvider.refresh(),
        if (_keyboardService != null) _keyboardService!.refreshFromStorage(),
      ]);
      unawaited(librariesProvider.refresh());

      // Import wrote straight to prefs, bypassing write() and its KVS mirror —
      // push the imported values so they reach the user's other devices.
      unawaited(ICloudSyncService.instance?.pushAllIfEnabled() ?? Future.value());

      if (!mounted) return;
      showSuccessSnackBar(context, t.settings.importSettingsSuccess);
    } on NoUserSignedInException {
      if (mounted) showErrorSnackBar(context, t.settings.importSettingsNoUser);
    } on InvalidExportFileException {
      if (mounted) showErrorSnackBar(context, t.settings.importSettingsInvalidFile);
    } on SettingsExportException {
      if (mounted) showErrorSnackBar(context, t.settings.importSettingsFailed);
    } catch (_) {
      if (mounted) showErrorSnackBar(context, t.settings.importSettingsFailed);
    }
  }

  /// Shared dispatch for the update tile and the search entry: native check,
  /// open the dialog when an update is already known, otherwise run a guarded
  /// check.
  void _handleCheckForUpdatesTap() {
    if (UpdateService.useNativeUpdater) {
      UpdateService.checkForUpdatesNative(inBackground: false);
      return;
    }
    if (_isCheckingForUpdate) return;
    if (_updateInfo != null && _updateInfo!['hasUpdate'] == true) {
      _showUpdateDialog();
    } else {
      _checkForUpdates();
    }
  }

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

  void _showUpdateDialog() {
    final updateInfo = _updateInfo;
    if (updateInfo == null) return;
    unawaited(
      showUpdateAvailableDialog(context, updateInfo, title: t.settings.updateAvailable, dismissLabel: t.common.close),
    );
  }
}

class _RelayUrlDialog extends StatefulWidget {
  final settings.SettingsService settingsService;

  const _RelayUrlDialog({required this.settingsService});

  @override
  State<_RelayUrlDialog> createState() => _RelayUrlDialogState();
}

class _RelayUrlDialogState extends State<_RelayUrlDialog> {
  late final TextEditingController _controller;
  final _saveFocusNode = FocusNode(debugLabel: 'WatchTogetherRelaySave');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settingsService.read(settings.SettingsService.customRelayUrl) ?? '',
    );
  }

  @override
  void dispose() {
    _saveFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    _controller.clear();
    await widget.settingsService.write(settings.SettingsService.customRelayUrl, null);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final trimmed = _controller.text.trim();
    await widget.settingsService.write(settings.SettingsService.customRelayUrl, trimmed.isEmpty ? null : trimmed);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.settings.watchTogetherRelay),
      content: FocusableTextField(
        controller: _controller,
        decoration: InputDecoration(labelText: t.settings.urlLabel, hintText: t.settings.watchTogetherRelayHint),
        autofocus: true,
        textInputAction: TextInputAction.done,
        onEditingComplete: () => _saveFocusNode.requestFocus(),
      ),
      actions: [
        DialogActionButton(onPressed: _reset, label: t.settings.resetToDefault),
        DialogActionButton(onPressed: () => Navigator.pop(context), label: t.common.cancel),
        DialogActionButton(focusNode: _saveFocusNode, onPressed: _save, label: t.common.save),
      ],
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
