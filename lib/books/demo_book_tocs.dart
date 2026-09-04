import 'book_toc.dart';

/// The fixed navigation behind `--dart-define=PLEYA_BOOKS=true`, so a simulator
/// screenshot and approved golden 06 can be put side by side.
///
/// One publication carries one, and that is deliberate. Atomic Habits is the
/// only book on the shelf whose edition names its chapters and groups them in
/// parts, which is what makes it the one that can show what a real chapter title
/// does on 393 pt; the rest declare no navigation, and a source that has nothing
/// to say answers `null` rather than an empty tree.
///
/// **The locator lives here and not on `Book.progress`.** Giving Atomic Habits a
/// shelf progress of 0.55 would put it at the head of Verder lezen, ahead of
/// Dune at 0.48, and that is the row approved golden 01b fixes the first three
/// cards of. Golden 06 anticipated a fourth card, not a new first one, so the
/// reading position stays where it belongs — with the reader — and Boeken-home
/// is left exactly as it was approved.
BookToc? demoBookToc(String bookId) => bookId == 'atomic-habits' ? _atomicHabits : null;

/// The parts and chapter names are the book's own. The reader stands in chapter
/// 12 of 20, at 55 % of the publication, which puts eleven chapters and the
/// introduction earlier in reading order — earlier, and nothing more than that.
final BookToc _atomicHabits = BookToc(
  hasPageList: true,
  locator: const BookTocLocator(entryId: 'ch-12', totalProgression: 0.55),
  nodes: [
    const BookTocEntry(id: 'introduction', label: 'Introduction: My Story'),
    _part('fundamentals', 'The Fundamentals: Why Tiny Changes Make a Big Difference', 1, 3),
    _part('law-1', 'The 1st Law: Make It Obvious', 4, 7),
    _part('law-2', 'The 2nd Law: Make It Attractive', 8, 10),
    _part('law-3', 'The 3rd Law: Make It Easy', 11, 14),
    _part('law-4', 'The 4th Law: Make It Satisfying', 15, 17),
    _part('advanced', 'Advanced Tactics: How to Go from Being Merely Good to Being Truly Great', 18, 20),
    const BookTocEntry(id: 'conclusion', label: 'Conclusion: The Secret to Results That Last'),
  ],
);

BookTocPart _part(String id, String label, int from, int to) => BookTocPart(
  id: id,
  label: label,
  chapters: [
    for (var number = from; number <= to; number++)
      BookTocChapter(id: 'ch-$number', number: number, title: _chapters[number]!),
  ],
);

const Map<int, String> _chapters = {
  1: 'The Surprising Power of Atomic Habits',
  2: 'How Your Habits Shape Your Identity (and Vice Versa)',
  3: 'How to Build Better Habits in 4 Simple Steps',
  4: "The Man Who Didn't Look Right",
  5: 'The Best Way to Start a New Habit',
  6: 'Motivation Is Overrated; Environment Often Matters More',
  7: 'The Secret to Self-Control',
  8: 'How to Make a Habit Irresistible',
  9: 'The Role of Family and Friends in Shaping Your Habits',
  10: 'How to Find and Fix the Causes of Your Bad Habits',
  11: 'Walk Slowly, but Never Backward',
  12: 'The Law of Least Effort',
  13: 'How to Stop Procrastinating by Using the Two-Minute Rule',
  14: 'How to Make Good Habits Inevitable and Bad Habits Impossible',
  15: 'The Cardinal Rule of Behavior Change',
  16: 'How to Stick with Good Habits Every Day',
  17: 'How an Accountability Partner Can Change Everything',
  18: "The Truth About Talent (When Genes Matter and When They Don't)",
  19: 'The Goldilocks Rule: How to Stay Motivated in Life and Work',
  20: 'The Downside of Creating Good Habits',
};
