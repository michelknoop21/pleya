/// Deterministic stand-in artwork for the fase-6 discovery goldens.
///
/// ## Why a second artwork helper
///
/// `TvGoldenArtwork` answers the catalogus question: twelve 2:3 posters on one
/// grid, all the same shape, and the only thing that varies between them is
/// colour. Discovery asks a different question. Hoofdstuk 10.2a's rail makes
/// the *focused* card wide and its neighbours compact, so one logical title has
/// to be picturable twice — as a poster among its neighbours, and as a
/// landscape panel the moment focus lands on it. A helper that only knows how
/// to paint a 2:3 poster cannot picture that transition at all, and one that
/// paints the same panel at both aspect ratios would hide the thing most worth
/// looking at: whether the card still reads as the same film after it grows.
///
/// So the sets are paired. [pathFor] and [widePathFor] at the same index draw
/// the same palette in two compositions, which is what lets a golden show a
/// recognisable title swapping shape rather than two unrelated pictures.
///
/// ## Why the paths are distinct
///
/// A fixture sets `thumbPath` and `artPath` independently, and a rail that
/// silently reaches for the poster when it meant to reach for the landscape art
/// is a real bug that a same-looking panel would hide completely. Every panel
/// therefore carries a key ([posterKey], [wideKey], [neutralKey]), so a widget
/// test can assert *which* artwork the rail actually drew instead of inferring
/// it from pixels.
///
/// ## The palette is the point
///
/// `#141414` is the cinema, not the film. Pleya's chrome is deliberately near
/// black, and the only honest way to find out whether it *presents* content or
/// flattens it is to hand it content that is not already dark. The set below
/// deliberately spans warm orange, bright blue, green nature, a loud family
/// animation, a high-key comedy that is almost white, neon, and a drama dark
/// enough that it risks disappearing into the background entirely. Each of
/// those is one named [TvDiscoveryMood], so a test or a reviewer can say which
/// mood a picture is about rather than pointing at a swatch.
///
/// They are deterministic — palette by index, never by a hash of a title and
/// never random — so the same golden is the same bytes on every machine, and a
/// reordered fixture list shows up as a visible diff rather than a silent
/// reshuffle.
///
/// What they still cannot prove is hardware colour. Hoofdstuk 29's point about
/// rasterization, render scale and HDR applies most sharply to artwork. These
/// pictures catch "the dark chrome is crushing the content"; they do not
/// replace looking at a real library on a real television.
library;

import 'package:flutter/material.dart';
import 'package:pleya/widgets/optimized_media_image.dart';

/// The moods the discovery set deliberately spans.
///
/// Named rather than numbered because the question these fixtures exist to
/// answer is a question about content, not about indices: "does a high-key
/// comedy survive this chrome" is answerable, "does artwork 4 survive this
/// chrome" is not.
enum TvDiscoveryMood {
  /// Warm orange. Late sun, high saturation, the easiest thing for a dark
  /// scrim to muddy.
  warmOrange,

  /// Bright, clean blue. The other end of the temperature range from
  /// [warmOrange], and the one that most often gets read as "cold UI" when a
  /// theme tints its surfaces.
  brightBlue,

  /// Green nature. Mid luminance, low contrast against a dark ground — the
  /// mood most likely to lose its subject to a gradient footer.
  greenNature,

  /// Colourful family animation. Several strong hues in one panel, which is
  /// what breaks a chrome that assumes artwork has a single dominant colour.
  familyAnimation,

  /// Light comedy: high key, near white. The hardest case for a near-black UI,
  /// because the card's own edge, focus ring and gradient all have to stay
  /// visible against a panel that is brighter than any of them.
  lightComedy,

  /// Neon. Saturated magenta and cyan on near black — the case where a scrim
  /// either preserves the glow or turns it into mud.
  neon,

  /// Dark drama. Deliberately close to the `#141414` ground, so a golden shows
  /// whether the card still has an edge when its content does not supply one.
  darkDrama,

  /// A second warm entry, drier and dustier than [warmOrange], so "warm" is not
  /// represented by a single lucky swatch.
  desertEpic,

  /// Cold noir: dark, but blue-cast rather than neutral like [darkDrama].
  coldNoir,

