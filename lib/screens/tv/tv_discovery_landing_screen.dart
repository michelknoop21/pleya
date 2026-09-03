/// The shared implementation behind `TvMoviesLandingScreen` and
/// `TvSeriesLandingScreen` (hoofdstuk 10.2a of docs/tvos-unified-experience.md,
/// [DEC-064]): the Films/Series *landing*, one level above the fase-5 complete
/// catalog those two screens already are.
///
/// A single implementation for the same reason `tv_unified_catalog_screen.dart`
/// is one screen for both kinds: the two landings differ in which
/// [UnifiedMediaHub]s the projection provider hands them and what the page
/// heading says. Everything else — layout, restoration, activation, the
/// View All row — is contract-identical, and two copies would drift on their
/// first bug fix.
///
/// The composition itself is not new: it is
/// `test/goldens/tv_discovery_golden_test.dart`'s own `_landing()` helper,
/// lifted here unchanged in shape (hoofdstuk 27 fase 6: "gebruik de bestaande
/// golden composition als basis"). What is new is that the rows are real —
/// `TvDiscoveryLandingProvider`'s projection of whatever `DiscoverProvider`
/// fetched — instead of a fixture, and that Select runs the real fase-4
/// activation path instead of a no-op.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../mixins/refreshable.dart';
import '../../navigation/main_screen_scope.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/tv_discovery_landing_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_discovery_rail.dart';
import '../../widgets/tv/tv_discovery_safe_area.dart';
import '../../widgets/tv/tv_panel_primitives.dart';
import '../../widgets/tv/tv_rail_stack.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_view_all_action.dart';
import 'tv_discovery_activation_mixin.dart';

class TvDiscoveryLandingScreen extends StatefulWidget {
  const TvDiscoveryLandingScreen({
    super.key,
    required this.title,
    required this.allTitle,
    required this.viewAllSemanticLabel,
    required this.railsOf,
    required this.buildAllScreen,
    this.onManageServers,
    this.onOpenAll,
  });

  final String title;

  /// "Alle films" / "Alle series" — the View All row's left-hand label.
  final String allTitle;

  final String viewAllSemanticLabel;

  /// Reads this landing's own rows off the shared projection provider —
  /// `movieRails` or `seriesRails` — so this screen never decides which kind
  /// it is browsing beyond what its caller already told it.
  final List<UnifiedMediaHub> Function(TvDiscoveryLandingProvider) railsOf;

  /// Builds the fase-5 complete catalog this landing's View All pushes to.
  final Widget Function() buildAllScreen;

  final VoidCallback? onManageServers;

  /// Opens the complete catalog inside the fase-7 shell, so the top navigation
  /// stays on screen — hoofdstuk 33's shared shell is binding on all eight
  /// references, and 33.5 draws "Alle films" with the bar above it and Films
  /// still lit.
  ///
  /// Null falls back to a plain push on this landing's own navigator, which is
  /// what a standalone mount does (a golden, a focus test). The fallback is
  /// kept rather than made required so this screen stays mountable on its own;
  /// production always passes the callback.
  final VoidCallback? onOpenAll;

  @override
  State<TvDiscoveryLandingScreen> createState() => _TvDiscoveryLandingScreenState();
}

