/// The billboard's two controls, split from `TvHeroBillboardCarousel`: the CTA
/// capsule and the short segment indicator.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../focus/input_mode_tracker.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/tv_hig.dart';
import '../app_icon.dart';
import 'tv_unified_layout.dart';

/// One CTA. 33.1: a white `▶ Afspelen` capsule and a dark `Meer info` one, and
/// white is reserved for focus — so the secondary pill inverts to white when
/// focused and the primary, already white, gains the ring instead.
class TvHeroPill extends StatefulWidget {
  const TvHeroPill({
    super.key,
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.scale,
    required this.primary,
    required this.onGainedFocus,
    this.progress,
    this.onTap,
    this.minHeight = 0,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final double scale;
  final bool primary;
  final VoidCallback onGainedFocus;

  /// Resume fraction, drawn as a slim bar inside the primary pill when the
  /// featured title has real progress.
  final double? progress;

  /// Set on a touch screen only. On a TV the wrapping `FocusableButton` hears
  /// Select and nothing here takes a pointer.
  final VoidCallback? onTap;

  /// A floor under the ten-foot height, for a finger.
  final double minHeight;

  @override
  State<TvHeroPill> createState() => TvHeroPillState();
}

class TvHeroPillState extends State<TvHeroPill> {
  bool _wasFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final has = widget.focusNode.hasFocus;
    if (has && !_wasFocused) widget.onGainedFocus();
    _wasFocused = has;
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = widget.scale;

    return ListenableBuilder(
      listenable: widget.focusNode,
      builder: (context, _) {
        final showFocus = widget.focusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
        // The primary is white at rest already, so focus cannot be "turn
        // white"; it is the ring. The secondary is dark at rest and inverts.
        final filled = widget.primary || showFocus;
        final bg = filled ? tk.text : tk.text.withValues(alpha: TvHomeLayout.heroSecondaryFillAlpha);
        final fg = filled ? tk.bg : tk.text;

        final height = math.max(TvHomeLayout.heroActionHeight * scale, widget.minHeight);
        final radius = math.max(TvHomeLayout.heroActionRadius * scale, widget.minHeight / 2);
        final motion = reduceMotion(context, FocusTheme.getAnimationDuration(context));

        // VIS-0925-E: one focus contract for the CTAs, the same as every other
        // TV control. The white ring (never `tk.text`, which is black in Light
        // and drew a black-and-white double rim) stands a small clear band
        // outside the fill, with the Light separator line from [FocusTheme],
        // plus the focus scale. The fill itself starts on the text column's
        // x, the halo goes outward.
        final pill = AnimatedScale(
          scale: showFocus ? FocusTheme.focusScale : 1,
          duration: motion,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            key: ValueKey(widget.primary ? 'tvHeroCta.play.fill' : 'tvHeroCta.info.fill'),
            duration: motion,
            curve: Curves.easeOutCubic,
            foregroundDecoration: FocusTheme.shapeFocusRing(
              context,
              isFocused: showFocus,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              // The same clear band as the category rail (D1): in Dark a
              // focused CTA is a white fill, and a white ring against it
              // would vanish without one.
              gap: TvMyPleyaLayout.tileFocusRingGap * TvHig.of(context),
            ),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: TvHomeLayout.heroActionPaddingHorizontal * scale),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: showFocus
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: TvDiscoveryLayout.cardFocusShadowAlpha),
                        blurRadius: TvDiscoveryLayout.cardFocusShadowBlur * scale,
                        offset: Offset(0, TvDiscoveryLayout.cardFocusShadowOffsetY * scale),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(widget.icon, fill: 1, size: TvHomeLayout.heroActionIconSize * scale, color: fg),
                SizedBox(width: TvHomeLayout.heroActionIconLabelGap * scale),
                if (widget.progress != null) ...[
                  Container(
                    width: 40 * scale,
                    height: 4 * scale,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2 * scale),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: widget.progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(2 * scale)),
                      ),
                    ),
                  ),
                  SizedBox(width: TvHomeLayout.heroActionIconLabelGap * scale),
                ],
                Text(
                  widget.label,
                  // VIS-0925-G (DEC-139): the CTA label in Body (29 pt), not 25.
                  style: TextStyle(color: fg, fontSize: TvHig.body * TvHig.of(context), fontWeight: .w600),
                ),
              ],
            ),
          ),
        );
        final onTap = widget.onTap;
        return onTap == null ? pill : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: pill);
      },
    );
  }
}

/// Hoofdstuk 9.6: "Geen permanente reeks kleine webachtige dots. Tijdens
/// handmatig wisselen verschijnt optioneel een korte segmentindicator, die na
/// twee seconden verdwijnt." Segments rather than dots, and excluded from
/// semantics — the slide position is already on the carousel's own label, and
/// announcing eight anonymous bars after it would be noise.
class TvHeroSegmentIndicator extends StatelessWidget {
  const TvHeroSegmentIndicator({super.key, required this.count, required this.active, required this.scale});

  final int count;
  final int active;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: TvHomeLayout.heroSegmentIndicatorGap * scale),
            Container(
              width: TvHomeLayout.heroSegmentIndicatorWidth * scale,
              height: TvHomeLayout.heroSegmentIndicatorHeight * scale,
              decoration: BoxDecoration(
                color: tk.text.withValues(alpha: i == active ? 1 : TvHomeLayout.heroSegmentIndicatorIdleAlpha),
                borderRadius: BorderRadius.circular(TvHomeLayout.heroSegmentIndicatorHeight * scale),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
