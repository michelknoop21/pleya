import 'package:flutter/painting.dart';

/// Approved golden 07's geometry, as measured on `07a-books-reader.png` and its
/// source (`docs/assets/ebooks/northstar/src/07-books-reader/reader.html`).
///
/// **Every band is reserved whether it is drawn or not.** That is the point of
/// the whole table and the one behaviour `07b` exists to prove: showing or
/// hiding the chrome may not move a single line. A page that repaginates when
/// you touch it loses your place. So the chrome, the running head, the column
/// and the footer are each anchored on their own, and none of them is stacked
/// on top of the one above it.
///
/// The numbers come off the frame. The chrome sits on the 62 to 94 band every
/// screen in this set holds; the running head on 128,0 to 137,3; the column
/// starts at 188 with a margin of 32; the scrubber and its label end 66 above
/// the bottom inset.
class BookReaderLayout {
  const BookReaderLayout._();

  /// The chrome hangs on the frame of the reader, so it keeps the set's page
  /// margin of 24, and the column hangs on the measure, which is wider.
  static const double chromeMargin = 24;
  static const double columnMargin = 32;

  /// The band the chrome occupies, measured from the top of the safe area's
  /// first drawable point (`viewPadding.top + 3`, which is 62 on the frame the
  /// golden was shot on).
  static const double chromeTop = 0;
  static const double chromeHeight = 32;

  /// A glyph slot and the gap between two of them.
  static const double glyphSlot = 26;
  static const double glyphGap = 24;

  /// The four glyph sizes of the golden, in the order the chrome draws them.
  static const double backGlyph = 24;
  static const double tocGlyph = 22;
  static const double searchGlyph = 21;
  static const double bookmarkGlyph = 20;

  /// The running head, 62 below the chrome's own top.
  ///
  /// Not chrome. It is the page's own header, the line a printed book carries at
  /// the top of every page, which is why it stays when the chrome goes.
  static const double runningHeadTop = 62;
  static const double runningHeadHeight = 18;
  static const double runningHeadSize = 12;
  static const double runningHeadTracking = 1.4;

  /// The top of the text column, 126 below the chrome's own top.
  static const double columnTop = 126;

  /// Between two paragraphs. Space, not an indent: the golden sets the measure
  /// with a blank line rather than a first-line indent.
  static const double paragraphGap = 24;

  /// How far a highlight bleeds past the words it covers, on both sides, the way
  /// a marker overshoots what it marks. Horizontal only: the vertical extent of
  /// a highlight is the line box, which comes from the text and never from here.
  static const double markBleed = 7;

  /// The air between the bottom of the footer's label and the top of the home
  /// indicator's inset. On the golden: the label ends on 804, the safe area ends
  /// on 818.
  static const double footBottomGap = 14;
  static const double trackTop = 8;
  static const double trackThickness = 3;
  static const double knobSize = 16;
  static const double labelTop = 34;
  static const double labelHeight = 18;
  static const double labelSize = 13;

  /// The height of the footer block, from the top of the scrubber's row to the
  /// bottom of its label.
  static const double footHeight = labelTop + labelHeight;

  /// Where the chrome's own top edge sits on this device.
  ///
  /// 62 on the iPhone 15 Pro the golden was shot on: a view padding of 59 and
  /// the 3 points every screen in this set puts under it.
  static double chromeTopFor(EdgeInsets viewPadding) => viewPadding.top + 3;

  /// Where the footer block's top edge sits, measured from the top of the frame.
  ///
  /// 752 on the golden: 852 tall, a bottom inset of 34, 14 points of air under
  /// the label, and the 52 the block itself is.
  static double footTopFor(Size frame, EdgeInsets viewPadding) =>
      frame.height - viewPadding.bottom - footBottomGap - footHeight;
}
