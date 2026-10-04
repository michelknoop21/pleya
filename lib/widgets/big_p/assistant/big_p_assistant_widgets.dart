/// Small building blocks of Big P's surface: the glass panel, the dark card
/// that sits on it, the example chip and the "Je vroeg" line.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/glass/glass_settings.dart';
import '../../../theme/glass/glass_surface.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../big_p_scale.dart';

/// Mockup 38 Paneel: the glass panel of LG-04 to LG-06, 800 pt wide. Glass
/// off renders the blurred dark card [TvPanelCard] uses.
class BigPGlassPanel extends StatelessWidget {
  const BigPGlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final radius = BorderRadius.circular(40 * pt);
    final padding = EdgeInsets.all(40 * pt);
    final legacy = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB3202424),
            borderRadius: radius,
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return GlassSurface(
      shape: RoundedRectangleBorder(borderRadius: radius),
      tokens: GlassTokens.tvFor(context, panel: true),
      legacy: legacy,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The dark ground cards keep on the glass, for contrast (Paneel).
class BigPCard extends StatelessWidget {
  const BigPCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xE6161616), borderRadius: BorderRadius.circular(20 * pt)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28 * pt, vertical: 22 * pt),
        child: child,
      ),
    );
  }
}

/// "Je vroeg: …", right-aligned above Big P's answer.
class BigPQuestion extends StatelessWidget {
  const BigPQuestion({super.key, required this.prompt, this.maxLines = 3, this.fill = false});

  final String prompt;

  /// Across the whole balloon, as on iPhone and iPad (39 E to I).
  final bool fill;

  /// One line in the summoned panel, so the results keep the room.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: fill ? double.infinity : null,
        constraints: fill ? null : BoxConstraints(maxWidth: 640 * pt),
        padding: EdgeInsets.symmetric(horizontal: 22 * pt, vertical: 12 * pt),
        decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(16 * pt)),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${t.assistant.youAsked} ',
                style: TextStyle(color: tk.text.withValues(alpha: 0.6)),
              ),
              TextSpan(text: prompt),
            ],
          ),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, height: 1.25),
        ),
      ),
    );
  }
}

/// A status line with a coloured dot ("● Ik luister…").
class BigPStatusLine extends StatelessWidget {
  const BigPStatusLine({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    return Row(
      children: [
        Container(
          width: 12 * pt,
          height: 12 * pt,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 14 * pt),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens(context).text.withValues(alpha: 0.7), fontSize: TvHig.caption2 * pt),
          ),
        ),
      ],
    );
  }
}

/// A full-width focusable capsule: an example question, or anything else
/// that reads as a sentence rather than a button label.
class BigPChip extends StatefulWidget {
  const BigPChip({
    super.key,
    required this.label,
    required this.onSelect,
    this.icon,
    this.dense = false,
    this.fill,
    this.focusNode,
    this.automationId,
    this.automationInstance,
  });

  final String label;
  final VoidCallback onSelect;

  /// The resting fill; a pill floating over the page (39 E) is opaque.
  final Color? fill;

  /// A leading glyph, e.g. the follow-up arrow; examples go without.
  final IconData? icon;

  /// A smaller pill, for a row of follow-ups.
  final bool dense;
  final FocusNode? focusNode;
  final String? automationId;
  final String? automationInstance;

  @override
  State<BigPChip> createState() => _BigPChipState();
}

class _BigPChipState extends State<BigPChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: widget.onSelect,
      behavior: HitTestBehavior.opaque,
      child: FocusableWrapper(
        focusNode: widget.focusNode,
        borderRadius: 40 * pt,
        disableScale: true,
        semanticLabel: widget.label,
        automationId: widget.automationId,
        automationInstance: widget.automationInstance,
        automationRole: 'button',
        onFocusChange: (focused) => setState(() => _focused = focused),
        onSelect: () {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          widget.onSelect();
        },
        child: AnimatedContainer(
          duration: tokens(context).fast,
          padding: widget.dense
              ? EdgeInsets.symmetric(horizontal: 20 * pt, vertical: 10 * pt)
              : EdgeInsets.symmetric(horizontal: 26 * pt, vertical: 14 * pt),
          decoration: BoxDecoration(
            color: _focused ? colors.inverseSurface : widget.fill ?? const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(40 * pt),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon case final icon?) ...[
                Icon(icon, size: 24 * pt, color: _focused ? colors.onInverseSurface : tokens(context).accent),
                SizedBox(width: 10 * pt),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _focused ? colors.onInverseSurface : tokens(context).text,
                    fontSize: (widget.dense ? TvHig.caption2 : TvHig.caption1) * pt,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mockup 38's capsule button at the panel's own size (Caption 1, bold):
/// white when primary or focused, a light tonal fill otherwise. The ring is
/// held off the capsule, as in [TvPanelButton], so a focused white button
/// still shows its ring. [enabled] false keeps it focusable but inert and
/// dimmed (Aanmaken before the password, 38 H).
class BigPButton extends StatefulWidget {
  const BigPButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
    this.icon,
    this.focusNode,
    this.automationId,
    this.automationInstance,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool enabled;
  final IconData? icon;
  final FocusNode? focusNode;
  final String? automationId;
  final String? automationInstance;

  @override
  State<BigPButton> createState() => _BigPButtonState();
}

class _BigPButtonState extends State<BigPButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final colors = Theme.of(context).colorScheme;
    final white = widget.enabled && (widget.primary || _focused);
    final ink = white ? colors.onInverseSurface : tokens(context).text;
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: widget.enabled ? widget.onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: FocusableWrapper(
        focusNode: widget.focusNode,
        borderRadius: 40 * pt,
        disableScale: true,
        semanticLabel: widget.label,
        automationId: widget.automationId,
        automationInstance: widget.automationInstance,
        automationRole: 'button',
        automationState: () => {'enabled': widget.enabled},
        onFocusChange: (focused) => setState(() => _focused = focused),
        onSelect: () {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          if (widget.enabled) widget.onPressed();
        },
        child: Padding(
          padding: EdgeInsets.all(6 * pt),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: tokens(context).fast,
              padding: EdgeInsets.symmetric(horizontal: 30 * pt, vertical: 14 * pt),
              decoration: BoxDecoration(
                color: white ? colors.inverseSurface : const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(40 * pt),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                // Centred when the button is given a width (39 G).
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: TvHig.caption1 * pt, color: ink),
                    SizedBox(width: 12 * pt),
                  ],
                  // Wraps rather than overflows when the button is given less
                  // width than its label (an iPhone SE balloon).
                  Flexible(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ink, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
