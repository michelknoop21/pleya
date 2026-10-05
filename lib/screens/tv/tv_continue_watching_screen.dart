/// The full Verder kijken overview on TV (mockup 38 D, DEC-144 fase 2): the
/// page title with the real count, then the four fixed sections as stacked
/// bands, each a `TvSectionHeader` with its count over a `TvCatalogCardRail`
/// of unified cards. D-pad UP and DOWN move between bands keeping the column,
/// exactly as `TvSearchView` does; LEFT off the first column goes to the
/// top navigation; Menu pops the route.
///
/// Everything here is read from `TvHomeProjectionProvider.continueWatchingAll`,
/// the same projection the Home row is a prefix of, so a title that is one
/// card on Home is one card here.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../navigation/tv/tv_navigation_coordinator.dart';
import '../../providers/continue_watching_hidden_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/continue_watching_sections.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/continue_watching_hidden_items.dart';
import '../../widgets/tv/tv_catalog_card_rail.dart';
import '../../widgets/tv/tv_catalog_header_bar.dart';
import '../../widgets/tv/tv_catalog_selection_tags.dart';
import '../../widgets/tv/tv_section_header.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_continue_watching_card.dart';
import '../../widgets/tv/tv_view_all_action.dart';
import 'tv_discovery_activation_mixin.dart';

const String tvContinueWatchingSurface = 'continueWatchingAll';

class TvContinueWatchingScreen extends StatefulWidget {
  const TvContinueWatchingScreen({super.key});

  @override
  State<TvContinueWatchingScreen> createState() => TvContinueWatchingScreenState();
}

