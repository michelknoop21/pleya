/// Ontdekken op Aanvragen, on TV, in the catalog language
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108), mockup 35 A and 35 B).
///
/// ## What changed, and what CAT11 actually reported
///
/// The page drew its posters through `buildSeerrGridSliver` and
/// `seerrRowMetricsOf`, both of which size from `SettingsService.libraryDensity`
/// — a preference that means something on a desktop window someone resizes and
/// nothing on a fixed 10-foot panel. That is why an item here was visibly a
/// different size from the same item on Alle films. Every card on this page now
/// comes off [TvCatalogGrid], like every other TV surface.
///
/// ## Two modes, one page
///
/// * **Rows** (35 A) is the resting state: one [TvCatalogCardRail] per shelf.
/// * **Grid** (35 B) is one shelf expanded, a genre picked, or a search run.
///   On TV "Alles tonen" does not push `SeerrRowGridScreen`; it switches this
///   page into its grid mode, which is what keeps the rail's own state — the
///   type and the genre the viewer picked — standing beside the expanded row
///   instead of being ferried into a second screen and back.
///
/// ## The rail carries Soort, Genre and Streamingdienst, and not Status
///
/// DEC-108 (2) names Soort, Genre and Status as this domain's filters, and
/// Status is built where the server can answer it: on Alle aanvragen, where
/// `/request` filters by it and `/request/count` reports how many are behind
/// each answer. Seerr's *discover* endpoints take no status parameter at all
/// (`discoverMovies`/`discoverTv` take a genre and a watch provider), so a
/// Status row here could only sift the page that happens to be loaded — an
/// answer that changes as the viewer scrolls, which is worse than not offering
/// it. Streamingdienst takes the third slot because it is a real discover
/// parameter and the page already offered it, as a strip of chips that the
/// catalog language has no room for.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_media.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_catalog_card_grid.dart';
import '../../widgets/tv/tv_catalog_card_rail.dart';
import '../../widgets/tv/tv_catalog_empty_state.dart';
import '../../widgets/tv/tv_catalog_filter_rail.dart';
import '../../widgets/tv/tv_catalog_header_bar.dart';
import '../../widgets/tv/tv_catalog_rail_scaffold.dart';
import '../../widgets/tv/tv_catalog_selection_tags.dart';
import '../../widgets/tv/tv_catalog_skeleton_grid.dart';
import '../../widgets/tv/tv_section_header.dart';
import '../../widgets/tv/tv_seerr_card.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import '../../widgets/tv/tv_view_all_action.dart';
import '../seerr/seerr_discover_filter_bar.dart';

/// What this page is called in `tv.catalog.*` automation ids (REQ1).
const String tvSeerrDiscoverSurface = 'discover';

/// Which of the rail's questions is open, if any.
enum TvSeerrDiscoverSubview { kind, genre, provider }

/// One shelf, as this view needs it: a title, the titles on it, and whether
/// there are more pages behind them.
class TvSeerrShelf {
  const TvSeerrShelf({
    required this.id,
    required this.title,
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onShowAll,
  });

  /// Stable across a rebuild, so the rail's focus nodes survive a page landing.
  final String id;
  final String title;
  final List<SeerrMedia> items;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  /// Opens this shelf as a full grid (35 B).
  final VoidCallback onShowAll;
}

