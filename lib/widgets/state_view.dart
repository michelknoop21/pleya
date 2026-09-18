import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';
import '../theme/mono_tokens.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';

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
///
/// ## SYS-4: scales itself on TV, does not delegate
///
/// `StateView` is called from roughly ten screens (discover, downloads,
/// search, watchlist, the four Seerr screens, the detail episode list) with a
/// mix of `compact`, custom icons/colors and optional retry actions.
/// `TvCatalogEmptyState` (`widgets/tv/tv_catalog_empty_state.dart`) is the
/// existing TV-scaled pattern for this shape, but it is fixed to the
/// catalog's needs: no `compact` mode, no per-caller icon color, and its
/// action button carries CAT5 rail-navigation hooks these callers don't use.
/// Making it generic enough for every `StateView` caller would turn it into a
/// second do-everything widget, which is the "vierde lege-staat-widget" the
/// spec forbids. So `StateView` reads `PlatformDetector.isTV()` and
/// `TvLayoutConstants.scaleOf` itself and scales its own constants; off TV,
/// [_tvFactor] is `1.0` and nothing changes.
///
/// The literal SYS-4 defect is that `StateView` never read the TV scale at
/// all: the same 48/32px icon rendered whether the TV's logical panel
/// matched the 1080 reference or was far taller or shorter, exactly as if it
/// were a phone. The fix gives it the same panel-size responsiveness
/// `TvCatalogEmptyState` already has (`scaleOf`, clamped between 0.85 and
/// 1.35). It deliberately does **not** copy `TvCatalogEmptyState`'s 42px
/// icon. That value is mockup-approved for one specific role: a small
/// affordance sitting inline next to a catalog's own chrome (filters, a
/// page title, potentially a rail). `StateView`'s non-`compact` default is
/// used almost everywhere as the opposite: a fullscreen placeholder with
/// nothing else on screen to anchor against (see the consumer inventory in
/// `task-5-report.md`), so it keeps its own base size rather than one tuned
/// for a different widget's different job. `compact` is the one `StateView`
/// mode that genuinely plays `TvCatalogEmptyState`'s inline role (used only
/// for a section embedded in `media_detail_screen`'s episode list, next to
/// the rest of the detail page), and its base size (32) already sits close
/// to that reference without needing to match it exactly.
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

  /// `TvLayoutConstants.scaleOf` alone, no extra multiplier: fix-round 1
  /// removed an earlier flat `2.0` factor that had no basis beyond "the
  /// audit called the old constants too small" and didn't hold up against
  /// `TvCatalogEmptyState.iconSize` (42, a mockup-approved value for a
  /// different, inline role, see the class doc above). Off TV this is
  /// `1.0`, so nothing changes there.
  double _tvFactor(BuildContext context) => PlatformDetector.isTV() ? TvLayoutConstants.scaleOf(context) : 1.0;

  double? _scaledFontSize(double? base, double factor) => base == null ? null : base * factor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTitle = _resolvedTitle();
    final resolvedMessage = _resolvedMessage();
    final resolvedRetryLabel = retryLabel ?? t.common.retry;
    // The app theme always installs [MonoTokens]; fall back to theme-derived
    // values so a bare [MaterialApp] (e.g. in widget tests) doesn't crash.
    final mono = theme.extension<MonoTokens>();
    final factor = _tvFactor(context);
    final space = (mono?.space ?? 12.0) * factor;
    final radiusSm = mono?.radiusSm ?? 8.0;
    final text = mono?.text ?? theme.colorScheme.onSurface;
    final textMuted = mono?.textMuted ?? theme.colorScheme.onSurfaceVariant;
    final surfaceElevated = mono?.surfaceElevated ?? theme.colorScheme.surfaceContainerHighest;
    final iconSize = (compact ? 32.0 : 48.0) * factor;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: text,
      fontSize: _scaledFontSize(theme.textTheme.titleMedium?.fontSize, factor),
    );
    final messageStyle = theme.textTheme.bodyMedium?.copyWith(
      color: textMuted,
      fontSize: _scaledFontSize(theme.textTheme.bodyMedium?.fontSize, factor),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize, color: textMuted),
        SizedBox(height: space),
        Text(resolvedTitle, textAlign: TextAlign.center, style: titleStyle),
        if (resolvedMessage != null) ...[
          SizedBox(height: space / 2),
          Text(resolvedMessage, textAlign: TextAlign.center, style: messageStyle),
        ],
        if (onRetry != null) ...[
          SizedBox(height: space * 1.5),
          FocusableButton(
            onPressed: onRetry,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20 * factor, vertical: 12 * factor),
              decoration: BoxDecoration(color: surfaceElevated, borderRadius: BorderRadius.circular(radiusSm)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.refresh_rounded, size: 18 * factor, color: text),
                  SizedBox(width: 8 * factor),
                  Text(
                    resolvedRetryLabel,
                    style: TextStyle(
                      color: text,
                      fontWeight: FontWeight.w600,
                      fontSize: (DefaultTextStyle.of(context).style.fontSize ?? 14.0) * factor,
                    ),
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
