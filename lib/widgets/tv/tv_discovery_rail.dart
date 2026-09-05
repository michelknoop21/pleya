/// One row of a fase-6 discovery landing (hoofdstuk 10.2a of
/// docs/tvos-unified-experience.md, [DEC-064]): a heading, a horizontal band of
/// [TvExpandableMediaTile]s, and one block of context that belongs to whichever
/// tile currently holds the focus.
///
/// ## Why this is not `TvBrowseRail`
///
/// The app already has a TV rail, and it is 2000 lines of a different idea: one
/// *active* rail at a time with the others collapsed to a peeking strip, built
/// over concrete `MediaHub`/`MediaItem` pairs. That model belongs to the current
/// Home, and fase 8 owns replacing it. This rail is the fase-6 shape: several
/// rails stacked and all readable at once, over [UnifiedMediaGroup]s that came
/// out of the projection layer — so a title that lives on two servers is one
/// tile here, and pressing it enters the fase-4 activation path rather than a
/// concrete item. Bending the old widget into that would have meant two
/// interaction models arguing inside one file.
///
/// ## Geometry is fixed before focus exists
///
/// Every vertical measurement this rail uses comes from
/// [TvDiscoveryLayout.railSectionHeight] and is computed from the scale alone.
/// The tile band is reserved at the expanded height, the context block is
/// reserved at three lines whether it has three or none, and the heading is one
/// line, always. So moving focus along the rail cannot change what is below the
/// rail — hoofdstuk 20, and the specific regression fase 5 already paid for once
/// on the catalog grid.
///
/// ## Rebuild scope
///
/// A focus move must not rebuild the landing. Two things change when focus
/// moves: the two tiles involved, which animate their own width from their own
/// state, and the context block, which is rebuilt by a
/// [ValueListenableBuilder] on [_focused] and nothing else. The rail's own
/// `build` does not read the focused group at all — hoofdstuk 43.
///
/// ## Focus identity is the group id
///
/// Focus nodes are keyed by [UnifiedMediaGroup.groupId], never by index. A late
/// server landing and lengthening the row must not move the focus to a
/// different title, and restoration after a detail page has to name the item it
/// is coming back to (hoofdstuk 37).
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../focus/focus_theme.dart';
import '../../services/unified_catalog/unified_artwork_prefetcher.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_image_helper.dart' show ImageType;
import 'tv_expandable_media_tile.dart';
import 'tv_section_header.dart';
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart' show resumeFractionFor, semanticLabelFor;

/// The three tiers of context a focused discovery tile gets: its title, one
/// line of facts, and at most two lines of synopsis.
///
/// A record rather than a widget, and top-level rather than private, because
/// hoofdstuk 15's "alleen wanneer data werkelijk beschikbaar is" is a claim a
/// test should be able to make about a group without rendering anything: given
/// an episode with a runtime and an offset you get "S2 E4 · 18 min left"; given
/// one without, you get neither half, not a zero.
typedef DiscoveryContext = ({String title, String context, String? synopsis});

/// Builds that context for [group].
///
/// Ordered by what a viewer standing three metres away actually needs to decide
/// whether to press play, most specific first. For an episode that is where in
/// the show they are and how much is left; for a film it is the year, what kind
/// of film it is, and how long it runs. No server or library name appears at
/// any position, because on a unified surface that is a detail of *storage*,
/// not of the title (hoofdstuk 26).
///
/// **The source count is not here (P10).** It used to be the last part, and it
/// was the one piece of the line that repeated something already on screen: the
/// tile above carries a [TvSourceCountBadge] with the same number, in the same
/// glance. A line at this size can hold four facts before it starts reading as
/// a database row, and spending one of them on a duplicate is the worst trade
/// available. Hoofdstuk 13's requirement that a multi-source title says so is
/// unchanged — the badge is what says it.
///
/// **A film gains its runtime.** It is the fact a viewer actually weighs before
/// committing an evening, and it was the one thing the line did not have. An
/// episode does not get it: its own place in that line is already the remaining
/// time, which is the same question answered better.
///
/// This supersedes 33.4's metadata format, which binds genre plus source count
/// literally.
DiscoveryContext discoveryContextFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  final isEpisode = item.kind == MediaKind.episode;
  final title = isEpisode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle;

  final parts = <String>[
    if (isEpisode) ?_episodeLabel(item),
    ?_remainingLabel(group, item),
    if (item.year != null) '${item.year}',
    if (item.genres != null && item.genres!.isNotEmpty) item.genres!.first,
    if (!isEpisode) ?_runtimeLabel(group, item),
  ];

  final summary = item.summary?.trim();
  return (title: title, context: parts.join(' · '), synopsis: summary == null || summary.isEmpty ? null : summary);
}

