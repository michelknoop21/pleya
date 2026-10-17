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

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/home_custom_row.dart';
import '../../services/unified_catalog/home_custom_row_loader.dart';
import '../../services/unified_catalog/home_row_draft.dart';
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

typedef _Step = HomeRowWizardStep;

class _TvHomeRowWizardState extends State<TvHomeRowWizard> {
  /// The three steps' state and rules, shared with the phone wizard
  /// (`home_row_draft.dart`); this widget only draws it with a remote.
  late final HomeRowDraft _d = HomeRowDraft(initial: widget.initial, preview: widget.preview)..addListener(_onDraft);

  void _onDraft() {
    if (mounted) setState(() {});
  }

  _Step get _step => _d.step;
  MediaKind get _kind => _d.kind;
  UnifiedCatalogPreferences get _preferences => _d.preferences;
  HomeCustomRowContent? get _content => _d.content;
  bool get _isPreviewing => _d.isPreviewing;
  TextEditingController get _name => _d.name;
  String get _id => _d.id;

  final Map<String, FocusNode> _nodes = {};

  @override
  void dispose() {
    _d.dispose();
    for (final entry in _nodes.entries) {
      if (entry.key != _borrowedKey) entry.value.dispose();
    }
    // Exactly once, and also when no control adopted it (ROW1l). The host makes
    // this node and hands it over; `_nodes` used to be the only thing that
    // disposed it.
    widget.initialFocusNode?.dispose();
    super.dispose();
  }

  /// The control the wizard opens on: the kind that is currently chosen, which
  /// is the first stop of the first step and, on an edit, the answer that is
  /// already true.
  ///
  /// Stated rather than "whichever key asks first". That was the rule until
  /// ROW1f, and the answer it gave was Annuleren: `_footer(scale)` is built
  /// eagerly into the Column's children while the step body sits inside a
  /// `LayoutBuilder`, which only runs during layout. So the footer asked first,
  /// took the initial-focus node, and the wizard opened one Select away from
  /// throwing itself away.
  String get _initialFocusKey => 'kind.${_kind.id}';

  /// The `_nodes` key holding the host's node, so `dispose` does not free it
  /// twice.
  String? _borrowedKey;

  FocusNode _nodeFor(String key) {
    final initial = widget.initialFocusNode;
    if (initial != null && _borrowedKey == null && key == _initialFocusKey) {
      _borrowedKey = key;
      return _nodes[key] = initial;
    }
    return _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'TvHomeRowWizard.$key'));
  }

  HomeCustomRow get _draft => _d.draft;

  /// Every library the chosen kind could draw from, restriction or not: a
  /// server the viewer excluded still needs a row in the panel, or there is no
  /// way back to it.
  List<CatalogLibrary> get _libraries => widget.librariesFor(_kind);

  UnifiedFilterCapabilities get _capabilities =>
      unifiedFilterCapabilitiesFor(_libraries.where(_preferences.filters.selects).map((library) => library.backend));

  void _goTo(_Step step) => _d.goTo(step);

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
    _d.setFilters(next);
  }

  Future<void> _openSort() async {
    final next = await showTvCatalogSortPanel(context, selected: _preferences.sort);
    if (next == null || !mounted) return;
    _d.setSort(next);
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
              onPressed: () => _d.setKind(kind),
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
    // The words come from the draft, the same five lines the phone wizard
    // shows; what is TV's own is the icon and the panel each line opens.
    final rows = [
      for (final line in _d.filterLines(sortLabel))
        (
          icon: switch (line.key) {
            'status' => Symbols.visibility_rounded,
            'genre' => Symbols.sort_rounded,
            'year' => Symbols.schedule_rounded,
            'sources' => Symbols.dns_rounded,
            _ => Symbols.swap_vert_rounded,
          },
          label: line.label,
          value: line.value,
          onPressed: switch (line.key) {
            'status' => () => _openFilters(TvCatalogFilterSection.status),
            'genre' => () => _openFilters(TvCatalogFilterSection.genre),
            'year' => () => _openFilters(TvCatalogFilterSection.year),
            'sources' => () => _openFilters(TvCatalogFilterSection.servers),
            _ => _openSort,
          },
          key: line.key,
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
