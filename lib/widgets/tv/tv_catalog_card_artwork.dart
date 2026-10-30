/// What sits on a catalog card's artwork: the 2:3 box itself and the marks it
/// carries. Split out of `tv_catalog_card.dart` unchanged when the compact card
/// of A-06c needed the same box under a different footer and focus treatment.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_catalog_artwork_window.dart';
import 'tv_unified_layout.dart';

/// The artwork box: image or fill, focus lift, markers and the resume bar.
class TvCatalogArtworkBox extends StatelessWidget {
  const TvCatalogArtworkBox({
    super.key,
    required this.scale,
    required this.isFocused,
    required this.artwork,
    required this.topLeftMarker,
    required this.topRightMarker,
    required this.bottomLeftMarker,
    required this.progressFraction,
    required this.aspectRatio,
    required this.overlay,
  });

  final double aspectRatio;
  final Widget? overlay;
  final double scale;
  final bool isFocused;
  final Widget artwork;
  final Widget? topLeftMarker;
  final Widget? topRightMarker;
  final Widget? bottomLeftMarker;
  final double? progressFraction;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final inset = TvCatalogLayout.badgeInset * scale;
    final fraction = progressFraction;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // CAT18: a card far from the grid's focus draws the fill instead, so
          // it does not keep a decoded poster alive. See the window file.
          if (TvCatalogArtworkScope.drawsArtwork(context)) artwork else const TvCatalogArtworkFill(),
          // Above the image and below every marker, so the poster brightens but
          // the badges keep the contrast they were measured for. The content
          // itself answers the remote, rather than only the chrome around it.
          AnimatedOpacity(
            duration: tk.fast,
            opacity: isFocused ? 1 : 0,
            child: ColoredBox(color: Colors.white.withValues(alpha: TvCatalogLayout.cardFocusArtworkLift)),
          ),
          if (overlay != null) Positioned(left: 0, right: 0, bottom: 0, child: overlay!),
          if (topLeftMarker != null) Positioned(top: inset, left: inset, child: topLeftMarker!),
          if (topRightMarker != null) Positioned(top: inset, right: inset, child: topRightMarker!),
          if (bottomLeftMarker != null) Positioned(bottom: inset, left: inset, child: bottomLeftMarker!),
          if (fraction != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TvCatalogResumeBar(fraction: fraction, scale: scale),
            ),
        ],
      ),
    );
  }
}

/// The placeholder fill a poster sits on while its image loads or fails.
///
/// A widget rather than a colour constant, because every caller needs the same
/// two-layer composition — fill, then image — and one of them getting it wrong
/// shows up as a card that flashes black between pages.
class TvCatalogArtworkFill extends StatelessWidget {
  const TvCatalogArtworkFill({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return ColoredBox(
      color: tk.text.withValues(alpha: TvCatalogLayout.artworkPlaceholderFill),
      child: child,
    );
  }
}

/// Hoofdstuk 10.3's dark capsule on the artwork: "2 bronnen", "Niet
/// beschikbaar", "In afwachting".
///
/// Two shapes, one widget. The default is the small rounded rectangle the
/// source badge has always been; [TvCatalogArtworkBadge.status] is the pill
/// with a coloured dot DEC-108 gives an aanvraag, where the dot carries the
/// state and the word says what it is. They share a fill and a type ramp on
/// purpose: a viewer should read them as the same kind of mark, and a second
/// capsule style on the same artwork is how a grid stops looking like one grid.
class TvCatalogArtworkBadge extends StatelessWidget {
  const TvCatalogArtworkBadge({super.key, required this.label, this.muted = false}) : dotColor = null;

  const TvCatalogArtworkBadge.status({super.key, required this.label, required this.dotColor, this.muted = true});

  final String label;

  /// Non-null draws the pill form with this dot in front of the label.
  final Color? dotColor;

  /// Whether the label reads one step below full ink.
  ///
  /// The source count does not: it is a fact about the title and the mockups
  /// give it the page's own ink. A state does, except the one that is good news
  /// — mockup 35's "Beschikbaar" is the single capsule drawn at full ink, so it
  /// separates from the waiting ones without needing a second shape.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final dot = dotColor;
    final ink = muted ? Colors.white.withValues(alpha: TvCatalogLayout.badgeInkMuted) : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: TvCatalogLayout.badgeFill),
        borderRadius: BorderRadius.circular(
          (dot == null ? TvCatalogLayout.badgeRadius : TvCatalogLayout.badgePillRadius) * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal:
              (dot == null ? TvCatalogLayout.badgePaddingHorizontal : TvCatalogLayout.badgePillPaddingHorizontal) *
              scale,
          vertical: TvCatalogLayout.badgePaddingVertical * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: TvCatalogLayout.badgeDotSize * scale,
                height: TvCatalogLayout.badgeDotSize * scale,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              SizedBox(width: TvCatalogLayout.badgeDotGap * scale),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.badgeFontSize * scale,
                fontWeight: FontWeight.w600,
                // White rather than the theme ink: this capsule sits on artwork,
                // and in the light theme the theme ink is near-black over a
                // black capsule.
                color: ink,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The watched marker, as a capsule on the artwork.
///
/// Same dark capsule as the source badge rather than a bare glyph: a white tick
/// laid straight onto artwork disappears into a bright poster, and this is the
/// one marker that has to be readable across every image in the grid.
class TvCatalogWatchedBadge extends StatelessWidget {
  const TvCatalogWatchedBadge({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: TvCatalogLayout.badgeFill),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: EdgeInsets.all(TvCatalogLayout.watchedBadgePadding * scale),
        child: Icon(
          Symbols.check_rounded,
          size: TvCatalogLayout.watchedIconSize * scale,
          // White, like the badge beside it: both sit on artwork, where the
          // theme's ink is the wrong colour in light mode.
          color: Colors.white,
        ),
      ),
    );
  }
}

/// The resume bar along the artwork's bottom edge.
///
/// Brand red, which is one of the four things hoofdstuk 8.2 and 34 allow red to
/// be used for. Drawn as two boxes rather than through `MediaProgressBar`
/// because it has to sit flush in the artwork's clip with no radius and no
/// track inset — the shared bar is a rounded, padded control for list rows.
class TvCatalogResumeBar extends StatelessWidget {
  const TvCatalogResumeBar({super.key, required this.fraction, required this.scale});

  final double fraction;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return SizedBox(
      height: TvCatalogLayout.progressBarHeight * scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: ColoredBox(color: tk.accent),
          ),
        ],
      ),
    );
  }
}