/// "1h 42m", but only for a title that is not already showing what is left of
/// it and that actually reported a duration.
///
/// A resumable film shows `_remainingLabel` instead: "42 min left" and
/// "1h 42m" side by side is two numbers about the same clock, and the first is
/// the one that answers the question.
String? _runtimeLabel(UnifiedMediaGroup group, MediaItem item) {
  if (_remainingLabel(group, item) != null) return null;
  final duration = item.durationMs;
  if (duration == null || duration <= 0) return null;
  return formatDurationTextual(duration);
}

String? _episodeLabel(MediaItem item) {
  final season = item.parentIndex;
  final episode = item.index;
  if (season == null || episode == null) return null;
  return t.unifiedCatalog.discovery.episodeLabel(season: season, episode: episode);
}

/// "18 min left", but only when there is a real offset and a real runtime to
/// subtract it from. A resumable row whose server reported no duration gets no
/// line rather than a made-up one.
String? _remainingLabel(UnifiedMediaGroup group, MediaItem item) {
  if (resumeFractionFor(group) == null) return null;
  final offset = item.viewOffsetMs;
  final duration = item.durationMs;
  if (offset == null || duration == null || duration <= offset) return null;
  final minutes = ((duration - offset) / 60000).round();
  if (minutes <= 0) return null;
  return t.discover.minutesLeft(minutes: minutes);
}

class TvDiscoveryRail extends StatefulWidget {
  const TvDiscoveryRail({
    super.key,
    required this.title,
    required this.groups,
    required this.onActivate,
    this.onContextMenu,
    this.clientFor,
    this.isPartial = false,
    this.autofocus = false,
    this.initialFocusedGroupId,
    this.alwaysDescribesCurrent = false,
    this.onFocusedGroupChanged,
    this.onNavigateUp,
    this.onNavigateDown,
    this.automationRailIndex,
    this.tileScrollAlignment = 0.5,
    this.precache,
  });

  final String title;

  /// Already projected, already deduplicated, already bounded. The rail does no
  /// grouping, no filtering and no fetching of its own — hoofdstuk 10.2a's
  /// architecture boundary is that a TV widget never builds a discovery row.
  final List<UnifiedMediaGroup> groups;

  final ValueChanged<UnifiedMediaGroup> onActivate;

  /// Hoofdstuk 23's menu on a long Select or the context-menu key. Null on a
  /// surface with no actions to offer, which keeps the gesture unarmed rather
  /// than opening an empty panel.
  final ValueChanged<UnifiedMediaGroup>? onContextMenu;
  final MediaServerClient? Function(String serverId)? clientFor;

  /// One or more sources that should have contributed did not answer. The rail
  /// shows what it has and says so quietly in the heading (hoofdstuk 41).
  final bool isPartial;

  final bool autofocus;

  /// Restoration: which tile to come back to (hoofdstuk 35). Ignored when the
  /// group is no longer in [groups] — a title that vanished cannot be focused,
  /// and the first tile is the honest fallback.
  final String? initialFocusedGroupId;

  final ValueChanged<String>? onFocusedGroupChanged;

  /// Where UP and DOWN out of this rail go, called with the **column** the step
  /// leaves from: the index of the tile the remote is standing on.
  ///
  /// The column is the whole point (LAND4). A stacked surface reads as one
  /// spatial plane, so a step to the rail above or below has to arrive at the
  /// same horizontal position — and only the rail the step leaves knows what
  /// that position is. Left to Flutter's directional traversal it is decided by
  /// *screen geometry*, and a rail's screen geometry is its scroll offset,
  /// which is its focus memory: a rail last walked to its tenth tile is still
  /// scrolled there, so DOWN from the third tile of the rail above landed on
  /// its eleventh. Memory is a restoration answer, not a traversal answer.
  ///
  /// Null hands the key back to Flutter's traversal, which is the right
  /// answer at the edges of a stack — off the last rail of TV Search there is a
  /// vertical result list, and geometry reaches it correctly.
  final ValueChanged<int>? onNavigateUp;
  final ValueChanged<int>? onNavigateDown;

