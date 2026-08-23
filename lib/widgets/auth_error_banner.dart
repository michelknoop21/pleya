import 'package:flutter/material.dart';
import '../media/ids.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_server_client.dart' show HealthStatus;
import '../providers/multi_server_provider.dart';
import '../screens/settings/add_connection_screen.dart';
import '../focus/focusable_button.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import '../utils/snackbar_helper.dart';
import 'app_icon.dart';

/// Top-of-app banner shown when one or more servers' tokens have been
/// rejected (HTTP 401/403 on the health probe). Distinct from "server
/// offline" — taps the user toward re-auth instead of leaving them
/// puzzled by empty hubs.
///
/// Tracks [MultiServerProvider.hasAuthErrorServers] and collapses to
/// `SizedBox.shrink()` when no servers are in the auth-error state. The
/// CTA opens [AddConnectionScreen]; the user picks the right backend and
/// the resulting token replaces the stale row in the registry, which
/// clears the auth-error state on the next health sweep.
class AuthErrorBanner extends StatefulWidget {
  const AuthErrorBanner({super.key});

  @override
  State<AuthErrorBanner> createState() => _AuthErrorBannerState();
}

class _AuthErrorBannerState extends State<AuthErrorBanner> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    final entries = context.select<MultiServerProvider, List<({ServerId serverId, String displayName})>>(
      (p) => p.authErrorServers,
    );
    if (entries.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final mono = tokens(context);
    final errorColor = mono.isLight ? kNoticeErrorLight : kNoticeErrorDark;
    final label = entries.length == 1
        ? t.connections.sessionExpiredOne(name: entries.first.displayName)
        : t.connections.sessionExpiredMany(count: entries.length);

    return Material(
      color: mono.surfaceElevated,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              AppIcon(Symbols.error_rounded, fill: 1, color: errorColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(color: mono.text, fontWeight: .w500),
                ),
              ),
              const SizedBox(width: 8),
              FocusableButton(
                onPressed: _retrying ? null : () => _retryThenReauth(context, entries),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(backgroundColor: errorColor, foregroundColor: mono.surfaceElevated),
                  onPressed: _retrying ? null : () => _retryThenReauth(context, entries),
                  child: _retrying
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: mono.surfaceElevated),
                        )
                      : Text(t.connections.signInAgain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One real refresh attempt before anyone has to type anything.
  ///
  /// A cold start recovers a chain that was never actually dead, because a
  /// fresh session gets to spend the kept token once. This gives the button
  /// the same second chance: for every Pleya Server on the banner it clears
  /// the in-memory revocation and runs one probe, which now reaches
  /// `POST /auth/refresh`. Only a proven rejection — the probe coming back as
  /// an auth error again — escalates to the sign-in screen. A server that
  /// turns out to be unreachable is a transport problem, and retyping
  /// credentials would not fix it, so that case gets a "isn't responding"
  /// notice and the state the probe measured.
  ///
  /// Plex and Jellyfin entries have no stored refresh chain to retry
  /// ([MultiServerManager.retryPleyaServerAuth] answers null for them), so
  /// they go straight to the sign-in screen, which is what this button always
  /// did for them.
  Future<void> _retryThenReauth(BuildContext context, List<({ServerId serverId, String displayName})> entries) async {
    setState(() => _retrying = true);
    var needsSignIn = false;
    var unreachable = false;
    try {
      final manager = context.read<MultiServerProvider>().serverManager;
      for (final entry in entries) {
        final health = await manager.retryPleyaServerAuth(entry.serverId);
        if (health == null || health == HealthStatus.authError) {
          needsSignIn = true;
        } else if (health == HealthStatus.offline) {
          unreachable = true;
        }
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    if (!context.mounted) return;
    if (needsSignIn) {
      await _openReauth(context);
    } else if (unreachable) {
      showErrorSnackBar(context, t.notices.connectionFailedBody(serverName: entries.first.displayName));
    }
    // A retry that came back online needs nothing more: _applyHealth already
    // cleared the auth-error state and this banner rebuilds itself away.
  }

  Future<void> _openReauth(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddConnectionScreen()));
  }
}
