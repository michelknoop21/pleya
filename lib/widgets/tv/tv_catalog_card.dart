/// The card body every TV surface in the catalog language draws — the poster
/// block, its markers, and the two or three lines under it.
///
/// It was `TvUnifiedMediaCard` and nothing else until 7 September 2026, when
/// [DEC-108](../../../docs/DECISIONS.md#dec-108) put the kijklijst, Aanvragen
/// and Zoeken on the same card. Those three do not carry an
/// [UnifiedMediaGroup]: a watchlist entry is a title the servers may not hold,
/// a Seerr row is a request against TMDB, and only Zoeken's film and series
/// results are groups at all. What they *do* share is every measurement and
/// every state of the card — 281 by 422 on the grid inset, the ring round the
/// artwork alone, the two-line title, the shadow that deepens under focus.
///
/// So the card is split along that line. This file owns the presentation and
/// knows nothing about media; each surface owns the adapter that fills it in.
/// The alternative was a second copy of the card per screen, which is exactly
/// how the three screens drifted apart in the first place (CAT11).
///
/// **What a caller supplies** is the artwork widget, up to three markers in
/// named corners, and the text. What it must *not* supply is geometry: the
/// width comes from [TvCatalogGrid.forWidth] and everything inside it from
/// [TvCatalogLayout], for the reason that file's own header gives.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

/// The artwork box of a catalog card — the real one and the loading
/// placeholder both carry it.
///
/// Shared deliberately: the placeholder's whole contract is that it occupies the
/// box the poster is about to, and one key on both is what lets a test assert
/// that rather than trust it.
const Key tvCatalogPosterKey = ValueKey('tvCatalogPoster');

class TvCatalogCard extends StatefulWidget {
  const TvCatalogCard({
    super.key,
    required this.width,
    required this.artwork,
    required this.title,
    required this.meta,
    required this.onSelect,
    this.tertiary,
    this.topLeftMarker,
    this.topRightMarker,
    this.bottomLeftMarker,
    this.progressFraction,
    this.onContextMenu,
    this.focusNode,
    this.autofocus = false,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
    this.onFocusChange,
    this.semanticLabel,
  });

  /// Resolved by the grid from the viewport, never assumed: see
  /// [TvCatalogGrid.forWidth].
  final double width;

  /// Fills the 2:3 poster box. The caller draws its own image, placeholder or
  /// fallback there; this widget clips it, rounds it, shadows it and lifts it
  /// under focus.
  final Widget artwork;

  /// Markers on the artwork, in the three corners the mockups use: the source
  /// count and Seerr's status capsule top left, watched and NEW top right,
  /// "Niet beschikbaar" bottom left.
  ///
  /// Named slots rather than a free list of `Positioned` children, because
  /// which corner a marker sits in is a contract and not a caller's choice:
  /// hoofdstuk 10.3 puts the source badge opposite the watched tick precisely
  /// so a title that is both duplicated and watched never collides with itself.
  final Widget? topLeftMarker;
  final Widget? topRightMarker;
  final Widget? bottomLeftMarker;

  /// How far through the title this card is, as a fraction, or null for no bar.
  final double? progressFraction;

  final String title;

  /// The line under the title: "2024 · Sciencefiction", "2024 · Serie".
  final String meta;

  /// A third, quieter line. Only Alle aanvragen draws one ("Aangevraagd door
  /// michel"); everything else leaves it null and gets the two-line card the
  /// rest of the app has. A card that draws it is [TvCatalogLayout.cardHeight]
  /// with `extraMetaLines: 1` tall, and the grid it sits in has to know that.
  final String? tertiary;

  /// Activation. A bare callback with no media in it — the card hands nothing
  /// upward and navigates nowhere.
  final VoidCallback onSelect;

  /// Opens the hoofdstuk 23 context menu. Null on a surface that has no
  /// actions to offer, which also leaves `FocusableWrapper.onLongPress` null
  /// so a long Select stays a plain Select and the context-menu key falls
  /// through unhandled rather than arming the select suppressor for nothing.
  final VoidCallback? onContextMenu;

  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  /// Menu on this card. Null is the ordinary case and leaves the press to the
  /// route, which is what pops a nested screen; a page that is *itself* in a
  /// sub-mode — Ontdekken with one shelf expanded — sets it so Menu leaves that
  /// mode before it leaves the page.
  final VoidCallback? onBack;