  /// This rail's position on the page, for Pleya Verify addressing only. Null
  /// leaves the rail and its tiles unregistered, which is what a standalone
  /// mount (a golden, a focus test) wants — and what a release build gets
  /// anyway, since `AutomationNode` is a pass-through when `!kPleyaVerify`.
  final int? automationRailIndex;

  /// Forwarded to every tile as [TvExpandableMediaTile.scrollAlignment]: the
  /// vertical anchor a focused tile scrolls the page to.
  final double tileScrollAlignment;

  /// Keep describing this rail's current tile even while the focus is
  /// elsewhere.
  ///
  /// Off by default, which is the contract for every surface that stacks rails
  /// as a feed: the projection belongs to the item that has the focus, and a
  /// rail nobody is standing in describes nothing. Two rails captioned at once
  /// reads as two focus contexts on screen, which is what a physical Apple TV
  /// showed.
  ///
  /// TV Search turns it on, and the reason is that its rails are not a feed.
  /// Each one is a result category, and a result's title appears *only* in this
  /// block, so gating it on focus would hand the viewer a page of unlabelled
  /// artwork with nothing to read until they walked into it. There the caption
  /// is a label, not a projection of where the remote is.
  ///
  /// A named property rather than a test on the screen inside the rail: the
  /// rail still does not know who mounted it, and a caller that wants the feed
  /// contract gets it by doing nothing.
  final bool alwaysDescribesCurrent;

  /// Replaces the artwork warm-up call. Null in production; a test injects its
  /// own to assert *which* artwork a focus move warms, without a network. Same
  /// seam and same reasoning as [TvUnifiedMediaGrid.precache].
  @visibleForTesting
  final UnifiedArtworkPrecache? precache;

  @override
  State<TvDiscoveryRail> createState() => TvDiscoveryRailState();
}

class TvDiscoveryRailState extends State<TvDiscoveryRail> {
  final _nodes = <String, FocusNode>{};
  final _scroll = ScrollController();
  late final ValueNotifier<UnifiedMediaGroup?> _focused;

  /// Whether the remote is standing anywhere in this rail.
  ///
  /// Separate from [_focused] because the two answer different questions.
  /// [_focused] is where this rail was left, which is what a viewer returning
  /// from a detail page comes back to and must survive the trip. This is
  /// whether the rail is being *looked at*, which is what decides if it may
  /// draw its metadata block.
  final _holdsFocus = ValueNotifier(false);

  /// The scale of the last build, so the post-frame warm-up has one without a
  /// `BuildContext` lookup on a widget that may already be gone.
  double _scale = 1;

  /// Artwork warm-up for this rail, owned here rather than started from
  /// `itemBuilder` (P8).
  ///
  /// The builder runs per item, per frame, during a scroll — starting a
  /// prefetch from inside it means the queue is rebuilt many times a frame from
  /// whichever item happened to be built last, which is not a window. This
  /// state object knows the whole row and where the focus is on it, so warming
  /// happens at exactly two moments: once after the first frame for the tiles a
  /// viewer can already see, and again on every focus gain, around the tile
  /// they moved to.
  late final UnifiedArtworkPrefetcher _prefetcher = UnifiedArtworkPrefetcher(
    clientFor: (serverId) => widget.clientFor?.call(serverId),
    precache: widget.precache,
    // The rail draws a *show's* poster for an episode tile, not the episode's
    // own still — see `discoveryPosterPath`. Warming `item.thumbPath` (the
    // service's default, and the right answer for the catalog grid) would warm
    // an image no discovery tile ever draws.
    primaryPathOf: discoveryPosterPath,
    secondary: UnifiedArtworkVariant(
      pathOf: discoveryWideArtPath,
      imageTypeOf: (item) => item.kind == MediaKind.episode ? ImageType.thumb : ImageType.art,
    ),
  );

