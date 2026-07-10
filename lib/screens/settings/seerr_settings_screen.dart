import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../providers/seerr_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../theme/mono_theme.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import '../seerr/seerr_requests_screen.dart';
import 'async_form_state_mixin.dart';

/// Connect / manage a Jellyseerr / Overseerr ("Requests") server.
///
/// Mirrors [AddJellyfinScreen]: URL + credentials with a Test-then-Save flow.
/// Three auth modes — Plex one-tap (default), local email/password, admin API
/// key — surfaced as a selector. When already configured, shows a status card
/// with the signed-in user, server version, permissions and Disconnect.
class SeerrSettingsScreen extends StatefulWidget {
  const SeerrSettingsScreen({super.key});

  @override
  State<SeerrSettingsScreen> createState() => _SeerrSettingsScreenState();
}

class _SeerrSettingsScreenState extends State<SeerrSettingsScreen> with AsyncFormStateMixin, ControllerDisposerMixin {
  late final _urlController = createTextEditingController();
  late final _emailController = createTextEditingController();
  late final _passwordController = createTextEditingController();
  late final _apiKeyController = createTextEditingController();

  final _urlFocus = FocusNode(debugLabel: 'Seerr:Url');
  final _testFocus = FocusNode(debugLabel: 'Seerr:Test');
  final _saveFocus = FocusNode(debugLabel: 'Seerr:Save');
  final _formKey = GlobalKey<FormState>();

  SeerrAuthMode _mode = SeerrAuthMode.plex;
  SeerrTestResult? _testResult;