  final ValueChanged<bool>? onFocusChange;

  /// What a screen reader reads for the whole card. The child is wrapped in
  /// `ExcludeSemantics`, so this is the entire reading — hoofdstuk 25's
  /// "decoratieve backdrops en clearlogo's worden uitgesloten van dubbele
  /// semantiek", which without it says the title and the year twice.
  final String? semanticLabel;

  @override
  State<TvCatalogCard> createState() => _TvCatalogCardState();
}

class _TvCatalogCardState extends State<TvCatalogCard> {
  /// Focus is a compositing input here, not just something the ring reacts to:
  /// the card's elevation and the brightness of its artwork both read it.
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvCatalogLayout.cardRadius * scale;
    final isFocused = _isFocused;

    // The width bounds the *wrapper*, not the card content. `FocusableWrapper`
    // draws its ring as a border on a container around the child, which adds
    // `focusBorderWidth` to each side — so sizing the child instead would make
    // every card 5 logical pixels wider than the grid budgeted for it, and a
    // six-column row would overflow by thirty. Constraining the outside lets the
    // ring eat into the card rather than out of the gutter.
    return SizedBox(
      width: widget.width,
      child: FocusableWrapper(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onSelect: widget.onSelect,
        onLongPress: widget.onContextMenu,
        enableLongPress: widget.onContextMenu != null,
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          widget.onFocusChange?.call(focused);
        },
        onNavigateUp: widget.onNavigateUp,
        onNavigateDown: widget.onNavigateDown,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onBack: widget.onBack,
        borderRadius: radius,
        focusScale: FocusTheme.fullCardFocusScale,
        // DEC-065 punt 4: the ring goes round the *artwork alone*, so the
        // wrapper keeps the focus, the scale and the lift but stops drawing
        // the box — the ring below is drawn around the poster block instead.
        // The wrapper still owns `focusScale`, which applies in every mode.
        mode: FocusIndicatorMode.delegated,
        semanticLabel: widget.semanticLabel,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The ring, round the poster block and nothing else (DEC-065
              // punt 4). It is drawn in `foregroundDecoration` on a container
              // whose padding is exactly the inset the wrapper's own border +
              // gap used to cost, so the poster keeps the size and position
              // the grid budgeted for it: the ring lands on the card's outer
              // bounds with `cardFocusRingGap` of page between it and the
              // artwork, and the footer below sits outside it entirely.
              AnimatedContainer(
                duration: tk.fast,
                curve: Curves.easeOut,
                padding: EdgeInsets.all(TvCatalogLayout.cardContentInset(scale)),
                foregroundDecoration: FocusTheme.focusDecoration(
                  context,
                  isFocused: isFocused,
                  borderRadius: radius + TvCatalogLayout.cardFocusRingGap * scale,
                ),
                // The shadow lives outside the clip, so it is a pool the poster
                // casts on the page rather than something drawn inside the
                // poster. `AnimatedContainer` rather than a swap, because the
                // whole point is that the card *rises* under the focus instead
                // of snapping to a second appearance.
                child: AnimatedContainer(
                  duration: tk.fast,
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isFocused ? TvCatalogLayout.cardFocusShadowAlpha : TvCatalogLayout.cardShadowAlpha,
                        ),
                        blurRadius:
                            (isFocused ? TvCatalogLayout.cardFocusShadowBlur : TvCatalogLayout.cardShadowBlur) * scale,
                        offset: Offset(
                          0,
                          (isFocused ? TvCatalogLayout.cardFocusShadowOffsetY : TvCatalogLayout.cardShadowOffsetY) *
                              scale,
                        ),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    key: tvCatalogPosterKey,
                    borderRadius: BorderRadius.circular(radius),
                    child: _ArtworkBox(
                      scale: scale,
                      isFocused: isFocused,
                      artwork: widget.artwork,
                      topLeftMarker: widget.topLeftMarker,
                      topRightMarker: widget.topRightMarker,
                      bottomLeftMarker: widget.bottomLeftMarker,
                      progressFraction: widget.progressFraction,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.cardContentInset(scale)),
                child: _Footer(title: widget.title, meta: widget.meta, tertiary: widget.tertiary, scale: scale, tk: tk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkBox extends StatelessWidget {
  const _ArtworkBox({
    required this.scale,
    required this.isFocused,
    required this.artwork,
    required this.topLeftMarker,
    required this.topRightMarker,
    required this.bottomLeftMarker,
    required this.progressFraction,
  });

  final double scale;
  final bool isFocused;
  final Widget artwork;
  final Widget? topLeftMarker;
  final Widget? topRightMarker;
  final Widget? bottomLeftMarker;
  final double? progressFraction;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final inset = TvCatalogLayout.badgeInset * scale;
    final fraction = progressFraction;

    return AspectRatio(
      aspectRatio: TvCatalogLayout.posterAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          artwork,
          // Above the image and below every marker, so the poster brightens but
          // the badges keep the contrast they were measured for. The content
          // itself answers the remote, rather than only the chrome around it.
          AnimatedOpacity(
            duration: tk.fast,
            opacity: isFocused ? 1 : 0,
            child: ColoredBox(color: Colors.white.withValues(alpha: TvCatalogLayout.cardFocusArtworkLift)),
          ),
          if (topLeftMarker != null) Positioned(top: inset, left: inset, child: topLeftMarker!),
          if (topRightMarker != null) Positioned(top: inset, right: inset, child: topRightMarker!),
          if (bottomLeftMarker != null) Positioned(bottom: inset, left: inset, child: bottomLeftMarker!),
          if (fraction != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TvCatalogResumeBar(fraction: fraction, scale: scale),
            ),
        ],
      ),
    );
  }
}

/// The placeholder fill a poster sits on while its image loads or fails.
///
/// A widget rather than a colour constant, because every caller needs the same
/// two-layer composition — fill, then image — and one of them getting it wrong
/// shows up as a card that flashes black between pages.
class TvCatalogArtworkFill extends StatelessWidget {
  const TvCatalogArtworkFill({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return ColoredBox(
      color: tk.text.withValues(alpha: TvCatalogLayout.artworkPlaceholderFill),
      child: child,
    );
  }
}

/// Hoofdstuk 10.3's dark capsule on the artwork: "2 bronnen", "Niet
/// beschikbaar", "In afwachting".
///
/// Two shapes, one widget. The default is the small rounded rectangle the
/// source badge has always been; [TvCatalogArtworkBadge.status] is the pill
/// with a coloured dot DEC-108 gives an aanvraag, where the dot carries the
/// state and the word says what it is. They share a fill and a type ramp on
/// purpose: a viewer should read them as the same kind of mark, and a second
/// capsule style on the same artwork is how a grid stops looking like one grid.
class TvCatalogArtworkBadge extends StatelessWidget {
  const TvCatalogArtworkBadge({super.key, required this.label, this.muted = false}) : dotColor = null;

  const TvCatalogArtworkBadge.status({super.key, required this.label, required this.dotColor, this.muted = true});

  final String label;

  /// Non-null draws the pill form with this dot in front of the label.
  final Color? dotColor;

  /// Whether the label reads one step below full ink.
  ///
  /// The source count does not: it is a fact about the title and the mockups
  /// give it the page's own ink. A state does, except the one that is good news
  /// — mockup 35's "Beschikbaar" is the single capsule drawn at full ink, so it
  /// separates from the waiting ones without needing a second shape.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final dot = dotColor;
    final ink = muted ? Colors.white.withValues(alpha: TvCatalogLayout.badgeInkMuted) : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: TvCatalogLayout.badgeFill),
        borderRadius: BorderRadius.circular(
          (dot == null ? TvCatalogLayout.badgeRadius : TvCatalogLayout.badgePillRadius) * scale,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal:
              (dot == null ? TvCatalogLayout.badgePaddingHorizontal : TvCatalogLayout.badgePillPaddingHorizontal) *
              scale,
          vertical: TvCatalogLayout.badgePaddingVertical * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: TvCatalogLayout.badgeDotSize * scale,
                height: TvCatalogLayout.badgeDotSize * scale,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              SizedBox(width: TvCatalogLayout.badgeDotGap * scale),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.badgeFontSize * scale,
                fontWeight: FontWeight.w600,
                // White rather than the theme ink: this capsule sits on artwork,
                // and in the light theme the theme ink is near-black over a
                // black capsule.
                color: ink,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The watched marker, as a capsule on the artwork.
///
/// Same dark capsule as the source badge rather than a bare glyph: a white tick
/// laid straight onto artwork disappears into a bright poster, and this is the
/// one marker that has to be readable across every image in the grid.
class TvCatalogWatchedBadge extends StatelessWidget {
  const TvCatalogWatchedBadge({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: TvCatalogLayout.badgeFill),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: EdgeInsets.all(TvCatalogLayout.watchedBadgePadding * scale),
        child: Icon(
          Symbols.check_rounded,
          size: TvCatalogLayout.watchedIconSize * scale,
          // White, like the badge beside it: both sit on artwork, where the
          // theme's ink is the wrong colour in light mode.
          color: Colors.white,
        ),
      ),
    );
  }
}

/// The resume bar along the artwork's bottom edge.
///
/// Brand red, which is one of the four things hoofdstuk 8.2 and 34 allow red to
/// be used for. Drawn as two boxes rather than through `MediaProgressBar`
/// because it has to sit flush in the artwork's clip with no radius and no
/// track inset — the shared bar is a rounded, padded control for list rows.
class TvCatalogResumeBar extends StatelessWidget {
  const TvCatalogResumeBar({super.key, required this.fraction, required this.scale});

  final double fraction;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return SizedBox(
      height: TvCatalogLayout.progressBarHeight * scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: ColoredBox(color: tk.accent),
          ),
        ],
      ),
    );
  }
}

