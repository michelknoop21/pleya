part of '../../media_detail_screen.dart';

const double _tvDetailTallPosterScale = TvBrowseRailLayout.compactTallPosterScale;
// Mockup 37 C (MOC-10) shows full-width episode/extras cards, not the
// pre-DEC-087 compact 0.8 scale: DEC-087's 615-wide card is the default
// (`widePosterScale: 1.0`), and 37 C never shrinks it.
const double _tvDetailEpisodeThumbnailScale = 1.0;

/// Height of the TV action row in HIG points (DENS1): above tvOS's 56 pt
/// minimum for a button, where the old `46 * scaleOf` came out at 72 pt.
const double _tvDetailActionPt = 60;
const double _tvDetailActionRailGap = 4;
// DET6: tolerance for the exact-fit comparison in `_buildTvDetailForeground`'s
// line-count loop, where `remainingForLogo` and `minLogoHeight` are the same
// real number by construction (see the comment at that comparison). Sized
// well above float noise (observed drift: ~3e-14) and far below anything a
// real shortfall would produce.
const double _tvDetailEpsilon = 0.01;
// DET6 (Michel, 13 september, hardware): the active rail (Acteurs, or
// whichever hub `TvBrowseRailLayout.maxActiveRailHeight` reserves against —
// DET2 already established that a taller *inactive* hub, like Trailers &
// Extra's, can be the one actually driving the reservation) could still cost
// the ideal two-line synopsis its second line on an adversarial hub
// combination. Both `tallPosterScale` (person hubs) and `widePosterScale`
// (wide-card hubs) shrink together at each fraction below, since either one
// can be the max-height hub and the fix has to reach whichever it is.
// Stepped rather than solved: the height `TvBrowseRailLayout.metricsForHub`
// returns is linear in either scale, but `cardWidthFor`'s own density/width
// branching would have to be mirrored exactly for a closed-form inverse to
// stay correct.
const List<double> _tvDetailRailShrinkFractions = [0.9, 0.8, 0.7, 0.6];
const String _tvDetailSeasonsErrorHubId = 'detail_seasons_error';
const String _tvDetailSeasonHubIdPrefix = 'detail_season_';
const String _tvDetailExtrasHubId = 'detail_extras';
const String _tvDetailActorsHubId = 'detail_actors';
const String _tvDetailActorPersonIdRawKey = 'tvDetailActorPersonId';