/// One grid: a shelf expanded, a genre, or a search result.
class TvSeerrGridPage {
  const TvSeerrGridPage({
    required this.title,
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final String title;
  final List<SeerrMedia> items;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
}

/// One streaming service the region reports.
typedef TvSeerrProviderOption = ({int id, String name});

class TvSeerrDiscoverView extends StatefulWidget {
  const TvSeerrDiscoverView({
    super.key,
    required this.shelves,
    required this.type,
    required this.onTypeSelected,
    required this.genres,
    required this.genreId,
    required this.onGenreSelected,
    required this.isLoading,
    required this.onReload,
    required this.onActivate,
    required this.searchField,
    this.onLeaveGrid,
    this.grid,
    this.providers = const [],
    this.providerId,
    this.onProviderSelected,
    this.error,
    this.onExitTop,
  });

  /// The shelves the current type shows, already filtered by the screen.
  /// Ignored while [grid] is set.
  final List<TvSeerrShelf> shelves;

  /// Set to put the page into its grid mode (35 B).
  final TvSeerrGridPage? grid;

  final SeerrDiscoverType type;
  final ValueChanged<SeerrDiscoverType> onTypeSelected;

  /// The genres of the active type. Empty drops the Genre row, the same way the
  /// old chip row hid itself: a question with no answers is a focus stop that
  /// costs a press to discover.
  final List<SeerrDiscoverGenre> genres;
  final int? genreId;
  final ValueChanged<int?> onGenreSelected;

  final List<TvSeerrProviderOption> providers;
  final int? providerId;
  final ValueChanged<int?>? onProviderSelected;

  final bool isLoading;
  final VoidCallback onReload;
  final String? error;

  /// Select on a card — the Seerr detail page, where a title is actually
  /// requested.
  final ValueChanged<SeerrMedia> onActivate;

  /// The search pill and the inbox button, built by the screen.
  ///
  /// Mockup 35 A draws neither, and they are kept anyway: on TV this is the only
  /// way into the Seerr search and into Alle aanvragen, and a screenshot is not
  /// a functional specification (the manifest says as much). Removing the only
  /// route to two screens is not something an image can authorise, and the
  /// alternative — inventing a way to reach them — would be a component family
  /// the approved set does not contain either. It is recorded as a deviation
  /// rather than resolved silently.
  final Widget searchField;

  final VoidCallback? onExitTop;

  /// Menu while [grid] is set: back to the shelves.
  ///
  /// Only bound in grid mode. On the shelves themselves Menu belongs to the
  /// route, which is what leaves the page — a card that swallowed it there would
  /// make Aanvragen the one Mijn Pleya section you cannot back out of.
  final VoidCallback? onLeaveGrid;

  @override
  State<TvSeerrDiscoverView> createState() => TvSeerrDiscoverViewState();
}

class TvSeerrDiscoverViewState extends State<TvSeerrDiscoverView> {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();
  final _railKeys = <String, GlobalKey<TvCatalogCardRailState>>{};
  final _kindFocus = FocusNode(debugLabel: 'TvSeerrDiscoverRailKind');
  final _genreFocus = FocusNode(debugLabel: 'TvSeerrDiscoverRailGenre');
  final _providerFocus = FocusNode(debugLabel: 'TvSeerrDiscoverRailProvider');
  final _clearFocus = FocusNode(debugLabel: 'TvSeerrDiscoverRailClear');
  final _stateActionFocus = FocusNode(debugLabel: 'TvSeerrDiscoverStateAction');
  final _viewAllFocus = <String, FocusNode>{};

  bool _railExpanded = false;
  TvSeerrDiscoverSubview? _subview;

  @override
  void dispose() {
    _kindFocus.dispose();
    _genreFocus.dispose();
    _providerFocus.dispose();
    _clearFocus.dispose();
    _stateActionFocus.dispose();
    for (final node in _viewAllFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  GlobalKey<TvCatalogCardRailState> _railKeyFor(String id) =>
      _railKeys.putIfAbsent(id, () => GlobalKey<TvCatalogCardRailState>(debugLabel: 'TvSeerrShelf($id)'));

  FocusNode _viewAllFocusFor(String id) =>
      _viewAllFocus.putIfAbsent(id, () => FocusNode(debugLabel: 'TvSeerrShowAll($id)'));

  // ---------------------------------------------------------------------------
  // Focus traversal
  // ---------------------------------------------------------------------------

  /// The first card under the search pill, or nothing when the page has none.
  ///
  /// There is deliberately no entry-focus method beside this one. Ontdekken is
  /// a section of the Mijn Pleya surface, and `TvNestedSurface` already places
  /// the focus on the first thing in traversal order when it opens — the search
  /// pill, which is the one element this page has in every state, including
  /// while it is still a skeleton. Alle aanvragen is a pushed route with no
  /// such fallback and does need its own; see
  /// `TvSeerrRequestsView.focusContent`.
  bool focusFirstContent() {
    final grid = _gridKey.currentState;
    if (grid != null && grid.hasFocusableCard) {
      grid.focusGrid();
      return true;
    }
    for (final shelf in widget.shelves) {
      if (_railKeyFor(shelf.id).currentState?.focusRail() ?? false) return true;
    }
    if (_stateActionFocus.canRequestFocus) {
      _stateActionFocus.requestFocus();
      return true;
    }
    return false;
  }

  void _openRail() {
    if (_railExpanded) return;
    setState(() {
      _railExpanded = true;
      _subview = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_railExpanded) return;
      if (_kindFocus.canRequestFocus) _kindFocus.requestFocus();
    });
  }

  void _closeRail() {
    if (!_railExpanded) return;
    setState(() {
      _railExpanded = false;
      _subview = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _railExpanded) return;
      focusFirstContent();
    });
  }

  void _leaveRailUpwards() {
    if (_railExpanded) {
      setState(() {
        _railExpanded = false;
        _subview = null;
      });
    }
    widget.onExitTop?.call();
  }

  /// DOWN off the bottom of the rail: nothing at all — see the kijklijst's own
  /// `_railEdge` for why this is explicit rather than null.
  void _railEdge() {}

  void _closeSubview() {
    final was = _subview;
    if (was == null) return;
    setState(() => _subview = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _subview != null) return;
      final node = switch (was) {
        TvSeerrDiscoverSubview.kind => _kindFocus,
        TvSeerrDiscoverSubview.genre => _genreFocus,
        TvSeerrDiscoverSubview.provider => _providerFocus,
      };
      if (node.canRequestFocus) node.requestFocus();
    });
  }

