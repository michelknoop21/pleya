import 'package:flutter/material.dart';
import 'package:pleya/widgets/optimized_media_image.dart';

/// Deterministic stand-in artwork for the Films/Series goldens.
///
/// ## Why this exists
///
/// `OptimizedMediaImage` ends every path in a network or file image, so a
/// widget test renders its placeholder and nothing else. The first Films
/// goldens were therefore twelve identical grey tiles, and they could not
/// answer the question the phase's art direction actually asks: Pleya's chrome
/// is deliberately dark, so does it *present* bright, warm and colourful
/// artwork, or does it flatten everything into one sombre grid?
///
/// A picture of a grid of placeholders cannot answer that. A picture of a grid
/// of colour can.
///
/// ## What these are and are not
///
/// They are **not** posters, and they are not claimed to be. They are synthetic
/// panels whose palette, luminance and composition are chosen to span the range
/// real libraries contain — a sunny family film, a neon sci-fi, a green nature
/// series, a muted drama, a bright comedy — so that a reviewer looking at the
/// golden is judging Pleya's chrome against varied content rather than against
/// twelve copies of the same grey.
///
/// They are deterministic: the palette is picked by the poster's index, never
/// by a hash of a title or by anything random, so the same golden is the same
/// bytes on every machine and a reordered fixture list is a visible diff rather
/// than a silent reshuffle.
///
/// What they still cannot prove is hardware colour: hoofdstuk 29's point about
/// rasterization, render scale and HDR applies here as much as anywhere, and
/// artwork is the part of the surface where it applies most. These pictures
/// catch "the dark UI is crushing the content"; they do not replace looking at
/// a real library on a real television.
class TvGoldenArtwork {
  const TvGoldenArtwork._();

  /// Makes every `OptimizedMediaImage` render [poster]. Pair with [remove] in
  /// `tearDownAll`, or the seam leaks into the next test file in the same
  /// process.
  ///
  /// The path a card asks for is `artwork/<n>`; anything else — a source with
  /// no artwork at all — falls through to a neutral panel, which is the honest
  /// picture of a title whose server has no poster for it.
  static void install() => OptimizedMediaImage.debugImageBuilder = (context, imagePath) => poster(imagePath);

  /// Clears the seam.
  static void remove() => OptimizedMediaImage.debugImageBuilder = null;

  /// The artwork path a fixture at [index] should carry.
  static String pathFor(int index) => 'artwork/$index';

  /// A poster panel for an `artwork/<n>` path.
  static Widget poster(String? imagePath) {
    final index = _indexOf(imagePath);
    if (index == null) return const _NeutralPanel();
    return _Poster(palette: _palettes[index % _palettes.length]);
  }

  static int? _indexOf(String? imagePath) {
    if (imagePath == null || !imagePath.startsWith('artwork/')) return null;
    return int.tryParse(imagePath.substring('artwork/'.length));
  }

  /// The range a real library spans, in the order the fixtures use it.
  ///
  /// Ordered so that neighbours differ: a grid that happens to put its three
  /// dark panels in one row would look like a rendering fault rather than like
  /// a library, and a grid that graded smoothly from light to dark would look
  /// like a designed gradient rather than like twelve unrelated films.
  static const List<_Palette> _palettes = [
    // Sunny family film.
    _Palette(Color(0xFFFFC24D), Color(0xFFF2704B), Color(0xFFFFF0C9)),
    // Deep-space science fiction.
    _Palette(Color(0xFF10203F), Color(0xFF2B1B4D), Color(0xFF6FC3FF)),
    // Bright animation.
    _Palette(Color(0xFF3DD68C), Color(0xFF1FA7C4), Color(0xFFEAFFF4)),
    // Muted drama.
    _Palette(Color(0xFF2A2622), Color(0xFF4A4038), Color(0xFFCFC1AF)),
    // Neon thriller.
    _Palette(Color(0xFFE5140F), Color(0xFF7A0AA8), Color(0xFFFF9CE8)),
    // Nature documentary.
    _Palette(Color(0xFF0E4C3A), Color(0xFF1F7A5C), Color(0xFFBDF3D8)),
    // Warm comedy.
    _Palette(Color(0xFFFF7BAC), Color(0xFFFFB020), Color(0xFFFFF3E0)),
    // Cold noir.
    _Palette(Color(0xFF0B0F14), Color(0xFF243447), Color(0xFF9CC2FF)),
    // Desert epic.
    _Palette(Color(0xFFC8752A), Color(0xFF8A3E12), Color(0xFFFFE0B0)),
    // Pastel romance.
    _Palette(Color(0xFFBFD7FF), Color(0xFFE7C6FF), Color(0xFFFFFFFF)),
    // Forest fantasy.
    _Palette(Color(0xFF1B3A1F), Color(0xFF5E7A2E), Color(0xFFE4F2B8)),
    // Monochrome classic.
    _Palette(Color(0xFF1A1A1A), Color(0xFF5C5C5C), Color(0xFFF0F0F0)),
  ];
}

class _Palette {
  const _Palette(this.top, this.bottom, this.highlight);

  final Color top;
  final Color bottom;

  /// The lightest note in the panel — a sky, a title treatment, a lit face.
  /// It is what makes a poster read as an image with a subject rather than as a
  /// two-stop gradient, and it is what a too-dark chrome visibly kills.
  final Color highlight;
}

/// A synthetic poster: a two-stop ground, a soft off-centre light, and one hard
/// shape. Enough structure that scaling, cropping and the card's own gradient
/// footer have something real to act on.
class _Poster extends StatelessWidget {
  const _Poster({required this.palette});

  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.top, palette.bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.55),
                radius: 0.95,
                colors: [palette.highlight.withValues(alpha: 0.85), palette.highlight.withValues(alpha: 0)],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0.55, 0.75),
            child: FractionallySizedBox(
              widthFactor: 0.7,
              heightFactor: 0.42,
              child: DecoratedBox(decoration: BoxDecoration(color: palette.bottom.withValues(alpha: 0.55))),
            ),
          ),
        ],
      ),
    );
  }
}

/// A source with no artwork at all.
class _NeutralPanel extends StatelessWidget {
  const _NeutralPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(color: scheme.surfaceContainerHighest);
  }
}
