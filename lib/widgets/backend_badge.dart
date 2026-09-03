import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../media/media_backend.dart';

/// Tiny badge naming the [MediaBackend] an item, library or connection came
/// from (Plex chevron / Jellyfin mark / Pleya P / local folder icon).
///
/// **All four take the ink of the line they sit in** ([DEC-076]): the two SVGs
/// render in `currentColor`, the folder is an `Icon`, and the Pleya P is tinted
/// through `BlendMode.srcIn`. Pass [color] to set that ink, otherwise it is
/// inherited from [DefaultTextStyle] / `IconTheme`. An alpha in [color]
/// survives on every branch, which is what callsites like `MediaCard`'s
/// metadata line rely on.
///
/// This is a *source glyph*, not the app's identity: the brand-red P belongs to
/// [PleyaLogo] and the wordmark. `side_navigation_rail.dart` shows both rules
/// in one screen — a red [PleyaLogo] in the header, a muted badge in the server
/// rows below it.
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
      // The generated `pleya_logo.png`, not the hand-made `pleya_mark.png`
      // source: the source's P sits off-centre on its own canvas and fills only
      // part of it, so at a fixed `size` box it drew smaller and lower than the
      // three glyphs beside it. The generated one is centred and fitted, and is
      // already in the image cache because `PleyaLogo` draws it.
      MediaBackend.pleyaServer => Image.asset(
        'assets/branding/pleya_logo.png',
        width: size,
        height: size,
        // `contain`, not the `Image` default of `scaleDown`: scaleDown refuses
        // to enlarge, so past the asset's own 512px the glyph would stop
        // growing while the two SVGs beside it kept filling their box, and the
        // set would come apart at exactly the sizes where it is most visible.
        fit: BoxFit.contain,
        color: tint,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      ),
      MediaBackend.local => Icon(Symbols.folder_rounded, size: size, fill: 1, color: tint),
    };
  }
}
