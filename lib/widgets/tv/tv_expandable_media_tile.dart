/// The tile a fase-6 discovery rail is made of (hoofdstuk 10.2a and the fase-6
/// brief's hoofdstuk 19/20): a 2:3 poster while the rail passes over it, a 16:9
/// frame while it holds the focus.
///
/// ## The one rule this widget exists to keep
///
/// **Height is constant. Only width moves.** A tile is
/// [TvDiscoveryLayout.cardHeight] tall focused or not; what changes is whether
/// it is that height times 2:3 or that height times 16:9 wide. Everything else
/// about the expansion follows from that, and the alternative — growing the
/// focused tile in both directions — is the failure fase 5 already paid for
/// once on the catalog grid: a band whose height depends on where focus is
/// drags every row beneath it up and down the screen while the user is reading
/// them. Here the band is reserved at its maximum from the first frame, the
/// neighbours slide sideways, and nothing below the rail moves at all.
///
/// ## Focus is authority, animation is presentation
///
/// The width is an [AnimatedContainer] target derived from the current focus
/// state, never a value some animation callback writes back. So four rapid
/// presses — A → B → C → D faster than the 200ms tween — leave four tiles each
/// heading toward the width its own focus state implies, with no stale callback
/// able to resurrect an earlier one, no activation fired on a tile the user has
/// already left, and no geometry race to lose. Nothing in this file schedules
/// work off an animation completing.
///
/// ## No footer
///
/// A discovery tile carries artwork and, at most, three markers on it. The
/// title, year, genre and synopsis belong to the focused item alone and are
/// drawn once, under the rail, by [TvDiscoveryRail] — hoofdstuk 26: metadata is
/// focus-driven, and a permanent caption under every tile is precisely the
/// database-listing impression the phase is against.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/card_focus_scope.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../media/media_kind.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../new_content_badge.dart';
import '../../utils/media_image_helper.dart' show ImageType;
import '../optimized_media_image.dart';
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart' show resumeFractionFor;

/// The wide (16:9) artwork for [item], or null when it has none.
///
/// An episode is the case worth spelling out: its own `thumbPath` already *is*
/// a 16:9 still, so a Continue Watching tile showing "S2 E4" should expand into
/// that still rather than into the show's backdrop — the still is the picture of
/// the thing you are about to resume. Everything else expands into `artPath`,
/// falling back to a show's backdrop for a season/episode row that has none.
///
/// Top-level and pure so a test can assert which of an item's three image paths
/// a tile will actually draw, without pumping a widget or a network.
String? discoveryWideArtPath(MediaItem item) => switch (item.kind) {
  MediaKind.episode => item.thumbPath ?? item.artPath ?? item.grandparentArtPath,
  MediaKind.season => item.artPath ?? item.grandparentArtPath ?? item.parentThumbPath,
  _ => item.artPath ?? item.grandparentArtPath,
};

/// The 2:3 poster for [item]. An episode borrows its show's, because a 16:9
/// still crammed into a poster slot is the extreme crop hoofdstuk 22 forbids.
String? discoveryPosterPath(MediaItem item) => switch (item.kind) {
  MediaKind.episode || MediaKind.season => item.grandparentThumbPath ?? item.parentThumbPath ?? item.thumbPath,
  _ => item.thumbPath,
};

class TvExpandableMediaTile extends StatefulWidget {
  const TvExpandableMediaTile({
    super.key,
    required this.group,
    required this.onSelect,
    this.onContextMenu,
    required this.semanticLabel,
    this.clientFor,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
  });

  final UnifiedMediaGroup group;

  /// Hoofdstuk 27: activation goes through the fase-4 coordinator. This tile
  /// never resolves a source and never picks one — it reports a press.
  final VoidCallback onSelect;

  /// Opens the hoofdstuk 23 context menu. Null on a surface that has no
  /// actions to offer, which also leaves `FocusableWrapper.onLongPress` null
  /// so a long Select stays a plain Select and the context-menu key falls
  /// through unhandled rather than arming the select suppressor for nothing.
  final VoidCallback? onContextMenu;

  /// Built by the rail, because only the rail knows the position in it.
  final String semanticLabel;

