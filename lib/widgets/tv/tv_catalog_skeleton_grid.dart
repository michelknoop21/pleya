/// What the Films/Series page looks like before the first round of results
/// lands (hoofdstuk 29 of docs/tvos-unified-experience.md).
///
/// Extracted from `tv_unified_catalog_screen.dart` unchanged when CAT5 gave
/// that screen a rail to wire: a placeholder that reproduces the grid's own
/// geometry is a second responsibility, and the screen was over the size
/// guideline in CLAUDE.md before it grew again.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart';

/// Finds the loading placeholder. Public so a test can assert *which* waiting
/// state is on screen rather than merely that the grid is absent.
const Key tvCatalogSkeletonKey = ValueKey('tvCatalogSkeleton');

/// What the page looks like before the first round of results lands.
///
/// A centred spinner on an otherwise empty page was the first build, and it is
/// the one frame that undoes the rest: the user presses Films and gets a black
/// screen with a small red circle in it, then the catalogue appears all at
/// once. Nothing about it says a wall of posters is coming.
///
/// So the placeholder is the page, on the page's own geometry —
/// [TvCatalogGrid.forWidth] is the same call the real grid makes, so the
/// columns, the card width, the gutter and the outer inset are not
/// approximated here, they are identical. The posters resolve in place instead
/// of replacing something shaped differently, and the first thing the eye is
/// given is the layout it is about to read.
///
/// Deliberately still. A shimmer is the reflex, and it would cost the goldens
/// their determinism — `pumpAndSettle` never returns under a repeating
/// animation — for motion that a 10-foot surface reads as flicker rather than
/// as progress.
class TvCatalogSkeletonGrid extends StatelessWidget {
  const TvCatalogSkeletonGrid({super.key, this.reservedLeading = 0});

  /// Width held back before the first column, so the placeholder keeps
  /// reproducing the real grid's geometry while CAT5's rail is open. Without
  /// it a catalog that is still loading shows six placeholder columns under a
  /// rail the loaded page will show five under.
  final double reservedLeading;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final grid = TvCatalogGrid.forWidth(
      MediaQuery.sizeOf(context).width,
      scale: scale,
      reservedLeading: reservedLeading,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = TvCatalogLayout.cardContentInset(scale);
        final cardHeight = (grid.cardWidth - inset * 2) / TvCatalogLayout.posterAspectRatio;
        // Enough rows to reach the bottom edge, so the placeholder fills the
        // surface it is standing in for rather than floating in the top half of
        // it. Partly-visible rows count: the real grid has them too.
        final rows = constraints.maxHeight.isFinite
            ? ((constraints.maxHeight + grid.gutter) / (cardHeight + grid.gutter)).ceil().clamp(1, 6)
            : 2;

        // Not a bare ClipRect: the bottom row is meant to run off the edge the
        // way the real grid's does, and a Column that overtops its constraints
        // asserts before anything gets clipped. A scroll view the user cannot
        // scroll gives the Column the unbounded height it needs and clips the
        // result — which is also, structurally, what the real grid is.
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(left: grid.inset + grid.leading, right: grid.inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var row = 0; row < rows; row++) ...[
                  if (row > 0) SizedBox(height: grid.gutter),
                  Row(
                    children: [
                      for (var column = 0; column < grid.columns; column++) ...[
                        if (column > 0) SizedBox(width: grid.gutter),
                        _SkeletonCard(width: grid.cardWidth, scale: scale, mono: mono),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One placeholder card: the poster block and the two text bars under it, on
/// the metrics [TvUnifiedMediaCard] uses for the real thing.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.width, required this.scale, required this.mono});

  final double width;
  final double scale;
  final MonoTokens mono;

  @override
  Widget build(BuildContext context) {
    final barHeight = TvCatalogLayout.cardTitleFontSize * scale;
    final metaHeight = TvCatalogLayout.cardMetaFontSize * scale;

    // The same inset the real card carries, and it is made of two things.
    // `TvUnifiedMediaCard` sizes the *wrapper* to the grid's card width, and
    // inside that wrapper `FocusableWrapper` draws its ring as a border — which
    // costs [FocusTheme.focusBorderWidth] a side whether or not the card has the
    // focus — before the card's own focus-ring gap pads it again. Sizing the
    // placeholder poster to the full column made every poster on screen shrink
    // and shift at the moment the data landed, which is the one frame this
    // placeholder exists to make uneventful. Counting only the gap and not the
    // border left two thirds of that jump in place.
    final inset = TvCatalogLayout.cardContentInset(scale);
    final posterWidth = width - inset * 2;

    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: tvCatalogPosterKey,
              width: posterWidth,
              height: posterWidth / TvCatalogLayout.posterAspectRatio,
              decoration: BoxDecoration(
                color: mono.text.withValues(alpha: TvCatalogLayout.skeletonArtworkFill),
                borderRadius: BorderRadius.circular(TvCatalogLayout.cardRadius * scale),
              ),
            ),
            SizedBox(height: TvCatalogLayout.cardFooterPaddingVertical * scale),
            _SkeletonBar(
              width: posterWidth * TvCatalogLayout.skeletonTitleWidthFraction,
              height: barHeight,
              scale: scale,
              mono: mono,
            ),
            SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale * 2),
            _SkeletonBar(
              width: posterWidth * TvCatalogLayout.skeletonMetaWidthFraction,
              height: metaHeight,
              scale: scale,
              mono: mono,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height, required this.scale, required this.mono});

  final double width;
  final double height;
  final double scale;
  final MonoTokens mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: mono.text.withValues(alpha: TvCatalogLayout.skeletonTextFill),
        borderRadius: BorderRadius.circular(TvCatalogLayout.skeletonBarRadius * scale),
      ),
    );
  }
}
