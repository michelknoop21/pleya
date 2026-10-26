import 'package:flutter/material.dart';

import '../utils/platform_detector.dart';
import 'mono_tokens.dart';

/// VIS-0925-C: an unselected Material 3 Switch has a surfaceContainerHighest
/// track and an `outline` rim and thumb. `monoTheme` maps the first onto the
/// surface a settings card or an overlay sheet is painted with, and keeps the
/// outline at 10-12%, so in Light an off switch vanished into its card on the
/// tv. Scoped to TV (review FIX 4): phone and desktop keep Material's switch.
/// Selected and disabled states resolve through the surrounding switch theme,
/// which is Material's own default outside Instellingen.
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
    final theme = Theme.of(context);
    final inherited = theme.switchTheme;
    // Selected and disabled defer to the switch theme around this one, which
    // is Material's default unless a page set its own (the Studio coral
    // inside Instellingen, A-24b).
    Color? offOnly(Set<WidgetState> states, Color color, WidgetStateProperty<Color?>? outer) =>
        states.contains(WidgetState.selected) || states.contains(WidgetState.disabled) ? outer?.resolve(states) : color;
    return Theme(
      data: theme.copyWith(
        switchTheme: inherited.copyWith(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => offOnly(states, t.text.withValues(alpha: t.isLight ? 0.14 : 0.18), inherited.trackColor),
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => offOnly(states, Colors.transparent, inherited.trackOutlineColor),
          ),
          thumbColor: WidgetStateProperty.resolveWith((states) => offOnly(states, t.textMuted, inherited.thumbColor)),
        ),
      ),
      child: child,
    );
  }
}
