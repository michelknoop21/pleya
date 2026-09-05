import 'package:flutter/material.dart';

import '../../../books/book_filter.dart';
import '../../../i18n/strings.g.dart';

/// Golden 03's measurements, in logical pixels at the viewport it was drawn on
/// (`docs/assets/ebooks/northstar/03a-filters-status.png`, 393 × 852).
///
/// Every number here was read off `04-filters-sheet.png` from the iOS Unified
/// set rather than chosen, so a books sheet and a films sheet are the same
/// object with different content in it.
class BookFilterSheetMetrics {
  BookFilterSheetMetrics._();

  /// The viewport the golden was drawn on, and the top edge of the sheet on
  /// it. The sheet keeps that ratio on other screen heights rather than a
  /// fixed 600, so it neither overflows a shorter phone nor floats on a taller
  /// one.
  static const double referenceHeight = 852;
  static const double referenceTopInset = 252;
  static const double heightFactor = (referenceHeight - referenceTopInset) / referenceHeight;

  static const double cornerRadius = 13;
  static const double handleWidth = 36;
  static const double handleHeight = 5;
  static const double handleTop = 8;

  /// Header band: 20 pt margins, its own 24 pt row starting 24 pt down.
  static const double pageMargin = 20;
  static const double headerTop = 24;
  static const double headerHeight = 24;

  /// Where both panes begin, measured from the top of the sheet.
  static const double paneTop = 61;

  static const double railWidth = 131;
  static const double groupRowHeight = 43.5;

  /// The white edge on the active group. A tint alone is invisible here: in
  /// `monoTheme` the container colours resolve to the same value as the
  /// surface behind them (DEC-053).
  static const double groupEdgeWidth = 3;

  static const double optionRowHeight = 37;
  static const double optionGap = 10.5;
  static const double optionMargin = 16;
  static const double optionRadius = 9;

  /// Action bar: a 40 pt row 15 pt down, then the home indicator's room. At
  /// the golden's 34 pt bottom inset that adds up to its measured 97.
  static const double actionRowTop = 15;
  static const double actionRowHeight = 40;
  static const double actionRowGap = 8;
  static const double applyWidth = 130;

  static const Color surface = Color(0xFF1F1F1F);
  static const Color divider = Color(0xFF303030);
  static const Color activeGroup = Color(0xFF2A2A2A);
  static const Color selectedOption = Color(0xFF3E3E3E);
  static const Color handle = Color(0xFF575757);
}

/// The reader-facing name of a status choice. Here rather than inside the
/// sheet because Alle boeken's result line names the same four values.
String bookStatusLabel(BookStatusFilter status) => switch (status) {
  BookStatusFilter.all => t.books.statusAll,
  BookStatusFilter.unread => t.books.statusUnread,
  BookStatusFilter.read => t.books.statusRead,
  BookStatusFilter.downloaded => t.books.statusDownloaded,
};
