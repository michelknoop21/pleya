/// Zoeken on TV, in the catalog card language
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108), mockup 36 A, B and C).
///
/// ## What this replaces, and why both halves had to go
///
/// CAT11 came off hardware: the tiles on Zoeken are much bigger than on Alle
/// films and do not follow the card language. Two separate causes sat under
/// that on this page. Films, series and episodes were drawn as
/// `TvDiscoveryRail` — the wide 16:9 feed tile, which is the Home landing's
/// identity and not a result's. The four source-concrete sections hoofdstuk
/// 16.1 keeps (collections, playlists, people, everything unnamed) fell back to
/// the non-TV `FocusableMediaCard` list, a phone widget on a ten-foot panel.
/// Both now draw [TvCatalogCardRail] of catalog cards, which is the same card
/// at the same width as Alle films.
///
/// ## SEARCH1
///
/// A `TvDiscoveryRail` caption follows the focus: on the Home feed the line
/// above a row tells you what you are standing on. On a result page that is
/// wrong, and the previous build patched it with `alwaysDescribesCurrent` — one
/// rail with an exception to the rail contract. Mockup 36 B settles it the
/// other way: "Films 4" is a *heading*, drawn by [TvSectionHeader] above a band
/// that owns no caption at all, so there is nothing left to make an exception
/// for.
///
/// ## What this view does not own
///
/// The search field. It is built by `SearchScreen`, which owns the controller,
/// the native text-entry session and the query, and is handed in whole — the
/// same arrangement Ontdekken uses. This view places it and states the result
/// count beside it (36 B's "14 resultaten", 36 C's "geen resultaten").
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_catalog_card_grid.dart';
import '../../widgets/tv/tv_catalog_card_rail.dart';
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_section_header.dart';
import '../../widgets/tv/tv_view_all_action.dart';
import '../../widgets/tv/tv_unified_layout.dart';

/// What this page is called in `tv.catalog.*` automation ids (SEARCH1).
const String tvSearchSurface = 'search';

/// One band of results under one heading.
///
/// The view is deliberately blind to what a card *is*: hoofdstuk 16.1 gives
/// this page two kinds at once — unified groups for films, series and episodes,
/// concrete items for the rest — and a view that knew about both would have to
/// carry the projection's shape as well as its own.
class TvSearchSection {
  const TvSearchSection({
    required this.id,
    required this.title,
    required this.itemIds,
    required this.cardBuilder,
    this.actionLabel,
    this.onAction,
    this.actionFocusNode,
  });

  /// Stable across queries, and what the automation instance is named after:
  /// `movies`, `shows`, `episodes`, `collections`, `playlists`, `people`,
  /// `other`, and `recent` for the row at rest.
  final String id;

  final String title;

  /// One stable id per card, in display order.
  final List<String> itemIds;

  final Widget Function(BuildContext context, TvCatalogGridCell cell) cardBuilder;

  /// One action beside the heading, or none.
  ///
  /// Mockup 36 A draws no button next to "Recent gezocht", and the row would
  /// then be the one list on TV a viewer cannot clear — the query chips it
  /// replaces always had a Wissen. Keeping the capability is worth the extra
  /// control; dropping it silently is not the kind of thing a card-language
  /// round is allowed to do.
  final String? actionLabel;
  final VoidCallback? onAction;
  final FocusNode? actionFocusNode;

  bool get hasAction => actionLabel != null && onAction != null;

  int get count => itemIds.length;
}

class TvSearchView extends StatefulWidget {
  const TvSearchView({
    super.key,
    required this.searchField,
    required this.sections,
    required this.hasQuery,
    required this.isSearching,
    required this.onExitLeft,
    required this.onExitTop,
    this.totalResultCount,
    this.error,
    this.onRetry,
    this.onSearchOnRequests,
    this.serverCount = 0,
  });

  /// The pill (and, where the native path is broken, the inline keyboard) as
  /// `SearchScreen` builds it.
  final Widget searchField;

  /// The bands, in hoofdstuk 16.1's order. Empty with [hasQuery] false means
  /// nothing has been opened from a search yet; empty with it true means the
  /// query matched nothing.
  final List<TvSearchSection> sections;

  final bool hasQuery;
  final bool isSearching;

