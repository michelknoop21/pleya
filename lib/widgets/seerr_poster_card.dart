import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/card_focus_scope.dart';
import '../focus/focus_theme.dart';
import '../focus/focusable_wrapper.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_constants.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/platform_detector.dart';
import 'pressable.dart';
import 'seerr_status_badge.dart';
import 'tv_browse_rail.dart';

/// Poster dimensions shared by every seerr surface (discover rows, grid, search
/// fallback, recommendations). TV gets slightly larger touch/focus targets.
double get seerrPosterWidth => PlatformDetector.isTV() ? 150 : 120;
double get seerrPosterHeight => seerrPosterWidth * 3 / 2; // TMDB posters are 2:3.

/// Density-aware poster size: follows the Settings → Appearance size slider
/// (`libraryDensity`) via the same [GridSizeCalculator] the native grids use, so
/// seerr horizontal rows scale with the rest of the app instead of a fixed size.
double seerrPosterWidthOf(BuildContext context) =>
    GridSizeCalculator.getMaxCrossAxisExtent(context, SettingsService.instance.read(SettingsService.libraryDensity));

/// Width of a seerr poster card inside a horizontal row, sized like the rest of
/// the home screen so seerr shelves don't render oversized. [availableWidth] must
/// be the row's real width (from a LayoutBuilder). The home screen uses two
/// different renderers, so match whichever is active: on TV the Netflix-style
/// [TvBrowseRail] (via [TvBrowseRailLayout.tallPosterCardWidth]); elsewhere the
/// `HubSection` rows (via [GridSizeCalculator.getCellWidth]).
double seerrRowCardWidthOf(BuildContext context, double availableWidth) {
  final density = SettingsService.instance.read(SettingsService.libraryDensity);
  if (PlatformDetector.isTV()) {
    return TvBrowseRailLayout.tallPosterCardWidth(
      viewportSize: MediaQuery.sizeOf(context),
      availableWidth: availableWidth,
      density: density,
    );
  }
  return GridSizeCalculator.getCellWidth(availableWidth, context, density);
}

/// Layout metrics for a horizontal seerr poster row. On TV the focused card
/// scales up ([FocusTheme.focusScale]) and draws a focus ring, so the row must
/// budget headroom above/below the card and a wider gap between cards —
/// otherwise the scaled card clips against the row bounds and paints over its
/// neighbours. [FocusableWrapper] scales the whole card (poster + text block),
/// so the reserve is computed from the full card height.
class SeerrRowMetrics {
  const SeerrRowMetrics({
    required this.cardWidth,
    required this.cardHeight,
    required this.focusReserve,
    required this.itemGap,
    required this.rowHeight,
  });

  /// Width of one card (same value as [seerrRowCardWidthOf]).
  final double cardWidth;

  /// Full card height: 2:3 poster plus the [seerrCardTextExtent] text block.
  final double cardHeight;

  /// Vertical headroom per side for the focus-scaled card + ring (0 off-TV).
  final double focusReserve;

  /// Gap between cards; wide enough on TV that the scaled card + ring never
  /// overlaps its neighbour. Plain 12 off-TV.
  final double itemGap;

  /// Total row height: [cardHeight] plus the reserve on both sides.
  final double rowHeight;
}

/// Computes the row metrics for the given available width — see
/// [SeerrRowMetrics]. Use this instead of a bare [seerrRowCardWidthOf] +
/// hardcoded gap/height wherever seerr cards live in a horizontal row.
SeerrRowMetrics seerrRowMetricsOf(BuildContext context, double availableWidth) {
  final cardWidth = seerrRowCardWidthOf(context, availableWidth);
  final cardHeight = cardWidth * 3 / 2 + seerrCardTextExtent;
  final isTv = PlatformDetector.isTV();
  final focusReserve = isTv ? cardHeight * (FocusTheme.focusScale - 1) / 2 + FocusTheme.focusBorderWidth : 0.0;
  final itemGap = isTv ? cardWidth * (FocusTheme.focusScale - 1) / 2 + FocusTheme.focusBorderWidth : 12.0;
  return SeerrRowMetrics(
    cardWidth: cardWidth,
    cardHeight: cardHeight,
    focusReserve: focusReserve,
    itemGap: itemGap,
    rowHeight: cardHeight + 2 * focusReserve,
  );
}

