/// One logical title in the Films or Series grid (hoofdstuk 10.2 and 10.3 of
/// docs/tvos-unified-experience.md).
///
/// A card shows a [UnifiedMediaGroup], not a [MediaItem]: one poster per title,
/// however many servers hold it. That is the whole point of the unified
/// catalog, and it is why this is a new widget rather than a configuration of
/// `MediaCard` — that one is bound to a concrete item and carries its own
/// navigation, and a card that could route on its own would be a second
/// activation path beside the one hoofdstuk 4.4 fixed.
///
/// ## Hierarchy, in the order the eye should resolve it
///
/// 1. **Artwork.** It fills the card's width at 2:3 and everything else is
///    smaller, dimmer or below it. Hoofdstuk 10.2 is binding on the aspect for
///    both pages; the Series mockup's landscape clearlogo variant is marked
///    richtinggevend precisely so this stays one grid rhythm.
/// 2. **Title**, up to two lines.
/// 3. **Watch state** — the resume bar on the artwork's bottom edge, the tick
///    in the context line.
/// 4. **Source multiplicity**, and only when there is any: hoofdstuk 10.3 puts
///    the badge on `sources.length > 1` and nowhere else. "1 bron" is not a
///    fact worth a capsule, and a server name on every card would turn a
///    catalog into an inventory.
///
/// The meta footer is a solid strip under the artwork rather than text laid
/// over it. Both come from the mockups — Films overlays, Series uses a footer —
/// and the footer is the one that survives contact with reality: an overlay
/// needs the poster cropped away from 2:3 to leave room, and a title over
/// artwork is legible or not depending on the artwork.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../new_content_badge.dart';
import '../../utils/layout_constants.dart';
import '../optimized_media_image.dart';
import 'tv_unified_layout.dart';

class TvUnifiedMediaCard extends StatefulWidget {
  const TvUnifiedMediaCard({
    super.key,
    required this.group,
    required this.width,
    required this.onSelect,
    this.clientFor,
    this.focusNode,
    this.autofocus = false,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onFocusChange,
  });

  final UnifiedMediaGroup group;

  /// Resolved by the grid from the viewport, never assumed: see
  /// [TvCatalogGrid.forWidth].
  final double width;

  /// Activation. Deliberately a bare callback with no source in it — the card
  /// hands the *group* upwards and the fase-4 coordinator decides which
  /// concrete source anything opens (hoofdstuk 4.4).
  final VoidCallback onSelect;

  /// Resolves the client that can sign this group's artwork URL. Null renders
  /// the placeholder, which is what an offline or not-yet-bound server should
  /// look like rather than a broken image.
  final MediaServerClient? Function(String serverId)? clientFor;

  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvUnifiedMediaCard> createState() => _TvUnifiedMediaCardState();
}

class _TvUnifiedMediaCardState extends State<TvUnifiedMediaCard> {
  /// Focus is a compositing input here, not just something the ring reacts to:
  /// the card's elevation and the brightness of its artwork both read it.
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvCatalogLayout.cardRadius * scale;
    final isFocused = _isFocused;
    final group = widget.group;
    final clientFor = widget.clientFor;

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
        onFocusChange: (focused) {
          setState(() => _isFocused = focused);
          widget.onFocusChange?.call(focused);
        },
        onNavigateUp: widget.onNavigateUp,
        onNavigateDown: widget.onNavigateDown,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        borderRadius: radius,
        focusScale: FocusTheme.fullCardFocusScale,
        // DEC-065 punt 4: the ring goes round the *artwork alone*, so the
        // wrapper keeps the focus, the scale and the lift but stops drawing
        // the box — the ring below is drawn around the poster block instead.
        // The wrapper still owns `focusScale`, which applies in every mode.
        mode: FocusIndicatorMode.delegated,
        semanticLabel: semanticLabelFor(group),
        // Hoofdstuk 25: "Decoratieve backdrops en clearlogo's worden uitgesloten
        // van dubbele semantiek." Without this the wrapper's composed label is
        // read *and then* every visible string under it, so VoiceOver says the
        // title and the year twice on every card — the composed sentence, then
        // the title, then the meta line. The label above is the whole reading;
        // the artwork, the badge and the footer are how it is drawn.
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
                    child: _Artwork(group: group, scale: scale, clientFor: clientFor, isFocused: isFocused),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.cardContentInset(scale)),
                child: _Footer(group: group, scale: scale, tk: tk, isFocused: isFocused),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The artwork box of a catalog card — the real one and the loading