  /// Every result across every section, for the line beside the pill. Null
  /// leaves it off, which is the state at rest.
  final int? totalResultCount;

  final String? error;
  final VoidCallback? onRetry;

  /// Mockup 36 C's way out: hand the query to Seerr. Null when no Seerr is
  /// configured, and then the empty state falls back to "try another term" —
  /// offering a request flow that does not exist would be worse than offering
  /// nothing.
  final VoidCallback? onSearchOnRequests;

  /// How many servers were searched, for 36 C's body line. It says "none of
  /// your three media servers", and the number is the part that makes it a
  /// statement about *this* setup rather than a shrug.
  final int serverCount;

  /// LEFT off the first card of any band.
  final VoidCallback onExitLeft;

  /// UP out of the first band: the search field above it.
  final VoidCallback onExitTop;

  @override
  State<TvSearchView> createState() => TvSearchViewState();
}

class TvSearchViewState extends State<TvSearchView> {
  final _railKeys = <String, GlobalKey<TvCatalogCardRailState>>{};
  final _stateActionFocus = FocusNode(debugLabel: 'TvSearchStateAction');

  @override
  void dispose() {
    _stateActionFocus.dispose();
    super.dispose();
  }

  GlobalKey<TvCatalogCardRailState> _railKeyFor(String id) =>
      _railKeys.putIfAbsent(id, () => GlobalKey<TvCatalogCardRailState>(debugLabel: 'TvSearchBand($id)'));

  /// DOWN off the search field, and the target every "focus the first result"
  /// call site on this screen already had.
  ///
  /// Returns false when the page has nothing to stand on — which is a real
  /// state here and not a failure: while a query is running the body is a
  /// skeleton, and the caller keeps the focus on the field rather than dropping
  /// it into a page that has nowhere to put it.
  bool focusFirstResult() {
    for (final section in widget.sections) {
      if (_railKeyFor(section.id).currentState?.focusRail() ?? false) return true;
    }
    // `context != null` is the attachment test, and the reason it is here
    // rather than a bare `canRequestFocus`: that property is true on a node
    // that is not in the tree at all, so it would answer yes for a page whose
    // body is a skeleton, and this method's answer is what decides whether the
    // caller lets go of the search field.
    if (_stateActionFocus.context != null && _stateActionFocus.canRequestFocus) {
      _stateActionFocus.requestFocus();
      return true;
    }
    return false;
  }

  /// Arriving at a band from something that is not another band — a heading
  /// action above it — where the band's own memory is the right answer.
  void _restoreBand(int index) {
    if (index < 0 || index >= widget.sections.length) return;
    _railKeyFor(widget.sections[index].id).currentState?.focusRail();
  }

