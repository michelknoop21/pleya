/// The iPhone library look (A-06, Michel 30 October 2026): the chrome and the
/// cards of every page behind the Bibliotheken picker.
///
/// `LibrariesScreen` also serves iPad, desktop and TV, and those must not move,
/// so the look is opt-in: `MobileLibrariesScreen` asks for it, the screen puts
/// [LibraryPhoneLook] around its tabs, and anything below reads that scope
/// instead of guessing from the platform.
library;

import 'package:flutter/material.dart';

/// Marks a subtree as drawn in the iPhone library look.
class LibraryPhoneLook extends InheritedWidget {
  const LibraryPhoneLook({super.key, required super.child});

  /// A marker never changes, so reading it needs no dependency.
  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<LibraryPhoneLook>() != null;

  @override
  bool updateShouldNotify(LibraryPhoneLook oldWidget) => false;
}

/// Sizes of the look, read off the reference screenshots at 402 pt wide.
class LibraryPhoneMetrics {
  LibraryPhoneMetrics._();

  static const double titleRowHeight = 52;
  static const double tabRowHeight = 52;
  static const double filterRowHeight = 48;
  static const double headerBlurSigma = 24;
  static const double headerTintAlpha = 0.78;
  static const double headerTitleSize = 20;
  static const double headerServerSize = 14;

  static const double tabFontSize = 16;
  static const double tabPillHeight = 36;
  static const double pillFontSize = 15;
  static const double pillIconSize = 18;
  static const double pillGap = 8;
  static const double pillHeight = 32;
  static const double countBadgeHorizontalPadding = 10;

  /// The right edge stays wider than the left: the scroll crown sits there.
  static const double gridInsetStart = 16;
  static const double gridInsetEnd = 21;
  static const double gridInsetTop = 4;
  static const double gridInsetBottom = 16;
  static const double gridColumnGap = 5;
  static const double gridRowGap = 14;
  static const int posterColumns = 3;

  /// 16:9 episode stills do not fit three across.
  static const int wideColumns = 2;

  /// Above this width a landscape phone gets more columns, not bigger posters.
  static const double maxPosterWidth = 150;

  static const double captionGap = 8;
  static const double captionTitleSize = 15;
  static const double captionSubtitleSize = 14;
  static const double captionLineHeight = 1.25;

  static const double watchedPlateSize = 30;
  static const double watchedPlateIconSize = 20;

  /// Same fill as the markers on the other mobile cards ([SourceCountCapsule]):
  /// a plate on artwork stays dark in both themes.
  static const double watchedPlateAlpha = 0.72;

  static const double sortRowInset = 24;
  static const double sortRowFontSize = 16;
  static const double sortGlyphSize = 22;

  static const TextStyle captionTitleStyle = TextStyle(
    fontWeight: FontWeight.w400,
    fontSize: captionTitleSize,
    height: captionLineHeight,
  );

  static TextStyle captionSubtitleStyle({required Color color}) =>
      TextStyle(color: color, fontSize: captionSubtitleSize, height: captionLineHeight);

  /// What stays on screen once the header has collapsed: the status bar and the
  /// title row. Every tab keeps its content below this.
  static double pinnedHeaderExtentOf(BuildContext context) => MediaQuery.paddingOf(context).top + titleRowHeight;

  /// Height of the two caption lines, resolved against the system text size so
  /// a larger setting cannot run into the row below.
  static double captionExtentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = scaler.scale(captionTitleSize) * captionLineHeight;
    final subtitle = scaler.scale(captionSubtitleSize) * captionLineHeight;
    return (title + subtitle).ceilToDouble();
  }

  /// Three across on a phone held upright; more only when the width allows it.
  static int columnsFor(double crossAxisExtent, {required bool wide}) {
    final minimum = wide ? wideColumns : posterColumns;
    final maxWidth = wide ? maxPosterWidth * 2 : maxPosterWidth;
    final fit = ((crossAxisExtent + gridColumnGap) / (maxWidth + gridColumnGap)).floor();
    return fit > minimum ? fit : minimum;
  }

  /// Insets of a grid or list inside a tab. The bottom clears the home
  /// indicator: this page has no tab bar.
  static EdgeInsets gridPaddingOf(BuildContext context) => EdgeInsets.fromLTRB(
    gridInsetStart,
    gridInsetTop,
    gridInsetEnd,
    gridInsetBottom + MediaQuery.paddingOf(context).bottom,
  );
}
