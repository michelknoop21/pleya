/// The full-bleed Home hero (hoofdstuk 9.1/9.2 as revised by [DEC-095],
/// mockup 30 A1/B/D): the backdrop across the whole content box and behind the
/// top navigation, its scrims, and the text column with the CTAs above the
/// first rail's label.
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
/// ## Why the page, and not a card
///
/// The fase-8 Home drew this as a 1770×718 rounded card on the page inset
/// (33.1, "nooit full bleed"). A 16:9 backdrop in that 2.465:1 card showed 72%
/// of itself, and HERO1 could only decide which 72%; Michel wanted the whole
/// item in view, chose full-bleed on mockup 29 D and A1 on mockup 30, and
/// DEC-095 supersedes 33.1 on that one point. So this is the picture at
/// screen size with no ring, radius or shadow, and the rail's own label and
/// posters peek under it — the *feed* lays this out behind its list and
/// scrolls it along; nothing here knows about a scroll.
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
    this.textBottom = 0,
    this.client,
    this.hideSpoilers = false,
    this.textOpacity = 1.0,
  });

  final UnifiedMediaGroup group;

  /// The full-bleed box: the content width by the content box plus the top
  /// navigation band above it. The feed computes it and passes it down, so the
  /// artwork layer can size its server request against the exact box it will
  /// fill (DEC-057, DEC-094).
  final Size size;

  /// From the bottom of [size] to the bottom of the CTA row. The feed sets it
  /// to the peeking-rail region plus [TvHomeLayout.heroTextRailGap], which puts
  /// the text 40 reference px above the first rail's label (mockup 30 A1).
  final double textBottom;

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
  /// parameter. The picture stepping back with the text is [TvHeroDimVeil],
  /// which the feed lays over this card rather than inside it.
  final double textOpacity;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final item = group.representativeSource.item;
    final motion = reduceMotion(context, tk.normal);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          artwork,
          // H20: the wash itself is [MonoTokens.artworkScrim] (`tk.bg`), but
          // its *strength* forks on theme — `artworkScrimAlpha`'s own doc: a
          // light-theme veil is white, so it brightens the artwork under the
          // text instead of dimming it, and needs to wash harder before
          // releasing the image.
          _ReadingScrim(color: tk.artworkScrim, alphaFor: (a) => _themed(tk, a)),
          _VerticalScrim(
            color: tk.artworkScrim,
            stops: TvHomeLayout.heroScrimVerticalStops,
            alphas: [for (final a in TvHomeLayout.heroScrimVerticalAlphas) _themed(tk, a)],
          ),
          Positioned(
            left: TvDiscoveryLayout.pageInset * scale,
            // `right`, not `width`. The *text* column is capped at
            // [TvHomeLayout.heroTextMaxWidth] (see `_HeroText`), but the CTA
            // row underneath it is not: a resume pill carrying a progress
            // bar beside a long "Meer info" label is wider than the prose
            // column on a long locale, and capping the whole block at the
            // prose width overflowed the row rather than wrapping it.
            right: TvDiscoveryLayout.pageInset * scale,
            bottom: textBottom,
            // Opacity, never a conditional subtree: the CTAs live in here,
            // and unmounting them would drop the remote's focus on the
            // floor the instant a row took it. `IgnorePointer` is not
            // needed either — a faded hero is still the thing UP returns
            // to, and its nodes must stay focusable.
            child: AnimatedOpacity(
              opacity: textOpacity,
              duration: motion,
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
    );
  }
}

/// A dark-theme scrim strength, resolved for the active theme: light keeps
/// the same shape and washes a little harder (H20), never past opaque.
double _themed(MonoTokens tk, double dark) =>
    tk.artworkScrimAlpha(dark: dark, light: (dark == 0 ? 0.0 : dark + 0.08).clamp(0.0, 1.0));

