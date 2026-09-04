/// The fase-8 TV Home: a rounded featured carousel with the content feed
/// beneath it (hoofdstuk 9 and 17 of docs/tvos-unified-experience.md, north
/// star 33.1/33.2).
///
/// ## What replaced what
///
/// This is the production owner of the surface `DiscoverScreen._buildTvContent`
/// used to compose out of a fullscreen `TvSpotlightBackground` and a
/// `TvBrowseRail` sliding up over it. Four things went with that composition,
/// and none of them is ported:
///
/// * the full-bleed billboard — 33.1 binds "afgeronde kaart ín de pagina …
///   nooit full bleed";
/// * `_tvRailRevealed` and the `AnimatedSlide` reveal — the rows are laid out
///   *under* the hero now, in one scrollable column, so there is nothing to
///   reveal;
/// * `_setSpotlightDebounced`, and with it the whole idea that row focus picks
///   the hero (hoofdstuk 7.3, DEC-066 punt 3, DEC-067 punt 3);
/// * `MediaHub`/`MediaItem` rows — the feed reads
///   `TvHomeProjectionProvider.continueWatching` and `.hubs`, the projected
///   rows `docs/tvos-unified-fase6-home-rows-deviation.md` built and then had
///   to leave without a consumer until this phase.
///
/// ## Hero and rows are two independent state machines
///
/// The carousel owns its active slide; this feed owns which row and card hold
/// the focus. Neither reads the other. The one signal that crosses is
/// deliberately not content: [_rowHasFocus] tells the carousel to hold its
/// rotation and to fade its text (33.2) — a *lifecycle* fact about where the
/// remote is, carrying no item, no group and no index. There is no path by
/// which focusing a card can change which film the billboard shows, and
/// `test/screens/tv/tv_content_feed_test.dart` asserts exactly that.
///
/// ## Everything a row shows has been through the identity pipeline
///
/// Rows arrive as [UnifiedMediaHub]s: one card per logical title, every
/// concrete source still on `group.sources`, visibility filtering applied
/// before grouping (the projection reads `DiscoverProvider`, which is already
/// hidden-library-filtered). Activation hands the whole group to the fase-4
/// coördinator. So the two deferred fase-6 requirements — no duplicate logical
/// title in a Home row, and Home-row activation through the coördinator — are
/// properties of the data this widget is given and of the one call it makes,
/// not of a check it performs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../screens/tv/tv_discovery_activation_mixin.dart';
import '../../screens/tv/tv_root_shell.dart' show TvShellSurface;
import '../../media/unified/unified_route_context.dart';
import '../../services/settings_service.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../state_view.dart';
import 'tv_content_row.dart';
import 'tv_hero_billboard_card.dart' show TvHeroDimVeil;
import 'tv_hero_billboard_carousel.dart';
import 'tv_rail_stack.dart';
import 'tv_unified_layout.dart';

class TvContentFeed extends StatefulWidget {
  const TvContentFeed({super.key, this.onManageServers, this.onNavigateUp, this.onBack});

  /// Hoofdstuk 14.7's escape from a source picker with nothing reachable.
  final VoidCallback? onManageServers;

  /// UP out of the hero, into the active top-navigation destination.
  final VoidCallback? onNavigateUp;

  final VoidCallback? onBack;

  @override
  State<TvContentFeed> createState() => TvContentFeedState();
}

