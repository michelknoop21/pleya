import 'book_reader_page.dart';

/// The page behind `--dart-define=PLEYA_BOOKS=true`, so a simulator screenshot
/// and approved golden 07 can be put side by side.
///
/// One publication carries one, and it is the one the golden is drawn with: Dune
/// at chapter 12, 48 % through, on page 248 of 616. That position is not picked
/// here. Golden 01b fixes Dune at 48 % as the first card of Verder lezen and
/// golden 05 draws the same book at the same place, so the reader arrives where
/// the rest of the set already says the reader is.
///
/// **The prose is written for this repository and not quoted from the book.** It
/// is in English because the fixed set carries Dune as an English edition; the
/// comp's Dutch filler would put a translation on screen that the shelf does not
/// have. The running head stays in the interface language, because the app makes
/// that line rather than the file.
BookReaderPage? demoBookReaderPage(String bookId) => bookId == 'dune' ? _dune : null;

/// 248 and 616 both come from the publication's `page-list`, which is what makes
/// the rich footer legal at all. That 616 happens to equal the `Pagina's` figure
/// in golden 05's stats row is a property of this edition and not a derivation:
/// swap the edition and the two numbers part company without either being wrong.
final BookReaderPage _dune = BookReaderPage(
  bookTitle: 'Dune',
  chapterNumber: 12,
  position: BookReaderPosition.fromPageList(totalProgression: 0.48, currentLabel: '248', terminalLabel: '616'),
  paragraphs: const [
    BookReaderParagraph(
      'The sun hung low over the horizon, a pale disc in an endless sea of sand. Paul felt the tremor of the '
      'desert under his feet, a rhythm he had come to know as well as his own heartbeat.',
    ),
    BookReaderParagraph('He thought of his father, of House Atreides, of everything that had been lost.'),
    BookReaderParagraph('But he thought too of what was still to come.'),
    BookReaderParagraph('In the silence he heard the voice of the desert, old and patient.', isHighlighted: true),
  ],
);
