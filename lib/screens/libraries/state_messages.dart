import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_button.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';

/// Base widget for displaying state messages (empty, error, etc.)
/// Provides a consistent UI pattern for showing icons, messages, and actions
///
/// ## SYS-4: scales itself on TV, does not delegate
///
/// Same reasoning as `StateView` (`widgets/state_view.dart`): callers here
/// (libraries, folder tree, downloads sync rules, profile switch, borrow
/// connection) pass custom `iconSize`, `iconColor`/`textColor`/`subtitleColor`
/// overrides and non-refresh action icons that `TvCatalogEmptyState` has no
/// slot for. Scaling in place keeps every caller's variant working; on TV
/// this reads `PlatformDetector.isTV()` and `TvLayoutConstants.scaleOf` and
/// multiplies its own constants, off TV [_tvFactor] is `1.0`.
///
/// Unlike `StateView`, [iconSize] is a per-caller parameter, not a fixed
/// widget constant: `sync_rules_screen.dart` deliberately passes `80` instead
/// of the `64` default for a more prominent glyph on that one screen.
/// Replacing that with a single fixed TV reference (the way `StateView`
/// reasons about `TvCatalogEmptyState.iconSize`) would erase exactly the
/// per-caller weighting the parameter exists for. So this scales whatever
/// value the caller already chose, which keeps their relative sizing intact
/// on TV while adding the panel-size responsiveness the audit found missing.
class StateMessageWidget extends StatelessWidget {
  /// The main message/title to display
  final String message;

  /// Optional subtitle/description below the message
  final String? subtitle;

  /// Optional icon to display above the message
  final IconData? icon;

  /// Optional size for the icon (default: 64)
  final double iconSize;

  /// Optional color for the icon
  final Color? iconColor;

  /// Optional color for the message text
  final Color? textColor;

  /// Optional color for the subtitle text
  final Color? subtitleColor;

  /// Optional callback for action button
  final VoidCallback? onAction;

  /// Optional label for the action button
  final String? actionLabel;

  /// Optional icon for the action button
  final IconData? actionIcon;

  const StateMessageWidget({
    super.key,
    required this.message,
    this.subtitle,
    this.icon,
    this.iconSize = 64,
    this.iconColor,
    this.textColor,
    this.subtitleColor,
    this.onAction,
    this.actionLabel,
    this.actionIcon,
  });

  /// `TvLayoutConstants.scaleOf` alone, no extra multiplier: see the class
  /// doc above and `StateView._tvFactor` (`widgets/state_view.dart`) for why
  /// fix-round 1's flat `2.0` factor was removed. Off TV this is `1.0`.
  double _tvFactor(BuildContext context) => PlatformDetector.isTV() ? TvLayoutConstants.scaleOf(context) : 1.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final factor = _tvFactor(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.0 * factor),
        child: Column(
          mainAxisAlignment: .center,
          children: [
            if (icon != null) ...[
              AppIcon(
                icon,
                fill: 1,
                size: iconSize * factor,
                color: iconColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              SizedBox(height: 16 * factor),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: textColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: theme.textTheme.titleLarge?.fontSize == null
                    ? null
                    : theme.textTheme.titleLarge!.fontSize! * factor,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: 8 * factor),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
                  fontSize: theme.textTheme.bodyMedium?.fontSize == null
                      ? null
                      : theme.textTheme.bodyMedium!.fontSize! * factor,
                ),
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              SizedBox(height: 24 * factor),
              FocusableButton(
                onPressed: onAction,
                child: FilledButton.icon(
                  onPressed: onAction,
                  icon: AppIcon(actionIcon ?? Symbols.refresh_rounded, fill: 1),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A reusable widget for displaying empty states throughout the app
class EmptyStateWidget extends StatelessWidget {
  /// The message to display
  final String message;

  /// Optional subtitle/description below the message
  final String? subtitle;

  /// Optional icon to display above the message
  final IconData? icon;

  /// Optional size for the icon
  final double iconSize;

  /// Optional callback for action button
  final VoidCallback? onAction;

  /// Optional label for the action button
  final String? actionLabel;

  /// Optional icon for the action button (defaults to a generic add icon)
  final IconData? actionIcon;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.subtitle,
    this.icon,
    this.iconSize = 64,
    this.onAction,
    this.actionLabel,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    return StateMessageWidget(
      message: message,
      subtitle: subtitle,
      icon: icon,
      iconSize: iconSize,
      onAction: onAction,
      actionLabel: actionLabel,
      actionIcon: actionIcon ?? Symbols.add_rounded,
    );
  }
}

/// A reusable widget for displaying error states throughout the app
class ErrorStateWidget extends StatelessWidget {
  /// The error message to display
  final String message;

  /// Optional icon to display above the message
  final IconData? icon;

  /// Optional callback for retry action
  final VoidCallback? onRetry;

  /// Optional label for the retry button
  final String? retryLabel;

  const ErrorStateWidget({super.key, required this.message, this.icon, this.onRetry, this.retryLabel});

  @override
  Widget build(BuildContext context) {
    return StateMessageWidget(
      message: message,
      icon: icon,
      iconColor: Theme.of(context).colorScheme.error,
      textColor: Theme.of(context).colorScheme.error,
      onAction: onRetry,
      actionLabel: retryLabel ?? 'Retry',
      actionIcon: Symbols.refresh_rounded,
    );
  }
}