class TvContinueWatchingScreenState extends State<TvContinueWatchingScreen>
    with TvDiscoveryActivationMixin<TvContinueWatchingScreen>
    implements TvFocusRestoreHost {
  final _railKeys = <ContinueWatchingSection, GlobalKey<TvCatalogCardRailState>>{};
  List<(ContinueWatchingSection, List<UnifiedMediaGroup>)> _sections = const [];
  final _hiddenFocus = FocusNode(debugLabel: 'TvContinueWatchingHidden');
  bool _hasHiddenEntry = false;

  @override
  void dispose() {
    _hiddenFocus.dispose();
    super.dispose();
  }

  GlobalKey<TvCatalogCardRailState> _railKeyFor(ContinueWatchingSection s) =>
      _railKeys.putIfAbsent(s, () => GlobalKey<TvCatalogCardRailState>(debugLabel: 'TvContinueWatchingBand($s)'));

  void _focusBand(int index, int column) {
    if (index < 0 || index >= _sections.length) return;
    _railKeyFor(_sections[index].$1).currentState?.focusColumn(column);
  }

  /// Back from a detail page or the player lands on the band that holds the
  /// card; the band's own focus memory puts the remote on the card itself.
  @override
  bool restoreTvFocus(TvFocusRestoreTarget target) {
    for (final (section, groups) in _sections) {
      if (groups.any((g) => g.groupId == target.itemId)) {
        return _railKeyFor(section).currentState?.focusRail() ?? false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final projection = context.watch<TvHomeProjectionProvider>();
    final groups = projection.continueWatchingAll?.groups ?? const <UnifiedMediaGroup>[];
    _sections = continueWatchingSections(groups, itemOf: (g) => g.representativeSource.item);

    final hiddenCount = context.watch<ContinueWatchingHiddenProvider?>()?.count ?? 0;
    _hasHiddenEntry = hiddenCount > 0;
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final geometry = TvCatalogGrid.forWidth(width, scale: scale);
    final headingInset = geometry.inset + TvCatalogLayout.cardContentInset(scale);

    return AutomationNode(
      id: AutomationIds.tvContinueWatchingAll,
      role: 'screen',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The same page chrome as the watchlist and the catalog: title left,
          // the real count as a muted tag beside it.
          TvCatalogHeaderBar(
            title: t.discover.continueWatching,
            tags: [TvCatalogSelectionTag('${groups.length}', muted: true)],
          ),
          Expanded(
            child: groups.isEmpty && hiddenCount == 0
                ? Center(
                    child: Text(t.discover.noContentAvailable, style: TextStyle(color: tk.textMuted)),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.only(
                      top: TvCatalogLayout.cardFocusRingGap * scale,
                      bottom: geometry.bottomSafeMargin,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < _sections.length; i++) ...[
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              headingInset,
                              TvCatalogLayout.headerContentGap * scale,
                              headingInset,
                              0,
                            ),
                            child: TvSectionHeader(
                              title: continueWatchingSectionTitle(_sections[i].$1),
                              count: _sections[i].$2.length,
                            ),
                          ),
                          _band(scale, i),
                        ],
                        // Mockup 38 D: the way back for a title hidden on this
                        // device, DOWN off the last band.
                        if (hiddenCount > 0)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              headingInset,
                              TvCatalogLayout.headerContentGap * scale,
                              headingInset,
                              0,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TvViewAllAction(
                                label: continueWatchingHiddenLabel(hiddenCount),
                                semanticLabel: continueWatchingHiddenLabel(hiddenCount),
                                focusNode: _hiddenFocus,
                                onSelect: _openHiddenItems,
                                onNavigateUp: _sections.isEmpty
                                    ? null
                                    : () => _railKeyFor(_sections.last.$1).currentState?.focusRail(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Restoring the last hidden title removes the very action the panel would
  /// hand the focus back to, so the remote goes to the last band instead.
  Future<void> _openHiddenItems() async {
    await showContinueWatchingHiddenItems(context);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasHiddenEntry || _sections.isEmpty) return;
      _railKeyFor(_sections.last.$1).currentState?.focusRail();
    });
  }

  MediaServerClient? _clientFor(String serverId) =>
      context.read<MultiServerProvider>().serverManager.getClient(ServerId(serverId));

  Widget _band(double scale, int index) {
    final (section, groups) = _sections[index];
    final dim = section == ContinueWatchingSection.stale;
    return AutomationNode(
      id: AutomationIds.tvCatalogGrid,
      instance: '$tvContinueWatchingSurface.${section.name}',
      role: 'rail',
      child: TvCatalogCardRail(
        key: _railKeyFor(section),
        itemIds: [for (final g in groups) g.groupId],
        cardHeight: (cardWidth) => TvCatalogLayout.wideCardHeight(cardWidth, scale),
        cardWidthFactor: 1.3,
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
        nodeDebugLabel: 'TvContinueWatchingCard(${section.name})',
        onExitUp: index == 0 ? null : (column) => _focusBand(index - 1, column),
        onExitDown: index == _sections.length - 1
            ? (_hasHiddenEntry ? (_) => _hiddenFocus.requestFocus() : null)
            : (column) => _focusBand(index + 1, column),
        itemBuilder: (context, cell) {
          final group = groups[cell.index];
          return AutomationNode(
            id: AutomationIds.tvCatalogGridItem,
            instance: '$tvContinueWatchingSurface.${section.name}.${cell.index}',
            role: 'grid.item',
            focusNode: cell.focusNode,
            child: Opacity(
              // Eerder begonnen is less prominent, not unreadable: the still
              // dims, the text does not (Michel, 4 oktober 2026).
              opacity: dim ? 0.85 : 1,
              child: TvContinueWatchingCard(
                group: group,
                width: cell.width,
                clientFor: _clientFor,
                focusNode: cell.focusNode,
                onSelect: () => activateDiscoveryGroup(group, containerId: tvContinueWatchingSurface),
                onContextMenu: () => openDiscoveryContextMenu(group, isInContinueWatching: true),
                onFocusChange: cell.onFocusChange,
                onNavigateUp: cell.onNavigateUp,
                onNavigateDown: cell.onNavigateDown,
                onNavigateLeft: cell.onNavigateLeft,
                onNavigateRight: cell.onNavigateRight,
              ),
            ),
          );
        },
      ),
    );
  }
}
