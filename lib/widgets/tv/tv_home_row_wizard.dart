/// Making a row out of a filter, in three steps (ROW1, mockup 32 C1 to C4,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100) (5) and (6)).
///
/// ## Three steps and not four
///
/// The sketch had name, filters, sorting and preview. Sorting is a fifth line
/// of the filters step here, because that is where it already lives in the
/// catalogue itself: one panel, five lines, and a viewer who has set a
/// catalogue up once knows this screen. A step of its own would have been a
/// press and a page for one radio list.
///
/// ## The filter step opens the catalogue's own panels
///
/// Status, Genre, Year and Sources open `showTvCatalogFilterPanel` on the
/// matching section, and Sorting opens `showTvCatalogSortPanel`. Not a copy of
/// them: a second genre list would drift from the first on its first bug fix,
/// and hoofdstuk 12's "geen tweede projectie-architectuur" has an interface
/// twin. What this file owns is the five lines that say what is currently set,
/// which is the shape mockup 28 D2 gave the catalogue's own rail.
///
/// ## The preview is a real query
///
/// C3 draws the first posters and a count, and both come from the same
/// single-round merge the row itself will use once it exists. A preview built
/// from anything else would be a promise rather than an answer, and the case it
/// exists for is exactly the one where the answer is "nothing" (C4).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/home_custom_row.dart';
import '../../services/unified_catalog/home_custom_row_loader.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/home_custom_row_labels.dart';
import '../../utils/layout_constants.dart';
import '../overlay_sheet.dart';
import '../overlay_sheet_geometry.dart';
import 'tv_catalog_filter_panel.dart';
import 'tv_catalog_selection_tags.dart';
import 'tv_catalog_sort_panel.dart';
import 'tv_home_row_wizard_parts.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// Finds the open wizard.
const Key tvHomeRowWizardKey = ValueKey('tvHomeRowWizard');

