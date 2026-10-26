/// What the rows of Instellingen do beyond opening a page: the confirm
/// dialogs, export and import, iCloud sync and the update check.
///
/// A `part` of `settings_screen.dart`: one definition of each action. A mixin
/// rather than an extension since A-24b, because three pages call them: the
/// TV page and the phone's search results on the main screen, and the phone's
/// Geavanceerd, Back-up and Updates pages ([_SettingsSystemPage]), which the
/// Studio series moved these rows to. Each page that mixes it in resolves the
/// keyboard service and iCloud the same way, from this one place.
part of '../settings_screen.dart';

mixin _SettingsActions<W extends StatefulWidget> on State<W> {
  KeyboardShortcutsService? _keyboardService;
  late final bool _keyboardShortcutsSupported = KeyboardShortcutsService.isPlatformSupported();

  /// Whether iCloud is signed in. null = not yet resolved (tile stays enabled
  /// optimistically until the check returns).
  bool? _icloudAvailable;

  // Update checking state
  bool _isCheckingForUpdate = false;
  Map<String, dynamic>? _updateInfo;

  /// Whether this page shows the update row itself. Where it does not (the
  /// phone's main page, which reaches the check from search), a found update
  /// opens its dialog straight away.
  bool get _showsUpdateTile;

  settings.SettingsService get _settingsService => settings.SettingsService.instance;

  @override
  void initState() {
    super.initState();
    if (_keyboardShortcutsSupported) {
      KeyboardShortcutsService.getInstance().then((s) {
        if (mounted) setState(() => _keyboardService = s);
      });
    }
    if (_SettingsScreenState._icloudSyncPlatform) {
      ICloudSyncService.instance?.isAvailable().then((available) {
        if (mounted) setState(() => _icloudAvailable = available);
      });
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
        } else if (!_showsUpdateTile) {
          // No update row on this page to show it, so surface it directly.
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

  Future<void> _handleDonateTap() async {
    final url = Uri.parse(DonationService.donationUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
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
      // Everything else that caches a preference: home layout and per-library
      // view state reload from the same signal a remote apply uses.
      PreferenceRefreshBus.instance.invalidateAll();

      // Import stamped every key it wrote; this reconcile makes sure each one
      // reached the store, including a send the transport held back.
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