  /// Pastel romance. Light and low-contrast — bright without being high-key,
  /// which is a different failure mode from [lightComedy].
  pastelRomance,

  /// Deep-space science fiction. Dark ground with one bright point of light.
  deepSpace,

  /// Monochrome classic. No hue at all, which is how you tell a chrome that
  /// tints artwork from one that does not.
  monochromeClassic,
}

class TvDiscoveryArtwork {
  const TvDiscoveryArtwork._();

  /// Makes every `OptimizedMediaImage` render a discovery panel. Pair with
  /// [remove] in `tearDownAll`, or the seam leaks into the next test file in
  /// the same process.
  ///
  /// A card asking for `discovery/poster/<n>` gets a 2:3-composed panel, one
  /// asking for `discovery/wide/<n>` gets the 16:9 composition of the same
  /// palette, and anything else — a source with no artwork at all — falls
  /// through to a neutral panel, which is the honest picture of a title whose
  /// server has no image for it.
  static void install() => OptimizedMediaImage.debugImageBuilder = (context, imagePath) => panel(imagePath);

  /// Clears the seam.
  static void remove() => OptimizedMediaImage.debugImageBuilder = null;

  /// The 2:3 poster path a fixture at [index] should carry in `thumbPath`.
  static String pathFor(int index) => 'discovery/poster/$index';

  /// The 16:9 landscape path a fixture at [index] should carry in `artPath`.
  /// Deliberately a different string from [pathFor] at the same index: the
  /// whole point is that a test can tell which one a rail asked for.
  static String widePathFor(int index) => 'discovery/wide/$index';

  /// Widget key on the poster panel for [index]. `find.byKey` on this proves a
  /// rail drew the poster and not the landscape art.
  static Key posterKey(int index) => ValueKey('tvDiscoveryArtwork/poster/$index');

  /// Widget key on the landscape panel for [index].
  static Key wideKey(int index) => ValueKey('tvDiscoveryArtwork/wide/$index');

  /// Widget key on the no-artwork panel.
  static const Key neutralKey = ValueKey('tvDiscoveryArtwork/neutral');

  /// How many distinct palettes the set holds. Indices wrap, so a fixture may
  /// exceed this; it just stops being able to promise that two entries differ.
  static int get paletteCount => _palettes.length;

  /// The mood pictured at [index]. Wraps with the palette list.
  static TvDiscoveryMood moodAt(int index) => _palettes[index % _palettes.length].mood;

  /// The index that pictures [mood] — the inverse of [moodAt], so a test that
  /// wants "the high-key comedy" can ask for it by name.
  static int indexOfMood(TvDiscoveryMood mood) => _palettes.indexWhere((p) => p.mood == mood);

  /// The panel for an artwork path, whichever set it names.
  static Widget panel(String? imagePath) {
    final poster = _indexOf(imagePath, 'discovery/poster/');
    if (poster != null) {
      return _DiscoveryPanel(key: posterKey(poster), palette: _palettes[poster % _palettes.length], wide: false);
    }
    final wide = _indexOf(imagePath, 'discovery/wide/');
    if (wide != null) {
      return _DiscoveryPanel(key: wideKey(wide), palette: _palettes[wide % _palettes.length], wide: true);
    }
    return const _NeutralPanel(key: neutralKey);
  }

  static int? _indexOf(String? imagePath, String prefix) {
    if (imagePath == null || !imagePath.startsWith(prefix)) return null;
    return int.tryParse(imagePath.substring(prefix.length));
  }

