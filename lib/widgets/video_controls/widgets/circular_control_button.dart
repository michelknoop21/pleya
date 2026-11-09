import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';

import '../film_frame_palette.dart';
import '../mobile_video_controls_glass.dart';

/// A circular semi-transparent button used in the mobile video controls.
///
/// Renders an [AppIcon] inside an [IconButton] on a black circle with 50%
/// opacity, or a glass circle when Liquid Glass is on. Disabled buttons grey
/// out the icon.
class CircularControlButton extends StatelessWidget {
  final String semanticLabel;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final bool primary;

  const CircularControlButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.iconSize,
    this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final button = Semantics(
      label: semanticLabel,
      button: true,
      enabled: isEnabled,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        icon: AppIcon(
          icon,
          fill: 1,
          color: primary
              ? kFilmInk
              : isEnabled
              ? Colors.white
              : Colors.white.withValues(alpha: 0.3),
          size: iconSize,
        ),
        iconSize: iconSize,
        onPressed: onPressed,
      ),
    );
    final filled = primary
        ? DecoratedBox(
            decoration: BoxDecoration(color: kFilmPrimary, borderRadius: BorderRadius.circular(16)),
            child: button,
          )
        : null;
    return playerGlassSurface(
      const CircleBorder(),
      filled ?? button,
      legacy:
          filled ??
          Container(
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
            child: button,
          ),
    );
  }
}
