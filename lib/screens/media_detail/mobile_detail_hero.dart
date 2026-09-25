import 'package:flutter/material.dart';

import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/glass/glass_text.dart';
import '../../theme/mono_tokens.dart';

/// Hero height as a fraction of the screen height (LG-02).
const double kMobileDetailHeroFraction = 0.62;

/// The scrim over the hero artwork: a light band under the status bar and
/// the glass circles, clear through the middle of the picture, then dark
/// under the title, chips and buttons, ending on the page colour [bg] so the
/// hero runs into the page without a seam. The dark stops are black rather
/// than [bg]: the text on them is always white, also in the light theme.
BoxDecoration mobileDetailHeroScrim(Color bg) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.black.withValues(alpha: 0.35),
      Colors.transparent,
      Colors.black.withValues(alpha: 0.35),
      Colors.black.withValues(alpha: 0.75),
      bg,
    ],
    stops: const [0, 0.2, 0.55, 0.8, 1],
  ),
);

/// The film-page hero with Liquid Glass on (mockup LG-02): the artwork over
/// the full width behind the status bar, at least [kMobileDetailHeroFraction]
/// of the screen high, with [title], [chips] and [actions] on the scrim at the
/// bottom and [leading]/[trailing] floating at the top. Grows past that
/// height instead of clipping when a long title wraps.
class MobileDetailHero extends StatelessWidget {
  const MobileDetailHero({
    super.key,
    required this.artwork,
    required this.title,
    required this.chips,
    required this.leading,
    this.trailing = const [],
    required this.actions,
    @visibleForTesting this.debugTransparentForeground = false,
  });

  final Widget artwork;
  final String title;
  final List<String> chips;
  final Widget leading;
  final List<Widget> trailing;
  final Widget actions;

  /// Title and chip labels painted transparent (shadows kept), so the
  /// contrast test can read the background under them; see
  /// `textContrastOverBackground`.
  final bool debugTransparentForeground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final foreground = debugTransparentForeground ? Colors.transparent : Colors.white;

    return Stack(
      children: [
        Positioned.fill(child: artwork),
        Positioned.fill(child: DecoratedBox(decoration: mobileDetailHeroScrim(tokens(context).bg))),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: mq.size.height * kMobileDetailHeroFraction),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, mq.padding.top + 72, 16, 24),
            child: Column(
              mainAxisAlignment: .end,
              crossAxisAlignment: .stretch,
              children: [
                Text(
                  title,
                  maxLines: 3,
                  overflow: .ellipsis,
                  style: glassText(
                    theme.textTheme.headlineMedium!.copyWith(fontWeight: .w800, color: foreground, height: 1.1),
                  ),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final c in chips) _HeroChip(c, color: foreground)]),
                ],
                const SizedBox(height: 20),
                actions,
              ],
            ),
          ),
        ),
        Positioned(
          top: mq.padding.top + 8,
          left: 16,
          right: 16,
          child: GlassLayer(child: Row(children: [leading, const Spacer(), ...trailing])),
        ),
      ],
    );
  }
}

/// Outlined tag on the scrim (year, rating, duration, quality), LG-02.
class _HeroChip extends StatelessWidget {
  const _HeroChip(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: glassText(TextStyle(color: color, fontSize: 14, fontWeight: .w700)),
        ),
      ),
    );
  }
}

/// A round glass button (back, more, watchlist) with a white glyph.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.foregroundColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null ? foregroundColor.withValues(alpha: 0.4) : foregroundColor;
    return GlassSurface(
      shape: const CircleBorder(),
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: color, size: 24, shadows: kGlassIconShadows),
        ),
      ),
    );
  }
}

/// A full-width glass capsule. [prominent] is the white Resume plate with a
/// black label; otherwise the dark phone plate with a white, shadowed label.
class GlassCapsuleButton extends StatelessWidget {
  const GlassCapsuleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
    this.foregroundColor,
  });

  static const double height = 52;

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? (prominent ? Colors.black : Colors.white);
    final shadows = prominent ? null : kGlassTextShadows;
    final surface = GlassSurface(
      shape: const StadiumBorder(),
      prominent: prominent,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: fg, shape: const StadiumBorder()),
          icon: Icon(icon, color: fg, shadows: shadows),
          label: Text(
            label,
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(color: fg, fontSize: 17, fontWeight: .w700, shadows: shadows),
          ),
        ),
      ),
    );
    // On the real tier a plate takes its tint from the nearest layer, so the
    // white plate needs a layer of its own next to the dark ones.
    return prominent ? GlassLayer(tokens: const GlassTokens.prominent(), child: surface) : surface;
  }
}
