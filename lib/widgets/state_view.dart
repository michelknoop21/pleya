import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../theme/mono_tokens.dart';

/// One reusable widget for the empty / error / offline / loading states that
/// were previously hand-rolled per screen. Style comes entirely from
/// [MonoTokens]; the retry action uses [FocusableButton] so it stays reachable
/// with a D-pad on TV.
///
/// Use [compact] for inline placement inside a section (smaller icon, no
/// vertical centering pressure); omit it for full-screen placeholders.
class StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool compact;

  const StateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.compact = false,
  });

  const StateView.empty({
    super.key,
    this.title = 'Nothing here yet',
    this.message,
    this.icon = Symbols.inbox_rounded,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.compact = false,
  });

  const StateView.error({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.icon = Symbols.error_rounded,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.compact = false,
  });

  const StateView.offline({
    super.key,
    this.title = 'You\'re offline',
    this.message = 'Reconnect to load this content.',
    this.icon = Symbols.wifi_off_rounded,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The app theme always installs [MonoTokens]; fall back to theme-derived
    // values so a bare [MaterialApp] (e.g. in widget tests) doesn't crash.
    final t = theme.extension<MonoTokens>();
    final space = t?.space ?? 12.0;
    final radiusSm = t?.radiusSm ?? 8.0;
    final text = t?.text ?? theme.colorScheme.onSurface;
    final textMuted = t?.textMuted ?? theme.colorScheme.onSurfaceVariant;
    final surfaceElevated = t?.surfaceElevated ?? theme.colorScheme.surfaceContainerHighest;
    final iconSize = compact ? 32.0 : 48.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize, color: textMuted),
        SizedBox(height: space),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: text),
        ),
        if (message != null) ...[
          SizedBox(height: space / 2),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: textMuted),
          ),
        ],
        if (onRetry != null) ...[
          SizedBox(height: space * 1.5),
          FocusableButton(
            onPressed: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: surfaceElevated, borderRadius: BorderRadius.circular(radiusSm)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.refresh_rounded, size: 18, color: text),
                  const SizedBox(width: 8),
                  Text(
                    retryLabel,
                    style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.all(compact ? space : space * 2),
      child: compact ? content : Center(child: content),
    );
  }
}
