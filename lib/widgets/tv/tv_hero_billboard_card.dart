/// One slide of the fase-8 Home featured carousel: the rounded, in-page
/// billboard of `docs/assets/tvos-unified/northstar/01-home.jpg` (33.1), which
/// is binding on this composition.
///
/// ## Presentation only
///
/// This widget takes a [UnifiedMediaGroup] for what it *says* and a concrete
/// representative [MediaItem] for what it *draws*, and it activates nothing.
/// The two CTAs are slots: the carousel hands in already-wired buttons, so the
/// hoofdstuk 4.4 boundary — a representative source never decides activation —
/// cannot be crossed from inside a presentation widget that has no coordinator
/// to reach for in the first place.
///
/// ## Why the card, and not the page
///
/// The fase-0..7 Home drew its hero as a fullscreen `TvSpotlightBackground`
/// with the rail sliding up over it. 33.1's first binding sentence is "de
/// featured card als afgeronde kaart ín de pagina … nooit full bleed", so this
/// is a sized box with a radius, a shadow and its own clip, laid out by the
/// feed above the first row rather than behind it. Everything that followed
/// from full-bleed — the ken-burns push, the deep bottom scrim that had to
/// carry a rail, the `AnimatedSlide` reveal — is gone with it, not ported.
///
/// ## Geometry does not depend on content
///
/// Title, meta line and synopsis are each pinned to the height
/// [TvHomeLayout] budgets. A two-line title and a one-line title put the CTA
/// row in the same place, so advancing the carousel never moves the buttons
/// out from under the remote — the hero equivalent of the constant-height rule
/// [TvExpandableMediaTile] keeps for a rail.
library;

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_image_helper.dart' show ImageType;
import '../optimized_media_image.dart';
import 'tv_unified_layout.dart';

/// The hero's one metadata line: kind, genre, year, runtime, and — only when
/// there is more than one — the source count.
///
/// Top-level and pure for the same reason `discoveryContextFor` is: hoofdstuk
/// 15's "alleen wanneer data werkelijk beschikbaar is" is a claim about a
/// group, testable without a widget. A film whose server reported no runtime
/// gets no runtime segment, never a zero.
String heroMetaLineFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  final duration = item.durationMs;
  return [
    switch (item.kind) {
      MediaKind.movie => t.discover.movie,
      MediaKind.show || MediaKind.season || MediaKind.episode => t.discover.tvShow,
      _ => null,
    },
    if (item.genres != null && item.genres!.isNotEmpty) item.genres!.first,
    if (item.year != null) '${item.year}',
    if (duration != null && duration > 0) formatDurationTextual(duration),
    if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
  ].nonNulls.join(' · ');
}

/// The hero's display title. An episode would show its show's name, but the
/// hero only ever carries films and series (hoofdstuk 9.5), so this is the
/// group's own title in every case the carousel can produce — and the
/// grandparent fallback is kept anyway rather than asserted away, because a
/// fallback billboard on an empty hero pool is allowed to be anything the
/// projection saw.
String heroTitleFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  return item.kind == MediaKind.episode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle;
}

class TvHeroBillboardCard extends StatelessWidget {
  const TvHeroBillboardCard({
    super.key,
    required this.group,
    required this.size,
    required this.actions,
    required this.artwork,
    this.client,
    this.hideSpoilers = false,
    this.textOpacity = 1.0,
  });

  final UnifiedMediaGroup group;

  /// The card's box. Computed by the feed from [TvHomeLayout.heroWidth] /
  /// [TvHomeLayout.heroHeight] and passed down, so the artwork layer can size
  /// its own server request against the exact box it will fill (DEC-057).
  final Size size;

  /// The already-wired `Afspelen` / `Meer info` pills. Slots, not callbacks —
  /// see the library doc.
  final Widget actions;

  /// The artwork layer, supplied by the carousel rather than built here.
  ///
  /// This is the whole reason the crossfade works: the carousel wraps
  /// [TvHeroArtwork] in an `AnimatedSwitcher` keyed on the slide, so two
  /// slides' *pictures* can be on screen at once, while the card — and with it
  /// the single pair of CTA `FocusNode`s — is built exactly once. Switching
  /// the whole card instead would put two widgets on one focus node for the
  /// length of the fade, which is an assertion, not a transition.
  final Widget artwork;