/// Title plus one or two context lines, directly under the artwork.
///
/// **There is no strip.** The first build drew this on a filled panel with the
/// artwork's bottom corners squared into it, so a card was a poster glued to a
/// caption bar. Against grey placeholders that read as one object, which is
/// what it was for; against real artwork it read as a grey slab bolted under
/// every image, and twelve of them turned a colourful grid into a filing
/// cabinet. Text on the page background costs the "one object" reading and buys
/// back the thing hoofdstuk 10.2 actually ranks first — the artwork is now the
/// only surface on the card, fully rounded on all four corners, and nothing
/// competes with it.
///
/// **And no fill under focus either** ([DEC-065](../../../docs/DECISIONS.md)
/// punt 4). The first correction kept a faint surface behind the text while
/// the card held the focus, on the reasoning that the ring otherwise drew a
/// box round a poster and two lines of page-coloured nothing. The north star
/// answers that differently and more simply: the ring goes round the artwork
/// alone, so there is no box wanting a floor, and the focused card's text sits
/// on the same page as its eleven neighbours. What marks it out is the poster
/// — ring, scale, lift, shadow — which is where hoofdstuk 10.2 wanted the
/// attention in the first place.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.title,
    required this.meta,
    required this.tertiary,
    required this.scale,
    required this.tk,
  });

  final String title;
  final String meta;
  final String? tertiary;
  final double scale;
  final MonoTokens tk;

  @override
  Widget build(BuildContext context) {
    final third = tertiary;

    return Padding(
      padding: EdgeInsets.symmetric(
        // The bottom is reserved whether the card holds the focus or not.
        // Paying for it only on focus made the focused card taller than the
        // five beside it, and a taller card in row one pushed row two down
        // while the eye was on it — the opposite of the "ruimtelijk stabiel"
        // focus hoofdstuk 10.2b requires of the complete catalogus.
        vertical: TvCatalogLayout.cardFooterPaddingVertical * scale,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hoofdstuk 10.2: at most two lines — and always the height of two,
          // whether the title needs them or not. Sizing to content made a card
          // with a long title taller than the five beside it, so its footer sat
          // lower and the row lost the baseline that makes a grid read as a
          // grid. Ellipsis rather than shrinking, for the same reason: a title
          // that fits by getting smaller stops matching its neighbours.
          SizedBox(
            height: TvCatalogLayout.cardTitleFontSize * scale * TvCatalogLayout.cardTitleLineHeight * 2,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.cardTitleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkPrimary),
                height: TvCatalogLayout.cardTitleLineHeight,
              ),
            ),
          ),
          SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TvCatalogLayout.cardMetaFontSize * scale,
              color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              height: TvCatalogLayout.cardMetaLineHeight,
            ),
          ),
          if (third != null) ...[
            SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale),
            Text(
              third,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.cardMetaFontSize * scale,
                // A step quieter than the meta line above it: who asked for a
                // title is context, not identity, and at three metres a third
                // line at the same weight competes with the one that says what
                // the card is.
                color: tk.text.withValues(alpha: TvCatalogLayout.inkTertiary),
                height: TvCatalogLayout.cardMetaLineHeight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