  @override
  void dispose() {
    _urlFocus.dispose();
    _testFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  String _mapError(Object e) {
    if (e is SeerrException) {
      if (e.isNetwork) return t.seerr.errorNetwork;
      if (e.isForbidden) return t.seerr.errorForbidden;
      if (e.isAuth) return t.seerr.errorAuth;
      // Surface the real Overseerr/Jellyseerr reason (server message, or the
      // bare "HTTP <code>" when the body carries none) instead of a generic
      // message — otherwise "Something went wrong" hides why the login failed.
      return e.message;
    }
    return t.seerr.errorGeneric;
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final provider = context.read<SeerrProvider>();
    String? plexToken;
    if (_mode == SeerrAuthMode.plex) {
      plexToken = await context.read<UserProfileProvider>().currentPlexUserToken();
      if (!mounted) return;
      if (plexToken == null || plexToken.isEmpty) {
        setErrorText(t.seerr.errorAuth);
        return;
      }
    }
    final result = await runAsync<SeerrTestResult>(
      () => provider.test(
        baseUrl: _urlController.text,
        mode: _mode,
        apiKey: _mode == SeerrAuthMode.apiKey ? _apiKeyController.text.trim() : null,
        email: _mode == SeerrAuthMode.local ? _emailController.text.trim() : null,
        password: _mode == SeerrAuthMode.local ? _passwordController.text : null,
        plexToken: plexToken,
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

  Future<void> _save() async {
    final result = _testResult;
    if (result == null) return;
    final provider = context.read<SeerrProvider>();
    await runAsync<void>(() => provider.commit(result.session), errorMapper: _mapError);
    if (mounted && provider.isConfigured) setState(() => _testResult = null);
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.seerr.disconnectConfirm),
        content: Text(t.seerr.disconnectConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.seerr.disconnect)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<SeerrProvider>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SeerrProvider>();
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.seerr.title),
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

  Widget _buildConnectedCard(ThemeData theme, SeerrProvider provider) {
    final session = provider.session!;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final perms = <String>[
      if (provider.isAdmin) t.seerr.permissionAdmin,
      if (!provider.isAdmin && provider.canManageRequests) t.seerr.permissionManage,
      if (!provider.isAdmin && !provider.canManageRequests && provider.canRequest) t.seerr.permissionRequest,
    ];
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
                  const AppIcon(Symbols.cloud_done_rounded, fill: 1),
                  const SizedBox(width: 12),
                  Expanded(child: Text(provider.host ?? '', style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              if (session.displayName != null)
                Text(t.seerr.connectedAs(name: session.displayName!), style: theme.textTheme.bodyMedium),
              if (perms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(perms.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FocusableButton(
          focusNode: _saveFocus,
          useBackgroundFocus: true,
          onPressed: busy
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeerrRequestsScreen())),
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeerrRequestsScreen())),
            icon: const AppIcon(Symbols.receipt_long_rounded, fill: 1),
            label: Text(provider.canManageRequests ? t.seerr.allRequests : t.seerr.myRequests),
          ),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          focusNode: _testFocus,
          useBackgroundFocus: true,
          onPressed: busy ? null : _disconnect,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _disconnect,
            icon: const AppIcon(Symbols.link_off_rounded, fill: 1),
            label: Text(t.seerr.disconnect),
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
      Text(t.seerr.hubSubtitle, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
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
          labelText: t.seerr.serverUrl,
          hintText: t.seerr.serverUrlHint,
          prefixIcon: const AppIcon(Symbols.link_rounded, fill: 1),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? t.seerr.errorNetwork : null,
      ),
      const SizedBox(height: 16),
      Text(t.seerr.authMode, style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      _buildModeSelector(theme),
      const SizedBox(height: 16),
      ..._buildModeFields(theme),
      if (_mode == SeerrAuthMode.apiKey) ...[
        const SizedBox(height: 8),
        Text(t.seerr.adminAttributionNote, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ],
      if (PlatformDetector.isTV()) ...[
        const SizedBox(height: 8),
        Text(t.seerr.setupOnDesktopNote, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ],
      const SizedBox(height: 20),
      FocusableButton(
        focusNode: _testFocus,
        useBackgroundFocus: true,
        onPressed: busy ? null : _test,
        child: FilledButton.icon(
          onPressed: busy ? null : _test,
          icon: busy ? const LoadingIndicatorBox() : const AppIcon(Symbols.wifi_tethering_rounded, fill: 1),
          label: Text(t.seerr.testConnection),
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
            label: Text(t.seerr.save),
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
    final modes = <(SeerrAuthMode, String)>[
      (SeerrAuthMode.plex, t.seerr.authPlex),
      (SeerrAuthMode.local, t.seerr.authLocal),
      (SeerrAuthMode.apiKey, t.seerr.authApiKey),
    ];
    return Column(
      children: [
        for (final (mode, label) in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FocusableButton(
              useBackgroundFocus: true,
              onPressed: busy
                  ? null
                  : () => setState(() {
                      _mode = mode;
                      _testResult = null;
                    }),
              child: _mode == mode
                  ? FilledButton(
                      onPressed: busy ? null : () {},
                      child: Align(alignment: Alignment.centerLeft, child: Text(label)),
                    )
                  : OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              _mode = mode;
                              _testResult = null;
                            }),
                      child: Align(alignment: Alignment.centerLeft, child: Text(label)),
                    ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildModeFields(ThemeData theme) {
    switch (_mode) {
      case SeerrAuthMode.plex:
        return [
          Text(
            t.seerr.authPlexSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ];
      case SeerrAuthMode.local:
        return [
          FocusableTextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: t.seerr.email,
              prefixIcon: const AppIcon(Symbols.mail_rounded, fill: 1),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? t.seerr.errorAuth : null,
          ),
          const SizedBox(height: 12),
          FocusableTextFormField(
            controller: _passwordController,
            obscureText: true,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: t.seerr.password,
              prefixIcon: const AppIcon(Symbols.lock_rounded, fill: 1),
            ),
            validator: (v) => (v == null || v.isEmpty) ? t.seerr.errorAuth : null,
          ),
        ];
      case SeerrAuthMode.apiKey:
        return [
          FocusableTextFormField(
            controller: _apiKeyController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: t.seerr.apiKey,
              hintText: t.seerr.apiKeyHint,
              prefixIcon: const AppIcon(Symbols.key_rounded, fill: 1),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? t.seerr.errorAuth : null,
          ),
        ];
    }
  }

  Widget _buildTestResultCard(ThemeData theme, SeerrTestResult result) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const AppIcon(Symbols.check_circle_rounded, fill: 1, color: kSuccess),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.seerr.serverVersion(version: result.version), style: theme.textTheme.titleSmall),
                if (result.displayName != null)
                  Text(
                    t.seerr.connectedAs(name: result.displayName!),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
