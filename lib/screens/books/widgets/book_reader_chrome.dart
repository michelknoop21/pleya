import 'package:flutter/material.dart';

import '../../../books/book_reader_layout.dart';
import '../../../books/book_reader_page.dart';
import '../../../books/book_reader_theme.dart';
import '../../../books/reader_page_fit.dart';
import '../../../books/reader_settings.dart';
import '../../../books/reader_typography.dart';

/// The glyphs of the reader's chrome, drawn from the paths of the golden's own
/// source rather than picked from Material Symbols.
///
/// A reader has five controls on a page of prose and they are the page's only
/// furniture, so "close enough" would be visible. Nothing else in this app draws
/// its own glyphs; nothing else in this app has a surface this bare either.
enum BookReaderGlyph {
  /// The way back out of the book. A full arrow rather than the set's iOS
  /// chevron: the chrome of a reader is not a navigation bar.
  back,

  /// The inhoudsopgave, three rules of unequal length.
  toc,

  /// Zoeken in boek. One magnifier, not the comp's two.
  search,

  /// `Aa`, the door to the reading settings, approved with golden 08.
  ///
  /// Set in the reading face rather than drawn as a path: it is a specimen of
  /// the thing the sheet behind it changes.
  settings,

  /// The bookmark, hollow.
  ///
  /// Hollow means the current locator carries no bookmark. Filled is a state,
  /// and drawing it would claim something approved golden 07 does not decide;
  /// filled becomes the bookmarked state when there is a bookmark model to back
  /// it.
  bookmark,
}

class BookReaderGlyphIcon extends StatelessWidget {
  const BookReaderGlyphIcon({super.key, required this.glyph, required this.colour});

  final BookReaderGlyph glyph;
  final Color colour;

  double get _size => switch (glyph) {
    BookReaderGlyph.back => BookReaderLayout.backGlyph,
    BookReaderGlyph.toc => BookReaderLayout.tocGlyph,
    BookReaderGlyph.settings => BookReaderLayout.glyphSlot,
    BookReaderGlyph.search => BookReaderLayout.searchGlyph,
    BookReaderGlyph.bookmark => BookReaderLayout.bookmarkGlyph,
  };

  @override
  Widget build(BuildContext context) {
    if (glyph == BookReaderGlyph.settings) {
      return SizedBox.square(
        dimension: _size,
        child: Center(
          child: Text(
            'Aa',
            style: ReaderTypography.styleFor(
              colour: colour,
              size: BookReaderLayout.settingsGlyphSize,
              lineHeight: BookReaderLayout.glyphSlot,
              weight: 500,
              // The specimen keeps the reading cut of the canonical page rather
              // than of its own 19 points: it stands for the page, not for
              // itself.
              opticalSize: ReaderTypography.canonicalOpticalSize,
            ),
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: _size,
      child: CustomPaint(
        painter: _GlyphPainter(glyph: glyph, colour: colour),
      ),
    );
  }
}

/// All four are stroked on a 24 grid at 2.1, the weight of the golden's source.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({required this.glyph, required this.colour});

  final BookReaderGlyph glyph;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_path(), paint);
    canvas.restore();
  }

  Path _path() => switch (glyph) {
    // Drawn as a text specimen and never through this painter.
    BookReaderGlyph.settings => Path(),
    BookReaderGlyph.back =>
      Path()
        ..moveTo(19, 12)
        ..lineTo(5, 12)
        ..moveTo(11, 6)
        ..lineTo(5, 12)
        ..lineTo(11, 18),
    BookReaderGlyph.toc =>
      Path()
        ..moveTo(4, 6)
        ..lineTo(20, 6)
        ..moveTo(4, 12)
        ..lineTo(15, 12)
        ..moveTo(4, 18)
        ..lineTo(18, 18),
    BookReaderGlyph.search =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(11, 11), radius: 7))
        ..moveTo(16.4, 16.4)
        ..lineTo(20, 20),
    BookReaderGlyph.bookmark =>
      Path()
        ..moveTo(12, 16.6)
        ..lineTo(19, 21)
        ..lineTo(19, 4)
        ..arcToPoint(const Offset(18, 3), radius: const Radius.circular(1), clockwise: false)
        ..lineTo(6, 3)
        ..arcToPoint(const Offset(5, 4), radius: const Radius.circular(1), clockwise: false)
        ..lineTo(5, 21)
        ..close(),
  };

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.colour != colour;
}

/// The running head: `DUNE · HOOFDSTUK 12`.
///
/// Not part of the chrome, which is why it has its own widget and its own band.
/// It is the page's own header, the line a printed book carries at the top of
/// every page, and it stays when the chrome goes.
class BookReaderRunningHead extends StatelessWidget {
  const BookReaderRunningHead({super.key, required this.text, required this.theme});

  final String text;
  final BookReaderTheme theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: BookReaderLayout.runningHeadSize,
        height: BookReaderLayout.runningHeadHeight / BookReaderLayout.runningHeadSize,
        fontWeight: FontWeight.w700,
        letterSpacing: BookReaderLayout.runningHeadTracking,
        color: theme.secondaryInk,
      ),
    );
  }
}

