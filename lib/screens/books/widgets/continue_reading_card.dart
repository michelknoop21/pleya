import 'package:flutter/material.dart';

import '../../../books/book.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart' show kAccent;
import 'book_cover.dart';

/// The Verder lezen card from golden 01b: a wide card carrying the book's
/// colour, its title and where the reader left off, with the cover sharp on
/// the right.
///
/// The background is **cover-derived ambience**, not the cover a second time.
/// Golden 01b's first round blurred the same cover across the card; you could
/// recognise it, and a pale, busy or purely typographic cover made the trick
/// fall apart. Only colour and light come across here. The inset is the one
/// place the cover itself is shown.
class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({super.key, required this.book, this.onTap});

  static const double width = 236;
  static const double height = 140;

  final Book book;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (book.progress ?? 0).clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Ambience(artwork: book.artwork),
              const _Scrim(),
              Positioned(
                right: 14,
                top: 14,
                width: 64,
                height: 96,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 20, offset: Offset(0, 8))],
                  ),
                  child: BookCover(artwork: book.artwork, title: book.title, borderRadius: 6),
                ),
              ),
              Positioned(
                left: 14,
                right: 88,
                bottom: 15,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _progressLabel(book),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.70)),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 3,
                // `stretch`, because a Row centres its children and a
                // ColoredBox has no height of its own: without this the bar
                // laid out 113 x 0 and the card shipped with no progress at
                // all, which is what comparing the simulator against approved
                // golden 01b caught.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: (progress * 1000).round(),
                      child: const ColoredBox(color: kAccent),
                    ),
                    Expanded(
                      flex: 1000 - (progress * 1000).round(),
                      child: ColoredBox(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `48% · Hoofdstuk 12`, the pair golden 01b approves. Without a chapter the
  /// percentage stands alone rather than trailing an empty separator.
  static String _progressLabel(Book book) {
    final percent = t.books.percentRead(percent: book.progressPercent);
    final chapter = book.chapterLabel;
    return chapter == null ? percent : '$percent · $chapter';
  }
}

/// Colour and light from the cover, none of its shapes.
class _Ambience extends StatelessWidget {
  const _Ambience({required this.artwork});

  final BookArtwork artwork;

  @override
  Widget build(BuildContext context) {
    final base = HSLColor.fromColor(artwork.base);
    final deep = base.withLightness((base.lightness * 0.5).clamp(0.0, 1.0)).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [deep, artwork.base]),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.5, -0.4),
                radius: 0.95,
                colors: [artwork.accent.withValues(alpha: 0.55), artwork.accent.withValues(alpha: 0)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.5, 0.5),
                radius: 0.9,
                colors: [deep.withValues(alpha: 0.75), deep.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two scrims, not one: the vertical seats the progress bar, the horizontal
/// puts the title on a dark field while leaving the cover side bright.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) {
    const ground = Color(0xFF141414);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00141414), Color(0x75141414)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [ground.withValues(alpha: 0.68), ground.withValues(alpha: 0.34), ground.withValues(alpha: 0)],
              stops: const [0, 0.48, 1],
            ),
          ),
        ),
      ],
    );
  }
}
