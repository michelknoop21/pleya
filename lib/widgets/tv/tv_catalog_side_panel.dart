/// The controls of a full-bleed catalog (A-06c): one panel that slides in from
/// the left, in the style of `2026-10-30-set2/02.png` mirrored, with every
/// choice inside it.
///
/// On the rail of hoofdstuk 10.2 Sorteren and Filters open a centred sheet over
/// the page. Here the page is the wall of posters and the panel the only thing
/// in front of it, so a second layer would have nothing to stand beside. Every
/// question replaces the panel's page instead, on
/// [TvCatalogFilterRailSubview].
///
/// **What stays the same is what the viewer can choose.** The session is
/// [TvCatalogFilterModel], the one the sheet draws: the categories, the draft
/// and Apply are not reinvented. Filters still batch behind Apply, so RIGHT and
/// Menu leave without changing the catalog.
///
/// **Where the remote goes.** RIGHT closes from anywhere and returns the ring to
/// the card it came from. Menu and LEFT go back one page, and Menu on the
/// overview closes. Choosing closes the panel too, and the screen puts the ring
/// on the first card: the choice changed the wall, so there is nothing to go
/// back to. DEC-XXX replaces CAT17's "focus stays on the rail" on this route.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import 'tv_catalog_filter_model.dart';
import 'tv_catalog_filter_rail.dart';
import 'tv_catalog_selection_tags.dart';
import 'tv_catalog_sort_panel.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

enum _Page { overview, sort, categories, category }

class TvCatalogSidePanel extends StatefulWidget {
  const TvCatalogSidePanel({
    super.key,
    required this.scale,
    required this.surface,
    required this.selection,
    required this.capabilities,
    required this.libraries,
    required this.clientFor,
    required this.sort,
    required this.sourcesValue,
    required this.filtersValue,
    required this.tags,
    required this.onChooseSort,
    required this.onApplyFilters,
    required this.onClose,
  });

  final double scale;

  /// `movies` or `series`, for the `tv.catalog.rail.row[...]` ids.
  final String surface;

  final UnifiedCatalogFilterSelection selection;
  final UnifiedFilterCapabilities capabilities;
  final List<CatalogLibrary> libraries;
  final MediaServerClient? Function(String serverId) clientFor;
  final UnifiedCatalogSort sort;

  /// What the Bronnen and Filters rows currently say.
  final String sourcesValue;
  final String filtersValue;

  /// The selection, under the overview's rows: the page has no heading any
  /// more to show it in.
  final List<TvCatalogSelectionTag> tags;

  final ValueChanged<UnifiedCatalogSort> onChooseSort;
  final ValueChanged<UnifiedCatalogFilterSelection> onApplyFilters;

  /// RIGHT, or Menu on the overview.
  final VoidCallback onClose;

  @override
  State<TvCatalogSidePanel> createState() => TvCatalogSidePanelState();
}

class TvCatalogSidePanelState extends State<TvCatalogSidePanel> {
  late final TvCatalogFilterModel _model = TvCatalogFilterModel(
    selection: widget.selection,
    capabilities: widget.capabilities,
    libraries: widget.libraries,
    clientFor: widget.clientFor,
  );

  _Page _page = _Page.overview;
  TvCatalogFilterSection _section = TvCatalogFilterSection.status;

  /// Where a page opens, by row. Set on the way back up a layer.
  int? _initialIndex = 0;

  /// The overview row each page returns to.
  int _overviewRow = 0;
  bool _optionsRequested = false;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  /// Puts the remote in the panel, on the row the page opens on.
  void focusEntry() {
    _pageKey.currentState?.focusSelected();
  }

  void _show(_Page page, {int? initialIndex, TvCatalogFilterSection? section}) {
    setState(() {
      _page = page;
      _initialIndex = initialIndex;
      if (section != null) _section = section;
    });
  }

  void _openCategories({required TvCatalogFilterSection wanted, required int overviewRow}) {
    _overviewRow = overviewRow;
    if (widget.capabilities.supportsMetadataFilters && !_optionsRequested) {
      _optionsRequested = true;
      unawaited(_model.loadOptions());
    }
    final resolved = _model.resolveInitialSection(wanted);
    _show(_Page.categories, initialIndex: _model.availableSections.indexOf(resolved));
  }

  /// Menu and LEFT: one page up, and off the overview only with Menu.
  void _back() {
    switch (_page) {
      case _Page.overview:
        widget.onClose();
      case _Page.category:
        // With something to apply the ring lands on Apply, one press from done.
        final sections = _model.availableSections;
        final dirty = _model.draft != widget.selection;
        _show(_Page.categories, initialIndex: dirty ? sections.length + 1 : sections.indexOf(_section));
      case _Page.sort:
      case _Page.categories:
        _show(_Page.overview, initialIndex: _overviewRow);
    }
  }

  String _instance(String row) => '${widget.surface}.$row';