  /// Moves between shelves. The rail below, or the rail above; off the top of
  /// the first shelf the search pill.
  void _focusShelf(int index) {
    if (index < 0) return;
    if (index >= widget.shelves.length) return;
    _railKeyFor(widget.shelves[index].id).currentState?.focusRail();
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final grid = widget.grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvCatalogHeaderBar(title: grid?.title ?? t.seerr.title, tags: _railExpanded ? const [] : _tags()),
        widget.searchField,
        Expanded(
          child: TvCatalogRailScaffold(
            cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
            rail: _railExpanded ? _buildRail(scale) : null,
            body: _buildBody(scale),
          ),
        ),
      ],
    );
  }

  double _railLeading() => TvCatalogRailScaffold.leadingFor(MediaQuery.sizeOf(context).width, expanded: _railExpanded);

  /// What the page is narrowed to.
  ///
  /// Mockup 35 A's "Populair nu" is the resting statement — the page is showing
  /// what is popular, not a slice the viewer chose — so it is drawn muted, the
  /// same way the catalog draws its sort: always true, never a narrowing.
  List<TvCatalogSelectionTag> _tags() {
    final tags = <TvCatalogSelectionTag>[
      if (widget.type != SeerrDiscoverType.all) TvCatalogSelectionTag(_typeLabel(widget.type)),
      ?_genreTag(),
      ?_providerTag(),
    ];
    if (tags.isNotEmpty) return tags;
    return [TvCatalogSelectionTag(t.seerr.discoverNow, muted: true)];
  }

  TvCatalogSelectionTag? _genreTag() {
    final id = widget.genreId;
    if (id == null) return null;
    for (final genre in widget.genres) {
      if (genre.id == id) return TvCatalogSelectionTag(genre.name);
    }
    return null;
  }

  TvCatalogSelectionTag? _providerTag() {
    final id = widget.providerId;
    if (id == null) return null;
    for (final provider in widget.providers) {
      if (provider.id == id) return TvCatalogSelectionTag(provider.name);
    }
    return null;
  }

  String _typeLabel(SeerrDiscoverType type) => switch (type) {
    SeerrDiscoverType.all => t.seerr.filterAll,
    SeerrDiscoverType.movies => t.seerr.kindMovie,
    SeerrDiscoverType.tv => t.seerr.kindShow,
  };

  bool get _hasFilters => widget.type != SeerrDiscoverType.all || widget.genreId != null || widget.providerId != null;

  void _clearFilters() {
    if (_clearFocus.hasFocus) _kindFocus.requestFocus();
    widget.onProviderSelected?.call(null);
    widget.onGenreSelected(null);
    widget.onTypeSelected(SeerrDiscoverType.all);
  }

  Widget _buildRail(double scale) {
    final subview = _subview;
    if (subview != null) {
      return AutomationNode(
        id: AutomationIds.tvCatalogRail,
        instance: '$tvSeerrDiscoverSurface.${subview.name}',
        role: 'region',
        child: TvCatalogFilterRailSubview(
          key: tvCatalogFilterRailSubviewKey,
          scale: scale,
          title: switch (subview) {
            TvSeerrDiscoverSubview.kind => t.seerr.railKind,
            TvSeerrDiscoverSubview.genre => t.seerr.railGenre,
            TvSeerrDiscoverSubview.provider => t.seerr.byStreamingService,
          },
          options: _subviewOptions(subview),
          onBack: _closeSubview,
          onExitUp: _leaveRailUpwards,
          onExitDown: _railEdge,
          onExitRight: _closeRail,
        ),
      );
    }

    final rows = _railRows();
    return AutomationNode(
      id: AutomationIds.tvCatalogRail,
      instance: tvSeerrDiscoverSurface,
      role: 'region',
      child: TvCatalogFilterRailPanel(
        key: tvCatalogFilterRailKey,
        scale: scale,
        rows: rows,
        tags: _tags(),
        onClear: _hasFilters ? _clearFilters : null,
        clearFocusNode: _clearFocus,
        onClearNavigateUp: () => rows.last.focusNode.requestFocus(),
        onClearNavigateDown: _railEdge,
        onClearNavigateLeft: _leaveRailUpwards,
        onClearNavigateRight: _closeRail,
        onClearBack: _closeRail,
      ),
    );
  }

  List<TvCatalogFilterRailRow> _railRows() {
    // Built as a list first, so each row can name the row actually above and
    // below it rather than assuming which of the three optional ones are drawn.
    final specs = <({IconData icon, String label, String value, String key, FocusNode node, VoidCallback open})>[
      (
        icon: Symbols.filter_list_rounded,
        label: t.seerr.railKind,
        value: _typeLabel(widget.type),
        key: 'kind',
        node: _kindFocus,
        open: () => setState(() => _subview = TvSeerrDiscoverSubview.kind),
      ),
      if (widget.genres.isNotEmpty)
        (
          icon: Symbols.star_rounded,
          label: t.seerr.railGenre,
          value: _genreTag()?.label ?? t.seerr.allGenres,
          key: 'genre',
          node: _genreFocus,
          open: () => setState(() => _subview = TvSeerrDiscoverSubview.genre),
        ),
      if (widget.providers.isNotEmpty && widget.onProviderSelected != null)
        (
          icon: Symbols.live_tv_rounded,
          label: t.seerr.byStreamingService,
          value: _providerTag()?.label ?? t.seerr.filterAll,
          key: 'provider',
          node: _providerFocus,
          open: () => setState(() => _subview = TvSeerrDiscoverSubview.provider),
        ),
    ];

    return [
      for (var i = 0; i < specs.length; i++)
        TvCatalogFilterRailRow(
          icon: specs[i].icon,
          label: specs[i].label,
          value: specs[i].value,
          automationInstance: '$tvSeerrDiscoverSurface.${specs[i].key}',
          focusNode: specs[i].node,
          onPressed: specs[i].open,
          onNavigateUp: i == 0 ? _leaveRailUpwards : () => specs[i - 1].node.requestFocus(),
          onNavigateDown: i == specs.length - 1
              ? (_hasFilters ? () => _clearFocus.requestFocus() : _railEdge)
              : () => specs[i + 1].node.requestFocus(),
          onNavigateLeft: _leaveRailUpwards,
          onNavigateRight: _closeRail,
          onBack: _closeRail,
        ),
    ];
  }

  List<TvCatalogRailOption> _subviewOptions(TvSeerrDiscoverSubview subview) => switch (subview) {
    TvSeerrDiscoverSubview.kind => [
      for (final type in SeerrDiscoverType.values)
        TvCatalogRailOption(
          label: _typeLabel(type),
          isSelected: widget.type == type,
          automationInstance: '$tvSeerrDiscoverSurface.kind.${type.name}',
          onPressed: () {
            widget.onTypeSelected(type);
            _closeSubview();
          },
        ),
    ],
    TvSeerrDiscoverSubview.genre => [
      TvCatalogRailOption(
        label: t.seerr.allGenres,
        isSelected: widget.genreId == null,
        automationInstance: '$tvSeerrDiscoverSurface.genre.all',
        onPressed: () {
          widget.onGenreSelected(null);
          _closeSubview();
        },
      ),
      for (final genre in widget.genres)
        TvCatalogRailOption(
          label: genre.name,
          isSelected: widget.genreId == genre.id,
          automationInstance: '$tvSeerrDiscoverSurface.genre.${genre.id}',
          onPressed: () {
            widget.onGenreSelected(genre.id);
            _closeSubview();
          },
        ),
    ],
    TvSeerrDiscoverSubview.provider => [
      TvCatalogRailOption(
        label: t.seerr.filterAll,
        isSelected: widget.providerId == null,
        automationInstance: '$tvSeerrDiscoverSurface.provider.all',
        onPressed: () {
          widget.onProviderSelected?.call(null);
          _closeSubview();
        },
      ),
      for (final provider in widget.providers)
        TvCatalogRailOption(
          label: provider.name,
          isSelected: widget.providerId == provider.id,
          automationInstance: '$tvSeerrDiscoverSurface.provider.${provider.id}',
          onPressed: () {
            widget.onProviderSelected?.call(provider.id);
            _closeSubview();
          },
        ),
    ],
  };

  Widget _buildBody(double scale) {
    if (widget.isLoading) {
      return TvCatalogSkeletonGrid(key: tvCatalogSkeletonKey, reservedLeading: _railLeading());
    }

    final error = widget.error;
    if (error != null) {
      return _state(
        'error',
        TvCatalogEmptyState(
          icon: Symbols.cloud_off_rounded,
          title: error,
          body: t.seerr.errorGeneric,
          actionLabel: t.common.retry,
          onAction: widget.onReload,
          onActionFocusNode: _stateActionFocus,
          onActionNavigateLeft: _openRail,
        ),
      );
    }

    final grid = widget.grid;
    if (grid != null) return _buildGrid(scale, grid);

    final shelves = widget.shelves.where((shelf) => shelf.items.isNotEmpty).toList(growable: false);
    if (shelves.isEmpty) {
      return _state(
        'empty',
        TvCatalogEmptyState(
          icon: Symbols.movie_rounded,
          title: t.seerr.noResults,
          body: _hasFilters ? t.unifiedCatalog.states.filterEmptyBody : t.seerr.errorGeneric,
          actionLabel: _hasFilters ? t.unifiedCatalog.states.clearFilters : t.common.retry,
          onAction: _hasFilters ? _clearFilters : widget.onReload,
          onActionFocusNode: _stateActionFocus,
          onActionNavigateLeft: _openRail,
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final geometry = TvCatalogGrid.forWidth(width, scale: scale, reservedLeading: _railLeading());
    final headingInset = geometry.inset + geometry.leading + TvCatalogLayout.cardContentInset(scale);

    return SingleChildScrollView(
      // Not the default clip: a focused card grows past its rail's box, and the
      // page must not shear the ring off at the viewport edge.
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(bottom: geometry.bottomSafeMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shelves.length; i++) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(headingInset, TvCatalogLayout.headerContentGap * scale, headingInset, 0),
              child: Row(
                children: [
                  Expanded(child: TvSectionHeader(title: shelves[i].title)),
                  TvViewAllAction(
                    label: t.seerr.showAll,
                    semanticLabel: t.seerr.showAll,
                    focusNode: _viewAllFocusFor(shelves[i].id),
                    onSelect: shelves[i].onShowAll,
                    onNavigateUp: i == 0 ? widget.onExitTop : () => _focusShelf(i - 1),
                    onNavigateDown: () => _focusShelf(i),
                  ),
                ],
              ),
            ),
            _buildShelf(scale, shelves, i),
          ],
        ],
      ),
    );
  }

  Widget _buildShelf(double scale, List<TvSeerrShelf> shelves, int index) {
    final shelf = shelves[index];
    return AutomationNode(
      id: AutomationIds.tvCatalogGrid,
      instance: '$tvSeerrDiscoverSurface.${shelf.id}',
      role: 'rail',
      child: TvCatalogCardRail(
        key: _railKeyFor(shelf.id),
        itemIds: [for (final media in shelf.items) '${media.mediaType}:${media.tmdbId}'],
        cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
        hasMore: shelf.hasMore,
        isLoadingMore: shelf.isLoadingMore,
        onLoadMore: shelf.onLoadMore,
        reservedLeading: _railLeading(),
        nodeDebugLabel: 'TvSeerrShelfCard',
        onExitUp: () => _viewAllFocusFor(shelf.id).requestFocus(),
        onExitDown: index == shelves.length - 1 ? null : () => _focusShelf(index + 1),
        onExitLeft: _openRail,
        itemBuilder: (context, cell) {
          final media = shelf.items[cell.index];
          return _card(media, cell, instance: '$tvSeerrDiscoverSurface.${shelf.id}.${cell.index}');
        },
      ),
    );
  }

  Widget _buildGrid(double scale, TvSeerrGridPage page) {
    if (page.items.isEmpty) {
      return _state(
        'grid_empty',
        TvCatalogEmptyState(
          icon: Symbols.search_off_rounded,
          title: t.seerr.noResults,
          body: t.unifiedCatalog.states.filterEmptyBody,
          actionLabel: t.common.retry,
          onAction: widget.onReload,
          onActionFocusNode: _stateActionFocus,
          onActionNavigateLeft: _openRail,
        ),
      );
    }

    return AutomationNode(
      id: AutomationIds.tvCatalogGrid,
      instance: tvSeerrDiscoverSurface,
      role: 'grid',
      child: TvCatalogCardGrid(
        key: _gridKey,
        itemIds: [for (final media in page.items) '${media.mediaType}:${media.tmdbId}'],
        cardHeight: (cardWidth) => TvCatalogLayout.cardHeight(cardWidth, scale),
        hasMore: page.hasMore,
        isLoadingMore: page.isLoadingMore,
        onLoadMore: page.onLoadMore,
        onExitTop: widget.onExitTop,
        onExitLeft: _openRail,
        onBack: widget.onLeaveGrid,
        reservedLeading: _railLeading(),
        nodeDebugLabel: 'TvSeerrGridCard',
        itemBuilder: (context, cell) {
          final media = page.items[cell.index];
          return _card(media, cell, instance: '$tvSeerrDiscoverSurface.${cell.index}');
        },
      ),
    );
  }

  Widget _card(SeerrMedia media, TvCatalogGridCell cell, {required String instance}) {
    return AutomationNode(
      id: AutomationIds.tvCatalogGridItem,
      instance: instance,
      role: 'grid.item',
      label: media.title,
      focusNode: cell.focusNode,
      child: TvSeerrMediaCard(
        key: ValueKey('${media.mediaType}:${media.tmdbId}'),
        media: media,
        width: cell.width,
        focusNode: cell.focusNode,
        onSelect: () => widget.onActivate(media),
        onFocusChange: cell.onFocusChange,
        onNavigateUp: cell.onNavigateUp,
        onNavigateDown: cell.onNavigateDown,
        onNavigateLeft: cell.onNavigateLeft,
        onNavigateRight: cell.onNavigateRight,
        onBack: cell.onBack,
      ),
    );
  }

  Widget _state(String which, Widget child) => AutomationNode(
    id: AutomationIds.tvCatalogState,
    instance: '$tvSeerrDiscoverSurface.$which',
    role: 'region',
    focusNode: _stateActionFocus,
    child: child,
  );
}
