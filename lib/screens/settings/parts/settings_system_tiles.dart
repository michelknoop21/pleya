/// The system rows of Instellingen: keyboard shortcuts, Geavanceerd, Debug,
/// Back-up with iCloud sync, and Updates.
///
/// A `part` of `settings_screen.dart`, for the same reason as
/// `settings_tiles.dart`.
part of '../settings_screen.dart';

extension _SettingsSystemTiles on _SettingsScreenState {
  Widget _buildKeyboardShortcutsSection() {
    if (_keyboardService == null) return const SizedBox.shrink();

    return SettingsGroup(
      title: t.settings.keyboardShortcuts,
      children: [
        SettingNavigationTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kVideoPlayerControls),
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
          focusNode: _focusTracker.get(_SettingsScreenState._kVideoPlayerNavigation),
          pref: settings.SettingsService.videoPlayerNavigationEnabled,
          icon: Symbols.gamepad_rounded,
          title: t.settings.videoPlayerNavigation,
          subtitle: t.settings.videoPlayerNavigationDescription,
        ),
      ],
    );
  }

  Widget _buildAdvancedSection() {
    return SettingsGroup(
      title: t.settings.advanced,
      children: [
        SettingNavigationTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kWatchTogetherRelay),
          icon: Symbols.dns_rounded,
          title: t.settings.watchTogetherRelay,
          subtitle: t.settings.watchTogetherRelayDescription,
          onTap: () => _showRelayUrlDialog(),
        ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kCrashReporting),
          pref: settings.SettingsService.crashReporting,
          icon: Symbols.monitoring_rounded,
          title: t.settings.crashReporting,
          subtitle: t.settings.crashReportingDescription,
        ),
        SettingSwitchTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kDebugLogging),
          pref: settings.SettingsService.enableDebugLogging,
          icon: Symbols.bug_report_rounded,
          title: t.settings.debugLogging,
          subtitle: t.settings.debugLoggingDescription,
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kViewLogs),
          icon: Symbols.article_rounded,
          title: t.settings.viewLogs,
          subtitle: t.settings.viewLogsDescription,
          destinationBuilder: (context) => const LogsScreen(),
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kClearCache),
          icon: Symbols.cleaning_services_rounded,
          title: t.settings.clearCache,
          subtitle: t.settings.clearCacheDescription,
          onTap: () => _showClearCacheDialog(),
        ),
        SettingNavigationTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kResetSettings),
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
    return SettingsGroup(
      title: 'Debug',
      children: [
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
    final isTv = PlatformDetector.isTV();
    return SettingsGroup(
      title: t.settings.backup,
      children: [
        // Export and import hand a file to a file picker, which a TV has no
        // sensible surface for. iCloud sync needs nothing but the toggle, so
        // it is the one tile in here that an Apple TV does get.
        if (!isTv) ...[
          SettingNavigationTile(
            focusNode: _focusTracker.get(_SettingsScreenState._kExportSettings),
            icon: Symbols.upload_rounded,
            title: t.settings.exportSettings,
            subtitle: t.settings.exportSettingsDescription,
            onTap: _handleExportSettings,
          ),
          SettingNavigationTile(
            focusNode: _focusTracker.get(_SettingsScreenState._kImportSettings),
            icon: Symbols.download_rounded,
            title: t.settings.importSettings,
            subtitle: t.settings.importSettingsDescription,
            onTap: _showImportSettingsDialog,
          ),
        ],
        if (_SettingsScreenState._icloudSyncPlatform) _buildIcloudSyncTile(),
      ],
    );
  }

  Widget _buildIcloudSyncTile() {
    final unavailable = _icloudAvailable == false;
    final status = ICloudSyncService.instance?.status;
    final tile = SettingSwitchTile(
      focusNode: _focusTracker.get(_SettingsScreenState._kIcloudSync),
      pref: settings.SettingsService.icloudSyncEnabled,
      icon: Symbols.cloud_sync_rounded,
      title: t.settings.icloudSync,
      subtitle: unavailable ? t.settings.icloudSyncUnavailable : t.settings.icloudSyncDescription,
      enabled: !unavailable,
      onAfterWrite: _handleIcloudSyncToggle,
    );
    if (status == null) return tile;

    // One line under the toggle. It carries the mixed-version boundary too:
    // after the v2 cutover this client neither writes the old format nor merges
    // it, so an out-of-date Apple device keeps working but stops exchanging
    // settings. Saying so is the difference between a known limitation and a
    // mystery.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        ICloudSyncStatusLine(status: status),
      ],
    );
  }

  Widget _buildAutoCheckUpdatesOnStartupTile() => SettingSwitchTile(
    focusNode: _focusTracker.get(_SettingsScreenState._kAutoCheckUpdatesOnStartup),
    pref: settings.SettingsService.autoCheckUpdatesOnStartup,
    icon: Symbols.notifications_active_rounded,
    title: t.settings.autoCheckUpdatesOnStartup,
    subtitle: t.settings.autoCheckUpdatesOnStartupDescription,
  );

  Widget _buildUpdateSection() {
    if (UpdateService.useNativeUpdater) {
      return SettingsGroup(
        title: t.settings.updates,
        children: [
          SettingNavigationTile(
            focusNode: _focusTracker.get(_SettingsScreenState._kCheckForUpdates),
            icon: Symbols.system_update_rounded,
            title: t.settings.checkForUpdates,
            onTap: _handleCheckForUpdatesTap,
          ),
          _buildAutoCheckUpdatesOnStartupTile(),
        ],
      );
    }

    final hasUpdate = _updateInfo != null && _updateInfo!['hasUpdate'] == true;

    return SettingsGroup(
      title: t.settings.updates,
      children: [
        ListTile(
          focusNode: _focusTracker.get(_SettingsScreenState._kCheckForUpdates),
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
}
