import 'package:flutter/material.dart';
import '../services/settings_service.dart' show LibraryDensity;
import 'layout_constants.dart';
import 'platform_detector.dart';

class GridSizeCalculator {
  static double _lerp(double min, double max, double t) => min + (max - min) * t;

  /// Calculates the maximum cross-axis extent for grid items based on screen size and density.
  /// [density] is an int 1–5 (1 = most compact, 5 = most comfortable).
  static double getMaxCrossAxisExtent(BuildContext context, int density) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final f = LibraryDensity.factor(density);

    if (PlatformDetector.isTV()) return _lerp(120, 220, f);
    if (ScreenBreakpoints.isDesktopOrLarger(screenWidth)) return _lerp(140, 280, f);
    if (ScreenBreakpoints.isTablet(screenWidth)) return _lerp(120, 230, f);
    return _lerp(100, 200, f);
  }

  /// Calculates the max cross-axis extent accounting for outer padding.
  /// [density] is an int 1–5.
  static double getMaxCrossAxisExtentWithPadding(BuildContext context, int density, double horizontalPadding) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final availableWidth = screenWidth - horizontalPadding;
    final f = LibraryDensity.factor(density);

    // TV-specific sizing for 10ft viewing distance
    if (PlatformDetector.isTV()) {
      final divisor = _lerp(12, 6, f);
      final maxItemWidth = _lerp(140, 240, f);
      return (availableWidth / divisor).clamp(0, maxItemWidth);
    }

    if (ScreenBreakpoints.isWideTabletOrLarger(screenWidth)) {
      final divisor = _lerp(10, 5, f);
      final maxItemWidth = _lerp(140, 280, f);
      return (availableWidth / divisor).clamp(0, maxItemWidth);
    } else if (ScreenBreakpoints.isTablet(screenWidth)) {
      final targetItemCount = _lerp(6, 3, f);
      return availableWidth / targetItemCount;
    } else {
      final targetItemCount = _lerp(5, 2, f);
      return availableWidth / targetItemCount;
    }
  }

  /// Calculates the number of columns for a given available width.
  ///
  /// Matches Flutter's SliverGridDelegateWithMaxCrossAxisExtent exactly (see
  /// rendering/sliver_grid.dart), so this navigation column count equals the
  /// number of columns the grid actually renders. A mismatch makes dpad "down"
  /// (`index + columnCount`) land diagonally — see issue #1288. Note the spacing
  /// is added to the denominator only, not the numerator:
  /// `(crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing)).ceil()`
  ///
  /// [crossAxisExtent] should come from layout constraints (e.g.
  /// `SliverCrossAxisLayoutBuilder` or `LayoutBuilder`), not from `MediaQuery`,
  /// to account for sidebars or other elements that reduce the grid's actual
  /// width. Never use a plain `SliverLayoutBuilder` for this: its constraints
  /// include the scroll offset, so it rebuilds the whole grid every scroll tick.
  static int getColumnCount(
    double crossAxisExtent,
    double maxCrossAxisExtent, {
    double crossAxisSpacing = GridLayoutConstants.crossAxisSpacing,
  }) {
    return (crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing)).ceil().clamp(1, 100);
  }

  /// Columns for a grid that has a minimum card width rather than a target
  /// one: how many cards of at least [minCardWidth] fit in [crossAxisExtent].
  ///
  /// [getColumnCount] rounds *up* from a target extent, which is right for a
  /// library that wants to fill the screen but wrong for a curated list: on a
  /// 390pt phone it put a fourth poster of 85pt in the row, and at that width
  /// a title, its year and a status badge all run out of room. This rounds
  /// down, so a card never ends up narrower than the minimum its content needs.
  static int getColumnCountForMinWidth(double crossAxisExtent, double minCardWidth, {double spacing = 0}) {
    if (minCardWidth <= 0) return 1;
    return (((crossAxisExtent + spacing) / (minCardWidth + spacing)).floor()).clamp(1, 100);
  }

  static double getCellWidthForColumnCount(
    double crossAxisExtent,
    int columnCount, {
    double crossAxisSpacing = GridLayoutConstants.crossAxisSpacing,
  }) {
    return (crossAxisExtent - (crossAxisSpacing * (columnCount - 1))) / columnCount;
  }

  /// Computes the actual cell width that a grid with [getMaxCrossAxisExtent] would produce
  /// for the given [availableWidth]. This matches SliverGridDelegateWithMaxCrossAxisExtent's
  /// internal calculation, so horizontal scroll lists can use the same width as grids.
  static double getCellWidth(double availableWidth, BuildContext context, int density) {
    final maxExtent = getMaxCrossAxisExtent(context, density);
    final columns = getColumnCount(availableWidth, maxExtent);
    return getCellWidthForColumnCount(availableWidth, columns);
  }

  static bool isFirstRow(int index, int columnCount) {
    return index < columnCount;
  }

  static bool isFirstColumn(int index, int columnCount) {
    return index % columnCount == 0;
  }
}