  /// The range a real library spans, in the order the fixtures use it.
  ///
  /// Ordered so that neighbours differ. A rail that happened to put its two
  /// darkest panels side by side would look like a rendering fault rather than
  /// like a library, and one that graded smoothly from light to dark would look
  /// like a designed gradient rather than like unrelated films.
  static const List<_Palette> _palettes = [
    _Palette(TvDiscoveryMood.warmOrange, Color(0xFFFF8A3D), Color(0xFFB32D0F), Color(0xFFFFE3B0)),
    _Palette(TvDiscoveryMood.brightBlue, Color(0xFF1E7FD6), Color(0xFF0B3E7A), Color(0xFFBFE6FF)),
    _Palette(TvDiscoveryMood.greenNature, Color(0xFF1E7A4B), Color(0xFF0B3B27), Color(0xFFCFF3D8)),
    _Palette(TvDiscoveryMood.familyAnimation, Color(0xFFFFCE2E), Color(0xFF7A3CFF), Color(0xFFFFFFFF)),
    _Palette(TvDiscoveryMood.lightComedy, Color(0xFFFFF6EE), Color(0xFFF2D9C4), Color(0xFFFFFFFF)),
    _Palette(TvDiscoveryMood.neon, Color(0xFFFF00A8), Color(0xFF1B0033), Color(0xFF45F0FF)),
    _Palette(TvDiscoveryMood.darkDrama, Color(0xFF14171A), Color(0xFF05070A), Color(0xFF6B7A8C)),
    _Palette(TvDiscoveryMood.desertEpic, Color(0xFFD98A2B), Color(0xFF6E3A12), Color(0xFFFFE7BC)),
    _Palette(TvDiscoveryMood.coldNoir, Color(0xFF0E1620), Color(0xFF263A52), Color(0xFFA9C8F5)),
    _Palette(TvDiscoveryMood.pastelRomance, Color(0xFFFFD9E8), Color(0xFFC9D8FF), Color(0xFFFFFFFF)),
    _Palette(TvDiscoveryMood.deepSpace, Color(0xFF101E42), Color(0xFF2C1550), Color(0xFF7CC8FF)),
    _Palette(TvDiscoveryMood.monochromeClassic, Color(0xFF202020), Color(0xFF6A6A6A), Color(0xFFF5F5F5)),
  ];
}

class _Palette {
  const _Palette(this.mood, this.top, this.bottom, this.highlight);

  final TvDiscoveryMood mood;
  final Color top;
  final Color bottom;

  /// The lightest note in the panel — a sky, a title treatment, a lit face. It
  /// is what makes artwork read as an image with a subject rather than as a
  /// two-stop gradient, and it is the first thing a too-dark chrome kills.
  final Color highlight;
}

/// One synthetic panel, composed for its aspect.
///
/// Both compositions share the palette, so the same title is recognisable
/// across the focus transition. What differs is where the light and the hard
/// shape sit: a poster carries its subject low and right, the way a 2:3 crop
/// does, and a landscape panel carries it left of centre with room on the right
/// for the metadata a focused discovery card puts there. A reviewer looking at
/// a rail should be able to tell the two apart without reading a key.
class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({super.key, required this.palette, required this.wide});

  final _Palette palette;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: wide ? Alignment.centerLeft : Alignment.topLeft,
          end: wide ? Alignment.centerRight : Alignment.bottomRight,
          colors: [palette.top, palette.bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: wide ? const Alignment(-0.6, -0.3) : const Alignment(-0.35, -0.55),
                radius: wide ? 0.8 : 0.95,
                colors: [palette.highlight.withValues(alpha: 0.85), palette.highlight.withValues(alpha: 0)],
              ),
            ),
          ),
          Align(
            alignment: wide ? const Alignment(-0.45, 0.85) : const Alignment(0.55, 0.75),
            child: FractionallySizedBox(
              widthFactor: wide ? 0.32 : 0.7,
              heightFactor: wide ? 0.3 : 0.42,
              child: DecoratedBox(decoration: BoxDecoration(color: palette.bottom.withValues(alpha: 0.55))),
            ),
          ),
          // Only the landscape composition gets a horizon. It is the cheapest
          // way to make a wide panel read as a still from a film rather than as
          // a stretched poster, and its absence is how a poster stays visibly a
          // poster when the two are side by side in one rail.
          if (wide)
            Align(
              alignment: const Alignment(0, 0.1),
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: 0.012,
                child: DecoratedBox(decoration: BoxDecoration(color: palette.highlight.withValues(alpha: 0.45))),
              ),
            ),
        ],
      ),
    );
  }
}

/// A source with no artwork at all. Kept reachable on purpose: a discovery rail
/// whose focused card has nothing to expand into is a state the design has to
/// survive, not one the fixtures should quietly avoid.
class _NeutralPanel extends StatelessWidget {
  const _NeutralPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(color: scheme.surfaceContainerHighest);
  }
}