/// The TV detail page's shell: the backdrop, the info band and the rail under
/// it, and the height reservation that keeps those two from colliding.
extension _MediaDetailTvScreen on _MediaDetailScreenState {
  Widget _buildTvDetailScreen(
    BuildContext context,
    MediaItem metadata,
    KeyEventResult Function(FocusNode, KeyEvent) handleBack,
  ) {
    // INV-1 (docs/tvos-redesign-implementatiecontract.md): this route can be
    // nested inside the TV shell, under the top navigation (PB-1), where the
    // box Flutter actually lays this screen out in is shorter than the
    // physical window. `MediaQuery.sizeOf` would not notice that — a smaller
    // layout box does not re-scope MediaQuery — so it would keep reporting the
    // full window and every measurement below would overshoot the box this
    // widget was actually given. `constraints`, from the `LayoutBuilder` this
    // whole screen now builds inside, is that box; `TvCatalogSkeletonGrid` in
    // `tv_unified_catalog_screen.dart` reads its own height the same way.
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final detailHubs = _tvDetailHubs(metadata);
        if (widget.initialEpisodeId != null && !_initialEpisodePagingDone) {
          _maybeLoadMoreForInitialEpisode();
        }
        final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
        // OVR1a on this surface (DEC-109): the ten-foot scale is a property of
        // the panel, not of this route's content box, which INV-1 already
        // makes shorter than the window when nested under the topnav.
        // `scaleForSize(size)` read the box and floored to 0.85 well before
        // the panel itself would, overshooting every measurement below.
        final detailScale = TvLayoutConstants.scaleOf(context);
        // DEC-115: under the shell the top edge belongs to the shell, and it
        // says how much this route has to keep clear itself through
        // `MediaQuery.padding.top` (0 under a persistent bar, the bar's own
        // overscan inset under a collapsible one). The 8% band is the frame of
        // a standalone, full-window detail and stacked on top of the bar's
        // band when nested.
        final spotlightTop = TvShellSurface.isPresent(context)
            ? MediaQuery.paddingOf(context).top
            : (size.height * 0.08).clamp(44.0 * detailScale, 110.0 * detailScale).toDouble();
        final spotlightLeft = (24 * detailScale).clamp(18.0, 40.0).toDouble();
        // Same box `_buildTvDetailForeground`'s own `Positioned` below gives
        // it, computed here too so the genre-line measurement in the
        // reservation metrics agrees with what that widget actually renders.
        final foregroundWidth = size.width - spotlightLeft - (size.width * 0.43);
        final showSeasonChips = _tvDetailShowsSeasonChips(metadata);
        final rawRailHeight = _estimateTvDetailRailHeight(size, detailHubs, showSeasonChips: showSeasonChips);
        if (!_tvDetailRevealed && _isTvDetailReadyToReveal(metadata)) {
          _scheduleTvDetailReveal(rawRailHeight, focusPrimaryAction: metadata.isMovie);
        }
        final stableRailHeight = _tvDetailStableRailHeight;
        var railHeight = stableRailHeight == null || rawRailHeight > stableRailHeight
            ? rawRailHeight
            : stableRailHeight;
        final railTopPadding = 12 * detailScale;
        // DET7 (Michel, 13 September): detail always uses the full screen, so
        // unlike `TvPageSurface` it keeps no `TvCatalogLayout.bottomSafeInset`
        // (DEC-087) under the rail. The rail's own bottom padding hangs off the
        // edge too, at the scale `TvBrowseRail` reads it with (SYS-3e).
        final railBottomPadding = TvBrowseRailLayout.railBottomPaddingForScale(detailScale);
        final initialForegroundBottom =
            (railHeight - railTopPadding - railBottomPadding) + (_tvDetailActionRailGap * detailScale);
        final initialRailHeight = railHeight;
        // DET2: on a small panel with a tall active hub (a person rail, full-
        // width extras cards), the reservation above can eat the whole
        // foreground and overflow `_buildTvDetailForeground`'s Column — the
        // metadata line, genres, the action row and the source line are drawn
        // unconditionally there, and the title never degrades to zero either
        // (see `_tvDetailMandatoryForegroundHeight`). Give space back by
        // dropping the rail's "next hub" peek hint (`showNextHubPeek` below):
        // it is decorative; the info band is not.
        //
        // Try clearing `_tvDetailIdealForegroundHeight` first — the mockup 37 A
        // target of title + two synopsis lines + action row — then
        // `_tvDetailMinimalForegroundHeight` (one line) before giving up on the
        // synopsis entirely at the bare `_tvDetailMandatoryForegroundHeight`
        // floor (DET2/H2, then the follow-up that added the minimal tier: a
        // single tall-but-not-adversarial hub, a full-width episode rail under
        // season chips with no extras involved, was landing straight on the
        // zero-line floor and losing the focused-episode-synopsis swap along
        // with it).
        ({double foregroundBottom, double railHeight, bool showNextHubPeek, bool fits}) reserveFor(
          double targetForegroundHeight,
        ) {
          var bottom = initialForegroundBottom;
          var rail = initialRailHeight;
          var peek = true;
          final maxBottom = (size.height - spotlightTop - targetForegroundHeight)
              .clamp(0.0, double.infinity)
              .toDouble();
          if (bottom > maxBottom && detailHubs.length > 1) {
            peek = false;
            final railHeightNoPeek = _estimateTvDetailRailHeight(
              size,
              detailHubs,
              showSeasonChips: showSeasonChips,
              includeNextHubPeek: false,
            );
            final peekGiveback = (rail - railHeightNoPeek).clamp(0.0, double.infinity).toDouble();
            rail -= peekGiveback;
            bottom -= peekGiveback;
          }
          return (foregroundBottom: bottom, railHeight: rail, showNextHubPeek: peek, fits: bottom <= maxBottom);
        }

        final idealForegroundHeight = _tvDetailIdealForegroundHeight(context, metadata, detailScale, foregroundWidth);
        var reservation = reserveFor(idealForegroundHeight);
        var railTallPosterScale = _tvDetailTallPosterScale;
        var railWidePosterScaleMultiplier = 1.0;
        // DET6: `reserveFor` above already gave back the next-hub peek, and
        // the ideal two-line synopsis still does
        // not fit. Before dropping to one line, try a smaller active rail at
        // each fraction in turn, recomputing the same reservation against it.
        if (!reservation.fits) {
          final maxBottomForIdeal = (size.height - spotlightTop - idealForegroundHeight)
              .clamp(0.0, double.infinity)
              .toDouble();
          for (final fraction in _tvDetailRailShrinkFractions) {
            final shrunkRailHeight = _estimateTvDetailRailHeight(
              size,
              detailHubs,
              showSeasonChips: showSeasonChips,
              includeNextHubPeek: false,
              tallPosterScale: _tvDetailTallPosterScale * fraction,
              widePosterScaleMultiplier: fraction,
            );
            final shrunkBottom =
                (shrunkRailHeight - railTopPadding - railBottomPadding) + (_tvDetailActionRailGap * detailScale);
            if (shrunkBottom <= maxBottomForIdeal) {
              railTallPosterScale = _tvDetailTallPosterScale * fraction;
              railWidePosterScaleMultiplier = fraction;
              reservation = (
                foregroundBottom: shrunkBottom,
                railHeight: shrunkRailHeight,
                showNextHubPeek: false,
                fits: true,
              );
              break;
            }
          }
        }
        if (!reservation.fits) {
          final minimalForegroundHeight = _tvDetailMinimalForegroundHeight(
            context,
            metadata,
            detailScale,
            foregroundWidth,
          );
          reservation = reserveFor(minimalForegroundHeight);
          if (!reservation.fits) {
            final mandatoryForegroundHeight = _tvDetailMandatoryForegroundHeight(
              context,
              metadata,
              detailScale,
              foregroundWidth,
            );
            reservation = reserveFor(mandatoryForegroundHeight);
          }
        }
        final foregroundBottom = reservation.foregroundBottom;
        railHeight = reservation.railHeight;
        final showNextHubPeek = reservation.showNextHubPeek;

        final revealContent = Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: spotlightLeft,
              right: size.width * 0.43,
              top: spotlightTop,
              bottom: foregroundBottom,
              child: _buildTvDetailForeground(context, metadata, hideSpoilers: hideSpoilers, scale: detailScale),
            ),
            // No back button here (PB-2 / BACK1). This branch only ever runs
            // on TV, where the remote cannot reach an `AppBarBackButton`,
            // which has no FocusNode, so the arrow was chrome that claimed to
            // be pressable and was not. Back is `_handleMediaDetailBackKey`
            // above, which routes Menu/Back to `_dismissTvDetail` for both the
            // nested and the pushed shape of this screen.
            if (detailHubs.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: -railBottomPadding,
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [
                    if (showSeasonChips) SizedBox(height: _tvDetailSeasonChipOverhang(detailScale)),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        TvBrowseRail(
                          key: _tvDetailRailKey,
                          hubs: detailHubs,
                          iconForHub: _getTvDetailHubIcon,
                          onFocusedHubItemChanged: _handleTvDetailFocusedRailItemChanged,
                          onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
                          onPlaybackReturned: (item) => unawaited(refreshAfterPlayback(playedItemId: item.id)),
                          onActiveHubChanged: _handleTvDetailHubChanged,
                          onActivateItem: _handleTvDetailRailItemActivated,
                          trailingForHub: _tvDetailTrailingState,
                          onRetryHub: _retryTvDetailHub,
                          onNavigateUp: () => _focusAboveTvDetailRail(metadata),
                          onBack: _popMediaDetailIfBackNotSuppressed,
                          tallPosterScale: railTallPosterScale,
                          widePosterScaleForHub: (hub) =>
                              _tvDetailWidePosterScaleForHub(hub) * railWidePosterScaleMultiplier,
                          initialHubId: _tvDetailInitialHubId(metadata),
                          initialItemId: _tvDetailInitialItemId(metadata),
                          episodePosterModeForHub: _tvDetailEpisodePosterModeForHub,
                          automationIdForHub: _tvDetailAutomationIdForHub,
                          showNextHubPeek: showNextHubPeek,
                        ),
                        // VIS2/37 C: the chips sit on the season rail's header
                        // line. The rail scrolls its active hub to the top, so
                        // once cast or extras is active that line belongs to
                        // another hub and the row steps aside.
                        if (showSeasonChips)
                          Positioned(
                            left: TvBrowseRailLayout.horizontalInsetForScale(detailScale),
                            right: 0,
                            top: _tvDetailSeasonChipRowTop(detailScale),
                            child: Visibility(
                              visible: _tvDetailSeasonHubActive,
                              maintainState: true,
                              child: _buildTvDetailSeasonChips(metadata, detailScale),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );

        final body = Focus(
          onKeyEvent: handleBack,
          child: Scaffold(
            body: Stack(
              children: [
                TvSpotlightBackground(
                  item: metadata,
                  client: _getArtworkMediaClient(context),
                  showInfo: false,
                  localArtworkPathResolver: widget.isOffline ? (path) => _offlineArtworkLocalPath(context, path) : null,
                ),
                _buildTvDetailRevealGate(revealContent, handleBack),
              ],
            ),
          ),
        );

        // INV-1: nested inside the shell this screen claims no second
        // shell-like layer, and `OverlaySheetHost` is named in that list. The
        // shell has one at its root, above the top bar; a second one here
        // would host this screen's sheets inside the content box, under the
        // bar and at the wrong size, and the shell's own
        // `onOverlaySheetOpenChanged` would never fire — so step 1 of the back
        // chain in hoofdstuk 7.5 would not know a sheet was open. Sheets are
        // found with `OverlaySheetHost.maybeOf`, which walks up, so dropping
        // this one hands them to the shell's rather than to nothing.
        //
        // Its `PopScope` goes with it for the reason
        // `FocusableDetailScreenMixin.buildDetailScaffold` documents: the route
        // it would guard is the shell's own.
        if (TvNestedRouteScope.of(context) != null) return body;

        final blockSystemBack = InputModeTracker.shouldBlockSystemBack(context);
        return OverlaySheetHost(
          // blockSystemBack keeps the route from double-popping on Android keyboard/
          // TV (the key handler owns dpad back); the host also closes an open sheet.
          canPop: !blockSystemBack,
          child: body,
        );
      },
    );
  }
}
