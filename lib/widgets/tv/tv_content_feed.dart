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
import '../../media/unified/unified_route_context.dart';
import '../../services/settings_service.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../state_view.dart';
import 'tv_content_row.dart';
import 'tv_discovery_rail.dart';
import 'tv_hero_billboard_carousel.dart';
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

  /// Keyed on the stable `hubId` (hoofdstuk 17.5), never on an index: a
  /// re-projection that reorders rows must not hand a row's focus nodes and
  /// scroll position to a different row.
  final _rowKeys = <String, GlobalKey<TvDiscoveryRailState>>{};

  /// Hoofdstuk 7.6/19 restoration, by **group id** rather than by index. A row
  /// that gained a source, lost one, or came back shorter still returns the
  /// viewer to the title they left, or to its first card when that title is
  /// genuinely gone.
  final _focusedGroupIdByRowId = <String, String>{};
  String? _heroGroupId;

  /// The rows of the last build, in the order they were drawn.
  ///
  /// Kept because `_rowKeys` cannot answer "which row is first". It is a map
  /// filled by `putIfAbsent`, so its iteration order is first-ever-insertion,
  /// and a Home-layout reorder or a re-projection changes what is on screen
  /// without changing that. Walking the keys for DOWN out of the hero therefore
  /// landed on whichever row happened to be built first — right until the
  /// viewer reordered their Home, and silently wrong after.
  List<UnifiedMediaHub> _visibleRows = const [];

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
  bool _focusFirstRow() {
    for (final row in _visibleRows) {
      final state = _rowKeys[row.hubId]?.currentState;
      if (state != null && state.focusCurrent()) return true;
    }
    return false;
  }

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
  void _focusHeroFromFirstRow() {
    if (_heroKey.currentState?.focusLastCta() ?? false) return;
    if (!_hasHero) {
      widget.onNavigateUp?.call();
      return;
    }
    if (_scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_heroKey.currentState?.focusLastCta() ?? false) return;
      widget.onNavigateUp?.call();
    });
  }

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
    _visibleRows = rows;

    if (rows.isEmpty && heroGroups.isEmpty && !reserveHeroSpace) return _emptyOrLoading(discover);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = TvLayoutConstants.scaleOf(context);
        final heroSize = Size(
          TvHomeLayout.heroWidth(constraints.maxWidth, scale),
          TvHomeLayout.heroHeight(constraints.maxWidth, constraints.maxHeight, scale),
        );

        return ShaderMask(
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
            padding: EdgeInsets.only(top: TvHomeLayout.heroTopGap * scale, bottom: TvHomeLayout.heroRowGap * scale),
            children: [
              if (reserveHeroSpace)
                // 9.7: "de billboardruimte wordt gereserveerd totdat de
                // featured-query gereed is". Space, not a spinner — the rows
                // below are already real, and a second loading indicator over
                // live content reads as a fault.
                SizedBox(height: heroSize.height + TvHomeLayout.heroRowGap * scale),
              if (heroGroups.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: TvDiscoveryLayout.pageInset * scale),
                  child: SizedBox(
                    height: heroSize.height,
                    child: TvHeroBillboardCarousel(
                      key: _heroKey,
                      groups: heroGroups,
                      size: heroSize,
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
                ),
                SizedBox(height: TvHomeLayout.heroRowGap * scale),
              ],
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
                          railKey: _rowKeys.putIfAbsent(
                            rows[i].hubId,
                            () => GlobalKey<TvDiscoveryRailState>(debugLabel: 'tvContentRow_${rows[i].hubId}'),
                          ),
                          clientFor: _clientFor,
                          initialFocusedGroupId: _focusedGroupIdByRowId[rows[i].hubId],
                          onFocusedGroupChanged: (id) => _focusedGroupIdByRowId[rows[i].hubId] = id,
                          onActivate: _activate,
                          onNavigateUp: i == 0 && heroGroups.isNotEmpty ? _focusHeroFromFirstRow : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