class _TvDiscoveryLandingScreenState extends State<TvDiscoveryLandingScreen>
    with TvDiscoveryActivationMixin
    implements FocusableTab {
  final _scrollController = ScrollController();
  final _viewAllFocus = FocusNode(debugLabel: 'TvDiscoveryViewAll');

  // Hoofdstuk 7.6/35 restoration: which tile a rail last showed, kept across
  // a re-projection (a fresh `List<UnifiedMediaHub>` on every
  // `DiscoverProvider` change) and across a detail push+pop — the rail's own
  // `FocusNode`s already survive that (they live in `TvDiscoveryRailState`,
  // which this screen never rebuilds away), so this map only has to survive
  // the case a rail's `FocusNode`s were never built at all yet, e.g. the very
  // first frame after a re-projection replaced a scrolled-away tile's node.
  final _focusedGroupIdByHubId = <String, String>{};

  // Who owns UP and DOWN between the rails (LAND4). Keyed by hub id, for the
  // same reason the rails themselves are: a re-projection reorders rows, and a
  // key held by index would hand DOWN out of the header to whichever rail
  // happened to land first.
  final _rails = TvRailStack();

  late DiscoverProvider _discover;

  @override
  void initState() {
    super.initState();
    _discover = context.read<DiscoverProvider>();
    // Same unconditional, coalescing call `DiscoverScreen.initState` makes —
    // a landing reached before Home was ever opened must not sit on an empty
    // projection forever.
    unawaited(_discover.load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _viewAllFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final landing = context.watch<TvDiscoveryLandingProvider>();
    final discover = context.watch<DiscoverProvider>();
    final rails = widget.railsOf(landing);
    // In draw order, so "the rail below this one" follows the page and not the
    // order the keys were first created in.
    _rails.layOut(rails.map((rail) => rail.hubId));

    if (rails.isEmpty) {
      return _buildEmptyOrLoading(discover);
    }

    return Builder(
      builder: (context) {
        final scale = TvLayoutConstants.scaleOf(context);
        // Hoofdstuk 33.3: the peeking poster tops at the bottom edge fade into
        // the page rather than being cut off flat. `dstIn` over the whole list
        // rather than a gradient box on top of it, because the thing that has
        // to disappear is artwork, and a scrim painted over it would have to
        // match the page colour exactly — which it cannot, since the page has
        // its own vertical lift.
        final safeArea = TvDiscoverySafeArea.maybe(context);
        final page = ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: const [Color(0x00000000), Color(0xFF000000)],
            stops: [0, TvDiscoveryLayout.pageBottomFade * scale / bounds.height],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.only(
              top: TvCatalogLayout.topSafeInset * scale,
              // The bottom edge is the one that carries the last readable line
              // and, once the viewer is on the final rail, its focus ring — so
              // it pays the wider band (P12, see
              // [TvCatalogLayout.bottomSafeInset]).
              bottom: TvCatalogLayout.bottomSafeInset * scale,
            ),
            children: [
              // DEC-068: the catalog action lives beside the page title, and is
              // the landing's only route into the complete catalog. The row is
              // baseline-aligned rather than centred — the two are type of very
              // different sizes, and centring them made the smaller one look
              // like it had floated up off the line.
              Padding(
                padding: EdgeInsets.only(
                  // The action carries its own focus-ring gap, so its side of
                  // the page inset pays that back to keep both ends of the band
                  // on the same margin as the rails below.
                  left: TvDiscoveryLayout.pageInset * scale,
                  right: (TvDiscoveryLayout.pageInset - TvDiscoveryLayout.viewAllFocusRingGap) * scale,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).extension<MonoTokens>()!.text,
                          fontSize: TvDiscoveryLayout.pageTitleFontSize * scale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    SizedBox(width: TvDiscoveryLayout.pageTitleActionGap * scale),
                    Flexible(
                      child: TvViewAllAction(
                        label: widget.allTitle,
                        focusNode: _viewAllFocus,
                        onSelect: _openAllScreen,
                        semanticLabel: widget.viewAllSemanticLabel,
                        // DOWN out of the header lands on the first rail's
                        // current tile — the short path the whole change exists
                        // for. UP goes to the top navigation, which fase 7 put
                        // above this header (hoofdstuk 7.4).
                        onNavigateDown: _focusFirstRail,
                        onNavigateUp: _focusTopNavigation,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: TvDiscoveryLayout.titleRailGap * scale),
              for (var i = 0; i < rails.length; i++) ...[
                if (i > 0) SizedBox(height: TvDiscoveryLayout.sectionGap * scale),
                SizedBox(
                  height: TvDiscoveryLayout.railSectionHeight(scale),
                  child: TvDiscoveryRail(
                    // Keyed on the stable hub id (hoofdstuk 17.5), not an index or
                    // the title: a re-projection reorders rows without losing
                    // this rail's own `TvDiscoveryRailState` — its `FocusNode`s,
                    // its scroll position — for a hub that is still there.
                    key: _rails.keyFor(rails[i].hubId),
                    title: rails[i].title,
                    groups: rails[i].groups,
                    automationRailIndex: i,
                    isPartial: rails[i].isPartial,
                    initialFocusedGroupId: _focusedGroupIdByHubId[rails[i].hubId],
                    onFocusedGroupChanged: (groupId) => _focusedGroupIdByHubId[rails[i].hubId] = groupId,
                    clientFor: (serverId) =>
                        context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId)),
                    onActivate: (group) => _activate(group),
                    onContextMenu: openDiscoveryContextMenu,
                    // Rail to rail, at the column the step leaves from
                    // (LAND4). UP that runs out of rails returns to the header
                    // action, so the two are a pair rather than a one-way trip;
                    // DOWN off the last rail has nothing below it and is left
                    // to Flutter, which correctly does nothing.
                    onNavigateUp: _rails.up(i, whenExhausted: _focusViewAll),
                    onNavigateDown: _rails.down(i),
                  ),
                ),
              ],
            ],
          ),
        );
        // The safe-area probe is measured, never drawn — see
        // [TvDiscoverySafeArea]. `maybe` returns null in an ordinary build, so
        // the Stack is not built either.
        if (safeArea == null) return page;
        return Stack(children: [page, safeArea]);
      },
    );
  }

  Future<void> _activate(UnifiedMediaGroup group) =>
      activateDiscoveryGroup(group, onManageServers: widget.onManageServers);

  /// DOWN out of the header action, into the first rail's current tile.
  ///
  /// `focusCurrent` rather than "the first tile": a rail that the viewer has
  /// already walked keeps its place, so going up to the header and back down
  /// returns to the title they were on rather than resetting them to the start
  /// of the row.
  void _focusFirstRail() => _rails.focusFirstCurrent();

  /// UP out of the first rail, back to the header action.
  void _focusViewAll() {
    if (_viewAllFocus.canRequestFocus) _viewAllFocus.requestFocus();
  }

  /// UP out of the header, into the root navigation (hoofdstuk 7.4: "Up vanaf
  /// header gaat naar topnav").
  ///
  /// Through [MainScreenFocusScope] rather than a callback of its own: every
  /// content screen already leaves content this way, and on the TV shell that
  /// target is the top navigation. A screen should not have to know which root
  /// it is mounted under.
  void _focusTopNavigation() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

  /// DOWN out of the top navigation lands on the page header, per hoofdstuk
  /// 7.1's "Top navigation → page header → first content row". The header, not
  /// the first card: it is the one control on this page that changes where you
  /// are, and starting under it would make it reachable only by going back up.
  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    if (_viewAllFocus.canRequestFocus) {
      _viewAllFocus.requestFocus();
      return;
    }
    // No header yet (still loading, or an empty projection): the rails are the
    // only thing to land on, and landing on nothing would strand the remote.
    _focusFirstRail();
  }

  /// Pushes the fase-5 complete catalog (DEC-064: "Alles bekijken is een
  /// eerste-klas route"). A plain push on this landing's own Navigator — the
  /// nested one `ProfileNavigationScope` owns — so popping it returns focus
  /// and scroll to exactly this screen, still mounted underneath.
  void _openAllScreen() {
    final inShell = widget.onOpenAll;
    if (inShell != null) {
      inShell();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => widget.buildAllScreen()));
  }

  Widget _buildEmptyOrLoading(DiscoverProvider discover) {
    if (discover.areHubsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (discover.errorMessage != null) {
      return _LandingMessage(
        title: t.unifiedCatalog.states.errorTitle,
        body: t.unifiedCatalog.states.errorBody,
        actionLabel: t.common.retry,
        onAction: () => unawaited(_discover.load()),
      );
    }
    return _LandingMessage(title: t.unifiedCatalog.discovery.emptyTitle, body: t.unifiedCatalog.discovery.emptyBody);
  }
}

class _LandingMessage extends StatelessWidget {
  const _LandingMessage({required this.title, required this.body, this.actionLabel, this.onAction});

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: tk.text,
              ),
            ),
            SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale * 2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
              TvPanelButton(scale: scale, label: actionLabel!, onPressed: onAction!, primary: true, autofocus: true),
            ],
          ],
        ),
      ),
    );
  }
}