/// One paragraph of the page, with its highlight if it carries one.
///
/// **The highlight follows the text and nothing else.** Its vertical extent is
/// the line boxes the reader's own text layout produces, read back out of the
/// same [TextPainter] that lays the paragraph out, so it stays right when the
/// type size, the line band or the face changes. The one number that comes from
/// the golden is the horizontal bleed, and that is a drawing rule about how far
/// a marker overshoots its words, not a measurement of this page.
class BookReaderMarkedText extends StatelessWidget {
  const BookReaderMarkedText({super.key, required this.paragraph, required this.style, required this.mark});

  final BookReaderParagraph paragraph;
  final TextStyle style;
  final Color mark;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = Text(paragraph.text, style: style);
    if (!paragraph.isHighlighted) return text;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _MarkPainter(text: paragraph.text, style: style, colour: mark, scaler: scaler),
          ),
        ),
        text,
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.text, required this.style, required this.colour, required this.scaler});

  final String text;
  final TextStyle style;
  final Color colour;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    // The same text, the same style, the same width and the same scaler as the
    // `Text` above it, so this is that paragraph's layout rather than a second
    // opinion about it.
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: size.width);
    // The line metrics and not `getBoxesForSelection`. A selection box runs to
    // the end of the line including the space the break ate, which put four
    // points of highlight past the last word; `LineMetrics.width` is the line's
    // own set width. Everything here comes out of the layout: the top is the
    // baseline less the ascent, the height is the line band. Nothing is copied
    // from the golden except the overshoot.
    final lines = painter.computeLineMetrics();
    final paint = Paint()..color = colour;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final top = line.baseline - line.ascent;
      // The overshoot belongs to the passage, not to each of its lines: a marker
      // is set down before the first word and lifted after the last one, and in
      // between it simply runs to the edge of the measure. Drawn on every line
      // it would notch the left margin at each break.
      final left = line.left - (i == 0 ? BookReaderLayout.markBleed : 0);
      final right = line.left + line.width + (i == lines.length - 1 ? BookReaderLayout.markBleed : 0);
      canvas.drawRect(Rect.fromLTRB(left, top, right, top + line.height), paint);
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.text != text || old.style != style || old.colour != colour || old.scaler != scaler;
}

/// The scrubber over the whole publication and the one line under it.
///
/// Drawn, and inert. What it shows while you drag it — a preview, a chapter name
/// running along, a jump-back control — is one of the things approved golden 07
/// leaves open, so there is nothing here to drag it with.
class BookReaderFoot extends StatelessWidget {
  const BookReaderFoot({super.key, required this.position, required this.theme, required this.accent});

  final BookReaderPosition position;
  final BookReaderTheme theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: BookReaderLayout.chromeMargin,
          right: BookReaderLayout.chromeMargin,
          top: BookReaderLayout.trackTop,
          height: BookReaderLayout.trackThickness,
          child: _Track(progress: position.totalProgression, theme: theme, accent: accent),
        ),
        Positioned(
          left: BookReaderLayout.chromeMargin,
          right: BookReaderLayout.chromeMargin,
          top: BookReaderLayout.labelTop,
          height: BookReaderLayout.labelHeight,
          child: Text(
            position.footerLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: BookReaderLayout.labelSize,
              height: BookReaderLayout.labelHeight / BookReaderLayout.labelSize,
              color: theme.secondaryInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.progress, required this.theme, required this.accent});

  final double progress;
  final BookReaderTheme theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // The knob's centre rides the filled edge, and it is taller than the
        // track, so it hangs out of this band on both sides. That is what
        // `clipBehavior: none` on the stack above is for.
        const knob = BookReaderLayout.knobSize;
        const radius = BorderRadius.all(Radius.circular(2));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.track, borderRadius: radius),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * progress,
              child: DecoratedBox(
                decoration: BoxDecoration(color: accent, borderRadius: radius),
              ),
            ),
            Positioned(
              left: width * progress - knob / 2,
              top: (BookReaderLayout.trackThickness - knob) / 2,
              width: knob,
              height: knob,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1))],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The text column: the paragraphs that fit, the space between them, and nothing
/// else.
///
/// **It draws the page and not the book.** Which paragraphs fit follows from the
/// type the reader has set, so at 24 points two of golden 07's four land here and
/// the rest belong to a page that does not exist yet. See [ReaderPageFit] for why
/// that is a first page and not pagination.
class BookReaderColumn extends StatelessWidget {
  const BookReaderColumn({super.key, required this.paragraphs, required this.theme, required this.settings});

  final List<BookReaderParagraph> paragraphs;
  final BookReaderTheme theme;
  final ReaderSettings settings;

  @override
  Widget build(BuildContext context) {
    final style = ReaderTypography.styleFor(colour: theme.ink, size: settings.size, lineHeight: settings.lineHeight);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = ReaderPageFit.paragraphCount(
          paragraphs: paragraphs,
          style: style,
          scaler: scaler,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          gap: settings.paragraphGap,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) SizedBox(height: settings.paragraphGap),
              BookReaderMarkedText(paragraph: paragraphs[i], style: style, mark: theme.mark),
            ],
          ],
        );
      },
    );
  }
}
