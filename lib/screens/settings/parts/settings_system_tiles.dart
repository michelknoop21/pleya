/// The system pages of Instellingen on phones, tablets and desktop:
/// Geavanceerd, Back-up and Updates (A-24b, series `ios/13` and `ios/14`).
///
/// They used to be groups at the bottom of the main page; the Studio series
/// gives the main page a SYSTEEM group with one row per page instead. A
/// `part` of `settings_screen.dart`, because the rows call the actions of
/// [_SettingsActions], the same definitions the TV page and the main page's
/// search results call.
part of '../settings_screen.dart';

/// Which of the system pages a [_SettingsSystemPage] shows.
enum _SystemPageKind { advanced, backup, updates }

class _SettingsSystemPage extends StatefulWidget {
  const _SettingsSystemPage(this.kind);

  final _SystemPageKind kind;

  @override
  State<_SettingsSystemPage> createState() => _SettingsSystemPageState();
}

class _SettingsSystemPageState extends State<_SettingsSystemPage>
    with _SettingsActions<_SettingsSystemPage>, _SettingsActivitySharing<_SettingsSystemPage> {
  @override
  bool get _showsUpdateTile => widget.kind == _SystemPageKind.updates;

  @override
  Widget build(BuildContext context) {
    final sharing = widget.kind == _SystemPageKind.advanced
        ? _syncActivitySharing(context.watch<MultiServerProvider?>())
        : const <ActivitySharingController>[];
    return switch (widget.kind) {
      _SystemPageKind.advanced => SettingsPage(
        title: Text(t.settings.advanced),
        hideDescriptions: true,
        children: [
          if (sharing.isNotEmpty) ...[
            SettingsSectionHeader(t.settings.privacy),
            for (final controller in sharing) _buildActivitySharingRow(controller),
          ],
          SettingsSectionHeader(t.settingsStudio.maintenance),
          ..._buildMaintenanceRows(),
          if (_keyboardShortcutsSupported && _keyboardService != null) ...[
            SettingsSectionHeader(t.settings.keyboardShortcuts),
            ..._buildKeyboardShortcutRows(),
          ],
          if (kDebugMode) ...[const SettingsSectionHeader('Debug'), ..._buildDebugRows()],
        ],
      ),
      _SystemPageKind.backup => SettingsPage(
        title: Text(t.settings.backup),
        hideDescriptions: true,
        children: [SettingsSectionHeader(t.settings.backup), ..._buildBackupRows()],
      ),
      _SystemPageKind.updates => SettingsPage(
        title: Text(t.settings.updates),
        hideDescriptions: true,
        children: [SettingsSectionHeader(t.settings.updates), ..._buildUpdateRows()],
      ),
    };
  }
}

extension _SettingsSystemTiles on _SettingsSystemPageState {
  List<Widget> _buildKeyboardShortcutRows() => [
    SettingNavigationTile(
      icon: Symbols.keyboard_rounded,
      title: t.settings.videoPlayerControls,
      subtitle: t.settings.keyboardShortcutsDescription,
      destinationBuilder: (_) => KeyboardShortcutsScreen(keyboardService: _keyboardService!),
    ),
    SettingSwitchTile(
      pref: settings.SettingsService.videoPlayerNavigationEnabled,
      icon: Symbols.gamepad_rounded,
      title: t.settings.videoPlayerNavigation,
      subtitle: t.settings.videoPlayerNavigationDescription,
    ),
  ];

  /// Series `ios/13`, Onderhoud: the relay, the two diagnostics switches, the
  /// logs, and the two destructive rows in the destructive ink.
  List<Widget> _buildMaintenanceRows() => [
    SettingNavigationTile(
      icon: Symbols.dns_rounded,
      title: t.settings.watchTogetherRelay,
      subtitle: t.settings.watchTogetherRelayDescription,
      onTap: _showRelayUrlDialog,
    ),
    SettingSwitchTile(
      pref: settings.SettingsService.crashReporting,
      icon: Symbols.monitoring_rounded,
      title: t.settings.crashReporting,
      subtitle: t.settings.crashReportingDescription,
    ),
    SettingSwitchTile(
      pref: settings.SettingsService.enableDebugLogging,
      icon: Symbols.bug_report_rounded,
      title: t.settings.debugLogging,
      subtitle: t.settings.debugLoggingDescription,
    ),
    SettingNavigationTile(
      icon: Symbols.article_rounded,
      title: t.settings.viewLogs,
      subtitle: t.settings.viewLogsDescription,
      destinationBuilder: (_) => const LogsScreen(),
    ),
    SettingNavigationTile(
      icon: Symbols.cleaning_services_rounded,
      title: t.settings.clearCache,
      subtitle: t.settings.clearCacheDescription,
      destructive: true,
      onTap: _showClearCacheDialog,
    ),
    SettingNavigationTile(
      icon: Symbols.restore_rounded,
      title: t.settings.resetSettings,
      subtitle: t.settings.resetSettingsDescription,
      destructive: true,
      onTap: _showResetSettingsDialog,
    ),
  ];

  /// Debug-only tools.
  List<Widget> _buildDebugRows() => [
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
  ];

  /// Export and import hand a file to a file picker; iCloud needs nothing but
  /// the toggle. TV has its own page, so these rows are never on a TV.
  List<Widget> _buildBackupRows() => [
    SettingNavigationTile(
      icon: Symbols.upload_rounded,
      title: t.settings.exportSettings,
      subtitle: t.settings.exportSettingsDescription,
      onTap: _handleExportSettings,
    ),
    SettingNavigationTile(
      icon: Symbols.download_rounded,
      title: t.settings.importSettings,
      subtitle: t.settings.importSettingsDescription,
      onTap: _showImportSettingsDialog,
    ),
    if (_SettingsScreenState._icloudSyncPlatform) _buildIcloudSyncTile(),
  ];

  Widget _buildIcloudSyncTile() {
    final unavailable = _icloudAvailable == false;
    final status = ICloudSyncService.instance?.status;
    final tile = SettingSwitchTile(
      pref: settings.SettingsService.icloudSyncEnabled,
      icon: Symbols.cloud_sync_rounded,
      title: t.settings.icloudSync,
      // Disabled when iCloud is unavailable, and then the line says so.
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
    pref: settings.SettingsService.autoCheckUpdatesOnStartup,
    icon: Symbols.notifications_active_rounded,
    title: t.settings.autoCheckUpdatesOnStartup,
    subtitle: t.settings.autoCheckUpdatesOnStartupDescription,
  );

  List<Widget> _buildUpdateRows() {
    if (UpdateService.useNativeUpdater) {
      return [
        SettingNavigationTile(
          icon: Symbols.system_update_rounded,
          title: t.settings.checkForUpdates,
          onTap: _handleCheckForUpdatesTap,
        ),
        _buildAutoCheckUpdatesOnStartupTile(),
      ];
    }

    final hasUpdate = _updateInfo != null && _updateInfo!['hasUpdate'] == true;
    return [
      ListTile(
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
    ];
  }
}
