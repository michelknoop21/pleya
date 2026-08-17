import 'package:flutter/material.dart';
import '../utils/grid_size_calculator.dart';
import '../focus/focus_theme.dart';
import '../utils/layout_constants.dart';
import 'media_card_metrics.dart';

/// Shared grid delegate configuration for media item grids
/// Maintains consistent aspect ratio and spacing across all media grids.
class MediaGridDelegate {
  /// Creates a standard grid delegate for media items
  ///
  /// Uses [GridSizeCalculator.getMaxCrossAxisExtent] by default.
  /// Set [usePaddingAware] to true to use [GridSizeCalculator.getMaxCrossAxisExtentWithPadding] instead.
  /// Set [useWideAspectRatio] to true to use 16:9 aspect ratio for episode thumbnails.
  /// Set [fullBleedImage] to true when the card is image-only and should not reserve text height.
  /// Pass [maxCrossAxisExtentOverride] to bypass the calculator and the wide-aspect multiplier —
  /// the caller is then responsible for providing a fully-resolved per-cell width.
  static SliverGridDelegateWithMaxCrossAxisExtent createDelegate({
    required BuildContext context,
    required int density,
    bool usePaddingAware = false,
    double horizontalPadding = 16,
    bool useWideAspectRatio = false,
    bool fullBleedImage = false,
    double? maxCrossAxisExtentOverride,
  }) {
    final aspectRatio = aspectRatioFor(useWideAspectRatio: useWideAspectRatio, fullBleedImage: fullBleedImage);
    final spacing = spacingFor(context: context, fullBleedImage: fullBleedImage);

    final maxCrossAxisExtent =
        maxCrossAxisExtentOverride ??
        _maxCrossAxisExtentFor(
          context: context,
          density: density,
          usePaddingAware: usePaddingAware,
          horizontalPadding: horizontalPadding,
          useWideAspectRatio: useWideAspectRatio,
        );

    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCrossAxisExtent,
      childAspectRatio: aspectRatio,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );
  }

  /// Resolves the max cross-axis extent the way [createDelegate] does,
  /// including the 1.8x widening for 16:9 episode thumbnails.
  static double _maxCrossAxisExtentFor({
    required BuildContext context,
    required int density,
    required bool usePaddingAware,
    required double horizontalPadding,
    required bool useWideAspectRatio,
  }) {
    var maxCrossAxisExtent = usePaddingAware
        ? GridSizeCalculator.getMaxCrossAxisExtentWithPadding(context, density, horizontalPadding)
        : GridSizeCalculator.getMaxCrossAxisExtent(context, density);

    // For wide aspect ratio (16:9), increase max extent so items are larger
    // and there are fewer per row (roughly 1.8x wider to maintain similar visual area)
    if (useWideAspectRatio) {
      maxCrossAxisExtent *= 1.8;
    }
    return maxCrossAxisExtent;
  }

  static double spacingFor({required BuildContext context, bool fullBleedImage = false}) {
    final scale = TvLayoutConstants.scaleOf(context);
    if (!fullBleedImage) return GridLayoutConstants.posterGridSpacingForScale(scale);
    return GridLayoutConstants.fullCardGridSpacingForScale(scale);
  }

  /// Aspect of the artwork inside a cell, width over height. Not the same as
  /// [aspectRatioFor], which describes the cell: a standard card also has to
  /// fit a caption under the artwork.
  static double imageAspectRatioFor({bool useWideAspectRatio = false}) => useWideAspectRatio
      ? GridLayoutConstants.episodeThumbnailAspectRatio
      : GridLayoutConstants.fullCardPosterAspectRatio;

  static double aspectRatioFor({bool useWideAspectRatio = false, bool fullBleedImage = false}) {
    if (fullBleedImage) {
      return useWideAspectRatio
          ? GridLayoutConstants.episodeThumbnailAspectRatio
          : GridLayoutConstants.fullCardPosterAspectRatio;
    }

    return useWideAspectRatio ? GridLayoutConstants.episodeGridCellAspectRatio : GridLayoutConstants.posterAspectRatio;
  }
}

/// The grid layout a media grid will render for a given cross-axis extent:
/// column count, cell size, spacing, and the matching delegate.
///
/// Use with `SliverCrossAxisLayoutBuilder` so this is resolved once per
/// width/settings change — never per scroll tick. [columnCount] follows the
/// same formula [SliverGridDelegateWithMaxCrossAxisExtent] uses at layout
/// time (see [GridSizeCalculator.getColumnCount], issue #1288), so d-pad row
/// math and the rendered grid always agree.
class MediaGridGeometry {
  final int columnCount;
  final double itemWidth;
  final double itemHeight;
  final double spacing;

