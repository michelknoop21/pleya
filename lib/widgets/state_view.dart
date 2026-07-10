import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';
import '../theme/mono_tokens.dart';

/// Which named constructor produced this [StateView], so [build] can resolve a
/// localized default title/message when the caller didn't supply one.
enum _StateKind { plain, empty, error, offline }

/// One reusable widget for the empty / error / offline / loading states that
/// were previously hand-rolled per screen. Style comes entirely from
/// [MonoTokens]; the retry action uses [FocusableButton] so it stays reachable
/// with a D-pad on TV.
///
/// Titles, messages and the retry label fall back to localized defaults
/// ([t.states.*], [t.common.retry]) when the caller leaves them null; passing
/// an explicit value keeps identical behavior.
///
/// Use [compact] for inline placement inside a section (smaller icon, no
/// vertical centering pressure); omit it for full-screen placeholders.
class StateView extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final bool compact;
  final _StateKind _kind;

  const StateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
  }) : _kind = _StateKind.plain;

  const StateView.empty({
    super.key,
    this.title,
    this.message,
    this.icon = Symbols.inbox_rounded,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
  }) : _kind = _StateKind.empty;

  const StateView.error({
    super.key,
    this.title,
    this.message,
    this.icon = Symbols.error_rounded,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
  }) : _kind = _StateKind.error;

  const StateView.offline({
    super.key,
    this.title,
    this.message,
    this.icon = Symbols.wifi_off_rounded,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
  }) : _kind = _StateKind.offline;

  String _resolvedTitle() =>
      title ??
      switch (_kind) {
        _StateKind.empty => t.states.emptyTitle,
        _StateKind.offline => t.states.offlineTitle,
        _ => t.states.errorTitle,
      };

  String? _resolvedMessage() => message ?? (_kind == _StateKind.offline ? t.states.offlineMessage : null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTitle = _resolvedTitle();
    final resolvedMessage = _resolvedMessage();
    final resolvedRetryLabel = retryLabel ?? t.common.retry;
    // The app theme always installs [MonoTokens]; fall back to theme-derived
    // values so a bare [MaterialApp] (e.g. in widget tests) doesn't crash.
    final mono = theme.extension<MonoTokens>();
    final space = mono?.space ?? 12.0;
    final radiusSm = mono?.radiusSm ?? 8.0;
    final text = mono?.text ?? theme.colorScheme.onSurface;
    final textMuted = mono?.textMuted ?? theme.colorScheme.onSurfaceVariant;
    final surfaceElevated = mono?.surfaceElevated ?? theme.colorScheme.surfaceContainerHighest;
    final iconSize = compact ? 32.0 : 48.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize, color: textMuted),
        SizedBox(height: space),
        Text(
          resolvedTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: text),
        ),
        if (resolvedMessage != null) ...[
          SizedBox(height: space / 2),
          Text(
            resolvedMessage,
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
                    resolvedRetryLabel,
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
