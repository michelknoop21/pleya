import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';

import '../film_frame_palette.dart';
import '../mobile_video_controls_glass.dart';

/// A round button used in the mobile video controls.
///
/// Renders an [AppIcon] inside an [IconButton] on the Filmbeeld disc
/// ([kFilmDisc]), or a glass circle when Liquid Glass is on. Disabled buttons
/// grey out the icon. [dimension], when set, fixes the outer size (mockup A:
/// 68 pt play, 52 pt skip) instead of deriving it from the icon.
class CircularControlButton extends StatelessWidget {
  final String semanticLabel;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final bool primary;
  final double? dimension;

  const CircularControlButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.iconSize,
    this.onPressed,
    this.primary = false,
    this.dimension,
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
        padding: dimension == null ? null : EdgeInsets.zero,
        constraints: dimension == null ? null : BoxConstraints.tight(Size.square(dimension!)),
        onPressed: onPressed,
      ),
    );
    final filled = primary
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: kFilmPrimary,
              // Mockup A: a 24% corner on the play square.
              borderRadius: BorderRadius.circular(dimension == null ? 16 : dimension! * 0.24),
            ),
            child: button,
          )
        : null;
    return playerGlassSurface(
      const CircleBorder(),
      filled ?? button,
      legacy:
          filled ??
          Container(
            decoration: const BoxDecoration(color: kFilmDisc, shape: BoxShape.circle),
            child: button,
          ),
    );
  }
}
