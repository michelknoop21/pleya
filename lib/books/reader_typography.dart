import 'package:flutter/painting.dart';

/// The reading face of the Pleya reader, and the axes it is cut at.
///
/// Approved with golden 07 revisie B. Literata is bundled rather than borrowed
/// from the operating system, because a reader is a product surface: golden and
/// app have to share one glyph metric, iPhone and iPad one cut, a fresh machine
/// has to be able to rebuild the golden, and an OS update must not quietly move
/// the type on a page. Provenance, version, hashes and the licence check live in
/// `assets/fonts/README.md`.
///
/// **Setting `fontFamily` alone is not enough, and that is the whole reason this
/// file exists.** Literata is a variable font with an `opsz` axis. Chromium
/// applies optical sizing by itself and feeds the type size into that axis;
/// Flutter does no such thing and sits on the font's own default of 12. A reader
/// that names the family and stops there draws a different cut than the approved
/// frames, at the same nominal size, and nothing in the widget tree looks wrong.
///
/// [canonical] is therefore the state the golden was approved in and a
/// regression check in its own right. It is not a claim that every future
/// setting stays here: when a reader picks 22 pt, `opsz` is meant to move with
/// it rather than stay pinned at 18. Whether that coupling is automatic or
/// steered is golden 08's decision, so [styleFor] takes a size and this file
/// makes no policy.
class ReaderTypography {
  const ReaderTypography._();

  /// The family name declared in `pubspec.yaml` for
  /// `assets/fonts/Literata-Variable.ttf`.
  static const String family = 'Literata';

  /// The canonical reading size and line band of golden 07: 18 pt on 28.
  static const double canonicalSize = 18;
  static const double canonicalLineHeight = 28;

  /// The weight axis of the canonical state. Literata's own default is 400 as
  /// well, but leaving it implicit would make the golden depend on a default
  /// rather than on a decision.
  static const double canonicalWeight = 400;

  /// The optical-size axis of the canonical state.
  ///
  /// Optical sizing means "cut for this point size", so the canonical value is
  /// the size the column is set at. Left unset it would be the font's default of
  /// 12, which is a text cut for footnotes.
  static const double canonicalOpticalSize = canonicalSize;

  /// The style the reader draws its page in.
  ///
  /// [opticalSize] defaults to [size] because that is what optical sizing means.
  /// It is a separate parameter so golden 08 can decide to steer it explicitly
  /// without this file having to change.
  ///
  /// **It inherits nothing, and that is not tidiness.** A `Text` merges the
  /// ambient [DefaultTextStyle] into its own, and the app's text theme carries
  /// `letterSpacing: 0.3` from Material's `bodyMedium`. Interface tracking on a
  /// page of prose ran the first line of the reader 11,7 points wider than the
  /// approved golden, with the same words and the same breaks — the kind of
  /// difference that is invisible in a widget test and obvious next to the
  /// frame. A reading page owns its typography completely or it does not own it.
  static TextStyle styleFor({
    required Color colour,
    double size = canonicalSize,
    double lineHeight = canonicalLineHeight,
    double weight = canonicalWeight,
    double? opticalSize,
  }) {
    return TextStyle(
      inherit: false,
      fontFamily: family,
      fontSize: size,
      height: lineHeight / size,
      color: colour,
      letterSpacing: 0,
      wordSpacing: 0,
      // Half-leading, the way CSS distributes the space a line band adds over
      // the font's own ascent and descent. Flutter's default is proportional,
      // which puts the baseline a fraction lower than the golden's browser did.
      leadingDistribution: TextLeadingDistribution.even,
      textBaseline: TextBaseline.alphabetic,
      decoration: TextDecoration.none,
      fontVariations: [FontVariation('wght', weight), FontVariation('opsz', opticalSize ?? size)],
    );
  }

  /// The exact state golden 07 was approved in.
  static TextStyle canonical(Color colour) => styleFor(colour: colour);
}
