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
import '../../media/library_menu_definition.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import 'tv_catalog_filter_model.dart';
import 'tv_catalog_filter_rail.dart';
import 'tv_catalog_jump_index.dart';
import 'tv_catalog_selection_tags.dart';
import 'tv_catalog_sort_fields.dart';
import 'tv_catalog_sort_panel.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

enum _Page { overview, sort, categories, category, jump }

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
    this.onJump,
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

  /// Spring naar: the chosen letter. Null leaves the row out, which is what a
  /// page does that is not sorted on title: a letter means nothing there.
  final ValueChanged<String>? onJump;

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

  /// The server category open on the category page, when [_section] is
  /// [TvCatalogFilterSection.serverCategory].
  LibraryServerFilter? _serverCategory;

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

  /// The live servers can answer after the panel opened.
  @override
  void didUpdateWidget(TvCatalogSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _model.capabilities = widget.capabilities;
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
    final quick = _model.quickFilters;
    final quickCount = quick.length + _model.extraQuickFilters.length;
    final section = _model.menuSections.indexOf(wanted);
    _show(
      _Page.categories,
      initialIndex: section >= 0 ? quickCount + section : quick.indexOf(_model.draft.quickFilter).clamp(0, quickCount),
    );
  }

  /// Menu and LEFT: one page up, and off the overview only with Menu.
  void _back() {
    switch (_page) {
      case _Page.overview:
        widget.onClose();
      case _Page.category:
        // With something to apply the ring lands on Apply, one press from done.
        final sections = _model.menuSections;
        final quick = _model.quickFilters.length + _model.extraQuickFilters.length;
        final categories = sections.length + _model.serverCategories.length;
        final dirty = _model.draft != widget.selection;
        final here = _section == TvCatalogFilterSection.serverCategory
            ? sections.length + _model.serverCategories.indexWhere((c) => c.key == _serverCategory?.key)
            : sections.indexOf(_section);
        _show(_Page.categories, initialIndex: quick + (dirty ? categories + 1 : here));
      case _Page.sort:
      case _Page.categories:
      case _Page.jump:
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
    if (widget.onJump != null)
      TvCatalogRailOption(
        label: t.unifiedCatalog.jumpTo,
        isSelected: false,
        automationInstance: _instance('jump'),
        onPressed: () {
          _overviewRow = 3;
          _show(_Page.jump, initialIndex: 0);
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

  List<TvCatalogRailOption> _jumpOptions() => [
    for (final letter in tvCatalogJumpLetters)
      TvCatalogRailOption(
        label: letter,
        isSelected: false,
        automationInstance: _instance('jump.$letter'),
        onPressed: () => widget.onJump?.call(letter),
      ),
  ];

  /// One row per field the sources can all run, in the order of the menu
  /// definition, the arrow on the one in force. See
  /// [tvCatalogSortAfterChoosing] for what choosing a row does.
  List<TvCatalogRailOption> _sortOptions() => [
    for (final field in tvCatalogSortFields.where(widget.capabilities.supportsSort))
      TvCatalogRailOption(
        label: tvCatalogSortFieldLabel(field),
        isSelected: field == widget.sort.field,
        trailingIcon: field == widget.sort.field ? tvCatalogDirectionIcon(widget.sort) : null,
        automationInstance: _instance('sort.${field.name}'),
        onPressed: () => widget.onChooseSort(tvCatalogSortAfterChoosing(widget.sort, field)),
      ),
  ];

  /// The page of `library_menu_definition.dart`: the quick choices, a line, the
  /// categories. One level per list. A quick choice is an answer, like a sort:
  /// it applies, with whatever the categories hold, and closes. The categories
  /// keep batching behind Apply.
  List<TvCatalogRailOption> _categoryOptions() => [
    for (final filter in _model.quickFilters)
      TvCatalogRailOption(
        label: libraryQuickFilterLabel(filter),
        isSelected: _model.draft.extraFilter == null && _model.draft.quickFilter == filter,
        automationInstance: _instance('quick.${filter.name}'),
        onPressed: () => widget.onApplyFilters(_model.draft.withQuickFilter(filter)),
      ),
    for (final extra in _model.extraQuickFilters)
      TvCatalogRailOption(
        label: extra.label,
        isSelected: _model.draft.extraFilter == extra.key,
        automationInstance: _instance('quick.server.${extra.key}'),
        onPressed: () => widget.onApplyFilters(_model.draft.withExtraFilter(extra.key)),
      ),
    for (final (i, section) in _model.menuSections.indexed)
      TvCatalogRailOption(
        label: tvCatalogFilterSectionLabel(section),
        count: _model.activeCountFor(section),
        isSelected: false,
        dividerAbove: i == 0,
        automationInstance: _instance('filter.${section.name}'),
        onPressed: () => _show(_Page.category, section: section),
      ),
    for (final (i, category) in _model.serverCategories.indexed)
      TvCatalogRailOption(
        label: category.label,
        count: _model.activeCountForServerCategory(category.key),
        isSelected: false,
        dividerAbove: i == 0 && _model.menuSections.isEmpty,
        automationInstance: _instance('filter.server.${category.key}'),
        onPressed: () {
          _serverCategory = category;
          unawaited(_model.loadServerCategory(category.key));
          _show(_Page.category, section: TvCatalogFilterSection.serverCategory);
        },
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
    final category = _serverCategory;
    final rows = _section == TvCatalogFilterSection.serverCategory && category != null
        ? _model.rowsForServerCategory(category.key)
        : _model.rowsFor(_section);
    return [
      for (var i = 0; i < rows.length; i++)
        TvCatalogRailOption(
          label: rows[i].label,
          value: rows[i].secondary,
          isSelected: rows[i].isSelected,
          automationInstance: _instance(
            'filter.${_serverCategory != null && _section == TvCatalogFilterSection.serverCategory ? 'server.${_serverCategory!.key}' : _section.name}.$i',
          ),
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
      _Page.sort => t.unifiedCatalog.sort.pageTitle,
      _Page.categories => t.unifiedCatalog.filters.pageTitle,
      _Page.category when _section == TvCatalogFilterSection.serverCategory => _serverCategory?.label ?? '',
      _Page.category => tvCatalogFilterSectionLabel(_section),
      _Page.jump => t.unifiedCatalog.jumpTo,
    };
    final options = switch (_page) {
      _Page.overview => _overviewOptions(),
      _Page.sort => _sortOptions(),
      _Page.categories => _categoryOptions(),
      _Page.category => _rowOptions(),
      _Page.jump => _jumpOptions(),
    };
    final String? note = switch (_page) {
      _Page.categories when _model.hasUnsupportedSections => t.unifiedCatalog.filters.someUnavailable,
      _Page.category when options.isEmpty =>
        _model.isLoadingOptions ||
                (_serverCategory != null &&
                    _section == TvCatalogFilterSection.serverCategory &&
                    _model.isLoadingServerCategory(_serverCategory!.key))
            ? t.common.loading
            : t.unifiedCatalog.filters.noValues,
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
    final name = page == _Page.category ? '${page.name}.${section.name}.${_serverCategory?.key ?? ''}' : page.name;
    if (_pageName != name) {
      _pageName = name;
      _pageKey = GlobalKey();
    }
    return _pageKey;
  }

  String? _pageName;
  GlobalKey<TvCatalogFilterRailSubviewState> _pageKey = GlobalKey();
}