/// Opens the wizard and returns the row to save, or null when the viewer backed
/// out. Nothing is written here; the caller owns the storage.
Future<HomeCustomRow?> showTvHomeRowWizard(
  BuildContext context, {
  HomeCustomRow? initial,
  required List<CatalogLibrary> Function(MediaKind kind) librariesFor,
  required Future<HomeCustomRowContent> Function(HomeCustomRow draft) preview,
  MediaServerClient? Function(String serverId)? clientFor,
}) {
  final initialFocusNode = FocusNode(debugLabel: 'TvHomeRowWizardInitialFocus');
  return OverlaySheetController.showAdaptive<HomeCustomRow>(
    context,
    presentation: OverlaySheetPresentation.panel,
    constraints: tvWidePanelConstraints(MediaQuery.sizeOf(context)),
    initialFocusNode: initialFocusNode,
    restoreLauncherFocus: true,
    builder: (sheetContext) => TvHomeRowWizard(
      key: tvHomeRowWizardKey,
      initial: initial,
      librariesFor: librariesFor,
      preview: preview,
      clientFor: clientFor,
      initialFocusNode: initialFocusNode,
      onSave: (row) => OverlaySheetController.closeAdaptive(sheetContext, row),
      onCancel: () => OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );
}

class TvHomeRowWizard extends StatefulWidget {
  const TvHomeRowWizard({
    super.key,
    required this.librariesFor,
    required this.preview,
    required this.onSave,
    required this.onCancel,
    this.initial,
    this.clientFor,
    this.initialFocusNode,
  });

  /// The row being edited, or null for a new one. An edit keeps the id, so the
  /// row keeps its place in the stored order and its focus memory on Home.
  final HomeCustomRow? initial;

  final List<CatalogLibrary> Function(MediaKind kind) librariesFor;
  final Future<HomeCustomRowContent> Function(HomeCustomRow draft) preview;
  final ValueChanged<HomeCustomRow> onSave;
  final VoidCallback onCancel;
  final MediaServerClient? Function(String serverId)? clientFor;
  final FocusNode? initialFocusNode;

  @override
  State<TvHomeRowWizard> createState() => _TvHomeRowWizardState();
}

enum _Step { nameAndKind, filters, preview }

class _TvHomeRowWizardState extends State<TvHomeRowWizard> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late MediaKind _kind = widget.initial?.kind ?? MediaKind.movie;
  late UnifiedCatalogPreferences _preferences = widget.initial?.preferences ?? UnifiedCatalogPreferences.defaults;
  late final String _id = widget.initial?.id ?? HomeCustomRow.newId();

  _Step _step = _Step.nameAndKind;

  HomeCustomRowContent? _content;
  bool _isPreviewing = false;

  /// Bumped on every preview request so a slow answer to a filter the viewer has
  /// already changed cannot land on top of a newer one.
  int _previewGeneration = 0;

  final Map<String, FocusNode> _nodes = {};

  @override
  void dispose() {
    _name.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String key) {
    if (_nodes.isEmpty && widget.initialFocusNode != null) return _nodes[key] = widget.initialFocusNode!;
    return _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'TvHomeRowWizard.$key'));
  }

  HomeCustomRow get _draft => HomeCustomRow(id: _id, kind: _kind, name: _name.text.trim(), preferences: _preferences);

  /// Every library the chosen kind could draw from, restriction or not: a
  /// server the viewer excluded still needs a row in the panel, or there is no
  /// way back to it.
  List<CatalogLibrary> get _libraries => widget.librariesFor(_kind);

  UnifiedFilterCapabilities get _capabilities =>
      unifiedFilterCapabilitiesFor(_libraries.where(_preferences.filters.selects).map((library) => library.backend));

  void _goTo(_Step step) {
    setState(() => _step = step);
    if (step == _Step.preview) unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    final generation = ++_previewGeneration;
    setState(() => _isPreviewing = true);
    final content = await widget.preview(_draft);
    if (!mounted || generation != _previewGeneration) return;
    setState(() {
      _content = content;
      _isPreviewing = false;
    });
  }

  Future<void> _openFilters(TvCatalogFilterSection section) async {
    final next = await showTvCatalogFilterPanel(
      context,
      selection: _preferences.filters,
      capabilities: _capabilities,
      libraries: _libraries,
      initialSection: section,
      clientFor: (serverId) => widget.clientFor?.call(serverId),
    );
    if (next == null || !mounted) return;
    setState(() => _preferences = _preferences.copyWith(filters: next));
  }

  Future<void> _openSort() async {
    final next = await showTvCatalogSortPanel(context, selected: _preferences.sort);
    if (next == null || !mounted) return;
    setState(() => _preferences = _preferences.copyWith(sort: next));
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final railWidth = (constraints.maxWidth * TvHomeRowsLayout.stepRailFraction)
                      .clamp(TvHomeRowsLayout.stepRailMinWidth, TvHomeRowsLayout.stepRailMaxWidth)
                      .toDouble();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: railWidth, child: _stepRail(mono, scale)),
                      SizedBox(width: TvHomeRowsLayout.stepZoneGap * scale),
                      // Scrollable, and not because the design overflows: the
                      // panel's height follows the viewport (hoofdstuk 14.1),
                      // the filter step is five rows plus tags, and the smallest
                      // canvas CAT1 has to survive is 1280x918. A step that
                      // cannot be scrolled there is a step with a control the
                      // remote cannot reach.
                      Expanded(child: SingleChildScrollView(child: _body(mono, scale))),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            _footer(scale),
          ],
        ),
      ),
    );
  }

  Widget _stepRail(MonoTokens mono, double scale) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        widget.initial == null ? t.unifiedCatalog.homeRows.wizardTitle : t.unifiedCatalog.homeRows.wizardEditTitle,
        style: TextStyle(
          fontSize: TvSourcePickerLayout.titleFontSize * scale,
          fontWeight: FontWeight.w700,
          color: mono.text,
          letterSpacing: -0.3,
        ),
      ),
      SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
      for (final step in _Step.values) ...[
        TvHomeWizardStepRow(
          index: step.index,
          label: switch (step) {
            _Step.nameAndKind => t.unifiedCatalog.homeRows.stepName,
            _Step.filters => t.unifiedCatalog.homeRows.stepFilters,
            _Step.preview => t.unifiedCatalog.homeRows.stepPreview,
          },
          isActive: step == _step,
          isDone: step.index < _step.index,
          scale: scale,
        ),
        SizedBox(height: TvHomeRowsLayout.stepRowGap * scale),
      ],
    ],
  );

  Widget _body(MonoTokens mono, double scale) => switch (_step) {
    _Step.nameAndKind => _nameStep(mono, scale),
    _Step.filters => _filterStep(mono, scale),
    _Step.preview => _previewStep(mono, scale),
  };

  Widget _stepHeader(MonoTokens mono, double scale, String title, String body) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: TvSourcePickerLayout.titleFontSize * scale,
          fontWeight: FontWeight.w700,
          color: mono.text,
          letterSpacing: -0.3,
        ),
      ),
      SizedBox(height: TvHomeRowsLayout.titleGap * scale),
      Text(
        body,
        style: TextStyle(fontSize: TvSourcePickerLayout.subtitleFontSize * scale, color: mono.textMuted),
      ),
      SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
    ],
  );

  Widget _nameStep(MonoTokens mono, double scale) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _stepHeader(mono, scale, t.unifiedCatalog.homeRows.stepName, t.unifiedCatalog.homeRows.stepNameBody),
      TvHomeWizardFieldLabel(text: t.unifiedCatalog.homeRows.kind, scale: scale),
      // The panel's own CTA capsule, not `FocusableFilterChip`. Two reasons,
      // and neither is taste. `TvCatalogOptionRow` is a full-width list row and
      // lays itself out as one, so two side by side in an unbounded Row have no
      // width to divide, which is a layout assertion. And the filter chip's
      // selected state is the red brand accent: hoofdstuk 34 pins the primary
      // CTA white and 33.6 #2 records that the mockup's red button loses, so a
      // red pill here would be the one red thing on a monochrome page.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kind in const [MediaKind.movie, MediaKind.show]) ...[
            if (kind == MediaKind.show) SizedBox(width: TvHomeRowsLayout.actionGap * scale),
            TvPanelButton(
              scale: scale,
              label: kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle,
              icon: kind == MediaKind.movie ? Symbols.movie_rounded : Symbols.live_tv_rounded,
              primary: _kind == kind,
              focusNode: _nodeFor('kind.${kind.id}'),
              // Changing the kind changes which libraries take part, so a
              // source restriction picked under the other kind names libraries
              // that no longer exist here. Dropping it is the same rule
              // hoofdstuk 10.6 applies to a vanished server: an invisible
              // filter with no row to untick it is worse than a lost choice.
              onPressed: () => setState(() {
                _kind = kind;
                _preferences = _preferences.copyWith(
                  filters: _preferences.filters.copyWith(serverIds: const {}, libraryKeys: const {}),
                );
              }),
            ),
          ],
        ],
      ),
      SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
      TvHomeWizardFieldLabel(text: t.unifiedCatalog.homeRows.name, scale: scale),
      // Both styles stated rather than inherited. The panel sets its own type
      // everywhere else, and a field that falls back to the Material theme's
      // default sits at a different size and weight from the label directly
      // above it — which on a 10-foot surface reads as a different kind of
      // control, not as a smaller font.
      FocusableTextField(
        controller: _name,
        focusNode: _nodeFor('name'),
        style: TextStyle(fontSize: TvHomeRowsLayout.titleFontSize * scale, color: mono.text),
        decoration: InputDecoration(
          hintText: homeCustomRowLabel(HomeCustomRow(id: _id, kind: _kind, preferences: _preferences)),
          hintStyle: TextStyle(fontSize: TvHomeRowsLayout.titleFontSize * scale, color: mono.textMuted),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      SizedBox(height: TvHomeRowsLayout.titleGap * scale * 2),
      Text(
        t.unifiedCatalog.homeRows.nameHint,
        style: TextStyle(fontSize: TvHomeRowsLayout.subtitleFontSize * scale, color: mono.textMuted),
      ),
    ],
  );

  Widget _filterStep(MonoTokens mono, double scale) {
    final filters = _preferences.filters;
    final rows = <({IconData icon, String label, String value, VoidCallback onPressed, String key})>[
      (
        icon: Symbols.visibility_rounded,
        label: t.unifiedCatalog.homeRows.status,
        value: filters.watchState == UnifiedWatchFilter.unwatched
            ? t.unifiedCatalog.filters.unwatched
            : t.unifiedCatalog.filters.all,
        onPressed: () => _openFilters(TvCatalogFilterSection.status),
        key: 'status',
      ),
      (
        icon: Symbols.sort_rounded,
        label: t.unifiedCatalog.homeRows.genre,
        value: filters.genres.isEmpty ? t.unifiedCatalog.rail.noFilters : (filters.genres.toList()..sort()).join(', '),
        onPressed: () => _openFilters(TvCatalogFilterSection.genre),
        key: 'genre',
      ),
      (
        icon: Symbols.schedule_rounded,
        label: t.unifiedCatalog.homeRows.year,
        value: filters.years.isEmpty ? t.unifiedCatalog.homeRows.allYears : (filters.years.toList()..sort()).join(', '),
        onPressed: () => _openFilters(TvCatalogFilterSection.year),
        key: 'year',
      ),
      (
        icon: Symbols.dns_rounded,
        label: t.unifiedCatalog.homeRows.sources,
        value: filters.restrictsSources
            ? t.unifiedCatalog.rail.filtersActive(count: filters.activeCount - filters.itemFilterCount)
            : t.unifiedCatalog.allSources,
        onPressed: () => _openFilters(TvCatalogFilterSection.servers),
        key: 'sources',
      ),
      (
        icon: Symbols.swap_vert_rounded,
        label: t.unifiedCatalog.homeRows.sorting,
        value: sortLabel(_preferences.sort),
        onPressed: _openSort,
        key: 'sort',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepHeader(mono, scale, t.unifiedCatalog.homeRows.stepFilters, t.unifiedCatalog.homeRows.stepFiltersBody),
        for (final row in rows) ...[
          TvHomeWizardFilterLine(
            icon: row.icon,
            label: row.label,
            value: row.value,
            scale: scale,
            focusNode: _nodeFor('filter.${row.key}'),
            onPressed: row.onPressed,
          ),
          SizedBox(height: TvHomeRowsLayout.rowGap * scale),
        ],
        SizedBox(height: TvHomeRowsLayout.titleGap * scale),
        TvCatalogSelectionTagStrip(tags: _tags(), scale: scale, wrap: true),
      ],
    );
  }

  List<TvCatalogSelectionTag> _tags() => [
    TvCatalogSelectionTag(_kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle),
    for (final part in homeCustomRowFilterParts(_draft)) TvCatalogSelectionTag(part),
    TvCatalogSelectionTag(sortLabel(_preferences.sort), muted: true),
  ];

  Widget _previewStep(MonoTokens mono, double scale) {
    final content = _content;
    final isEmpty = content != null && content.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepHeader(mono, scale, t.unifiedCatalog.homeRows.stepPreview, t.unifiedCatalog.homeRows.stepPreviewBody),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                homeCustomRowLabel(_draft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvHomeRowsLayout.titleFontSize * scale * 1.15,
                  fontWeight: FontWeight.w700,
                  color: mono.text,
                ),
              ),
            ),
            SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
            Flexible(
              child: Text(
                [
                  ?homeCustomRowCountLabel(content),
                  _kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle,
                  ...homeCustomRowFilterParts(_draft),
                  sortLabel(_preferences.sort),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvHomeRowsLayout.subtitleFontSize * scale,
                  // Amber when the filter yields nothing: C4's one colour
                  // change, on the line that carries the number.
                  color: isEmpty ? mono.accentAlt : mono.textMuted,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
        if (_isPreviewing || content == null)
          SizedBox(
            height: TvHomeRowsLayout.previewPosterHeight * scale,
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (isEmpty)
          TvHomeWizardEmptyPreview(scale: scale)
        else
          TvHomeWizardPreviewPosters(content: content, scale: scale, clientFor: widget.clientFor),
        SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
        Text(
          isEmpty ? t.unifiedCatalog.homeRows.emptyPreviewBody : t.unifiedCatalog.homeRows.landsBelowContinue,
          style: TextStyle(fontSize: TvHomeRowsLayout.subtitleFontSize * scale, color: mono.textMuted),
        ),
      ],
    );
  }

  Widget _footer(double scale) {
    final content = _content;
    final canSave = _step == _Step.preview && content != null && !content.isEmpty;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TvPanelButton(
          scale: scale,
          primary: false,
          focusNode: _nodeFor('footer.back'),
          icon: _step == _Step.nameAndKind ? null : Symbols.arrow_back_rounded,
          label: _step == _Step.nameAndKind ? t.common.cancel : t.unifiedCatalog.homeRows.back,
          onPressed: () => _step == _Step.nameAndKind ? widget.onCancel() : _goTo(_Step.values[_step.index - 1]),
        ),
        SizedBox(width: TvHomeRowsLayout.actionGap * scale),
        if (_step != _Step.preview)
          TvPanelButton(
            scale: scale,
            primary: true,
            focusNode: _nodeFor('footer.next'),
            icon: Symbols.arrow_forward_rounded,
            label: t.unifiedCatalog.homeRows.next,
            onPressed: () => _goTo(_Step.values[_step.index + 1]),
          )
        // C4: an empty filter cannot be saved, and the way forward is the
        // filters step rather than a disabled button with nothing to say.
        else if (!canSave)
          TvPanelButton(
            scale: scale,
            primary: true,
            autofocus: true,
            focusNode: _nodeFor('footer.adjust'),
            icon: Symbols.tune_rounded,
            label: t.unifiedCatalog.homeRows.adjustFilters,
            onPressed: () => _goTo(_Step.filters),
          )
        else
          TvPanelButton(
            scale: scale,
            primary: true,
            focusNode: _nodeFor('footer.save'),
            icon: Symbols.add_rounded,
            label: widget.initial == null ? t.unifiedCatalog.homeRows.addRow : t.unifiedCatalog.homeRows.saveRow,
            onPressed: () => widget.onSave(_draft),
          ),
      ],
    );
  }
}
