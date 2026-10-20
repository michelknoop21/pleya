import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Pleya Fly glyph (Playback Handoff, A-23). Follows the surrounding
/// [IconTheme] for size and colour, like a Material Symbol would.
class PleyaFlyIcon extends StatelessWidget {
  static const asset = 'assets/icons/pleya-fly.svg';

  final double? size;
  final Color? color;

  const PleyaFlyIcon({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return SvgPicture.asset(
      asset,
      width: side,
      height: side,
      colorFilter: ColorFilter.mode(color ?? theme.color ?? Theme.of(context).colorScheme.onSurface, BlendMode.srcIn),
    );
  }
}
