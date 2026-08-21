import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../exceptions/media_server_exceptions.dart';
import '../../i18n/strings.g.dart';
import '../../services/plex_auth_service.dart';
import '../../focus/focusable_button.dart';
import '../../media/media_backend.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/backend_badge.dart';
import '../../utils/app_logger.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/platform_detector.dart';

/// Self-contained Plex PIN/QR auth flow.
///
/// Renders the polling UI (QR code or browser-waiting spinner) once an
/// auth attempt is started via [PlexPinAuthFlowController.startBrowser] /
/// [PlexPinAuthFlowController.startQr]. When polling resolves successfully
/// it invokes [onTokenReceived(token)]; the parent decides what to do next
/// (the legacy [AuthScreen] connects to all servers + navigates to
/// MainScreen, while [AddPlexAccountScreen] pops with success or routes
/// into the borrow flow).
///
/// Both screens previously implemented this flow inline — same `PlexAuthService`
/// orchestration, same QR widget, same browser-waiting state. Extracting
/// here removes ~300 lines of duplicate UI code and centralises the
/// poll-cancel-retry plumbing.
class PlexPinAuthFlow extends StatefulWidget {
  /// Fires when the user successfully claims the PIN. The token is the raw
  /// `X-Plex-Token` value — parent code is responsible for exchanging it
  /// for a [PlexAccountConnection] (account label + servers list).
  final Future<void> Function(String token) onTokenReceived;

  /// QR size on mobile / narrow layouts.
  final double mobileQrSize;

  /// QR size on desktop / wide layouts (where the auth screen has more
  /// horizontal room). The two-column login screen uses 300; the bottom-sheet
  /// add-account screen uses 200.
  final double desktopQrSize;

  /// When `true` and running on TV, auto-start the QR flow on first build so
  /// the user doesn't have to navigate to the QR button with the remote.
  final bool autoStartQrOnTV;

  /// Override the QR-vs-browser default before any user interaction. Useful
  /// for callers that want to force one mode (the add-account screen
  /// auto-starts QR on TV; the legacy login screen offers both).
  final bool? initialUseQr;

  /// Optional builder for the initial action buttons. The default (`null`)
  /// shows two buttons — "Sign in with Plex" (browser) and "Show QR Code".
  /// Pass a custom builder when the parent wants to integrate the buttons
  /// into a richer layout (extra Jellyfin button, debug button, branding).
  ///
  /// `clearError` wipes any lingering Plex error text — call it from buttons
  /// that route the user away from the Plex flow so a stale red message
  /// doesn't hang around underneath an unrelated screen.
  final Widget Function(
    BuildContext context,
    VoidCallback startBrowser,
    VoidCallback startQr,
    bool busy,
    VoidCallback clearError,
  )?
  initialButtonsBuilder;

  /// When non-null, the sign-in offers a way out to the other backend — both
  /// while the PIN is outstanding and after it times out. Kept as a callback
  /// so this widget stays independent of [AuthScreen]; [AddPlexAccountScreen]
  /// passes nothing and keeps its current behaviour.
  final VoidCallback? onSwitchToJellyfin;

  /// Injection seam for widget tests that need to drive the polling UI
  /// without reaching plex.tv. Production always gets [PlexAuthService.create].
  @visibleForTesting
  final Future<PlexAuthService> Function()? authServiceFactory;

  const PlexPinAuthFlow({
    super.key,
    required this.onTokenReceived,
    this.mobileQrSize = 200,
    this.desktopQrSize = 300,
    this.autoStartQrOnTV = true,
    this.initialUseQr,
    this.initialButtonsBuilder,
    this.onSwitchToJellyfin,
    this.authServiceFactory,
  });

  @override
  State<PlexPinAuthFlow> createState() => _PlexPinAuthFlowState();
}

class _PlexPinAuthFlowState extends State<PlexPinAuthFlow> {
  PlexAuthService? _authService;
  bool _isPolling = false;
  bool _useQr = false;
  String? _qrAuthUrl;
  int _attemptId = 0;
  String? _errorMessage;