/// placeholder both carry it.
///
/// Shared deliberately: the placeholder's whole contract is that it occupies the
/// box the poster is about to, and one key on both is what lets a test assert
/// that rather than trust it.
const Key tvCatalogPosterKey = ValueKey('tvCatalogPoster');

/// What VoiceOver reads for one card (hoofdstuk 25).
///
/// Title first, then only the facts that are actually true of this group:
/// announcing "1 source, not watched" on every card would make a grid of forty
/// unusable to listen to. Public and pure so the semantics contract is
/// assertable without pumping a widget.
String semanticLabelFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  final parts = <String>[
    item.displayTitle,
    if (item.year != null) '${item.year}',
    ?_watchStatePhrase(group),
    if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
  ];
  return parts.join(', ');
}

/// How far through the title this group is, in words, or null when there is
/// nothing worth saying.
///
/// Hoofdstuk 25's card example is "Dune, 2021, 42 procent bekeken, 3 bronnen",
/// so a partly-watched title is announced as a *percentage* rather than as
/// "in progress" — the number is the part a listener can act on, and it is the
/// same number the bar under the artwork draws. `inProgress` is what is left
/// when the representative source reports progress without a runtime to measure
/// it against, which is the one case where the bar cannot be drawn either.
String? _watchStatePhrase(UnifiedMediaGroup group) {
  if (group.watchState.isWatched) return t.unifiedCatalog.semantics.watched;
  if (!group.watchState.hasActiveProgress) return null;
  final fraction = resumeFractionFor(group);
  if (fraction == null) return t.unifiedCatalog.semantics.inProgress;
  return t.accessibility.mediaCardPartiallyWatched(percent: (fraction * 100).round());
}

/// How far through this title the group is, as a fraction, or null when there
/// is nothing to draw.
///
/// Read off the *representative* source's item, which hoofdstuk 13.2 already
/// chose as the one whose progress speaks for the group — so a film half
/// watched on the laptop server and untouched on the NAS shows one bar, not an
/// average of two runtimes that are not comparable.
///
/// Top-level and pure because two callers need the same number: the bar the
/// card draws, and the percentage [semanticLabelFor] speaks. Computing it twice
/// is how the picture and the announcement drift apart.
double? resumeFractionFor(UnifiedMediaGroup group) {
  if (!group.watchState.hasActiveProgress) return null;
  final item = group.sources
      .firstWhere(
        (s) => s.sourceKey == group.watchState.representativeSourceKey,
        orElse: () => group.representativeSource,
      )
      .item;
  final offset = item.viewOffsetMs;
  final duration = item.durationMs;
  if (offset == null || duration == null || duration <= 0) return null;
  return (offset / duration).clamp(0.0, 1.0);
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.group, required this.scale, required this.clientFor, required this.isFocused});

  final UnifiedMediaGroup group;
  final double scale;
  final MediaServerClient? Function(String serverId)? clientFor;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final item = group.representativeSource.item;
    final serverId = group.representativeSource.serverId.value;
    final inset = TvCatalogLayout.badgeInset * scale;

    return AspectRatio(
      aspectRatio: TvCatalogLayout.posterAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: tk.text.withValues(alpha: TvCatalogLayout.artworkPlaceholderFill),
            child: OptimizedMediaImage(
              client: clientFor?.call(serverId),
              imagePath: item.thumbPath,
              fit: BoxFit.cover,
              fallbackIcon: Symbols.movie_rounded,
            ),
          ),
          // Above the image and below every marker, so the poster brightens but
          // the badges keep the contrast they were measured for. The content
          // itself answers the remote, rather than only the chrome around it.
          AnimatedOpacity(
            duration: tk.fast,
            opacity: isFocused ? 1 : 0,
            child: ColoredBox(color: Colors.white.withValues(alpha: TvCatalogLayout.cardFocusArtworkLift)),
          ),
          // Hoofdstuk 10.3: only above one known source, and never a server
          // name or logo.
          if (group.hasMultipleSources)
            Positioned(
              top: inset,
              left: inset,
              child: _SourceBadge(count: group.sources.length, scale: scale),
            ),
          // Opposite corner from the source badge, so a title that is both
          // duplicated and watched carries two markers that never collide.
          //
          // NEW shares that corner with the watched tick, and the two cannot
          // both appear: `newBadgeLabel` returns null for a film with a view
          // count and for a show with every episode seen, so "new" and "watched"
          // are mutually exclusive by construction rather than by a rule this
          // widget has to keep. Hoofdstuk 10.2 ("Nieuw-badge blijft bestaan")
          // and 33.3, which binds the marking for Series; the same
          // `NewContentBadge` every other card in the app already uses, so the
          // one place the brand gradient reaches the grid looks the same here as
          // it does everywhere else.
          if (group.watchState.isWatched)
            Positioned(
              top: inset,
              right: inset,
              child: _WatchedBadge(scale: scale),
            )
          else
            Positioned(
              top: inset,
              right: inset,
              child: NewContentBadge(item: group.representativeSource.item),
            ),
          if (_resumeFraction != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ResumeBar(fraction: _resumeFraction!, scale: scale),
            ),
        ],
      ),
    );
  }

  double? get _resumeFraction => resumeFractionFor(group);
}