  final MediaServerClient? client;

  /// Suppresses the synopsis for an unwatched episode, the same rule the rest
  /// of the app applies. The hero carries films and series, so in practice
  /// this only ever bites on a fallback billboard.
  final bool hideSpoilers;

  /// 33.2: "Focusverlies op de hero dooft zijn tekst". Set to zero once a
  /// content row holds the focus, so the billboard reads as the picture it
  /// has become rather than as a second, competing block of type under the
  /// row the viewer is actually reading.
  ///
  /// Not this card's own decision, nor the carousel's either — [_rowHasFocus]
  /// is state `TvContentFeed` owns (the library doc's "two independent state
  /// machines"), which the carousel only forwards unchanged as this
  /// parameter. Naming the carousel here would be exactly the kind of
  /// misattributed "who decides this" this file otherwise guards against for
  /// activation (see the class doc's "Presentation only").
  final double textOpacity;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final item = group.representativeSource.item;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TvHomeLayout.heroRadius * scale),
          color: tk.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: TvDiscoveryLayout.cardShadowAlpha),
              blurRadius: TvDiscoveryLayout.cardShadowBlur * scale,
              offset: Offset(0, TvDiscoveryLayout.cardShadowOffsetY * scale),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TvHomeLayout.heroRadius * scale),
          child: Stack(
            fit: StackFit.expand,
            children: [
              artwork,
              // 33.1: "scrim alleen lokaal linksonder". Two gradients rather
              // than one diagonal, so the right half of the artwork — where the
              // subject is — keeps its own colour untouched (fase-8 brief §5:
              // "natuurlijke kleur; geen globale grading").
              _ReadingScrim(color: tk.bg),
              _BottomScrim(color: tk.bg),
              Positioned(
                left: TvHomeLayout.heroContentInset * scale,
                bottom: TvHomeLayout.heroContentBottom * scale,
                // `right`, not `width`. The *text* column is capped at
                // [TvHomeLayout.heroTextMaxWidth] (see `_HeroText`), but the CTA
                // row underneath it is not: a resume pill carrying a progress
                // bar beside a long "Meer info" label is wider than the prose
                // column on a long locale, and capping the whole block at the
                // prose width overflowed the row rather than wrapping it.
                right: TvHomeLayout.heroContentInset * scale,
                // Opacity, never a conditional subtree: the CTAs live in here,
                // and unmounting them would drop the remote's focus on the
                // floor the instant a row took it. `IgnorePointer` is not
                // needed either — a faded hero is still the thing UP returns
                // to, and its nodes must stay focusable.
                child: AnimatedOpacity(
                  opacity: textOpacity,
                  duration: reduceMotion(context, tk.normal),
                  curve: Curves.easeOut,
                  child: _HeroText(
                    group: group,
                    item: item,
                    client: client,
                    scale: scale,
                    tokens: tk,
                    hideSpoilers: hideSpoilers,
                    actions: actions,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wash the title, metadata and synopsis are read against: a left-to-right
/// ramp, *masked* by a bottom-to-top one so it exists only where the text is.
///
/// The mask is the point. A plain horizontal gradient is opaque all the way up
/// the card's left edge, darkening artwork that carries nothing — and stacked
/// with a bottom gradient it turns 33.1's lower-left scrim into an L over half
/// the card, taking the bottom-right corner with it. A product of the two
/// ramps is the shape 33.1 actually specifies.
class _ReadingScrim extends StatelessWidget {
  const _ReadingScrim({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, TvHomeLayout.heroScrimReadingPlateau, TvHomeLayout.heroScrimReadingFade],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                color.withValues(alpha: TvHomeLayout.heroScrimAlpha),
                Colors.transparent,
              ],
              stops: const [0, TvHomeLayout.heroScrimHorizontalStop],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's lower edge, melted into the page. Weak on purpose — it carries no
/// type, and at reading strength it took the bottom-right corner with it.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: TvHomeLayout.heroScrimBottomAlpha),
              Colors.transparent,
            ],
            stops: const [0, TvHomeLayout.heroScrimBottomStop],
          ),
        ),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText({
    required this.group,
    required this.item,
    required this.client,
    required this.scale,
    required this.tokens,
    required this.hideSpoilers,
    required this.actions,
  });

  final UnifiedMediaGroup group;
  final MediaItem item;
  final MediaServerClient? client;
  final double scale;
  final MonoTokens tokens;
  final bool hideSpoilers;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final summary = item.summary?.trim();
    final showSynopsis = summary != null && summary.isNotEmpty && !(hideSpoilers && item.kind == MediaKind.episode);

    // The prose column, capped; the actions below it are not — see the
    // `Positioned` that hosts this block.
    Widget column(Widget child) => SizedBox(width: TvHomeLayout.heroTextMaxWidth * scale, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        column(_titleBlock(context)),
        SizedBox(height: TvHomeLayout.heroTitleMetaGap * scale),
        // Pinned to one line's budget: a meta line that wrapped would push the
        // CTA row down by the height of a line, mid-carousel.
        column(
          SizedBox(
            height: TvHomeLayout.heroMetaFontSize * TvHomeLayout.heroLineHeight * scale,
            child: Text(
              heroMetaLineFor(group),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.text.withValues(alpha: TvHomeLayout.inkSecondary),
                fontSize: TvHomeLayout.heroMetaFontSize * scale,
                height: TvHomeLayout.heroLineHeight,
              ),
            ),
          ),
        ),
        SizedBox(height: TvHomeLayout.heroMetaSynopsisGap * scale),
        column(
          SizedBox(
            height:
                TvHomeLayout.heroSynopsisFontSize *
                TvHomeLayout.heroLineHeight *
                TvHomeLayout.heroSynopsisMaxLines *
                scale,
            child: showSynopsis
                ? Text(
                    summary,
                    maxLines: TvHomeLayout.heroSynopsisMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.text.withValues(alpha: TvHomeLayout.inkTertiary),
                      fontSize: TvHomeLayout.heroSynopsisFontSize * scale,
                      height: TvHomeLayout.heroLineHeight,
                    ),
                  )
                : null,
          ),
        ),
        SizedBox(height: TvHomeLayout.heroSynopsisActionsGap * scale),
        actions,
      ],
    );
  }

  /// Hoofdstuk 9.4: the clearlogo when the title has one, its own typography
  /// when it does not. Both occupy the same reserved band, so the metadata line
  /// under them sits in one place whichever a slide turns out to have.
  Widget _titleBlock(BuildContext context) {
    final logo = item.clearLogoPath;
    final band = TvHomeLayout.heroLogoMaxHeight * scale;

    if (logo != null && logo.isNotEmpty) {
      return SizedBox(
        height: band,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: OptimizedMediaImage(
            client: client,
            imagePath: logo,
            width: TvHomeLayout.heroLogoMaxWidth * scale,
            height: band,
            // Contain, never cover: a clearlogo cropped to fill its box is a
            // mangled wordmark, and the box is deliberately larger than most.
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            imageType: ImageType.logo,
            fadeInDuration: Duration.zero,
            placeholder: (context, _) => const SizedBox.shrink(),
            errorWidget: (context, _, _) => _titleType(context, band),
          ),
        ),
      );
    }
    return _titleType(context, band);
  }

  Widget _titleType(BuildContext context, double band) {
    return SizedBox(
      height: band,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          heroTitleFor(group),
          maxLines: TvHomeLayout.heroTitleMaxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tokens.text,
            fontSize: TvHomeLayout.heroTitleFontSize * scale,
            // Natural case, deliberately. The north-star render sets its
            // example title in tracked capitals, and 33.1 binds "titel" —
            // not "titel in kapitalen". Upper-casing an arbitrary catalogue
            // is not a typographic choice a mockup can make: it mangles
            // titles that carry meaningful case and does nothing at all for
            // scripts without it.
            fontWeight: FontWeight.w700,
            letterSpacing: TvHomeLayout.heroTitleLetterSpacing,
            height: 1.05,
          ),
        ),
      ),
    );
  }
}
