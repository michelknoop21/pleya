import 'package:flutter/foundation.dart';

import 'book_reader_theme.dart';
import 'reader_typography.dart';

/// How the reader sets the page, and the stops it may set it to.
///
/// Approved with golden 08. Every scale here is a list of stops rather than a
/// range: a reading size is a choice out of a set a typographer can vouch for,
/// not a number you can land between. Each list carries the state approved
/// golden 07 was drawn in, so the reader's own default is a stop and not a
/// special case.
@immutable
class ReaderSettings {
  /// Six sizes in points. The third is 18, the size golden 07 was drawn at.
  static const List<double> sizes = [15, 16.5, 18, 20, 22, 24];

  /// Three line bands, as a multiple of the type size. The middle one is
  /// golden 07's 28 on 18, written as that division so the two cannot drift.
  static const List<double> leadings = [
    4 / 3,
    ReaderTypography.canonicalLineHeight / ReaderTypography.canonicalSize,
    16 / 9,
  ];

  /// Four measures. The third is golden 07's 32.
  static const List<double> margins = [20, 26, 32, 40];

  final int sizeIndex;
  final int leadingIndex;
  final int marginIndex;
  final BookReaderThemeId themeId;

  /// Drawn and not operable. Vertical scrolling instead of turning pages is a
  /// second reading mode with its own page, its own footer and its own answer
  /// to what a page still is; golden 08 draws the switch and leaves what it
  /// turns on open, so nothing here can move it.
  static const bool scrollMode = false;

  const ReaderSettings({
    this.sizeIndex = 2,
    this.leadingIndex = 1,
    this.marginIndex = 2,
    this.themeId = BookReaderThemeId.sepia,
  });

  /// The state golden 07 was approved in, and the one the reader opens on.
  ///
  /// Which theme a fresh profile gets is a different question: panel 12 puts
  /// `Leesthema` on `Donker` as a profile setting and that is golden 12. Sepia
  /// here is the value the approved frames were shot in.
  static const ReaderSettings canonical = ReaderSettings();

  double get size => sizes[sizeIndex];
  double get lineHeight => size * leadings[leadingIndex];
  double get margin => margins[marginIndex];

  /// The space between two paragraphs: a third of a line more than the type
  /// size, which is golden 07's 24 on 18 and golden 08b's 32 on 24.
  double get paragraphGap => size * 4 / 3;

  BookReaderTheme get theme => BookReaderTheme.of(themeId);

  ReaderSettings copyWith({int? sizeIndex, int? leadingIndex, int? marginIndex, BookReaderThemeId? themeId}) {
    return ReaderSettings(
      sizeIndex: sizeIndex ?? this.sizeIndex,
      leadingIndex: leadingIndex ?? this.leadingIndex,
      marginIndex: marginIndex ?? this.marginIndex,
      themeId: themeId ?? this.themeId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.sizeIndex == sizeIndex &&
      other.leadingIndex == leadingIndex &&
      other.marginIndex == marginIndex &&
      other.themeId == themeId;

  @override
  int get hashCode => Object.hash(sizeIndex, leadingIndex, marginIndex, themeId);
}