/// The backdrop stepping back once a row holds the focus (mockup 30 B): a veil
/// of [TvHomeLayout.heroDimAlpha] over the whole picture, and a vertical scrim
/// that reaches the page ground at 40% so the focused band under it sits on
/// ground.
///
/// **Screen-fixed, not scrolled.** The feed translates the card with the list,
/// so the picture moves; this veil is laid over the card's *box* and does not,
/// exactly as the mockup draws it (`translateY` on the image, the scrim on the
/// container). Drawn inside the card it travelled with the picture, and
/// everything below its last stop — which after the scroll was the whole
/// visible strip — was solid ground: the dimmed backdrop 33.2 asks to keep
/// above the rail was never on screen.
class TvHeroDimVeil extends StatelessWidget {
  const TvHeroDimVeil({super.key, required this.dim});

  /// 0 to 1, 1 once a content row holds the focus.
  final double dim;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: dim.clamp(0.0, 1.0),
        duration: reduceMotion(context, tk.normal),
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tk.artworkScrim.withValues(alpha: _themed(tk, TvHomeLayout.heroDimAlpha))),
            _VerticalScrim(
              color: tk.artworkScrim,
              stops: TvHomeLayout.heroDimScrimStops,
              alphas: [for (final a in TvHomeLayout.heroDimScrimAlphas) _themed(tk, a)],
            ),
          ],
        ),
      ),
    );
  }
}

/// The wash the title, metadata and synopsis are read against: a left-to-right
/// ramp over the full height (mockup 30 A1), so the text column and the
/// profile chip in the top navigation above it both stand on it.
///
/// Directional, not physical: the wash exists to make the text column readable,
/// so it has to start on the same edge that column starts on. Under an RTL
/// directionality a left-pinned ramp would sit opposite the type it is there
/// for (hoofdstuk 25, "RTL": "tekstkolom en scrim spiegelen"). `DecoratedBox`
/// resolves the geometry against the ambient direction, so nothing else
/// changes.
class _ReadingScrim extends StatelessWidget {
  const _ReadingScrim({required this.color, required this.alphaFor});

  final Color color;

  /// Theme-resolves one of [TvHomeLayout.heroScrimReadingAlphas] — this widget
  /// never reads [MonoTokens] itself, so it cannot silently drift back to a
  /// single hardcoded strength for both themes (H20).
  final double Function(double dark) alphaFor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [for (final a in TvHomeLayout.heroScrimReadingAlphas) color.withValues(alpha: alphaFor(a))],
            stops: TvHomeLayout.heroScrimReadingStops,
          ),
        ),
      ),
    );
  }
}

/// A top-to-bottom wash with explicit stops: under the top navigation, clear
/// across the subject, and down to the page ground before the first rail's
/// posters, so they stand on the ground and not on the picture.
class _VerticalScrim extends StatelessWidget {
  const _VerticalScrim({required this.color, required this.stops, required this.alphas});

  final Color color;
  final List<double> stops;

  /// Already theme-resolved by the caller — see [_ReadingScrim.alphaFor].
  final List<double> alphas;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [for (final a in alphas) color.withValues(alpha: a)],
            stops: stops,
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
                // H20: dimmed ink reads as secondary on dark artwork but washed
                // out on light — `onArtworkInk`'s own doc — so light keeps more
                // ink than dark rather than sharing one alpha.
                color: tokens.onArtworkInk(dark: TvHomeLayout.inkSecondary, light: 0.92),
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
                      // H20: see the meta line's own note just above.
                      color: tokens.onArtworkInk(dark: TvHomeLayout.inkTertiary, light: 0.84),
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
    // The band fits the tallest thing it can hold, which is a two-line title;
    // the logo keeps its own smaller height inside it (HERO2).
    final band = TvHomeLayout.heroTitleBandHeight * scale;

    if (logo != null && logo.isNotEmpty) {
      return SizedBox(
        height: band,
        child: Align(
          alignment: AlignmentDirectional.bottomStart,
          child: OptimizedMediaImage(
            client: client,
            imagePath: logo,
            width: TvHomeLayout.heroLogoMaxWidth * scale,
            height: TvHomeLayout.heroLogoMaxHeight * scale,
            // Contain, never cover: a clearlogo cropped to fill its box is a
            // mangled wordmark, and the box is deliberately larger than most.
            fit: BoxFit.contain,
            alignment: AlignmentDirectional.bottomStart,
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
        alignment: AlignmentDirectional.bottomStart,
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