/// Hoofdstuk 10.3's "N bronnen" capsule.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.count, required this.scale});

  final int count;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: TvCatalogLayout.badgeFill),
        borderRadius: BorderRadius.circular(TvCatalogLayout.badgeRadius * scale),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: TvCatalogLayout.badgePaddingHorizontal * scale,
          vertical: TvCatalogLayout.badgePaddingVertical * scale,
        ),
        child: Text(
          t.unifiedCatalog.sources(count: count),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: TvCatalogLayout.badgeFontSize * scale,
            fontWeight: FontWeight.w600,
            // White rather than the theme ink: this capsule sits on artwork, and
            // in the light theme the theme ink is near-black over a black
            // capsule.
            color: Colors.white,
            height: 1.1,
          ),
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
class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge({required this.scale});

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
class _ResumeBar extends StatelessWidget {
  const _ResumeBar({required this.fraction, required this.scale});

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

/// Title plus one context line, directly under the artwork.
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
  const _Footer({required this.group, required this.scale, required this.tk, required this.isFocused});

  final UnifiedMediaGroup group;
  final double scale;
  final MonoTokens tk;

  /// Text emphasis only — the focused title brightens, nothing gains a
  /// surface (see the class doc).
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final item = group.representativeSource.item;
    final context_ = _contextLine;

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
              item.displayTitle,
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
            context_,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TvCatalogLayout.cardMetaFontSize * scale,
              color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Year and first genre, as the mockups show and hoofdstuk 10.2 allows
  /// ("Jaar optioneel onder titel").
  ///
  /// One genre, not the list: at card width a second one is always truncated,
  /// and a truncated genre reads as a broken string rather than as more
  /// information. Empty when neither is known, which keeps the line's height
  /// reserved — dropping the row instead would make cards in the same row
  /// different heights and break the grid's baseline.
  /// The line under the title, and the one place a show is allowed to look
  /// unlike a film.
  ///
  /// A series is a different object from a film: you resume into an episode,
  /// not into a runtime, and "2015 · Family" under *Bluey* tells a viewer
  /// nothing they can act on. So a show spends its second slot on how much
  /// there is of it rather than on a genre — hoofdstuk 33.3's "S/A-aanduiding
  /// onder de titel". Films keep the genre, which is the fact that separates
  /// two films of the same year.
  ///
  /// Falls back to the genre when the backend did not report a season count, so
  /// a show whose `childCount` is missing gets a film's line rather than a line
  /// with a hole in it.
  String get _contextLine {
    final item = group.representativeSource.item;
    final parts = <String>[if (item.year != null) '${item.year}', ?_seasonsOrGenre(item)];
    return parts.join('  ·  ');
  }

  String? _seasonsOrGenre(MediaItem item) {
    if (item.kind == MediaKind.show) {
      final seasons = item.childCount ?? 0;
      if (seasons > 0) {
        return seasons == 1 ? t.unifiedCatalog.oneSeason : t.unifiedCatalog.seasons(count: seasons);
      }
    }
    final genre = (item.genres ?? const <String>[]).firstOrNull;
    return genre != null && genre.isNotEmpty ? genre : null;
  }
}
