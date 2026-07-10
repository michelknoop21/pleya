import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../profiles/active_profile_binder.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/plex_home_service.dart';
import '../profiles/profile.dart';
import '../services/plex_auth_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../providers/user_profile_provider.dart';
import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import '../focus/key_event_utils.dart';
import '../media/media_backend.dart';
import '../navigation/profile_session_screen.dart';
import '../utils/navigation_transitions.dart';
import '../widgets/backend_badge.dart';
import '../widgets/dialog_action_button.dart';
import 'auth/plex_pin_auth_flow.dart';
import 'profile/profile_switch_screen.dart';
import 'settings/add_jellyfin_screen.dart';

/// Recovery-oriented auth failure states. When set, the auth screen shows
/// a structured recovery widget instead of a bare error string, giving the
/// user a clear next action instead of a technical dead end.
enum _AuthRecoveryState { noServersFound, networkError }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isAuthenticating = false;
  _AuthRecoveryState? _recoveryState;
  // Reuse a one-shot service for the debug-token verify path; the Plex
  // PIN/QR flow inside [PlexPinAuthFlow] owns its own service instance.
  PlexAuthService? _verifyOnlyService;

  @override
  void initState() {
    super.initState();
    unawaited(_initVerifyService());
  }

  Future<void> _initVerifyService() async {
    final svc = await PlexAuthService.create();
    if (!mounted) {
      svc.dispose();
      return;
    }
    setState(() => _verifyOnlyService = svc);
  }

  @override
  void dispose() {
    _verifyOnlyService?.dispose();
    super.dispose();
  }

  /// Auto-select the active profile after sign-in *only* when there's a
  /// single Plex Home user — there's no choice for the user to make. With
  /// multiple Home users (the "real" Home case) we leave the active id
  /// unset so [MainScreen] forces the picker before the binder runs,
  /// avoiding a surprise PIN prompt on whichever user we'd otherwise
  /// pre-select.
  Future<void> _selectInitialProfile(
    PlexHomeService plexHome,
    ActiveProfileProvider activeProfiles,
    PlexAccountConnection accountConn,
  ) async {
    await activeProfiles.initialize();
    final profile = initialPlexHomeProfileFromCache(plexHome, accountConn);
    if (profile == null) {
      await activeProfiles.clearActiveProfile();
      return;
    }
    await activeProfiles.activate(profile);
  }

  /// Persist the new Plex account into the connection pipeline, resolve the
  /// initial active profile when possible, and navigate to the main screen.
  /// The top-level [ActiveProfileBinder] picks up the active profile id and
  /// connects servers via [MultiServerManager.refreshTokensForProfile].
  Future<void> _connectToAllServersAndNavigate(String plexToken) async {
    if (!mounted) return;

    setState(() {
      _isAuthenticating = true;
      _recoveryState = null;
    });

    final connectionRegistry = context.read<ConnectionRegistry>();
    final plexHome = context.read<PlexHomeService>();
    final svc = await PlexAuthService.create();

    try {
      final userInfo = await svc.getUserInfo(plexToken);
      final username = userInfo['username'] as String? ?? '';
      final email = userInfo['email'] as String? ?? '';
      final accountUuid = (userInfo['uuid'] as String?)?.trim() ?? '';

      final servers = await svc.fetchServers(plexToken);
      final storage = await StorageService.getInstance();

      if (servers.isEmpty) {
        await storage.clearCredentials();
        if (!mounted) return;
        setState(() {
          _isAuthenticating = false;
          _recoveryState = _AuthRecoveryState.noServersFound;
        });
        return;
      }

      final clientId = await storage.getOrCreateClientIdentifier();
      final accountConnection = PlexAccountConnection(
        // Key the row by the plex.tv account UUID so signing into a second
        // Plex account on the same device produces a distinct row. The
        // clientIdentifier is per-device and would collide. Falls back to
        // clientId only if plex.tv didn't return a uuid (rare).
        id: 'plex.${accountUuid.isNotEmpty ? accountUuid : clientId}',
        accountToken: plexToken,
        clientIdentifier: clientId,
        accountLabel: username.isNotEmpty ? username : (email.isNotEmpty ? email : 'Plex'),
        servers: servers,
        createdAt: DateTime.now(),
        lastAuthenticatedAt: DateTime.now(),
      );
      await connectionRegistry.upsert(accountConnection);
      await plexHome.refresh(accountConnection);
      if (!mounted) return;
      final activeProfiles = context.read<ActiveProfileProvider>();
      await _selectInitialProfile(plexHome, activeProfiles, accountConnection);

      if (!mounted) return;

      // Start the binder before the picker/MainScreen, mirroring the
      // cold-start SetupScreen ordering. On a fresh install SetupScreen
      // routes here without ever starting it, so without this the profile
      // activated above is bound only by MainScreen's post-frame start() —
      // Discover renders a "No servers available" flash in the gap, and the
      // picker's awaitBindingSettle resolves before anything is bound.
      context.read<ActiveProfileBinder>().start();

      final settings = await SettingsService.getInstance();
      if (!mounted) return;

      final promptHandled = shouldPromptForInitialProfileSelection(
        activeProfile: activeProfiles.active,
        hasProfiles: activeProfiles.profiles.isNotEmpty,
        accountHasHomeUsers: plexHome.current[accountConnection.id]?.isNotEmpty == true,
        requireProfileSelectionOnOpen:
            settings.read(SettingsService.requireProfileSelectionOnOpen) && activeProfiles.hasMultipleProfiles,
      );
      if (promptHandled) {
        final selected = await Navigator.of(
          context,
        ).push<bool>(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen(requireSelection: true)));
        if (!mounted) return;
        if (selected != true || activeProfiles.active == null) {
          setState(() => _isAuthenticating = false);
          return;
        }
      }

      await context.read<UserProfileProvider>().initialize();

      if (!mounted) return;
      unawaited(
        Navigator.pushReplacement(context, fadeRoute(ProfileSessionScreen(initialPromptHandled: promptHandled))),
      );
    } catch (e) {
      appLogger.e('Failed to connect to servers', error: e);
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _recoveryState = _AuthRecoveryState.networkError;
      });
    } finally {
      svc.dispose();
    }
  }

  void _handleDebugTap() {
    if (!kDebugMode) return;
    _showDebugTokenDialog();
  }

  Future<void> _connectToJellyfin() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddJellyfinScreen()));
    if (!mounted || added != true) return;
    // The connection persisted and the manager registered the client; move
    // straight to the main screen. [MainScreen] reads the active client
    // from the server provider, so no client argument is needed here.
    unawaited(Navigator.pushReplacement(context, fadeRoute(const ProfileSessionScreen())));
  }

  void _showDebugTokenDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _DebugTokenDialog(verifyService: _verifyOnlyService, onTokenAccepted: _connectToAllServersAndNavigate);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use two-column layout on desktop, single column on mobile
    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => handleBackKeyNavigation(context, event),
      child: Scaffold(
        body: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: isDesktop ? 800 : 400),
            padding: const EdgeInsets.all(24),
            child: isDesktop
                ? Row(
                    crossAxisAlignment: .center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: .center,
                          crossAxisAlignment: .center,
                          children: [_buildBrandHeader(context), const SizedBox(height: 24), _buildHelpText(context)],
                        ),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: .min,
                              crossAxisAlignment: .stretch,
                              children: [_buildAuthBody()],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      children: [
                        _buildBrandHeader(context),
                        const SizedBox(height: 16),
                        _buildHelpText(context),
                        const SizedBox(height: 32),
                        _buildAuthBody(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthBody() {
    if (_isAuthenticating) {
      return Column(
        mainAxisSize: .min,
        children: [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            t.auth.waitingForAuth,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ],
      );
    }
    if (_recoveryState != null) {
      return _AuthRecoveryView(
        state: _recoveryState!,
        onRetry: () => setState(() {
          _recoveryState = null;
        }),
        onConnectJellyfin: _connectToJellyfin,
      );
    }
    return PlexPinAuthFlow(
      onTokenReceived: _connectToAllServersAndNavigate,
      autoStartQrOnTV: false,
      initialButtonsBuilder: _buildInitialButtons,
    );
  }

  /// Brand block per the app-intro mockup: logo mark, the PLEYA wordmark and
  /// the tagline.
  Widget _buildBrandHeader(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset('assets/branding/pleya_logo.png', width: 96, height: 96),
        ),
        const SizedBox(height: 22),
        Text(
          'PLEYA',
          textAlign: TextAlign.center,
          style: TextStyle(color: textColor, fontSize: 24, fontWeight: .w800, letterSpacing: 9.6),
        ),
        const SizedBox(height: 8),
        Text(
          'Your media. Your way.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, letterSpacing: 1, color: textColor.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  Widget _buildHelpText(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        Text(
          t.auth.chooseHowToSignIn,
          textAlign: TextAlign.center,
          style: TextStyle(color: textColor, fontSize: 16, fontWeight: .w600),
        ),
        const SizedBox(height: 8),
        Text(
          t.auth.chooseHowToSignInDescription,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.6)),
        ),
      ],
    );
  }

  /// Primary CTA using the global FilledButton theme (white-on-black, radius 4).
  Widget _primaryCta({required VoidCallback? onPressed, required Widget child}) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      child: child,
    );
  }

  Widget _buildInitialButtons(BuildContext context, VoidCallback startBrowser, VoidCallback startQr, bool busy) {
    final isTV = PlatformDetector.isTV();
    final isAppleTV = PlatformDetector.isAppleTV();
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        if (isTV) ...[
          FocusableButton(
            autofocus: true,
            onPressed: busy ? null : startQr,
            child: _primaryCta(
              onPressed: busy ? null : startQr,
              child: Row(
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  const BackendBadge(backend: MediaBackend.plex, size: 18),
                  const SizedBox(width: 8),
                  Text(t.auth.signInWithPlex),
                ],
              ),
            ),
          ),
          if (!isAppleTV) ...[
            const SizedBox(height: 12),
            FocusableButton(
              onPressed: busy ? null : startBrowser,
              child: OutlinedButton(
                onPressed: busy ? null : startBrowser,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(t.auth.useBrowser),
              ),
            ),
          ],
        ] else ...[
          FocusableButton(
            onPressed: busy ? null : startBrowser,
            child: _primaryCta(
              onPressed: busy ? null : startBrowser,
              child: Row(
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  const BackendBadge(backend: MediaBackend.plex, size: 18),
                  const SizedBox(width: 8),
                  Text(t.auth.signInWithPlex),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FocusableButton(
            onPressed: busy ? null : startQr,
            child: OutlinedButton(
              onPressed: busy ? null : startQr,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(t.auth.showQRCode),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                t.auth.or,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
            Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: 12),
        FocusableButton(
          onPressed: _connectToJellyfin,
          child: OutlinedButton.icon(
            onPressed: _connectToJellyfin,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            icon: const BackendBadge(backend: MediaBackend.jellyfin, size: 18),
            label: Text(t.auth.connectToJellyfin),
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          FocusableButton(
            onPressed: _handleDebugTap,
            child: OutlinedButton(
              onPressed: _handleDebugTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
              ),
              child: const Text('Debug: Enter Plex Token', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ],
    );
  }
}

@visibleForTesting
Profile? initialPlexHomeProfileFromCache(PlexHomeService plexHome, PlexAccountConnection accountConn) {
  final users = plexHome.current[accountConn.id];
  if (users == null || users.length != 1) return null;
  return Profile.virtualPlexHome(connectionId: accountConn.id, homeUser: users.single);
}

@visibleForTesting
bool shouldPromptForInitialProfileSelection({
  required Profile? activeProfile,
  required bool hasProfiles,
  required bool accountHasHomeUsers,
  required bool requireProfileSelectionOnOpen,
}) {
  return requireProfileSelectionOnOpen || (activeProfile == null && (hasProfiles || accountHasHomeUsers));
}

/// Recovery-oriented error view shown when the initial Plex sign-in succeeds
/// but yields no usable servers, or when the server-fetch call fails. Instead
/// of a bare error string, the user gets a title, a plain-language explanation,
/// and concrete next actions (retry, try Jellyfin, or re-authenticate).
class _AuthRecoveryView extends StatelessWidget {
  final _AuthRecoveryState state;
  final VoidCallback onRetry;
  final VoidCallback onConnectJellyfin;

  const _AuthRecoveryView({required this.state, required this.onRetry, required this.onConnectJellyfin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, description) = switch (state) {
      _AuthRecoveryState.noServersFound => (
        t.serverSelection.noServersFoundTitle,
        t.serverSelection.noServersFoundDescription,
      ),
      _AuthRecoveryState.networkError => (
        t.serverSelection.networkErrorTitle,
        t.serverSelection.networkErrorDescription,
      ),
    };

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Icon(Symbols.cloud_off_rounded, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 24),
        FocusableButton(
          autofocus: true,
          onPressed: onRetry,
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh_rounded),
            label: Text(t.auth.tryAgain),
          ),
        ),
        if (state == _AuthRecoveryState.noServersFound) ...[
          const SizedBox(height: 12),
          FocusableButton(
            onPressed: onConnectJellyfin,
            child: OutlinedButton.icon(
              onPressed: onConnectJellyfin,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: const Color(0xFFFFB020),
                side: const BorderSide(color: Color(0xFFFFB020)),
              ),
              icon: const BackendBadge(backend: MediaBackend.jellyfin, size: 18),
              label: Text(t.serverSelection.noServersFoundTryJellyfin),
            ),
          ),
        ],
      ],
    );
  }
}

