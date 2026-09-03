import 'package:flutter/material.dart';

import 'book.dart';

/// Whether this build carries an e-book source at all.
///
/// The e-book data layer does not exist yet; this branch builds the screens it
/// will land in. A production build answers `false`, gets [EmptyBooksSource],
/// and behaves exactly as before: no Boeken destination, fourth navigation
/// slot to Live TV, Kijklijst or Downloads. A build with
/// `--dart-define=PLEYA_BOOKS=true` gets [DemoBooksSource], which is how
/// golden 01b is verified against the running app.
const bool kBooksEnabled = bool.fromEnvironment('PLEYA_BOOKS');

/// The source this build uses. One decision, one place.
BooksSource createBooksSource() => kBooksEnabled ? const DemoBooksSource() : const EmptyBooksSource();

/// Where books come from.
///
/// The seam between the Boeken screens and whatever ends up serving books.
/// Nothing behind this interface exists yet: e-books are a Pleya-native
/// content type, the server does not carry them, and the wire contract for
/// `/v1` is frozen. The screens are built against this, so the day a real
/// source lands it is one implementation and no screen changes.
abstract class BooksSource {
  /// Every book the acting profile may open.
  Future<List<Book>> books();

  /// The series those books belong to.
  Future<List<BookSeries>> series();
}

/// A source with nothing in it: the honest answer for a profile that has no
/// e-books, and the default in a normal build.
class EmptyBooksSource implements BooksSource {
  const EmptyBooksSource();

  @override
  Future<List<Book>> books() async => const [];

  @override
  Future<List<BookSeries>> series() async => const [];
}

/// The fixed set behind `--dart-define=PLEYA_BOOKS=true`.
///
/// It is the same set golden 01b was drawn with, in the same order, so a
/// simulator screenshot and the approved golden can be put side by side and
/// any difference is a difference in the implementation rather than in the
/// data. It is not a demo mode and not a fallback: a build without that
/// define never constructs it.
class DemoBooksSource implements BooksSource {
  const DemoBooksSource();

  static final DateTime _epoch = DateTime.utc(2026, 9, 1);

  static const _dune = BookArtwork(
    base: Color(0xFF3A1A0B),
    accent: Color(0xFFE08A3C),
    ink: Color(0xFFF7E2C6),
    shape: BookArtworkShape.orb,
  );
  static const _hailMary = BookArtwork(
    base: Color(0xFF101010),
    accent: Color(0xFFF6C62D),
    ink: Color(0xFF111111),
    shape: BookArtworkShape.diagonal,
  );
  static const _sapiens = BookArtwork(
    base: Color(0xFFEFE7D8),
    accent: Color(0xFF3A2F22),
    ink: Color(0xFFB3261E),
    shape: BookArtworkShape.rings,
  );
  static const _nineteen = BookArtwork(
    base: Color(0xFF0C0C0C),
    accent: Color(0xFFCFD6DE),
    ink: Color(0xFFE5140F),
    shape: BookArtworkShape.eye,
  );
  static const _alchemist = BookArtwork(
    base: Color(0xFFC8401A),
    accent: Color(0xFFF7B545),
    ink: Color(0xFFFFF3DF),
    shape: BookArtworkShape.orb,
  );
  static const _atomic = BookArtwork(
    base: Color(0xFFF4F2EC),
    accent: Color(0xFFE5140F),
    ink: Color(0xFF111111),
    shape: BookArtworkShape.plain,
  );

  @override
  Future<List<Book>> books() async => [
    Book(
      id: 'dune',
      title: 'Dune',
      author: 'Frank Herbert',
      artwork: _dune,
      seriesId: 'dune',
      progress: 0.48,
      chapterLabel: 'Hoofdstuk 12',
      addedAt: _epoch.subtract(const Duration(days: 30)),
    ),
    Book(
      id: 'hail-mary',
      title: 'Project Hail Mary',
      author: 'Andy Weir',
      artwork: _hailMary,
      progress: 0.21,
      chapterLabel: 'Hoofdstuk 5',
      addedAt: _epoch.subtract(const Duration(days: 1)),
    ),
    Book(
      id: 'sapiens',
      title: 'Sapiens',
      author: 'Yuval Noah Harari',
      artwork: _sapiens,
      progress: 0.03,
      chapterLabel: 'Hoofdstuk 1',
      addedAt: _epoch.subtract(const Duration(days: 2)),
    ),
    Book(
      id: '1984',
      title: '1984',
      author: 'George Orwell',
      artwork: _nineteen,
      addedAt: _epoch.subtract(const Duration(days: 3)),
    ),
    Book(
      id: 'alchemist',
      title: 'De Alchemist',
      author: 'Paulo Coelho',
      artwork: _alchemist,
      addedAt: _epoch.subtract(const Duration(days: 4)),
    ),
    Book(
      id: 'atomic-habits',
      title: 'Atomic Habits',
      author: 'James Clear',
      artwork: _atomic,
      addedAt: _epoch.subtract(const Duration(days: 5)),
    ),
  ];

  @override
  Future<List<BookSeries>> series() async => const [
    BookSeries(id: 'dune', title: 'Dune', bookCount: 6, artwork: _dune),
    BookSeries(
      id: 'zeven-zussen',
      title: 'De Zeven Zussen',
      bookCount: 7,
      artwork: BookArtwork(
        base: Color(0xFF5C1A12),
        accent: Color(0xFFE8E4EA),
        ink: Color(0xFFF6D9C4),
        shape: BookArtworkShape.orb,
      ),
    ),
    BookSeries(
      id: 'midden-aarde',
      title: 'Midden-aarde',
      bookCount: 4,
      artwork: BookArtwork(
        base: Color(0xFF15522F),
        accent: Color(0xFFCFE7C6),
        ink: Color(0xFFEAF5D8),
        shape: BookArtworkShape.orb,
      ),
    ),
    BookSeries(id: 'james-clear', title: 'James Clear', bookCount: 2, artwork: _atomic),
  ];
}
