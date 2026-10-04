import 'package:flutter/material.dart';

import '../utils/platform_detector.dart';
import 'mono_tokens.dart';

/// VIS-0925-C: an unselected Material 3 Switch has a surfaceContainerHighest
/// track and an `outline` rim and thumb. `monoTheme` maps the first onto the
/// surface a settings card or an overlay sheet is painted with, and keeps the
/// outline at 10-12%, so in Light an off switch vanished into its card on the
/// tv. Scoped to TV (review FIX 4): phone and desktop keep Material's switch.
/// Selected and disabled states resolve to null, Material's own defaults.
///
/// Applied by `TvSettingsDensity` (settings rows) and by the overlay sheet host
/// on TV (the Seerr request, recording options and filter sheets).
class TvSwitchTheme extends StatelessWidget {
  const TvSwitchTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<MonoTokens>();
    if (!PlatformDetector.isTV() || t == null) return child;
    Color? offOnly(Set<WidgetState> states, Color color) =>
        states.contains(WidgetState.selected) || states.contains(WidgetState.disabled) ? null : color;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        switchTheme: theme.switchTheme.copyWith(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => offOnly(states, t.text.withValues(alpha: t.isLight ? 0.14 : 0.18)),
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith((states) => offOnly(states, Colors.transparent)),
          thumbColor: WidgetStateProperty.resolveWith((states) => offOnly(states, t.textMuted)),
        ),
      ),
      child: child,
    );
  }
}
