import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How a cover is drawn when the source has no cover image.
///
/// E-books are a Pleya-native content type and the artwork pipeline for them
/// does not exist yet, so the demo source describes a cover instead of
/// shipping one. Deliberately a small closed set of shapes rather than an
/// illustration engine: it has to be enough to tell six covers apart on a
/// 110 pt card, and no more. A real cover image replaces this whole value.
enum BookArtworkShape {
  /// A lit sphere over a graded ground. Dune, De Alchemist.
  orb,

  /// Concentric rings. Sapiens.
  rings,

  /// A ring inside a ring, high contrast. 1984.
  eye,

  /// A hard diagonal split between two fields. Project Hail Mary.
  diagonal,

  /// Type on a flat ground, no motif. Atomic Habits.
  plain,
}

/// Everything needed to draw a cover: the palette and one shape.
@immutable
class BookArtwork {
  /// Ground colour, and the colour the ambience behind a continue-reading card
  /// is derived from.
  final Color base;

  /// The lit accent: the orb, the rings, the bright half of a diagonal.
  final Color accent;

  /// Title colour on the cover.
  final Color ink;

  final BookArtworkShape shape;

  const BookArtwork({required this.base, required this.accent, required this.ink, this.shape = BookArtworkShape.plain});
}

/// One e-book.
///
/// Plain and immutable rather than `freezed`: nothing serialises a book yet.
/// It is not persisted, not cached and not on any wire, so a generated
/// `toJson` would be a generated file with no reader. When books gain a
/// source that speaks over the network, this becomes a `@freezed` model like
/// the rest of `lib/media/`.
@immutable
class Book {
  final String id;
  final String title;
  final String author;
  final BookArtwork artwork;

  /// Series this book belongs to, if any.
  final String? seriesId;

  /// How far in, 0.0 to 1.0. `null` means never opened, which is a different
  /// thing from 0: an unopened book does not belong in Verder lezen.
  final double? progress;

  /// Where the reader left off, e.g. `Hoofdstuk 12`. Shown next to the
  /// percentage, because that is the pair the reader is actually looking for
  /// (golden 01b).
  final String? chapterLabel;

  /// Sort key for Recent toegevoegd; newest first.
  final DateTime addedAt;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.artwork,
    required this.addedAt,
    this.seriesId,
    this.progress,
    this.chapterLabel,
  });

  /// Whether this book belongs in Verder lezen.
  ///
  /// A finished book drops out on its own: at 1.0 there is nothing to
  /// continue. The upper bound is deliberately not 1.0 exactly, because a
  /// reader who is 99.5% through a long book has one page left and does not
  /// want it back on the shelf as unfinished-looking work.
  bool get isInProgress {
    final value = progress;
    return value != null && value > 0 && value < 0.995;
  }

  /// `48%`, for the line under a continue-reading title. Rounded down, so a
  /// book never claims a percentage the reader has not reached.
  int get progressPercent => ((progress ?? 0) * 100).floor();
}

/// A series of books, e.g. Dune. Shown as one cover plus a count.
@immutable
class BookSeries {
  final String id;
  final String title;
  final int bookCount;
  final BookArtwork artwork;

  const BookSeries({required this.id, required this.title, required this.bookCount, required this.artwork});
}