  /// Moves between bands, keeping the column (LAND4).
  ///
  /// The band's own focus memory is what makes coming back from a detail page
  /// land where you left it; it must not decide a vertical step. Standing on
  /// the third result of Films, the third result of Series is where DOWN goes,
  /// however far right Series was parked.
  void _focusBand(int index, int column) {
    if (index < 0 || index >= widget.sections.length) return;
    _railKeyFor(widget.sections[index].id).currentState?.focusColumn(column);
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.searchField,
        Expanded(child: _buildBody(scale)),
      ],
    );
  }

  /// The count beside the pill, or null when there is nothing to count yet.
  ///
  /// Public and pure so `SearchScreen` can put it *inside* its own pill without
  /// this view having to reach into the field it was handed.
  static String? resultCountLabel({required bool hasQuery, required bool isSearching, required int? total}) {
    if (!hasQuery || isSearching || total == null) return null;
    if (total == 0) return t.search.noResultsShort;
    return total == 1 ? t.search.oneResult : t.search.resultCount(count: total);
  }

  Widget _buildBody(double scale) {
    if (widget.isSearching) {
      return TvCatalogSkeletonGrid(key: tvCatalogSkeletonKey);
    }

    final error = widget.error;
    if (error != null) {
      return _state(
        'error',
        TvCatalogEmptyState(
          icon: Symbols.cloud_off_rounded,
          title: t.search.errorTitle,
          body: error,
          actionLabel: widget.onRetry == null ? null : t.common.retry,
          onAction: widget.onRetry,
          onActionFocusNode: _stateActionFocus,
        ),
      );
    }

    if (widget.sections.isEmpty) {
      // Mockup 36 C. A query that matched nothing is a different situation
      // from a page nobody has searched on yet, and only the first one has a
      // way out worth offering.
      if (widget.hasQuery) {
        // Requests first when there is a Seerr, Opnieuw when there is not, and
        // no button at all when there is neither — `TvCatalogEmptyState` draws
        // only the button, so a label without a callback would be a claim the
        // page cannot honour (CAT14).
        final onRequests = widget.onSearchOnRequests;
        final action = onRequests ?? widget.onRetry;
        return _state(
          'no_results',
          TvCatalogEmptyState(
            icon: Symbols.search_off_rounded,
            title: t.search.nothingOnServersTitle,
            body: widget.serverCount == 1
                ? t.search.nothingOnOneServerBody
                : t.search.nothingOnServersBody(count: widget.serverCount),
            actionLabel: action == null ? null : (onRequests != null ? t.search.searchOnRequests : t.common.retry),
            onAction: action,
            onActionFocusNode: _stateActionFocus,
          ),
        );
      }
      return _state(
        'idle',
        TvCatalogEmptyState(
          icon: Symbols.search_rounded,
          title: t.search.searchYourMedia,
          body: t.search.enterTitleActorOrKeyword,
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final geometry = TvCatalogGrid.forWidth(width, scale: scale);
    final headingInset = geometry.inset + TvCatalogLayout.cardContentInset(scale);

    return SingleChildScrollView(
      // Not the default clip: a focused card grows past its band's box, and the
      // page must not shear the ring off at the viewport edge.
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(bottom: geometry.bottomSafeMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.sections.length; i++) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(headingInset, TvCatalogLayout.headerContentGap * scale, headingInset, 0),
              // The count lives in the heading, not in the band: that is what
              // closes SEARCH1. It states how many results the section has and
              // does not move when the focus does.
              child: Row(
                children: [
                  Expanded(
                    child: TvSectionHeader(title: widget.sections[i].title, count: widget.sections[i].count),
                  ),
                  if (widget.sections[i].hasAction)
                    TvViewAllAction(
                      label: widget.sections[i].actionLabel!,
                      semanticLabel: widget.sections[i].actionLabel!,
                      focusNode: widget.sections[i].actionFocusNode,
                      onSelect: widget.sections[i].onAction!,
                      onNavigateUp: i == 0 ? widget.onExitTop : () => _restoreBand(i - 1),
                      onNavigateDown: () => _restoreBand(i),
                    ),
                ],
              ),
            ),
            _buildBand(scale, i),
          ],
        ],
      ),
    );
  }

  Widget _buildBand(double scale, int index) {
    final section = widget.sections[index];
    return AutomationNode(
      id: AutomationIds.tvCatalogGrid,
      instance: '$tvSearchSurface.${section.id}',
      role: 'rail',
      child: TvCatalogCardRail(
        key: _railKeyFor(section.id),
        itemIds: section.itemIds,
        cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
        // Search returns what it returns: there is no second page behind a
        // result set, so nothing here ever asks for one.
        hasMore: false,
        isLoadingMore: false,
        onLoadMore: () {},
        nodeDebugLabel: 'TvSearchCard(${section.id})',
        onExitUp: section.hasAction
            ? (_) => section.actionFocusNode?.requestFocus()
            : (index == 0 ? (_) => widget.onExitTop() : (column) => _focusBand(index - 1, column)),
        onExitDown: index == widget.sections.length - 1 ? null : (column) => _focusBand(index + 1, column),
        onExitLeft: widget.onExitLeft,
        itemBuilder: (context, cell) => AutomationNode(
          id: AutomationIds.tvCatalogGridItem,
          instance: '$tvSearchSurface.${section.id}.${cell.index}',
          role: 'grid.item',
          focusNode: cell.focusNode,
          child: section.cardBuilder(context, cell),
        ),
      ),
    );
  }

  Widget _state(String which, Widget child) => AutomationNode(
    id: AutomationIds.tvCatalogState,
    instance: '$tvSearchSurface.$which',
    role: 'region',
    focusNode: _stateActionFocus,
    child: child,
  );
}
