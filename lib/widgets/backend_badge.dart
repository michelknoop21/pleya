import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_backend.dart';

/// Tiny badge for a [MediaBackend] (Plex chevron / Jellyfin mark / local folder icon).
/// Both SVG assets render in `currentColor` so they pick up whatever foreground
/// the parent provides — pass [color] to override, otherwise inherits from
/// [DefaultTextStyle] / `IconTheme`.
class BackendBadge extends StatelessWidget {
  final MediaBackend backend;
  final double size;
  final Color? color;

  const BackendBadge({super.key, required this.backend, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    final tint =
        color ??
        DefaultTextStyle.of(context).style.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return switch (backend) {
      MediaBackend.plex => SvgPicture.asset(
        'assets/plex_chevron.svg',
        width: size,
        height: size,
        theme: SvgTheme(currentColor: tint),
      ),
      MediaBackend.jellyfin => SvgPicture.asset(
        'assets/jellyfin_icon.svg',
        width: size,
        height: size,
        theme: SvgTheme(currentColor: tint),
      ),
      MediaBackend.pleyaServer => Image.asset('assets/branding/pleya_mark.png', width: size, height: size),
      MediaBackend.local => Icon(Symbols.folder_rounded, size: size, fill: 1, color: tint),
    };
  }
}
