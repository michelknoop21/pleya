/// The artwork layer of a fase-8 Home hero slide (hoofdstuk 9.4 of
/// docs/tvos-unified-experience.md).
///
/// Extracted from `TvSpotlightBackground` rather than reused from it, for the
/// reason hoofdstuk 27 fase 8 gives: that widget paints a *fullscreen*
/// background and reasons in `MediaQuery.sizeOf` — screen width, screen
/// height, a viewport aspect ratio — while a hero slide is a 2.465:1 rounded
/// card whose box the caller already knows exactly. Handing the screen size to
/// a card-sized layer is how the DEC-057 request-ratio invariant gets broken:
/// the server would crop to the screen's ratio and Flutter would crop again to
/// the card's.
///
/// So this layer takes its box as an argument, and every decision follows from
/// that box:
///
/// * **Which artwork.** `MediaItem.billboardArt(containerAspectRatio: …)` with
///   the *card's* ratio, so a wide card resolves to a 16:9 backdrop and the
///   [BillboardArtKind] it returns is the truth about whether that artwork can
///   be drawn sharp.
/// * **What size to ask the server for.** The card's own pixels, at the card's
///   own ratio (DEC-057): the request box and the sharp layer have one shape,
///   so the server-side crop is a no-op instead of a second, invisible one.
/// * **How to draw it.** Sharp `BoxFit.cover` for a real backdrop or square
///   art; a blurred wash plus the poster drawn sharp at its own 2:3 in the
///   card's right half for a poster-only title; a themed gradient when the
///   title has no artwork at all.
///
/// **Never another title's artwork.** Every candidate comes from the one
/// `MediaItem` passed in — hoofdstuk 23 of the fase-8 brief, and the reason
/// this file resolves nothing and fetches nothing on its own. A group's
/// representative source decides what is *shown*; it never decides what is
/// activated (hoofdstuk 4.4), and the split is why this widget takes a
/// `MediaItem` and knows nothing about [UnifiedMediaGroup] at all.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_image_helper.dart' show ImageType;
import '../optimized_media_image.dart';
import 'tv_unified_layout.dart';

/// How [TvHeroArtwork] will draw [item] in a box of [containerAspectRatio].
///
/// A record rather than an implementation detail, and top-level, because
/// hoofdstuk 9.4's fallback chain is a claim a test should be able to make
/// about an item without pumping a widget or a network: give it a film with
/// only a poster and you get [TvHeroArtKind.posterFill], not a silent crop.
enum TvHeroArtKind {
  /// A real 16:9 backdrop (or square background art on a box narrow enough to
  /// want it), drawn sharp and cover-cropped.
  sharp,

  /// Only portrait poster art exists. It becomes a blurred, darkened fill with
  /// the poster itself drawn sharp at its own ratio — never a hugely magnified
  /// centre crop of a poster across a 2.465:1 card.
  posterFill,

  /// No usable artwork on this title at all.
  none,
}

/// Which artwork path [item] resolves to for a hero card of
/// [containerAspectRatio], and how it has to be drawn.
///
/// Pure, so `test/widgets/tv_hero_artwork_test.dart` can assert the fallback
/// order — backdrop, then square, then poster-as-fill, then nothing — directly.
({TvHeroArtKind kind, String? path}) tvHeroArtFor(MediaItem item, {required double containerAspectRatio}) {
  final art = item.billboardArt(containerAspectRatio: containerAspectRatio);
  if (art != null && art.canRenderSharp) return (kind: TvHeroArtKind.sharp, path: art.path);

  // `billboardArt` already fell through to whatever poster-ish art exists, and
  // told us it must not be drawn sharp under the app's own title.
  final fallback = art?.path ?? item.thumbPath ?? item.grandparentThumbPath;
  if (fallback != null && fallback.isNotEmpty) return (kind: TvHeroArtKind.posterFill, path: fallback);
  return (kind: TvHeroArtKind.none, path: null);
}

class TvHeroArtwork extends StatelessWidget {
  const TvHeroArtwork({super.key, required this.item, required this.size, this.client});

  final MediaItem item;

