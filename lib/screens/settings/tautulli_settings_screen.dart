import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../providers/tautulli_provider.dart';
import '../../services/storage_service.dart';
import '../../services/tautulli/tautulli_client.dart';
import '../../services/tautulli/tautulli_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import 'async_form_state_mixin.dart';

/// Connect Tautulli, the Plex monitoring service, to this profile.
///
/// Mirrors [SeerrSettingsScreen]: URL plus credentials with a Test-then-Save
/// flow. Two modes, and the order is the recommendation: a per-device token
/// generated in Tautulli, or the permanent API key.
///
/// The difference from seerr that shapes this screen: Tautulli has no per-user
/// login. One key opens the whole admin API, so what is configured here only
/// ever serves the person holding it, and the copy says so instead of implying
/// the household gets it too.
class TautulliSettingsScreen extends StatefulWidget {
  const TautulliSettingsScreen({super.key});

  @override
  State<TautulliSettingsScreen> createState() => _TautulliSettingsScreenState();
}

class _TautulliSettingsScreenState extends State<TautulliSettingsScreen>
    with AsyncFormStateMixin, ControllerDisposerMixin {
  late final _urlController = createTextEditingController();
  late final _tokenController = createTextEditingController();

  final _urlFocus = FocusNode(debugLabel: 'Tautulli:Url');
  final _testFocus = FocusNode(debugLabel: 'Tautulli:Test');
  final _saveFocus = FocusNode(debugLabel: 'Tautulli:Save');
  final _formKey = GlobalKey<FormState>();

  TautulliAuthMode _mode = TautulliAuthMode.device;
  TautulliTestResult? _testResult;

  @override
  void dispose() {
    _urlFocus.dispose();
    _testFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  String _mapError(Object e) {
    if (e is TautulliException) {
      if (e.isNetwork) return t.tautulli.errorNetwork;
      // A device token that already expired reads as "Invalid apikey", which is
      // the single most likely failure here: it only lives five minutes.
      if (e.isAuth) {
        return _mode == TautulliAuthMode.device ? t.tautulli.errorTokenExpired : t.tautulli.errorAuth;
      }
      return e.message;
    }
    return t.tautulli.errorGeneric;
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final provider = context.read<TautulliProvider>();
    final storage = await StorageService.getInstance();
    final deviceId = await storage.getOrCreateClientIdentifier();
    if (!mounted) return;

    final result = await runAsync<TautulliTestResult>(
      () => provider.test(
        baseUrl: _urlController.text,
        mode: _mode,
        token: _tokenController.text.trim(),
        deviceId: deviceId,
        deviceName: _deviceName(),
      ),
      errorMapper: _mapError,
    );
    if (result != null && mounted) {
      setState(() => _testResult = result);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _saveFocus.canRequestFocus) _saveFocus.requestFocus();
      });
    }
  }

  /// Shown in Tautulli's own device list, so it has to identify this install at
  /// a glance when the admin goes to revoke one.
  String _deviceName() => 'Pleya (${PlatformDetector.isTV() ? 'TV' : defaultTargetPlatform.name})';

  Future<void> _save() async {
    final result = _testResult;
    if (result == null) return;
    final provider = context.read<TautulliProvider>();
    await runAsync<void>(() => provider.commit(result.session), errorMapper: _mapError);
    if (mounted && provider.isConfigured) setState(() => _testResult = null);
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.tautulli.disconnectConfirm),
        content: Text(t.tautulli.disconnectConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.tautulli.disconnect)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<TautulliProvider>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TautulliProvider>();
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.tautulli.title),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: provider.isConfigured
                ? _buildConnectedCard(theme, provider)
                : Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _buildForm(theme)),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedCard(ThemeData theme, TautulliProvider provider) {
    final session = provider.session!;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppIcon(Symbols.insights_rounded, fill: 1),
                  const SizedBox(width: 12),
                  Expanded(child: Text(session.serverName ?? provider.host ?? '', style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              Text(provider.host ?? '', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (session.version != null) session.version!,
                    session.isDeviceToken ? t.tautulli.modeDevice : t.tautulli.modeApiKey,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(t.tautulli.adminOnlyNote, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: 16),
        FocusableButton(
          focusNode: _testFocus,
          useBackgroundFocus: true,
          onPressed: busy ? null : _disconnect,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _disconnect,
            icon: const AppIcon(Symbols.link_off_rounded, fill: 1),
            label: Text(t.tautulli.disconnect),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(errorText!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  List<Widget> _buildForm(ThemeData theme) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return [
      Text(t.tautulli.subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
      const SizedBox(height: 16),
      FocusableTextFormField(
        controller: _urlController,
        focusNode: _urlFocus,
        autofocus: true,
        tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !busy,
        onChanged: (_) {
          if (_testResult != null) setState(() => _testResult = null);
        },
        decoration: InputDecoration(
          labelText: t.tautulli.serverUrl,
          // Tautulli's default is 8181, but a reverse-proxied subdomain on 443
          // is just as common, so the hint shows both rather than teaching one.
          hintText: t.tautulli.serverUrlHint,
          prefixIcon: const AppIcon(Symbols.link_rounded, fill: 1),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? t.tautulli.errorUrlRequired : null,
      ),
      const SizedBox(height: 16),
      Text(t.tautulli.authMode, style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      _buildModeSelector(theme),
      const SizedBox(height: 8),
      Text(
        _mode == TautulliAuthMode.device ? t.tautulli.modeDeviceHelp : t.tautulli.modeApiKeyHelp,
        style: theme.textTheme.bodySmall?.copyWith(color: muted),
      ),
      const SizedBox(height: 16),
      FocusableTextFormField(
        controller: _tokenController,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !busy,
        onChanged: (_) {
          if (_testResult != null) setState(() => _testResult = null);
        },
        decoration: InputDecoration(
          labelText: _mode == TautulliAuthMode.device ? t.tautulli.deviceToken : t.tautulli.apiKey,
          prefixIcon: const AppIcon(Symbols.key_rounded, fill: 1),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? t.tautulli.errorTokenRequired : null,
      ),
      if (PlatformDetector.isTV()) ...[
        const SizedBox(height: 8),
        Text(t.tautulli.setupOnDesktopNote, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ],
      const SizedBox(height: 20),
      FocusableButton(
        focusNode: _testFocus,
        useBackgroundFocus: true,
        onPressed: busy ? null : _test,
        child: FilledButton.icon(
          onPressed: busy ? null : _test,
          icon: busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.wifi_tethering_rounded, fill: 1),
          label: Text(t.tautulli.testConnection),
        ),
      ),
      if (_testResult != null) ...[
        const SizedBox(height: 16),
        _buildTestResultCard(theme, _testResult!),
        const SizedBox(height: 12),
        FocusableButton(
          focusNode: _saveFocus,
          useBackgroundFocus: true,
          onPressed: busy ? null : _save,
          child: FilledButton.icon(
            onPressed: busy ? null : _save,
            icon: const AppIcon(Symbols.check_rounded, fill: 1),
            label: Text(t.tautulli.save),
          ),
        ),
      ],
      if (errorText != null) ...[
        const SizedBox(height: 12),
        Text(errorText!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
      ],
    ];
  }

  Widget _buildModeSelector(ThemeData theme) {
    final modes = <(TautulliAuthMode, String)>[
      (TautulliAuthMode.device, t.tautulli.modeDevice),
      (TautulliAuthMode.apiKey, t.tautulli.modeApiKey),
    ];
    return Column(
      children: [
        for (final (mode, label) in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FocusableButton(
              useBackgroundFocus: true,
              onPressed: busy ? null : () => _selectMode(mode),
              child: _mode == mode
                  ? FilledButton(
                      onPressed: busy ? null : () {},
                      child: Align(alignment: Alignment.centerLeft, child: Text(label)),
                    )
                  : OutlinedButton(
                      onPressed: busy ? null : () => _selectMode(mode),
                      child: Align(alignment: Alignment.centerLeft, child: Text(label)),
                    ),
            ),
          ),
      ],
    );
  }

  void _selectMode(TautulliAuthMode mode) => setState(() {
    _mode = mode;
    _testResult = null;
  });

  Widget _buildTestResultCard(ThemeData theme, TautulliTestResult result) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIcon(Symbols.check_circle_rounded, fill: 1),
              const SizedBox(width: 12),
              Expanded(child: Text(result.serverName ?? t.tautulli.connected, style: theme.textTheme.titleMedium)),
            ],
          ),
          if (result.version != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(result.version!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
        ],
      ),
    );
  }
}