  /// Padding a grid must put around every cell's card. See
  /// [MediaCardMetrics.focusInset]: it is the room a focused card grows into,
  /// and reserving it here is what keeps [spacing] intact under focus.
  final double cellInset;

  final SliverGridDelegateWithMaxCrossAxisExtent delegate;

  const MediaGridGeometry._({
    required this.columnCount,
    required this.itemWidth,
    required this.itemHeight,
    required this.spacing,
    required this.cellInset,
    required this.delegate,
  });

  /// Wraps one cell's card in the focus room this geometry reserved for it.
  /// Grids should build every cell through this, otherwise a focused card
  /// grows straight into the gap next to it.
  Widget insetCell(Widget child) => cellInset <= 0 ? child : Padding(padding: EdgeInsets.all(cellInset), child: child);

  /// Resolves the geometry for a grid laid out in [crossAxisExtent] (the
  /// sliver's width AFTER any wrapping [SliverPadding]).
  ///
  /// [crossAxisExtentForColumnCount], when non-null, computes the column
  /// count from that width instead, and pins the delegate's cell width to the
  /// resulting [itemWidth] — used by the library browse grid so the alpha
  /// jump bar's reservation doesn't repack the grid into fewer columns.
  static MediaGridGeometry resolve({
    required BuildContext context,
    required double crossAxisExtent,
    required int density,
    double? crossAxisExtentForColumnCount,
    bool usePaddingAware = false,
    double horizontalPadding = 16,
    bool useWideAspectRatio = false,
    bool fullBleedImage = false,
  }) {
    final spacing = MediaGridDelegate.spacingFor(context: context, fullBleedImage: fullBleedImage);
    final aspectRatio = MediaGridDelegate.aspectRatioFor(
      useWideAspectRatio: useWideAspectRatio,
      fullBleedImage: fullBleedImage,
    );
    final maxCrossAxisExtent = MediaGridDelegate._maxCrossAxisExtentFor(
      context: context,
      density: density,
      usePaddingAware: usePaddingAware,
      horizontalPadding: horizontalPadding,
      useWideAspectRatio: useWideAspectRatio,
    );

    final columnCount = GridSizeCalculator.getColumnCount(
      crossAxisExtentForColumnCount ?? crossAxisExtent,
      maxCrossAxisExtent,
      crossAxisSpacing: spacing,
    );
    final itemWidth = GridSizeCalculator.getCellWidthForColumnCount(
      crossAxisExtent,
      columnCount,
      crossAxisSpacing: spacing,
    );

    final cellInset = MediaCardMetrics.focusInset(
      itemWidth,
      focusScale: fullBleedImage ? FocusTheme.fullCardFocusScale : FocusTheme.focusScale,
    );

    // A cell that carries a caption is measured, not proportioned: the poster
    // keeps its own aspect and the title and metadata line get exactly the room
    // they need. An aspect ratio for the whole cell cannot do that, because the
    // caption does not grow with the column width, so on a narrow column it ran
    // out of the cell and into the row below it.
    final double itemHeight;
    final double? mainAxisExtent;
    if (fullBleedImage) {
      itemHeight = itemWidth / aspectRatio;
      mainAxisExtent = null;
    } else {
      itemHeight = MediaCardMetrics.cellHeight(
        context,
        itemWidth,
        imageAspectRatio: MediaGridDelegate.imageAspectRatioFor(useWideAspectRatio: useWideAspectRatio),
        focusInset: cellInset,
      );
      mainAxisExtent = itemHeight;
    }

    return MediaGridGeometry._(
      columnCount: columnCount,
      itemWidth: itemWidth,
      itemHeight: itemHeight,
      spacing: spacing,
      cellInset: cellInset,
      delegate: SliverGridDelegateWithMaxCrossAxisExtent(
        // When the column count is pinned to a different basis width, the
        // delegate must pack exactly [columnCount] columns into the real
        // extent, so cap cells at the derived width instead.
        maxCrossAxisExtent: crossAxisExtentForColumnCount != null ? itemWidth : maxCrossAxisExtent,
        childAspectRatio: aspectRatio,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
    );
  }
}