/// Stateful so the [TextEditingController] is disposed when the dialog
/// closes — the previous inline `showDialog` builder created the
/// controller in a closure and leaked it on every dismissal.
class _DebugTokenDialog extends StatefulWidget {
  final PlexAuthService? verifyService;
  final Future<void> Function(String token) onTokenAccepted;

  const _DebugTokenDialog({required this.verifyService, required this.onTokenAccepted});

  @override
  State<_DebugTokenDialog> createState() => _DebugTokenDialogState();
}

class _DebugTokenDialogState extends State<_DebugTokenDialog> with ControllerDisposerMixin {
  late final TextEditingController _tokenController = createTextEditingController();
  String? _errorMessage;
  bool _busy = false;

  Future<void> _submit() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = t.errors.pleaseEnterToken);
      return;
    }
    final svc = widget.verifyService;
    if (svc == null) {
      setState(() => _errorMessage = 'Auth service not ready');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _errorMessage = null;
      _busy = true;
    });
    try {
      final isValid = await svc.verifyToken(token);
      if (!mounted) return;
      if (!isValid) {
        setState(() {
          _errorMessage = t.errors.invalidToken;
          _busy = false;
        });
        return;
      }
      navigator.pop();
      await widget.onTokenAccepted(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = t.errors.failedToVerifyToken(error: e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Debug: Enter Plex Token'),
      content: Column(
        mainAxisSize: .min,
        children: [
          FocusableTextFormField(
            controller: _tokenController,
            decoration: InputDecoration(
              labelText: 'Plex Auth Token',
              hintText: 'Enter your Plex.tv token',
              errorText: _errorMessage,
              border: const OutlineInputBorder(),
            ),
            obscureText: true,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
          ),
        ],
      ),
      actions: [
        DialogActionButton(onPressed: _busy ? () {} : () => Navigator.of(context).pop(), label: t.common.cancel),
        DialogActionButton(onPressed: _busy ? () {} : _submit, label: t.auth.authenticate, isPrimary: true),
      ],
    );
  }
}