  /// True when the last attempt ended because the PIN was never claimed (as
  /// opposed to a hard failure). That case is recoverable and almost always
  /// means the user signed in somewhere it couldn't count — e.g. typing
  /// Jellyfin credentials into plex.tv — so it gets actions, not just text.
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _useQr = widget.initialUseQr ?? PlatformDetector.isTV();
    unawaited(_initService());
  }

  Future<void> _initService() async {
    final svc = await (widget.authServiceFactory ?? PlexAuthService.create)();
    if (!mounted) {
      svc.dispose();
      return;
    }
    setState(() {
      _authService = svc;
    });
    if (widget.autoStartQrOnTV && PlatformDetector.isTV()) {
      unawaited(_start(useQr: true));
    }
  }

  @override
  void dispose() {
    _attemptId++;
    _authService?.dispose();
    super.dispose();
  }

  Future<void> _start({required bool useQr}) async {
    final svc = _authService;
    if (svc == null) return;
    final attemptId = ++_attemptId;
    setState(() {
      _useQr = useQr;
      _isPolling = true;
      _errorMessage = null;
      _timedOut = false;
      _qrAuthUrl = null;
    });

    try {
      final pinData = await svc.createPin();
      if (!_isCurrentAttempt(attemptId)) return;
      final pinId = pinData['id'] as int;
      final pinCode = pinData['code'] as String;
      final url = svc.getAuthUrl(pinCode);

      if (!_isCurrentAttempt(attemptId)) return;
      if (useQr) {
        setState(() => _qrAuthUrl = url);
      } else {
        final uri = Uri.parse(url);
        try {
          final mode = PlatformDetector.isTV() ? LaunchMode.inAppWebView : LaunchMode.inAppBrowserView;
          await launchUrl(uri, mode: mode);
        } catch (_) {
          // Chrome Custom Tabs may not be available — fall back to default
          // external browser.
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      final token = await svc.pollPinUntilClaimed(pinId, shouldCancel: () => attemptId != _attemptId);
      if (!_isCurrentAttempt(attemptId)) return;

      if (token == null) {
        setState(() {
          _isPolling = false;
          _qrAuthUrl = null;
          _errorMessage = t.auth.authenticationTimeout;
          _timedOut = true;
        });
        return;
      }

      // Auto-close the in-app browser on mobile (no-op on desktop / when
      // already closed).
      if (!useQr) {
        try {
          await closeInAppWebView();
        } catch (_) {}
      }

      if (!_isCurrentAttempt(attemptId)) return;
      setState(() {
        _qrAuthUrl = null;
      });
      await widget.onTokenReceived(token);
      if (!_isCurrentAttempt(attemptId)) return;
      setState(() {
        _isPolling = false;
      });
    } catch (e) {
      appLogger.w('Plex PIN auth failed', error: e);
      if (!_isCurrentAttempt(attemptId)) return;
      setState(() {
        _isPolling = false;
        _qrAuthUrl = null;
        _errorMessage = _authErrorMessage(e);
        _timedOut = false;
      });
    }
  }

  String _authErrorMessage(Object error) {
    // The one auth failure with a more specific, actionable message than
    // friendlyError's generic "Authentication failed" — everything else
    // delegates.
    if (error is MediaServerPinExpiredException) return t.addServer.pinExpired;
    return friendlyError(error);
  }

  bool _isCurrentAttempt(int attemptId) => mounted && attemptId == _attemptId;

  void _clearError() {
    if (_errorMessage == null && !_timedOut) return;
    setState(() {
      _errorMessage = null;
      _timedOut = false;
    });
  }

  void _switchToJellyfin() {
    final onSwitch = widget.onSwitchToJellyfin;
    if (onSwitch == null) return;
    // Abandon the Plex attempt first. The parent pushes the Jellyfin route on
    // top of this widget, so it stays alive and polling; a PIN claimed after
    // the user walked away would fire `onTokenReceived` and navigate out from
    // under whatever they are typing. Bumping the attempt id makes
    // `shouldCancel` true and orphans any in-flight poll result.
    _attemptId++;
    setState(() {
      _isPolling = false;
      _qrAuthUrl = null;
      _errorMessage = null;
      _timedOut = false;
    });
    onSwitch();
  }

  /// Single rendering of the error state. On a timeout it's not just red text:
  /// the user gets a retry and — when the parent offered one — a route to the
  /// other backend, because "the PIN was never claimed" usually means they were
  /// never going to succeed on Plex in the first place.
  Widget _buildErrorBlock(ThemeData theme) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Text(
          _errorMessage!,
          style: TextStyle(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
        if (_timedOut) ...[
          const SizedBox(height: 16),
          FocusableButton(
            onPressed: _retry,
            child: FilledButton(
              onPressed: _retry,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(t.auth.tryAgain),
            ),
          ),
          if (widget.onSwitchToJellyfin != null) ...[
            const SizedBox(height: 8),
            FocusableButton(
              onPressed: _switchToJellyfin,
              child: OutlinedButton.icon(
                onPressed: _switchToJellyfin,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const BackendBadge(backend: MediaBackend.jellyfin, size: 18),
                label: Text(t.auth.usingJellyfinInstead),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// The same escape hatch as in [_buildErrorBlock], but offered *while* the
  /// PIN is still outstanding. Someone who typed Jellyfin credentials on
  /// plex.tv will never claim this PIN, and waiting out the five-minute poll
  /// to be told so reads as a broken app (App Review 2.1(a) twice over).
  /// Deliberately a quiet text button — the PIN/QR stays the main event.
  Widget? _buildJellyfinEscape() {
    if (widget.onSwitchToJellyfin == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FocusableButton(
        onPressed: _switchToJellyfin,
        child: TextButton.icon(
          onPressed: _switchToJellyfin,
          icon: const BackendBadge(backend: MediaBackend.jellyfin, size: 16),
          label: Text(t.auth.usingJellyfinInstead, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  void _retry() {
    final useQr = _useQr;
    _attemptId++;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) unawaited(_start(useQr: useQr));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isPolling) {
      final isDesktop = MediaQuery.sizeOf(context).width > 700;
      if (_useQr && _qrAuthUrl != null) {
        return _buildQr(theme, isDesktop ? widget.desktopQrSize : widget.mobileQrSize);
      }
      return _buildBrowserWaiting(theme);
    }

    final builder = widget.initialButtonsBuilder ?? _defaultInitialButtons;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        builder(context, () => _start(useQr: false), () => _start(useQr: true), _authService == null, _clearError),
        if (_errorMessage != null) ...[const SizedBox(height: 16), _buildErrorBlock(theme)],
      ],
    );
  }

  Widget _defaultInitialButtons(
    BuildContext context,
    VoidCallback browser,
    VoidCallback qr,
    bool busy,
    VoidCallback clearError,
  ) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        FocusableButton(
          onPressed: busy ? null : browser,
          child: FilledButton(onPressed: busy ? null : browser, child: Text(t.auth.signInWithPlex)),
        ),
        const SizedBox(height: 12),
        FocusableButton(
          onPressed: busy ? null : qr,
          child: OutlinedButton(onPressed: busy ? null : qr, child: Text(t.auth.showQRCode)),
        ),
      ],
    );
  }

  Widget _buildQr(ThemeData theme, double qrSize) {
    final jellyfinEscape = _buildJellyfinEscape();
    return Column(
      mainAxisSize: .min,
      children: [
        Text(
          t.auth.scanQRToSignIn,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 24),
        Center(
          // Tight SizedBox so ancestors that measure intrinsics (e.g.
          // SliverFillRemaining with hasScrollBody: false) never recurse into
          // QrImageView's internal LayoutBuilder, which doesn't support them.
          child: SizedBox.square(
            dimension: qrSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens(context).radiusMd),
              child: QrImageView(
                data: _qrAuthUrl!,
                size: qrSize,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FocusableButton(
          onPressed: _retry,
          child: OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24)),
            child: Text(t.common.retry),
          ),
        ),
        ?jellyfinEscape,
        if (_errorMessage != null) ...[const SizedBox(height: 12), _buildErrorBlock(theme)],
      ],
    );
  }

  Widget _buildBrowserWaiting(ThemeData theme) {
    final jellyfinEscape = _buildJellyfinEscape();
    return Column(
      mainAxisSize: .min,
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text(
          t.auth.waitingForAuth,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 16),
        FocusableButton(
          onPressed: _retry,
          child: OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24)),
            child: Text(t.common.retry),
          ),
        ),
        ?jellyfinEscape,
        if (_errorMessage != null) ...[const SizedBox(height: 12), _buildErrorBlock(theme)],
      ],
    );
  }
}