class TvContentFeedState extends State<TvContentFeed> with TvDiscoveryActivationMixin, WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _heroKey = GlobalKey<TvHeroBillboardCarouselState>();

  /// Who owns UP and DOWN between the rows (LAND4), and the keys they are
  /// reached by.
  ///
  /// Keyed on the stable `hubId` (hoofdstuk 17.5), never on an index: a
  /// re-projection that reorders rows must not hand a row's focus nodes and
  /// scroll position to a different row.
  final _rowStack = TvRailStack();

  /// Hoofdstuk 7.6/19 restoration, by **group id** rather than by index. A row
  /// that gained a source, lost one, or came back shorter still returns the
  /// viewer to the title they left, or to its first card when that title is
  /// genuinely gone.
  final _focusedGroupIdByRowId = <String, String>{};
  String? _heroGroupId;

  bool _rowHasFocus = false;
  bool _atTop = true;

  /// Whether the last build had a billboard at all, so [_focusHeroFromFirstRow]
  /// can tell "the hero is scrolled out of the viewport" from "there is no
  /// hero" without reading a provider off the focus path.
  bool _hasHero = false;
  bool _appResumed = true;

  /// Set by the shell when Home stops being the active destination. Read
  /// rather than inferred: an offstage `IndexedStack` child keeps building, so
  /// "am I on screen" is not something this widget can see for itself.
  bool _destinationActive = true;

  late DiscoverProvider _discover;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _discover = context.read<DiscoverProvider>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed != _appResumed) setState(() => _appResumed = resumed);
  }

  void _onScroll() {
    final atTop = !_scroll.hasClients || _scroll.offset <= 0.5;
    if (atTop != _atTop) setState(() => _atTop = atTop);
  }

  /// Called by the shell on a destination switch. Stopping the rotation is the
  /// point (hoofdstuk 9.6, fase-8 brief §9: "Bij Home verlaten: timer
  /// stopt/pausert"), and it is a flag rather than a dispose so returning to
  /// Home finds the feed exactly as it was left — scroll position, focused
  /// card, active slide (§19).
  void setDestinationActive(bool active) {
    if (active == _destinationActive) return;
    setState(() => _destinationActive = active);
  }

  /// Hoofdstuk 7.1/7.3: DOWN out of the top navigation lands on Afspelen.
  /// Falls through to the first row for a Home with no hero at all, so the
  /// remote is never stranded.
  bool focusPrimary() {
    if (_heroKey.currentState?.focusPlay() ?? false) return true;
    return _focusFirstRow();
  }

  /// Restoration entry point: the card the viewer was last on, else the hero.
  bool focusRestored() => _focusFirstRow() || focusPrimary();

  /// The first row that can actually take the focus, in **display** order.
  ///
  /// `focusCurrent` rather than "the first card": a row the viewer has already
  /// walked keeps its place, so going up to the hero and back down returns them
  /// to the title they were on. A row whose cards are scrolled out of the band
  /// has no focus node yet and reports false, and the next row down is then the
  /// honest answer.
  bool _focusFirstRow() => _rowStack.focusFirstCurrent();

  /// UP out of the first row (hoofdstuk 7.3: "terug naar de laatst gebruikte
  /// hero-CTA"). Falls through to the top navigation when there is no hero.
  ///
  /// The scroll is not a flourish, it is the fix for a real dead end. Focusing
  /// a content row scrolls the feed so the row is fully visible (33.2 draws
  /// exactly that), and a `ListView` disposes what it can no longer see — so by
  /// the time the viewer presses UP, the carousel is very often not in the tree
  /// and `_heroKey.currentState` is null. Without this the press fell through
  /// to the top navigation and the billboard became unreachable from below,
  /// which is precisely the traversal 7.3 specifies.
  ///
  /// `jumpTo`, not `animateTo`: the hero has to be *built* before its CTA can
  /// take the focus, and an animated scroll gives no frame at which that is
  /// guaranteed. The viewer reads this as the billboard coming back with the
  /// focus, not as a jump — and under reduced motion an instant change is the
  /// right answer anyway.
  ///
  /// **The scroll comes first, in both branches.** The earlier version tried
  /// `focusLastCta()` before restoring the offset and returned as soon as it
  /// succeeded. That reads as "the hero is still here, nothing to scroll" and
  /// it is not: a `ListView` keeps building for a whole `cacheExtent` past the
  /// viewport, `canRequestFocus` is true for a mounted-but-offscreen node, and
  /// a bare `requestFocus()` provokes no `ensureVisible` of its own — only the
  /// traversal policy does that, and this is not traversal. So on the ordinary
  /// case, one row down and straight back up, the CTA took the focus while the
  /// billboard was entirely off the top of the screen, and `jumpTo(0)` on the
  /// line below was skipped. The next press then left for the top navigation
  /// and the hero was unreachable from below — the exact dead end this method
  /// exists to close. The doc that defended the early return only reasoned
  /// about the *disposed* hero, which is the other half of the same case.
  void _focusHeroFromFirstRow() {
    if (!_hasHero) {
      widget.onNavigateUp?.call();
      return;
    }
    if (_scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
    if (_heroKey.currentState?.focusLastCta() ?? false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_heroKey.currentState?.focusLastCta() ?? false) return;
      widget.onNavigateUp?.call();
    });
  }

  /// The feed's scroll offset, so a test can prove the hero is back *in view*
  /// and not merely focused — the two came apart, and only the second was ever
  /// asserted.
  @visibleForTesting
  double get scrollOffset => _scroll.hasClients ? _scroll.offset : 0;

  /// Every hoofdstuk 9.6 pause condition this widget owns, in one place.
  ///
  /// `ModalRoute.isCurrent` is what covers "een overlay open is" and "een
  /// source picker open is" without this widget having to know what an overlay
  /// is — a pushed picker, detail page or player makes Home's own route
  /// non-current, and reading it in `build` means a push rebuilds this. It is
  /// the same predicate the pre-fase-8 Home used for the same question.
  ///
  /// Deliberately *not* "does the feed hold the focus". That reads as the same
  /// thing and is not: the fase-7 top navigation is outside this widget, so
  /// resting on the bar would stop the carousel — and a viewer standing on the
  /// nav watching the billboard cycle is the case hoofdstuk 9.6 is describing,
  /// not one it excludes. A *content row* holding the focus is excluded, and
  /// that is a condition 9.6 names.
  bool get _autoplayEnabled => _destinationActive && _appResumed && _routeIsCurrent && !_rowHasFocus && _atTop;

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  Future<void> _activate(UnifiedMediaGroup group) =>
      activateDiscoveryGroup(group, onManageServers: widget.onManageServers);

  /// Hoofdstuk 23's menu on a Home row.
  ///
  /// [isInContinueWatching] is passed per row rather than derived from the
  /// group, because it is a fact about *where the card is*: the same title can
  /// sit in Verder kijken and in a recommendation row on one screen, and
  /// "Verwijder uit Verder kijken" only means something on the first.
  Future<void> _openContextMenu(UnifiedMediaGroup group, {required bool isInContinueWatching}) =>
      openDiscoveryContextMenu(
        group,
        isInContinueWatching: isInContinueWatching,
        onChanged: () => _refreshGroupSources(group),
      );

  /// Refreshes every source [group] carries after a hoofdstuk-23 write landed.
  ///
  /// **Not "the projection recomputes on its own" — that is true of Continue
  /// Watching alone, and this menu opens on every row, not only that one.**
  /// `DiscoverProvider._onWatchStateChanged` reacts to every
  /// [WatchStateEvent] and calls `refreshContinueWatching()`, whose own doc
  /// says it "never refetches hubs" — by design, it is a background poll of
  /// one row, not a general invalidation. A markeer bekeken/onbekeken done
  /// from a Top Picks or Recently Released card is exactly the case that
  /// misses: `_hubs` stays the list that was already there, so
  /// [TvHomeProjectionProvider]'s own change guard (element-identity
  /// `listEquals`) never fires and that card's watched badge — read straight
  /// off the projected `group.watchState`, hoofdstuk 12's groups carry no
  /// live patch of their own — is stale until the next full [DiscoverProvider.load].
  ///
  /// [DiscoverProvider.updateItem] is the same incremental refresh I19 already
  /// gives a playback return (`activateDiscoveryGroup`'s `onPlaybackReturned`):
  /// refetch one item, swap it into on-deck/hubs by id, notify. Looping every
  /// source rather than only the representative one is deliberate — "Alle
  /// bronnen" writes every membership, so every membership's card (a title can
  /// appear once per server it is on) needs the same refresh, not just the one
  /// the group happens to display first.
  void _refreshGroupSources(UnifiedMediaGroup group) {
    final discover = context.read<DiscoverProvider>();
    for (final source in group.sources) {
      unawaited(discover.updateItem(source.item.id, serverId: source.item.serverId));
    }
  }

  Future<void> _activateHero(
    UnifiedMediaGroup group, {
    required UnifiedActivationIntent intent,
    required bool playDirectly,
  }) => activateDiscoveryGroup(
    group,
    intent: intent,
    playDirectly: playDirectly,
    onManageServers: widget.onManageServers,
  );

  /// Continue Watching, then Recently Released, then the recommendation rows
  /// in `DiscoverProvider`'s own order.
  ///
  /// That is exactly the order the pre-fase-8 TV Home had (`_tvBrowseHubs`:
  /// continue watching, latest movies, hubs), and it is kept rather than
  /// re-derived from hoofdstuk 9.1's three-row sketch. 33.1 and 33.2 bind the
  /// *first* row as Continue Watching, which holds either way; 33.3 binds
  /// "de canonieke providervolgorde" for what follows, and reordering the rows
  /// of a shipped Home on the strength of a sketch would be a product change
  /// made silently.
  ///
  /// Hoofdstuk 17.5's hide/reorder applies to the recommendation rows, and
  /// applies to the *unified* ones: see `home_row_layout.dart` for why a merged
  /// row needs every contributor hidden before it disappears. Continue Watching
  /// and Recently Released sit outside that layout, exactly as they did before
  /// — neither was ever one of the rows the settings screen lists.
  List<UnifiedMediaHub> _rows(TvHomeProjectionProvider projection, HomeLayoutProvider? layout) {
    final cw = projection.continueWatching;
    final latest = projection.latestMovies;
    final hubs = layout == null
        ? projection.hubs
        : applyHomeLayoutToUnifiedRows(projection.hubs, hiddenRowIds: layout.hiddenRowIds, order: layout.order);
    return [if (cw != null && cw.groups.isNotEmpty) cw, if (latest != null) latest, ...hubs];
  }

  /// Hoofdstuk 9.5's last sentence, and fase-8 brief §22's "0 hero groups":
  /// when the deduplicated recent-film pool is genuinely empty — a show-only
  /// library, or every recent film ineligible — the billboard falls through to
  /// the first Continue Watching title, then to the first hub's, exactly as
  /// `DiscoverScreen` did before this phase. Existing behaviour, not new
  /// fallback semantics.
  ///
  /// One slide, never a rotation over the whole library: this is a stand-in for
  /// a featured title, and rotating it would claim these are new releases. And
  /// it is still a group, so its Afspelen resolves through the fase-4
  /// coördinator like every other card on the page.
  List<UnifiedMediaGroup> _fallbackHero(List<UnifiedMediaHub> rows) {
    for (final row in rows) {
      if (row.groups.isNotEmpty) return [row.groups.first];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final projection = context.watch<TvHomeProjectionProvider>();
    final discover = context.watch<DiscoverProvider>();
    final layout = context.watch<HomeLayoutProvider?>();
    final rows = _rows(projection, layout);
    // Read off the projection's own row rather than matched against a slug
    // literal: the slug is a parameter of `projectContinueWatching`, so a
    // literal here would be a second definition that can drift from it.
    final continueWatchingHubId = projection.continueWatching?.hubId;

    // Hoofdstuk 9.7: an empty `heroGroups` for the films Home is *currently*
    // showing is an answer; an empty one because the projection has not yet
    // consumed the films that just landed is not. The two get different
    // treatment — the fallback billboard for the first, reserved space for the
    // second — because flashing a Continue Watching title as the billboard and
    // then replacing it a beat later with a film is the exact "hero mag niet
    // boven een al gefocuste rij ingevoegd worden" jump 9.7 forbids.
    final heroSettled =
        projection.hasProjectedHero && identical(projection.projectedLatestMovies, discover.latestMovies);
    final heroGroups = projection.heroGroups.isNotEmpty
        ? projection.heroGroups
        : (heroSettled ? _fallbackHero(rows) : const <UnifiedMediaGroup>[]);
    final reserveHeroSpace = heroGroups.isEmpty && !heroSettled;
    _hasHero = heroGroups.isNotEmpty;
    // In draw order, so "the row below this one" follows the page rather than
    // the order the keys were first created in — a Home-layout reorder or a
    // re-projection changes the former and not the latter.
    _rowStack.layOut(rows.map((row) => row.hubId));

    if (rows.isEmpty && heroGroups.isEmpty && !reserveHeroSpace) return _emptyOrLoading(discover);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = TvLayoutConstants.scaleOf(context);
        final viewportHeight = constraints.maxHeight;
        // DEC-095, mockup 30 A1. The *hero block* is what the landing shows
        // above the first rail's label, and it is a list child like the rows,
        // so the label, the peeking posters and the text scroll as one page.
        // The *backdrop* is taller than that block — it runs up behind the top
        // navigation and down behind the peeking rail — so it cannot live
        // inside the list's viewport; it is a layer under the list, translated
        // by the list's own offset, which reads as the same page scrolling.
        final heroBlock = TvHomeLayout.heroBlockHeight(viewportHeight, scale);
        final navBand = TvShellSurface.topBandHeightOf(context);
        final bleed = Size(constraints.maxWidth, navBand + viewportHeight);
        final textBottom = (viewportHeight - heroBlock) + TvHomeLayout.heroTextRailGap * scale;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (heroGroups.isNotEmpty)
              Positioned(
                top: -navBand,
                left: 0,
                right: 0,
                height: bleed.height,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: _scroll,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, -(_scroll.hasClients ? _scroll.offset : 0.0)),
                          child: child,
                        ),
                        child: TvHeroBillboardCarousel(
                          key: _heroKey,
                          groups: heroGroups,
                          size: bleed,
                          textBottom: textBottom,
                          clientFor: _clientFor,
                          autoplayEnabled: _autoplayEnabled,
                          // 33.2: the hero's text fades once a row has the focus.
                          textOpacity: _rowHasFocus ? 0 : 1,
                          hideSpoilers: SettingsService.instance.read(SettingsService.hideSpoilers),
                          initialGroupId: _heroGroupId,
                          onActiveGroupChanged: (id) => _heroGroupId = id,
                          onActivate: _activateHero,
                          onNavigateDown: _focusFirstRow,
                          onNavigateUp: widget.onNavigateUp,
                          onBack: widget.onBack,
                        ),
                      ),
                      // Under full-bleed the picture steps back with the text
                      // (mockup 30 B). Screen-fixed over the scrolled card,
                      // see [TvHeroDimVeil].
                      TvHeroDimVeil(dim: _rowHasFocus ? 1 : 0),
                    ],
                  ),
                ),
              ),
            ShaderMask(
              // Same treatment as the landings (33.3): the peeking row at the
              // bottom edge fades into the page instead of being cut off flat.
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: const [Color(0x00000000), Color(0xFF000000)],
                stops: [0, TvDiscoveryLayout.pageBottomFade * scale / bounds.height],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.only(bottom: TvHomeLayout.heroRowGap * scale),
                children: [
                  // The hero block, or 9.7's reserved space while the featured
                  // query is still out: "de billboardruimte wordt gereserveerd
                  // totdat de featured-query gereed is". Space, not a spinner —
                  // the rows below are already real, and a second loading
                  // indicator over live content reads as a fault.
                  if (reserveHeroSpace || heroGroups.isNotEmpty) SizedBox(height: heroBlock),
                  // One `Focus` around the rows and nothing else: this is the
                  // single bit the carousel is told about, and it carries no
                  // content — see the library doc.
                  Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (has) {
                      if (has != _rowHasFocus) setState(() => _rowHasFocus = has);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0) SizedBox(height: TvDiscoveryLayout.sectionGap * scale),
                          SizedBox(
                            height: TvContentRow.height(scale),
                            child: TvContentRow(
                              hub: rows[i],
                              railKey: _rowStack.keyFor(rows[i].hubId),
                              clientFor: _clientFor,
                              initialFocusedGroupId: _focusedGroupIdByRowId[rows[i].hubId],
                              onFocusedGroupChanged: (id) => _focusedGroupIdByRowId[rows[i].hubId] = id,
                              onActivate: _activate,
                              onContextMenu: (group) =>
                                  _openContextMenu(group, isInContinueWatching: rows[i].hubId == continueWatchingHubId),
                              // Row to row, at the column the step leaves from
                              // (LAND4). UP that runs out of rows above goes back
                              // to the hero; DOWN off the last row has nothing
                              // below it.
                              onNavigateUp: _rowStack.up(
                                i,
                                whenExhausted: heroGroups.isEmpty ? null : _focusHeroFromFirstRow,
                              ),
                              onNavigateDown: _rowStack.down(i),
                              // DEC-095 (3)/(4): a focused rail puts its label
                              // under the top navigation, first row and deeper
                              // rows alike, so the rail below it is wholly on
                              // screen and no band is held open for the hero.
                              tileScrollAlignment: TvHomeLayout.rowTileScrollAlignment(viewportHeight, scale),
                              automationRailIndex: i,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  MediaServerClient? Function(String serverId) get _clientFor =>
      (serverId) => context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId));

  Widget _emptyOrLoading(DiscoverProvider discover) {
    if (discover.isLoading || discover.areHubsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (discover.errorMessage != null) {
      return StateView.error(
        title: discover.errorMessage!,
        icon: Symbols.error_outline_rounded,
        onRetry: () => unawaited(_discover.load()),
      );
    }
    final tk = tokens(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.movie_rounded, fill: 1, size: 64, color: tk.text.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(t.discover.noContentAvailable, style: TextStyle(color: tk.text)),
          const SizedBox(height: 8),
          Text(t.discover.addMediaToLibraries, style: TextStyle(color: tk.textMuted)),
        ],
      ),
    );
  }
}