  @override
  void initState() {
    super.initState();
    _focused = ValueNotifier(_restoredOrFirst());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The tiles the row opens on. `_warmAround(0)` rather than "the visible
      // range": the rail is a `ListView.builder`, so what is built *is* roughly
      // what is visible, and the prefetcher adds its own margin either side.
      final focused = _focused.value;
      final index = focused == null ? 0 : widget.groups.indexWhere((g) => g.groupId == focused.groupId);
      _warmAround(index < 0 ? 0 : index);
    });
  }

  @override
  void didUpdateWidget(TvDiscoveryRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rail whose groups changed under it (a late server merged in) keeps
    // describing the same title when that title is still there, and falls back
    // to the first only when it is not.
    final current = _focused.value;
    if (current == null || !widget.groups.any((g) => g.groupId == current.groupId)) {
      _focused.value = _restoredOrFirst();
    }
  }

  UnifiedMediaGroup? _restoredOrFirst() {
    if (widget.groups.isEmpty) return null;
    final wanted = widget.initialFocusedGroupId;
    if (wanted != null) {
      for (final group in widget.groups) {
        if (group.groupId == wanted) return group;
      }
    }
    return widget.groups.first;
  }

  @override
  void dispose() {
    _prefetcher.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    _focused.dispose();
    _holdsFocus.dispose();
    super.dispose();
  }

  /// Warms the artwork around [index], both variants, on one budget.
  ///
  /// The window is a screenful either side of the tile in question; the
  /// prefetcher clamps it and adds its own margins, and holds the wide variant
  /// to four items on each side.
  void _warmAround(int index) {
    if (!mounted || widget.groups.isEmpty) return;
    final scale = _scale;
    final height = TvDiscoveryLayout.cardHeight * scale;
    final poster = Size(TvDiscoveryLayout.posterWidth(scale), height);
    if (poster.width <= 0 || poster.height <= 0) return;
    final clamped = index.clamp(0, widget.groups.length - 1);
    _prefetcher.prefetchAround(
      context: context,
      groups: widget.groups,
      firstVisibleIndex: clamped,
      lastVisibleIndex: clamped,
      posterSize: poster,
      secondarySize: Size(TvDiscoveryLayout.wideWidth(scale), height),
    );
  }

  /// The offset [_revealFocused] would scroll to for the tile at [index], or
  /// null when the band is already there or cannot be measured yet.
  ///
  /// Split out because the arithmetic is the useful half. It reads layout
  /// tokens and an index, never a render box, so it answers for a tile that has
  /// not been built — which is what [focusColumn] needs to move the band to a
  /// tile the viewport has virtualised away.
  double? _revealTarget(int index, double scale) {
    if (!_scroll.hasClients) return null;
    final position = _scroll.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) return null;
    final viewport = position.viewportDimension;
    if (viewport <= 0) return null;

    final lead = TvDiscoveryLayout.railLeadInset(scale);
    final start = lead + index * TvDiscoveryLayout.railPitch(scale);
    final end = start + TvDiscoveryLayout.tileWidth(scale, focused: true);

    var target = position.pixels;
    if (end > target + viewport - lead) target = end - viewport + lead;
    // Second, and deliberately after: when the expanded tile is wider than the
    // band can show (a narrow window, a test viewport) the left edge is the one
    // that has to win, or the viewer is looking at the tail of a tile whose
    // start they cannot see.
    if (start < target + lead) target = start - lead;
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return null;
    return target;
  }

  /// Scrolls the band so the tile at [index] is fully visible **at its focused
  /// width**, inside the page inset on both sides (P9).
  ///
  /// Flutter's own directional traversal does scroll a focused item into view,
  /// and that is exactly the problem: it measures the tile at the instant focus
  /// lands, which is still its *resting* 2:3 width, and the tile then grows to
  /// 2.67 times that. `FocusableWrapper._scrollIntoView` cannot help either —
  /// it looks for the nearest *vertical* scrollable and a rail is horizontal.
  /// So the arithmetic is done here, from the layout tokens rather than from
  /// render boxes: every tile before the focused one is at rest, so the focused
  /// tile's left edge is `lead + index * pitch` and its right edge is that plus
  /// the focused width. No measurement mid-tween, and therefore no dependence
  /// on which frame this runs on.
  ///
  /// The [TvDiscoveryLayout.railLeadInset] margin is kept on both sides while
  /// scrolled, not just at offset 0: the band is as wide as the screen, so a
  /// tile flush against the viewport edge is a focus ring inside the overscan
  /// band (hoofdstuk 8.1). That is the same rect `tvos.discovery.overscan`
  /// asserts against `discover.safe_area`.
  void _revealFocused(int index, double scale) {
    final target = _revealTarget(index, scale);
    if (target == null) return;

    final duration = reduceMotion(context, FocusTheme.getAnimationDuration(context));
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
      return;
    }
    // The same curve and duration the tile expands on, so the two read as one
    // movement rather than as a scroll chasing a resize.
    _scroll.animateTo(target, duration: duration, curve: Curves.easeOutCubic);
  }

  FocusNode _nodeFor(String groupId) =>
      _nodes.putIfAbsent(groupId, () => FocusNode(debugLabel: 'tvDiscoveryTile_$groupId'));

  /// Puts the focus on the tile this rail is currently describing, so a landing
  /// returning from a detail page lands on the title it left from.
  bool focusCurrent() {
    final group = _focused.value;
    return group != null && focusGroup(group.groupId);
  }

  /// Puts the focus on one named tile, or reports that it could not.
  ///
  /// Fails rather than approximates when the tile is not built: the rail is
  /// virtualized, so a group scrolled far out of the viewport has no focus node
  /// yet, and quietly focusing the nearest built tile instead would restore the
  /// user to a title they never chose. The caller decides what to do with a
  /// false — for restoration that means falling back to the rail's first tile.
  bool focusGroup(String groupId) {
    final node = _nodes[groupId];
    if (node == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  /// Takes the focus at [column] — the horizontal position a vertical step
  /// arrived from — and reports whether this rail could take it (LAND4).
  ///
  /// The column is an index and not an x-coordinate, and the two are the same
  /// thing here: [TvDiscoveryLayout.railPitch] is a function of the page scale
  /// alone, so every rail on a page lays its tiles on one grid and column *n*
  /// of any rail is column *n* of every other. "every rail on a page lays its
  /// tiles on one grid" in `test/widgets/tv/tv_discovery_rail_test.dart` holds
  /// that against the rendered x-positions. Should a rail ever get its own tile
  /// width, this is the method that has to start comparing centres instead of
  /// indices, and nothing else does.
  ///
  /// A shorter rail clamps rather than declines: seven tiles with the focus on
  /// the sixth, stepping into a rail of four, is that rail's fourth. Declining
  /// would send the step past a rail that is plainly there, which is the one
  /// thing the contract rules out.
  bool focusColumn(int column) {
    if (widget.groups.isEmpty) return false;
    return _focusIndex(column.clamp(0, widget.groups.length - 1));
  }

  bool _focusIndex(int index) {
    final groupId = widget.groups[index].groupId;
    final node = _nodes[groupId];
    if (node != null && node.parent != null && node.canRequestFocus) {
      node.requestFocus();
      return true;
    }

    // The tile is not in the built window: the band is a `ListView.builder`, so
    // a rail parked at its tenth tile has no widget — and therefore no
    // focusable node — for its second. Move the band first and take the focus
    // on the frame the tile exists on.
    //
    // This is not the post-frame `requestFocus` the LAND4 note rules out. That
    // one papers over a focus graph that is wrong *now*; here the graph is
    // right and the target genuinely does not exist yet, because a viewport
    // decides what exists. The jump rather than an animation is what makes the
    // next frame the frame: the tile has to be built when the callback runs,
    // and `_revealFocused`'s own animation would land it several frames later.
    // No band at all means this rail is not laid out: offstage, or never
    // built. That is the one case where declining is right, and the caller
    // carries the step on to the next rail.
    if (!_scroll.hasClients) return false;
    final target = _revealTarget(index, _scale);
    if (target != null) _scroll.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final built = _nodes[groupId];
      if (built != null && built.parent != null && built.canRequestFocus) built.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    _scale = scale;

    // An ancestor of every tile rather than a callback per tile: moving from
    // one tile to its neighbour hands the focus over inside this subtree, so
    // the ancestor never sees it leave and the block does not blink on a
    // horizontal step. A per-tile `onFocusChange(false)` would.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) => _holdsFocus.value = hasFocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned to exactly what [TvDiscoveryLayout.railSectionHeight] budgets
          // for it. A heading left to its intrinsic height is a fraction of a
          // pixel taller than one line of its own font metrics, and a rail that
          // overflows its section by a fraction is a rail whose section height is
          // no longer the constant the whole no-jank contract rests on.
          SizedBox(
            height: TvDiscoveryLayout.sectionTitleFontSize * TvDiscoveryLayout.metaLineHeight * scale,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: TvDiscoveryLayout.pageInset * scale),
              child: TvSectionHeader(
                title: widget.title,
                isPartial: widget.isPartial,
                partialLabel: t.unifiedCatalog.discovery.partial,
              ),
            ),
          ),
          SizedBox(height: TvDiscoveryLayout.sectionHeaderGap * scale),
          // The band, not the whole section: `discover.rail`'s bounds are what a
          // scenario measures a tile against, so it has to be the box the tiles
          // are actually laid out in — not the heading and the metadata block as
          // well. Pass-through when `!kPleyaVerify`.
          AutomationNode(
            id: widget.automationRailIndex == null ? null : AutomationIds.discoverRail,
            instance: widget.automationRailIndex?.toString(),
            role: 'rail',
            label: widget.title,
            child: SizedBox(height: TvDiscoveryLayout.railBandHeight(scale), child: _band(scale)),
          ),
          SizedBox(height: TvDiscoveryLayout.railMetaGap * scale),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: TvDiscoveryLayout.pageInset * scale),
            child: SizedBox(
              height: TvDiscoveryLayout.metaBlockHeight(scale),
              // Hoofdstuk 33.3/33.4: metadata sits "alléén onder het gefocuste
              // item, begrensd op zijn breedte". Full width let a synopsis start
              // left of the expanded tile and end right of it, so it read as a
              // page-level caption rather than as this title's description.
              width: TvDiscoveryLayout.wideWidth(scale),
              // Only the rail the remote is standing in describes its tile.
              //
              // Every rail used to draw this block, its own current tile
              // included, so a stacked feed showed one caption per rail at once.
              // On a physical Apple TV that read as two focus contexts on screen
              // together: the title and synopsis of a film in one rail stayed up
              // while the focus already stood on a film in the rail below, which
              // also had its own block. The earlier note here weighed a gate
              // against TV Search, where these captions are the only place a
              // result's title appears, and left it ungated on the grounds that
              // making the caption conditional was a product change rather than
              // a layout fix. It has since been decided as a product contract
              // for every surface that stacks rails, Search included: the
              // projection belongs to the item that has the focus, and to no
              // other. A rail nobody is standing in is not describing anything.
              child: ValueListenableBuilder<bool>(
                valueListenable: _holdsFocus,
                builder: (context, holdsFocus, _) => !holdsFocus && !widget.alwaysDescribesCurrent
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<UnifiedMediaGroup?>(
                        valueListenable: _focused,
                        builder: (context, group, _) =>
                            group == null ? const SizedBox.shrink() : _MetaBlock(group: group),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _band(double scale) {
    // The tile pads itself by its focus-ring gap, so the list's own padding is
    // the page inset minus that — otherwise the first tile's artwork sits
    // further right than the heading above it and the column stops lining up.
    final lead = TvDiscoveryLayout.railLeadInset(scale);

    return ListView.builder(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      // The page inset on both sides, plus the room the last tile needs to
      // expand into (LAND3).
      //
      // P9 was first read as "the last tile has no trailing room", then argued
      // away: a tile's expansion is an `AnimatedContainer` inside the
      // scrollable, so growing it grows the content, and `maxScrollExtent` ends
      // up exactly at the offset [_revealFocused] wants for the last tile, to
      // the pixel. That is true, and it is true too late. The reveal is decided
      // on the frame the focus lands, when nothing in this band is expanded
      // yet, so the extent it clamps against is the *resting* content and the
      // target comes out [TvDiscoveryLayout.railFocusHeadroom] short. Walking
      // the rail hides that, because the tile being left is still wide while
      // the next one grows. Arriving from elsewhere, on a vertical step or a
      // restore, does not: on the canonical canvas it put the last tile's right
      // edge at 1209 on a 1038-wide screen (LAND3).
      //
      // So the room is reserved, and it is reserved unconditionally: an extent
      // that changed with where the focus is would be the same frame-ordering
      // bug wearing a different hat. Nothing scrolls into it, because every
      // scroll this rail makes comes from [_revealTarget], which asks for the
      // offset a tile needs and never for the end of the band.
      padding: EdgeInsets.only(left: lead, right: lead + TvDiscoveryLayout.railFocusHeadroom(scale)),
      // Lazy by construction: only the tiles the viewport can reach are built,
      // so a rail of forty groups costs the images of the six on screen
      // (hoofdstuk 42).
      itemCount: widget.groups.length,
      itemBuilder: (context, index) {
        final group = widget.groups[index];
        return Padding(
          // Between tiles only, so the row's outer edges stay on the page inset.
          padding: EdgeInsets.only(right: index == widget.groups.length - 1 ? 0 : TvDiscoveryLayout.itemGap * scale),
          child: TvExpandableMediaTile(
            // Stable across a re-projection that reorders or lengthens the row.
            key: ValueKey(group.groupId),
            group: group,
            clientFor: widget.clientFor,
            focusNode: _nodeFor(group.groupId),
            scrollAlignment: widget.tileScrollAlignment,
            autofocus: widget.autofocus && index == 0,
            // Instance is `<railIndex>.<tileIndex>` so one scenario can address
            // "the third tile of the second rail" without the rails having to
            // agree on a global counter.
            automationId: AutomationIds.discoverRailItem,
            automationInstance: widget.automationRailIndex == null ? null : '${widget.automationRailIndex}.$index',
            onSelect: () => widget.onActivate(group),
            onContextMenu: widget.onContextMenu == null ? null : () => widget.onContextMenu!(group),
            semanticLabel:
                '${semanticLabelFor(group)}, '
                '${t.unifiedCatalog.discovery.semantics.position(position: index + 1, count: widget.groups.length)}',
            onFocusChange: (focused) {
              // Only on gain. A move within this rail would otherwise clear the
              // block for one frame on the way out of the old tile, and a move
              // *off* the rail would empty it entirely — the rail should keep
              // describing where it was left, which is also what the user comes
              // back to.
              if (!focused) return;
              _focused.value = group;
              widget.onFocusedGroupChanged?.call(group.groupId);
              _revealFocused(index, scale);
              _warmAround(index);
            },
            // The anchor for the next vertical step is the tile being left,
            // so LEFT and RIGHT move it without having to say so.
            onNavigateUp: widget.onNavigateUp == null ? null : () => widget.onNavigateUp!(index),
            onNavigateDown: widget.onNavigateDown == null ? null : () => widget.onNavigateDown!(index),
            // Hard stops at both ends of the row. Left as `null` these fall
            // through to Flutter's geometric traversal, and on a stacked feed
            // the nearest focusable to the right of a row's last tile is the
            // *next row's* first tile — so RIGHT off the end of Continue
            // Watching silently dropped the viewer a row down, which reads as
            // the remote having a mind of its own. A row is horizontal; its
            // ends are ends (the same convention the top navigation states as
            // "geen wrap van laatste naar eerste").
            onNavigateLeft: index == 0 ? () {} : null,
            onNavigateRight: index == widget.groups.length - 1 ? () {} : null,
          ),
        );
      },
    );
  }
}

/// The focused tile's three tiers, under the rail.
class _MetaBlock extends StatelessWidget {
  const _MetaBlock({required this.group});

  final UnifiedMediaGroup group;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final ctx = discoveryContextFor(group);

    // Each tier gets exactly the height [TvDiscoveryLayout.metaBlockHeight]
    // budgets for it. Left to their intrinsic heights the three texts land a
    // fraction of a pixel over that budget — enough for a RenderFlex overflow,
    // and enough for the block to stop being the constant the rail's section
    // height is computed from.
    Widget line(double fontSize, int maxLines, Widget child) =>
        SizedBox(height: fontSize * TvDiscoveryLayout.metaLineHeight * maxLines * scale, child: child);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        line(
          TvDiscoveryLayout.metaTitleFontSize,
          1,
          Text(
            ctx.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text.withValues(alpha: TvDiscoveryLayout.inkPrimary),
              fontSize: TvDiscoveryLayout.metaTitleFontSize * scale,
              height: TvDiscoveryLayout.metaLineHeight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: TvDiscoveryLayout.metaLineGap * scale),
        line(
          TvDiscoveryLayout.metaContextFontSize,
          1,
          Text(
            ctx.context,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text.withValues(alpha: TvDiscoveryLayout.inkSecondary),
              fontSize: TvDiscoveryLayout.metaContextFontSize * scale,
              height: TvDiscoveryLayout.metaLineHeight,
            ),
          ),
        ),
        SizedBox(height: TvDiscoveryLayout.metaLineGap * scale),
        if (ctx.synopsis != null)
          line(
            TvDiscoveryLayout.metaSynopsisFontSize,
            TvDiscoveryLayout.metaSynopsisMaxLines,
            Text(
              ctx.synopsis!,
              maxLines: TvDiscoveryLayout.metaSynopsisMaxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tk.text.withValues(alpha: TvDiscoveryLayout.inkTertiary),
                fontSize: TvDiscoveryLayout.metaSynopsisFontSize * scale,
                height: TvDiscoveryLayout.metaLineHeight,
              ),
            ),
          ),
      ],
    );
  }
}