  List<TvCatalogRailOption> _overviewOptions() => [
    TvCatalogRailOption(
      label: t.unifiedCatalog.rail.sources,
      value: widget.sourcesValue,
      isSelected: false,
      automationInstance: _instance('sources'),
      onPressed: () => _openCategories(wanted: TvCatalogFilterSection.servers, overviewRow: 0),
    ),
    TvCatalogRailOption(
      label: t.unifiedCatalog.filters.title,
      value: widget.filtersValue,
      isSelected: false,
      automationInstance: _instance('filters'),
      onPressed: () => _openCategories(wanted: TvCatalogFilterSection.status, overviewRow: 1),
    ),
    TvCatalogRailOption(
      label: t.unifiedCatalog.sort.title,
      value: sortLabel(widget.sort),
      isSelected: false,
      automationInstance: _instance('sort'),
      onPressed: () {
        _overviewRow = 2;
        _show(_Page.sort);
      },
    ),
    if (!widget.selection.isEmpty)
      TvCatalogRailOption(
        label: t.unifiedCatalog.states.clearFilters,
        isSelected: false,
        automationInstance: _instance('clear'),
        onPressed: () => widget.onApplyFilters(UnifiedCatalogFilterSelection.empty),
      ),
  ];

  List<TvCatalogRailOption> _sortOptions() => [
    for (final sort in UnifiedCatalogSort.values)
      TvCatalogRailOption(
        label: sortLabel(sort),
        isSelected: sort == widget.sort,
        automationInstance: _instance('sort.${sort.name}'),
        onPressed: () => widget.onChooseSort(sort),
      ),
  ];

  List<TvCatalogRailOption> _categoryOptions() => [
    for (final section in _model.availableSections)
      TvCatalogRailOption(
        label: tvCatalogFilterSectionLabel(section),
        count: _model.activeCountFor(section),
        isSelected: false,
        automationInstance: _instance('filter.${section.name}'),
        onPressed: () => _show(_Page.category, section: section),
      ),
    TvCatalogRailOption(
      label: t.unifiedCatalog.filters.clearAll,
      isSelected: false,
      automationInstance: _instance('filter.clear'),
      onPressed: _model.clearAll,
    ),
    TvCatalogRailOption(
      label: t.unifiedCatalog.filters.apply,
      isSelected: false,
      automationInstance: _instance('filter.apply'),
      onPressed: () => widget.onApplyFilters(_model.draft),
    ),
  ];

  List<TvCatalogRailOption> _rowOptions() {
    final rows = _model.rowsFor(_section);
    return [
      for (var i = 0; i < rows.length; i++)
        TvCatalogRailOption(
          label: rows[i].label,
          value: rows[i].secondary,
          isSelected: rows[i].isSelected,
          automationInstance: _instance('filter.${_section.name}.$i'),
          onPressed: rows[i].onPressed,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = widget.scale;
    final title = switch (_page) {
      _Page.overview => t.unifiedCatalog.filters.title,
      _Page.sort => t.unifiedCatalog.sort.title,
      _Page.categories => t.unifiedCatalog.filters.title,
      _Page.category => tvCatalogFilterSectionLabel(_section),
    };
    final options = switch (_page) {
      _Page.overview => _overviewOptions(),
      _Page.sort => _sortOptions(),
      _Page.categories => _categoryOptions(),
      _Page.category => _rowOptions(),
    };
    final String? note = switch (_page) {
      _Page.categories when _model.hasUnsupportedSections => t.unifiedCatalog.filters.someUnavailable,
      _Page.category when options.isEmpty =>
        _model.isLoadingOptions ? t.common.loading : t.unifiedCatalog.filters.noValues,
      _ => null,
    };

    return DecoratedBox(
      decoration: tvPanelDecoration(tk, TvCatalogFullBleedLayout.sheetRadius * scale),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: TvCatalogFullBleedLayout.sheetPaddingHorizontal * scale,
          vertical: TvCatalogFullBleedLayout.sheetPaddingVertical * scale,
        ),
        child: TvCatalogFilterRailSubview(
          key: _keyFor(_page, _section),
          sheet: true,
          title: title,
          options: options,
          scale: scale,
          note: note,
          initialIndex: _initialIndex,
          onBack: _back,
          onExitLeft: _page == _Page.overview ? _edge : null,
          onExitUp: _edge,
          onExitDown: _edge,
          onExitRight: widget.onClose,
          footer: _page == _Page.overview && widget.tags.isNotEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: TvCatalogFullBleedLayout.sheetTagsTopGap * scale),
                  child: TvCatalogSelectionTagStrip(tags: widget.tags, scale: scale, wrap: true),
                )
              : null,
        ),
      ),
    );
  }

  /// UP and DOWN off the ends: nothing. Explicit, because a null handler falls
  /// through to directional traversal, which finds the grid under the panel.
  void _edge() {}

  /// A page is a new question: new rows, opened on its own row. So each page
  /// gets a key of its own, and [focusEntry] reaches the one on screen.
  GlobalKey<TvCatalogFilterRailSubviewState> _keyFor(_Page page, TvCatalogFilterSection section) {
    final name = page == _Page.category ? '${page.name}.${section.name}' : page.name;
    if (_pageName != name) {
      _pageName = name;
      _pageKey = GlobalKey();
    }
    return _pageKey;
  }

  String? _pageName;
  GlobalKey<TvCatalogFilterRailSubviewState> _pageKey = GlobalKey();
}
