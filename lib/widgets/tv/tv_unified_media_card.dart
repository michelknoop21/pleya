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
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../optimized_media_image.dart';
import 'tv_unified_layout.dart';

class TvUnifiedMediaCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvCatalogLayout.cardRadius * scale;

    // The width bounds the *wrapper*, not the card content. `FocusableWrapper`
    // draws its ring as a border on a container around the child, which adds
    // `focusBorderWidth` to each side — so sizing the child instead would make
    // every card 5 logical pixels wider than the grid budgeted for it, and a
    // six-column row would overflow by thirty. Constraining the outside lets the
    // ring eat into the card rather than out of the gutter.
    return SizedBox(
      width: width,
      child: FocusableWrapper(
        focusNode: focusNode,
        autofocus: autofocus,
        onSelect: onSelect,
        onFocusChange: onFocusChange,
        onNavigateUp: onNavigateUp,
        onNavigateDown: onNavigateDown,
        onNavigateLeft: onNavigateLeft,
        onNavigateRight: onNavigateRight,
        borderRadius: radius,
        focusScale: FocusTheme.fullCardFocusScale,
        semanticLabel: semanticLabelFor(group),
        child: Padding(
          padding: EdgeInsets.all(TvCatalogLayout.cardFocusRingGap * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: _Artwork(group: group, scale: scale, clientFor: clientFor),
              ),
              _Footer(group: group, scale: scale, tk: tk),
            ],
          ),
        ),
      ),
    );
  }
}

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
    if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
    if (group.watchState.isWatched)
      t.unifiedCatalog.semantics.watched
    else if (group.watchState.hasActiveProgress)
      t.unifiedCatalog.semantics.inProgress,
  ];
  return parts.join(', ');
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.group, required this.scale, required this.clientFor});

  final UnifiedMediaGroup group;
  final double scale;
  final MediaServerClient? Function(String serverId)? clientFor;

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
          if (group.watchState.isWatched)
            Positioned(
              top: inset,
              right: inset,
              child: _WatchedBadge(scale: scale),
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

  /// How far through this title the group is, or null when there is nothing to
  /// draw.
  ///
  /// Read off the *representative* source's item, which hoofdstuk 13.2 already
  /// chose as the one whose progress speaks for the group — so a film half
  /// watched on the laptop server and untouched on the NAS shows one bar, not
  /// an average of two runtimes that are not comparable.
  double? get _resumeFraction {
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
/// What still binds the two together is the focus ring, which wraps poster and
/// text as one shape. That is the same containment the fill used to provide,
/// drawn only when it is needed.
class _Footer extends StatelessWidget {
  const _Footer({required this.group, required this.scale, required this.tk});

  final UnifiedMediaGroup group;
  final double scale;
  final MonoTokens tk;

  @override
  Widget build(BuildContext context) {
    final item = group.representativeSource.item;
    final context_ = _contextLine;

    return Padding(
      padding: EdgeInsets.only(top: TvCatalogLayout.cardFooterPaddingVertical * scale),
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
  String get _contextLine {
    final item = group.representativeSource.item;
    final genre = (item.genres ?? const <String>[]).firstOrNull;
    return [if (item.year != null) '${item.year}', if (genre != null && genre.isNotEmpty) genre].join('  ·  ');
  }
}