  final MediaServerClient? Function(String serverId)? clientFor;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  @override
  State<TvExpandableMediaTile> createState() => _TvExpandableMediaTileState();
}

class _TvExpandableMediaTileState extends State<TvExpandableMediaTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvDiscoveryLayout.cardRadius * scale;
    final artworkWidth = _isFocused ? TvDiscoveryLayout.wideWidth(scale) : TvDiscoveryLayout.posterWidth(scale);

    return FocusableWrapper(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onSelect: widget.onSelect,
      onLongPress: widget.onContextMenu,
      enableLongPress: widget.onContextMenu != null,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onFocusChange: (focused) {
        if (mounted && focused != _isFocused) setState(() => _isFocused = focused);
        widget.onFocusChange?.call(focused);
      },
      // Reduce Motion, hoofdstuk 44: `reduceMotion` reads the platform
      // accessibility setting and `getAnimationDuration` the performance tier —
      // two different reasons to stop moving, and the expansion has to answer to
      // both. Zero duration snaps the width instead of tweening it; the
      // geometry, and therefore the no-jank contract, is unchanged.
      //
      // The geometry already expands by a factor of 2.7 in width; hoofdstuk 25
      // is explicit that a further scale on top of that would only push the
      // focused tile over its neighbours, which must stay visible.
      disableScale: true,
      // The ring belongs on the artwork rect, and the artwork is what animates.
      mode: FocusIndicatorMode.delegated,
      semanticLabel: widget.semanticLabel,
      // Hoofdstuk 25: "Decoratieve backdrops en clearlogo's worden uitgesloten
      // van dubbele semantiek." `FocusableWrapper` wraps the child in a
      // `Semantics(label: …)` without excluding what is underneath, so the
      // source-count badge and the NEW badge would each announce themselves
      // again after the composed label already named them — VoiceOver reading
      // "Dune, 2021, 2 sources" and then "2". `TvUnifiedMediaCard` solves it
      // the same way.
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvDiscoveryLayout.cardFocusRingGap * scale),
          child: AnimatedContainer(
            duration: reduceMotion(context, FocusTheme.getAnimationDuration(context)),
            curve: Curves.easeOutCubic,
            width: artworkWidth,
            height: TvDiscoveryLayout.cardHeight * scale,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _isFocused ? TvDiscoveryLayout.cardFocusShadowAlpha : TvDiscoveryLayout.cardShadowAlpha,
                  ),
                  blurRadius:
                      (_isFocused ? TvDiscoveryLayout.cardFocusShadowBlur : TvDiscoveryLayout.cardShadowBlur) * scale,
                  offset: Offset(
                    0,
                    (_isFocused ? TvDiscoveryLayout.cardFocusShadowOffsetY : TvDiscoveryLayout.cardShadowOffsetY) *
                        scale,
                  ),
                ),
              ],
            ),
            child: CardFocusBorder(
              borderRadius: radius,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: _TileArtwork(group: widget.group, scale: scale, clientFor: widget.clientFor, isWide: _isFocused),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture, and the at-most-three markers allowed on top of it.
class _TileArtwork extends StatelessWidget {
  const _TileArtwork({required this.group, required this.scale, required this.clientFor, required this.isWide});

  final UnifiedMediaGroup group;
  final double scale;
  final MediaServerClient? Function(String serverId)? clientFor;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final item = group.representativeSource.item;
    final client = clientFor?.call(group.representativeSource.serverId.value);
    final inset = TvDiscoveryLayout.badgeInset * scale;
    final fraction = resumeFractionFor(group);

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: tk.surface, child: isWide ? _wide(client, item) : _poster(client, item)),
        // Above the picture, below every marker: the tile the remote is
        // standing on gets a little more light than the wall, and the badges
        // keep the contrast they were measured against.
        AnimatedOpacity(
          duration: reduceMotion(context, tk.fast),
          opacity: isWide ? 1 : 0,
          child: ColoredBox(color: Colors.white.withValues(alpha: TvDiscoveryLayout.cardFocusArtworkLift)),
        ),
        // The opposite treatment for a neighbour. Small on purpose — hoofdstuk
        // 19 requires neighbours to stay visible, so this recedes them, it does
        // not curtain them off.
        AnimatedOpacity(
          duration: reduceMotion(context, tk.fast),
          opacity: isWide ? 0 : 1,
          child: ColoredBox(color: Colors.black.withValues(alpha: TvDiscoveryLayout.neighbourDim)),
        ),
        if (group.hasMultipleSources)
          Positioned(
            top: inset,
            left: inset,
            child: TvSourceCountBadge(count: group.sources.length, scale: scale),
          ),
        if (group.watchState.isWatched)
          Positioned(
            top: inset,
            right: inset,
            child: TvWatchedTick(scale: scale),
          )
        else
          Positioned(
            top: inset,
            right: inset,
            child: NewContentBadge(item: item),
          ),
        if (fraction != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ProgressBar(fraction: fraction, scale: scale),
          ),
      ],
    );
  }

  Widget _poster(MediaServerClient? client, MediaItem item) => OptimizedMediaImage.poster(
    client: client,
    imagePath: discoveryPosterPath(item),
    fit: BoxFit.cover,
    fallbackIcon: item.kind == MediaKind.show ? Symbols.live_tv_rounded : Symbols.movie_rounded,
  );

  /// The expanded frame.
  ///
  /// With wide artwork this is simply that artwork, covering. Without it — a
  /// library whose backdrops were never fetched, a film that has none — the
  /// choice is between cropping a 2:3 poster into 16:9, which throws away most
  /// of the image and is the "extreme crop" hoofdstuk 22 rules out, and
  /// building a frame around the poster instead. This builds the frame: the
  /// poster blurred and darkened to fill the width, the poster itself drawn
  /// whole and centred on top. The colour still comes from the artwork
  /// (hoofdstuk 23), nothing is cropped away, and the tile keeps the one width
  /// the rail's geometry depends on.
  Widget _wide(MediaServerClient? client, MediaItem item) {
    final widePath = discoveryWideArtPath(item);
    if (widePath != null) {
      return OptimizedMediaImage(
        client: client,
        imagePath: widePath,
        fit: BoxFit.cover,
        imageType: item.kind == MediaKind.episode ? ImageType.thumb : ImageType.art,
        fallbackIcon: Symbols.movie_rounded,
      );
    }

    final poster = discoveryPosterPath(item);
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 18 * scale, sigmaY: 18 * scale, tileMode: TileMode.clamp),
          child: OptimizedMediaImage.poster(client: client, imagePath: poster, fit: BoxFit.cover, fallbackIcon: null),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
        Center(
          child: AspectRatio(
            aspectRatio: TvDiscoveryLayout.posterAspectRatio,
            child: OptimizedMediaImage.poster(
              client: client,
              imagePath: poster,
              fit: BoxFit.cover,
              fallbackIcon: item.kind == MediaKind.show ? Symbols.live_tv_rounded : Symbols.movie_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hoofdstuk 10.3's "N bronnen" capsule, in the discovery rail's scale.
///
/// Public because the rail's own empty/skeleton states and the goldens read it,
/// and because one badge shape has to mean one thing at both levels of Films.
class TvSourceCountBadge extends StatelessWidget {
  const TvSourceCountBadge({super.key, required this.count, required this.scale});

  final int count;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.layers_rounded, size: 11 * scale, color: tk.text),
          SizedBox(width: 3 * scale),
          Text(
            '$count',
            style: TextStyle(color: tk.text, fontSize: 10.5 * scale, fontWeight: FontWeight.w600, height: 1),
          ),
        ],
      ),
    );
  }
}

/// The watched marker. Same glyph and the same corner as the catalog card's.
class TvWatchedTick extends StatelessWidget {
  const TvWatchedTick({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Container(
      padding: EdgeInsets.all(3 * scale),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), shape: BoxShape.circle),
      child: Icon(Symbols.check_rounded, size: 12 * scale, color: tk.text),
    );
  }
}

/// Resume position. Pleya red, which is hoofdstuk 24's one sanctioned use of it
/// on a browse surface: progress, small, and never as an interface colour.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction, required this.scale});

  final double fraction;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return SizedBox(
      height: TvDiscoveryLayout.progressBarHeight * scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black.withValues(alpha: TvDiscoveryLayout.progressTrackAlpha + 0.23)),
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