/// Fixed height of the text block under every poster (gap + two title lines +
/// year). One shared constant so rows and grids budget identical space and all
/// cards line up — nothing overflows, nothing clips. Add this to
/// [seerrPosterHeight] for the total card height / row height.
const double seerrCardTextExtent = 54;

/// TV: extra top padding above the seerr grid so the first row's focus-scaled
/// card + ring stays inside the sliver's paint bounds. Half the scale overhang
/// of the tallest plausible cell (≈400px → 400 × 0.025 + 2.5 ring), rounded up.
const double seerrGridFocusTopPad = 14;

/// A focusable seerr poster: artwork + availability badge + title/year.
///
/// Extracted from the discover screen so discover, search and the media detail
/// recommendations row all render identical cards. Tapping is left to the
/// caller (usually: open [SeerrMediaDetailScreen]).
class SeerrPosterCard extends StatelessWidget {
  const SeerrPosterCard({super.key, required this.media, required this.onTap, this.width, this.focusNode});

  final SeerrMedia media;
  final VoidCallback onTap;

  /// Override the shared [seerrPosterWidth] (e.g. inside a fixed-size grid).
  final double? width;

  /// Optional external focus node (e.g. so a search field can jump focus onto
  /// the first result card).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final w = width ?? seerrPosterWidthOf(context);
    final h = w * 3 / 2;
    return FocusableWrapper(
      onSelect: onTap,
      focusNode: focusNode,
      borderRadius: t.radiusSm,
      delegateFocusBorder: true,
      semanticLabel: media.title,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CardFocusBorder(
                borderRadius: t.radiusSm,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.radiusSm),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: w,
                        height: h,
                        child: SeerrPosterImage(url: media.posterUrl),
                      ),
                      // Bounded on both sides. With only `left` set the badge
                      // was laid out unconstrained, grew to its intrinsic width
                      // and was then cut off by the ClipRRect at the poster
                      // edge; the label has to shrink instead.
                      if (media.status != SeerrMediaStatus.unknown)
                        Positioned(
                          top: 6,
                          left: 6,
                          right: 6,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: SeerrStatusBadge(status: media.status, compact: true),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Fixed-height text block so every card lines up regardless of a
              // one- or two-line title / present-or-absent year.
              SizedBox(
                height: seerrCardTextExtent - 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, height: 1.1),
                    ),
                    if (media.year != null)
                      Text(
                        media.year!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: t.textMuted, fontSize: 11, height: 1.1),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A poster image with a graceful placeholder for empty/failed URLs.
class SeerrPosterImage extends StatelessWidget {
  const SeerrPosterImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SeerrPosterPlaceholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, _) => const SeerrPosterPlaceholder(),
      errorBuilder: (context, _, _) => const SeerrPosterPlaceholder(),
    );
  }
}

class SeerrPosterPlaceholder extends StatelessWidget {
  const SeerrPosterPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(Symbols.movie_rounded, color: scheme.onSurfaceVariant, size: 32)),
    );
  }
}

/// Trailing focusable tile that loads the next page. Loads on activation and
/// also opportunistically when it gains focus (d-pad reaches the row's end).
class SeerrLoadMoreTile extends StatelessWidget {
  const SeerrLoadMoreTile({super.key, required this.loading, required this.onActivate, this.width});

  final bool loading;
  final VoidCallback onActivate;

  /// Override the shared [seerrPosterWidth] (e.g. inside a fixed-size grid).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = tokens(context).radiusSm;
    final w = width ?? seerrPosterWidthOf(context);
    return FocusableWrapper(
      onSelect: onActivate,
      onFocusChange: (focused) {
        if (focused) onActivate();
      },
      borderRadius: radius,
      delegateFocusBorder: true,
      semanticLabel: t.seerr.loadMore,
      child: Pressable(
        onTap: onActivate,
        child: SizedBox(
          width: w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CardFocusBorder(
                borderRadius: radius,
                child: Container(
                  width: w,
                  height: w * 3 / 2,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: Center(
                    child: loading
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Symbols.add_circle_rounded, color: scheme.onSurfaceVariant, size: 36),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.seerr.loadMore,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
