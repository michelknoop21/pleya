import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';

/// The Pleya lockup — the "P" mark and the "LEYA" lettering — as one widget.
///
/// ## Two layers, because the two halves answer to different authorities
///
/// The mark is the brand: red, amber speed lines, and a counter that is an
/// actual hole rather than painted shut, so whatever surface it sits on shows
/// through it. None of that follows the theme, and none of it may be tinted
/// away (hoofdstuk 8.2 keeps Pleya red for brand details).
///
/// The lettering is lettering. On a dark surface it is white; on the light
/// palette white lands at 1,12:1 against the page ground and the word simply
/// is not there — that was register row J18. So the lettering takes the theme's
/// ink where the lockup sits on a themed surface, and keeps its own white where
/// the surface is fixed.
///
/// One image cannot do both, so `scripts/gen_brand_assets.py` emits the lockup
/// as two layers on one shared canvas. Drawn into the same rect they reproduce
/// the canonical lockup exactly — the invariant
/// `test/assets/brand_wordmark_layers_test.dart` holds.
///
/// ## One path, not a light/dark fork
///
/// Both palettes come through here. An earlier version drew a single undivided
/// asset on dark and only composited on light, to keep dark goldens
/// byte-identical; refreshing the mark moved those goldens anyway, so that
/// reason is gone and with it the second code path ([DEC-074]).
///
/// ## Sizing
///
/// Callers give an intended visual **height** and the lockup keeps its own
/// aspect. Nothing here depends on the canvas being any particular width —
/// composing the mark from `pleya_mark.png` made it wider than the file it
/// replaced, and a caller that had pinned a width would have silently squashed
/// or cropped it.
class PleyaWordmark extends StatelessWidget {
  const PleyaWordmark({super.key, required this.height, this.letteringColor});

  /// The intended visual height of the lockup.
  final double height;

  /// The ink the lettering takes.
  ///
  /// `null` is the canonical brand presentation: the lettering keeps its own
  /// white. Pass a colour only where the lockup sits on a themed surface — the
  /// mark is never affected either way.
  final Color? letteringColor;

  /// The brand half. Generated; never tinted.
  static const String markAsset = 'assets/branding/pleya_wordmark_mark.png';

  /// The lettering half. Generated; tinted by [letteringColor] when given.
  static const String letteringAsset = 'assets/branding/pleya_wordmark_text.png';

  /// Both layers, so a caller that needs them decoded before it paints (a
  /// golden, a splash) can precache without naming the asset strings itself.
  static const List<String> assets = [markAsset, letteringAsset];

  Widget _layer(String asset, {Color? color}) => Image.asset(
    asset,
    height: height,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    color: color,
    // srcIn keeps each pixel's alpha and replaces only its colour, so the
    // glyph antialiasing survives the tint.
    colorBlendMode: color == null ? null : BlendMode.srcIn,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          _layer(markAsset),
          _layer(letteringAsset, color: letteringColor),
        ],
      ),
    );
  }
}

/// The height both idents draw the lockup at. `340` logical pixels of *width*
/// on the old 1452x659 asset worked out to this, and keeping the height is what
/// keeps the ident the same size now that the lockup is composed from
/// `pleya_mark.png` and wider than the file it replaced.
const double kIdentLockupHeight = 154.3;

/// The ground the idents play on. Permanently dark — that is what lets the
/// lettering keep its own white without an ink override ([DEC-074]) — and the
/// same ground the app lands on, so the ident dissolves into a page of the
/// same colour instead of stepping from black. Dark and OLED read their own
/// `bg`; the light theme still gets the dark palette's, because the ident is
/// not a themed surface.
Color identGround(BuildContext context) {
  final tk = Theme.of(context).extension<MonoTokens>();
  if (tk == null || tk.isLight) return const Color(0xFF141414);
  return tk.bg;
}

/// The lockup with its tagline, at the proportions `scripts/gen_brand_assets.py`
/// gives the Top Shelf, the Android TV banner and the OG image
/// (`lockup(tagline=True)`). One spec for every large-format brand moment, so
/// the ident on screen is the same picture as the one on the shelf.
///
/// Canonical presentation only — no ink override. Both consumers sit on
/// [identGround], where the lettering's own white is the right ink.
class PleyaBrandLockup extends StatelessWidget {
  const PleyaBrandLockup({super.key, required this.height, this.taglineOpacity = 1});

  /// The lockup height; the tagline and the gap derive from it.
  final double height;

  /// Lets an ident bring the tagline in after the mark, without a second
  /// opacity layer over the lockup itself.
  final double taglineOpacity;

  static const String tagline = 'YOUR MEDIA. YOUR WAY.';

  // The generator's own numbers, so the picture here and the one it renders
  // cannot drift apart: `tagline_image(int(wd.height * 0.12))`, tracking
  // `px * 0.30`, gap `int(wd.height * 0.12)`, ink `(255, 255, 255, 102)`.
  static const double taglineHeightFraction = 0.12;
  static const double taglineTrackingFraction = 0.30;
  static const double taglineGapFraction = 0.12;
  static const double taglineAlpha = 102 / 255;

  @override
  Widget build(BuildContext context) {
    final size = height * taglineHeightFraction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PleyaWordmark(height: height),
        SizedBox(height: height * taglineGapFraction),
        Opacity(
          opacity: taglineOpacity,
          child: Text(
            tagline,
            style: TextStyle(
              // Inter Medium — the face the generator rasterises the tagline in.
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: size,
              letterSpacing: size * taglineTrackingFraction,
              // White on purpose: canonical brand ink on the permanently dark
              // ident ground, not a themed surface.
              color: Colors.white.withValues(alpha: taglineAlpha),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}
