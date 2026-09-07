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
///
/// ## What is here, and what moved
///
/// Since [DEC-108](../../../docs/DECISIONS.md#dec-108) the drawing lives in
/// [TvCatalogCard], because the kijklijst, Aanvragen and Zoeken draw the same
/// card over three different domains. What is left here is the half that is
/// genuinely about a group: which poster, which markers, and the two strings
/// under it. The split is along the line hoofdstuk 10.3 already drew — the
/// badge exists on `sources.length > 1` and the tick on `watchState`, and
/// neither is a fact the card body could work out for itself.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../utils/layout_constants.dart';
import '../new_content_badge.dart';
import '../optimized_media_image.dart';
import 'tv_catalog_card.dart';
import 'tv_catalog_meta.dart';

export 'tv_catalog_card.dart' show tvCatalogPosterKey;

class TvUnifiedMediaCard extends StatelessWidget {
  const TvUnifiedMediaCard({
    super.key,
    required this.group,
    required this.width,
    required this.onSelect,
    this.onContextMenu,
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

  /// Opens the hoofdstuk 23 context menu. Null on a surface that has no
  /// actions to offer, which also leaves `FocusableWrapper.onLongPress` null
  /// so a long Select stays a plain Select and the context-menu key falls
  /// through unhandled rather than arming the select suppressor for nothing.
  final VoidCallback? onContextMenu;

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
    final scale = TvLayoutConstants.scaleOf(context);
    final item = group.representativeSource.item;
    final serverId = group.representativeSource.serverId.value;

    return TvCatalogCard(
      width: width,
      artwork: TvCatalogArtworkFill(
        child: OptimizedMediaImage(
          client: clientFor?.call(serverId),
          imagePath: item.thumbPath,
          fit: BoxFit.cover,
          fallbackIcon: Symbols.movie_rounded,
        ),
      ),
      // Hoofdstuk 10.3: only above one known source, and never a server
      // name or logo.
      topLeftMarker: group.hasMultipleSources
          ? TvCatalogArtworkBadge(label: t.unifiedCatalog.sources(count: group.sources.length))
          : null,
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
      topRightMarker: group.watchState.isWatched
          ? TvCatalogWatchedBadge(scale: scale)
          : NewContentDot(item: item, scale: scale),
      progressFraction: resumeFractionFor(group),
      title: item.displayTitle,
      meta: tvCatalogMetaLine(item),
      onSelect: onSelect,
      onContextMenu: onContextMenu,
      focusNode: focusNode,
      autofocus: autofocus,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onFocusChange: onFocusChange,
      semanticLabel: semanticLabelFor(group),
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