  /// The card's box, in logical pixels. Not read off `MediaQuery` — see the
  /// library doc.
  final Size size;

  final MediaServerClient? client;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final art = tvHeroArtFor(item, containerAspectRatio: size.width / size.height);

    return switch (art.kind) {
      TvHeroArtKind.none => _EmptyHeroArt(tokens: tk),
      TvHeroArtKind.sharp => OptimizedMediaImage(
        client: client,
        imagePath: art.path,
        width: size.width,
        height: size.height,
        fit: BoxFit.cover,
        // Top-anchored for the same reason the fullscreen billboard is: a
        // backdrop taller than its slot loses the sky, not the faces.
        alignment: Alignment.topCenter,
        // heroArt, not art: same wide-backdrop handling, but sized against
        // the TV output surface. On `art`'s 2560 cap this card -- 3538 physical
        // pixels wide on Apple TV -- received every backdrop 1.38x too small,
        // and the request box was reshaped to 16:9 on the way out.
        imageType: ImageType.heroArt,
        fadeInDuration: Duration.zero,
        placeholder: (context, _) => _EmptyHeroArt(tokens: tk),
        errorWidget: (context, _, _) => _EmptyHeroArt(tokens: tk),
      ),
      TvHeroArtKind.posterFill => _PosterFillHeroArt(client: client, path: art.path!, size: size, tokens: tk),
    };
  }
}

/// Hoofdstuk 9.4, "Alleen poster": the poster sharp on the right, the same
/// poster blurred and darkened behind it. One artwork, two roles — so the card
/// still reads as *this* title rather than as a placeholder, and nothing is
/// borrowed from another one.
class _PosterFillHeroArt extends StatelessWidget {
  const _PosterFillHeroArt({required this.client, required this.path, required this.size, required this.tokens});

  final MediaServerClient? client;
  final String path;
  final Size size;
  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    // The sharp poster keeps its own 2:3 and is inset from the card's edges, so
    // it reads as a poster standing in the frame rather than as a failed
    // backdrop. Height-driven: 2:3 of the card height is always narrower than
    // the card, on every clamp the layout can produce.
    final posterHeight = size.height * 0.82;
    final posterWidth = posterHeight * TvDiscoveryLayout.posterAspectRatio;

    return Stack(
      fit: StackFit.expand,
      children: [
        // `blurArtwork`'s own default sigma is the screenshot-obfuscation
        // switch; this is a design layer, so the blur is explicit and the
        // darkening rides on top of it.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: OptimizedMediaImage(
            client: client,
            imagePath: path,
            width: size.width,
            height: size.height,
            fit: BoxFit.cover,
            imageType: ImageType.poster,
            fadeInDuration: Duration.zero,
            placeholder: (context, _) => _EmptyHeroArt(tokens: tokens),
            errorWidget: (context, _, _) => _EmptyHeroArt(tokens: tokens),
          ),
        ),
        ColoredBox(color: tokens.bg.withValues(alpha: 0.44)),
        Align(
          alignment: const Alignment(0.62, 0),
          child: SizedBox(
            width: posterWidth,
            height: posterHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TvDiscoveryLayout.cardRadius),
              child: OptimizedMediaImage(
                client: client,
                imagePath: path,
                width: posterWidth,
                height: posterHeight,
                fit: BoxFit.cover,
                imageType: ImageType.poster,
                fadeInDuration: Duration.zero,
                placeholder: (context, _) => ColoredBox(color: tokens.surface),
                errorWidget: (context, _, _) => ColoredBox(color: tokens.surface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hoofdstuk 9.4, "Geen artwork": a Pleya gradient the title type still reads
/// against. Not a random image and not another title's backdrop — the hero
/// stays usable and stays honest.
class _EmptyHeroArt extends StatelessWidget {
  const _EmptyHeroArt({required this.tokens});

  final MonoTokens tokens;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [tokens.surface, tokens.bg],
        ),
      ),
      child: Align(
        alignment: const Alignment(0.62, 0),
        child: Icon(Symbols.movie_rounded, fill: 1, size: 64, color: tokens.text.withValues(alpha: 0.10)),
      ),
    );
  }
}
