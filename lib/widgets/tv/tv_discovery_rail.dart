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

import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_item.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
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
/// the show they are and how much is left; for a film it is the year and what
/// kind of film it is. The source count is last and only when there is more
/// than one — hoofdstuk 13 — and no server or library name appears at any
/// position, because on a unified surface that is a detail of *storage*, not of
/// the title (hoofdstuk 26).
DiscoveryContext discoveryContextFor(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  final isEpisode = item.kind == MediaKind.episode;
  final title = isEpisode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle;

  final parts = <String>[
    if (isEpisode) ?_episodeLabel(item),
    ?_remainingLabel(group, item),
    if (item.year != null) '${item.year}',
    if (item.genres != null && item.genres!.isNotEmpty) item.genres!.first,
    if (group.hasMultipleSources) t.unifiedCatalog.sources(count: group.sources.length),
  ];

  final summary = item.summary?.trim();
  return (title: title, context: parts.join(' · '), synopsis: summary == null || summary.isEmpty ? null : summary);
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
    this.clientFor,
    this.isPartial = false,
    this.autofocus = false,
    this.initialFocusedGroupId,
    this.onFocusedGroupChanged,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final String title;

  /// Already projected, already deduplicated, already bounded. The rail does no
  /// grouping, no filtering and no fetching of its own — hoofdstuk 10.2a's
  /// architecture boundary is that a TV widget never builds a discovery row.
  final List<UnifiedMediaGroup> groups;

  final ValueChanged<UnifiedMediaGroup> onActivate;
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
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  State<TvDiscoveryRail> createState() => TvDiscoveryRailState();
}

class TvDiscoveryRailState extends State<TvDiscoveryRail> {
  final _nodes = <String, FocusNode>{};
  final _scroll = ScrollController();
  late final ValueNotifier<UnifiedMediaGroup?> _focused;

  @override
  void initState() {
    super.initState();
    _focused = ValueNotifier(_restoredOrFirst());
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
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    _focused.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);

    return Column(
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
        SizedBox(height: TvDiscoveryLayout.railBandHeight(scale), child: _band(scale)),
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
            // Every rail describes its own current tile, including the ones
            // the focus is not on. A visual review read hoofdstuk 33.3's
            // "alléén onder het gefocuste item" as also meaning "only on the
            // focused rail", and gating it that way does match the north-star
            // render — but it costs more than it buys: on TV Search the rails
            // carry the results, and titles live *only* in this block, so
            // results would arrive as unlabelled artwork until the viewer
            // moved focus into them. The binding half of that sentence is the
            // position and width, which the `width` above now honours; making
            // the seeded caption conditional as well is a product change, not
            // a layout fix, and is not one to make from a mockup alone.
            child: ValueListenableBuilder<UnifiedMediaGroup?>(
              valueListenable: _focused,
              builder: (context, group, _) => group == null ? const SizedBox.shrink() : _MetaBlock(group: group),
            ),
          ),
        ),
      ],
    );
  }

  Widget _band(double scale) {
    // The tile pads itself by its focus-ring gap, so the list's own padding is
    // the page inset minus that — otherwise the first tile's artwork sits
    // further right than the heading above it and the column stops lining up.
    final tileInset = TvDiscoveryLayout.cardFocusRingGap * scale;
    final lead = (TvDiscoveryLayout.pageInset * scale - tileInset).clamp(0.0, double.infinity);

    return ListView.builder(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: lead),
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
            autofocus: widget.autofocus && index == 0,
            onSelect: () => widget.onActivate(group),
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
            },
            onNavigateUp: widget.onNavigateUp,
            onNavigateDown: widget.onNavigateDown,
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
