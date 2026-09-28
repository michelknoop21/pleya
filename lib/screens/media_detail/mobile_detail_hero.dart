import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/glass/glass_text.dart';

/// The glass back/more row over the detail page (LG-02). The page pins it
/// above its scroll view, so it stays on screen when the hero scrolls away
/// (final review B5); place it at the top of a [Stack]. As
/// [collapseProgress] goes from 0 to 1 the bar fades in an opaque background
/// with [title] centred (D-03b). The page has no cheap source for the poster's
/// tone, so the background is the theme's `surface`.
class MobileDetailHeroBar extends StatelessWidget {
  const MobileDetailHeroBar({
    super.key,
    required this.leading,
    this.trailing = const [],
    this.title = '',
    this.collapseProgress = 0,
  });

  final Widget leading;
  final List<Widget> trailing;
  final String title;
  final double collapseProgress;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final scheme = Theme.of(context).colorScheme;
    final progress = collapseProgress.clamp(0.0, 1.0);
    final bar = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: progress,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: const Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
                ),
              ),
            ),
          ),
        ),
        // Only once it shows: the hero already carries the title for
        // screen readers.
        if (progress > 0)
          Positioned(
            top: top,
            bottom: 0,
            left: 68,
            right: 68,
            child: IgnorePointer(
              child: Opacity(
                opacity: progress,
                child: ExcludeSemantics(
                  child: Center(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(color: scheme.onSurface, fontSize: 17, fontWeight: .w700),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 8, 16, 8),
          child: GlassLayer(child: Row(children: [leading, const Spacer(), ...trailing])),
        ),
      ],
    );
    if (progress == 0) return bar;
    // Status bar content that reads on the bar once it shows.
    final dark = ThemeData.estimateBrightnessForColor(scheme.surface) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: bar,
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
          style: TextButton.styleFrom(foregroundColor: fg),
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
