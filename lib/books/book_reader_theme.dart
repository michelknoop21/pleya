import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The three reading themes of approved golden 07, measured on `07c`.
///
/// `07c` is a shape specification and not a runtime state: it lifts the same two
/// paragraphs out in all three grounds so they can be judged against each other.
/// The reader shows one at a time.
///
/// **Which one it opens on is not decided here.** Panel 7 of the comp draws sepia
/// and panel 12 puts `Leesthema` on `Donker`; those two contradict each other and
/// golden 07 says so out loud. Sepia in `07a` and `07b` proves the sepia reading
/// state, not a default setting. Golden 08 picks the default, and until then
/// [sepia] is what the reader draws because it is the state the approved frames
/// were shot in.
enum BookReaderThemeId { light, sepia, dark }

@immutable
class BookReaderTheme {
  /// The ground the page is printed on.
  final Color page;

  /// The reading ink.
  final Color ink;

  /// The secondary ink: the running head and the footer line. Not a third
  /// colour, the reading ink at reduced strength.
  final Color secondaryInk;

  /// The highlight. Painted behind the text, never over it.
  final Color mark;

  /// The unfilled part of the scrubber. The filled part is the app accent, which
  /// is the same in all three themes: the reader changes its paper, not its
  /// brand.
  final Color track;

  final BookReaderThemeId id;

  const BookReaderTheme({
    required this.id,
    required this.page,
    required this.ink,
    required this.secondaryInk,
    required this.mark,
    required this.track,
  });

  static const BookReaderTheme light = BookReaderTheme(
    id: BookReaderThemeId.light,
    page: Color(0xFFFFFFFF),
    ink: Color(0xFF1A1A1A),
    secondaryInk: Color(0x8C1A1A1A),
    mark: Color(0xFFFFE9A8),
    track: Color(0xFFDFDCD6),
  );

  /// The ground golden 07a and 07b are drawn on.
  static const BookReaderTheme sepia = BookReaderTheme(
    id: BookReaderThemeId.sepia,
    page: Color(0xFFF0E5D7),
    ink: Color(0xFF2A2117),
    secondaryInk: Color(0x8C2A2117),
    mark: Color(0xFFFDDF9E),
    track: Color(0xFFD0C7BB),
  );

  /// `#141414`, the app's own non-OLED ground, so a reader that goes dark lands
  /// on the surface the rest of Pleya uses rather than on a second, nearly
  /// identical black.
  static const BookReaderTheme dark = BookReaderTheme(
    id: BookReaderThemeId.dark,
    page: Color(0xFF141414),
    ink: Color(0xCCFFFFFF),
    secondaryInk: Color(0x80FFFFFF),
    mark: Color(0x42F5C542),
    track: Color(0xFF3A3A3A),
  );

  static const List<BookReaderTheme> all = [light, sepia, dark];

  static BookReaderTheme of(BookReaderThemeId id) => switch (id) {
    BookReaderThemeId.light => light,
    BookReaderThemeId.sepia => sepia,
    BookReaderThemeId.dark => dark,
  };

  /// Whether the platform should draw its status bar in light ink.
  ///
  /// iOS inverts the status bar with the content underneath it, and a reader
  /// that fills the screen is content. The notch itself stays black in all three,
  /// because it is a hole and not a colour.
  bool get wantsLightStatusBar => id == BookReaderThemeId.dark;
}
