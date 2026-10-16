/// "Nieuwe rij" and "Rij bewerken" on iPhone, iPad and Mac (HOME-R1, mockup 44
/// G to J and L): the tvOS wizard's three steps, drawn for touch and pointer.
///
/// Same steps, same five filter lines, same texts. What the steps decide is
/// `HomeRowDraft`, shared with the tv wizard; a filter line opens the catalog's
/// own filter and sort sheets (northstar 04), so there is no second genre list.
/// The preview is a real query, and an empty one cannot be saved (C4).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../services/unified_catalog/home_custom_row.dart';
import '../../../services/unified_catalog/home_custom_row_loader.dart';
import '../../../services/unified_catalog/home_row_draft.dart';
import '../../../services/unified_catalog/home_row_editing.dart';
import '../../../services/unified_catalog/source_cursor.dart' show CatalogLibrary;
import '../../../services/unified_catalog/unified_catalog_filters.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/home_custom_row_labels.dart';
import '../../../widgets/focusable_filter_chip.dart';
import '../../../widgets/mobile/mobile_catalog_filters_sheet.dart';
import '../../../widgets/mobile/mobile_catalog_sort_sheet.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/tv/tv_expandable_media_tile.dart' show discoveryPosterPath;

class HomeRowWizardView extends StatefulWidget {
  const HomeRowWizardView({
    super.key,
    required this.editing,
    required this.onSave,
    required this.onCancel,
    this.initial,
    this.stepsAsTabs = false,
  });

  final HomeRowEditing editing;
  final HomeCustomRow? initial;
  final ValueChanged<HomeCustomRow> onSave;
  final VoidCallback onCancel;

  /// Three tabs instead of the progress bar, for the wide layout (mockup 44 L).
  final bool stepsAsTabs;

  @override
  State<HomeRowWizardView> createState() => _HomeRowWizardViewState();
}

class _HomeRowWizardViewState extends State<HomeRowWizardView> {
  late final HomeRowDraft _d = HomeRowDraft(initial: widget.initial, preview: widget.editing.preview)
    ..addListener(_onDraft);

  void _onDraft() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _d.dispose();
    super.dispose();
  }

  String _stepLabel(HomeRowWizardStep step) => switch (step) {
    HomeRowWizardStep.nameAndKind => t.unifiedCatalog.homeRows.stepName,
    HomeRowWizardStep.filters => t.unifiedCatalog.homeRows.stepFilters,
    HomeRowWizardStep.preview => t.unifiedCatalog.homeRows.stepPreview,
  };

  List<CatalogLibrary> get _libraries => widget.editing.librariesFor(_d.kind);

  Future<void> _openFilters(MobileCatalogFilterSection section) async {
    final libraries = _libraries;
    final capabilities = unifiedFilterCapabilitiesFor(
      libraries.where(_d.preferences.filters.selects).map((library) => library.backend),
    );
    final next = await showMobileCatalogFiltersSheet(
      context,
      selection: _d.preferences.filters,
      capabilities: capabilities,
      libraries: libraries,
      clientFor: widget.editing.clientFor,
      initialSection: section,
    );
    if (next != null && mounted) _d.setFilters(next);
  }

  Future<void> _openSort() async {
    final next = await showMobileCatalogSortSheet(context, current: _d.preferences.sort);
    if (next != null && mounted) _d.setSort(next);
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final home = t.unifiedCatalog.homeRows;
    final editing = widget.initial != null;
    final title = editing ? home.wizardEditTitle : home.wizardTitle;
    return AutomationNode(
      id: AutomationIds.homeCustomizeWizard,
      role: 'wizard',
      state: () => {
        'step': _d.step.name,
        'can_save': _d.canSave,
        'kind': _d.kind.id,
        'preview_count': _d.content?.loadedCount,
        'preview_empty': _d.content?.isEmpty,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: home.close,
                  icon: const Icon(Symbols.close_rounded),
                  onPressed: widget.onCancel,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: widget.stepsAsTabs ? _tabs(mono) : _progress(mono),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: switch (_d.step) {
                HomeRowWizardStep.nameAndKind => _nameStep(mono),
                HomeRowWizardStep.filters => _filterStep(mono),
                HomeRowWizardStep.preview => _previewStep(mono),
              },
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 12), child: _footer()),
        ],
      ),
    );
  }

  Widget _progress(MonoTokens mono) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          for (final step in HomeRowWizardStep.values) ...[
            if (step.index > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: step.index <= _d.step.index ? mono.text : mono.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${t.unifiedCatalog.homeRows.stepOf(step: _d.step.index + 1)} · ${_stepLabel(_d.step)}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mono.textMuted),
      ),
    ],
  );

  Widget _tabs(MonoTokens mono) => Row(
    children: [
      for (final step in HomeRowWizardStep.values) ...[
        if (step.index > 0) const SizedBox(width: 8),
        Expanded(
          child: FocusableFilterChip(
            variant: FilterChipVariant.scope,
            selected: step == _d.step,
            icon: step.index < _d.step.index ? Symbols.check_rounded : null,
            label: '${step.index + 1}  ${_stepLabel(step)}',
            // Done steps can be revisited, and the next one is one press on,
            // like "Volgende". Further than that has nothing to show yet: the
            // preview needs the filters, and the filters need a kind.
            onPressed: () {
              if (step.index <= _d.step.index + 1) _d.goTo(step);
            },
          ),
        ),
      ],
    ],
  );

  Widget _intro(String body) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens(context).textMuted)),
  );

  Widget _nameStep(MonoTokens mono) {
    final home = t.unifiedCatalog.homeRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(home.stepNameBody),
        Text(home.kind, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final kind in const [MediaKind.movie, MediaKind.show]) ...[
              if (kind == MediaKind.show) const SizedBox(width: 8),
              // The app's own chip: a bare SegmentedButton shows no difference
              // between chosen and not chosen in this theme (DEC-053).
              FocusableFilterChip(
                variant: FilterChipVariant.scope,
                selected: _d.kind == kind,
                icon: kind == MediaKind.movie ? Symbols.movie_rounded : Symbols.live_tv_rounded,
                label: kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle,
                // Changing the kind drops a source restriction, see `HomeRowDraft`.
                onPressed: () => _d.setKind(kind),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Text(home.name, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        FocusableTextField(
          controller: _d.name,
          decoration: InputDecoration(
            hintText: homeCustomRowLabel(HomeCustomRow(id: _d.id, kind: _d.kind, preferences: _d.preferences)),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(home.nameHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mono.textMuted)),
      ],
    );
  }

  Widget _filterStep(MonoTokens mono) {
    final lines = _d.filterLines(mobileCatalogSortLabel);
    IconData iconOf(String key) => switch (key) {
      'status' => Symbols.visibility_rounded,
      'genre' => Symbols.sort_rounded,
      'year' => Symbols.schedule_rounded,
      'sources' => Symbols.dns_rounded,
      _ => Symbols.swap_vert_rounded,
    };
    void open(String key) => switch (key) {
      'status' => _openFilters(MobileCatalogFilterSection.status),
      'genre' => _openFilters(MobileCatalogFilterSection.genre),
      'year' => _openFilters(MobileCatalogFilterSection.year),
      'sources' => _openFilters(MobileCatalogFilterSection.servers),
      _ => _openSort(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(t.unifiedCatalog.homeRows.stepFiltersBody),
        Material(
          color: mono.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) Divider(height: 1, color: mono.outline),
                AutomationNode(
                  id: AutomationIds.homeCustomizeWizardAction,
                  instance: 'filter.${lines[i].key}',
                  role: 'button',
                  child: ListTile(
                    leading: Icon(iconOf(lines[i].key)),
                    title: Text(lines[i].label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            lines[i].value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: mono.textMuted),
                          ),
                        ),
                        const Icon(Symbols.chevron_right_rounded),
                      ],
                    ),
                    onTap: () => open(lines[i].key),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in _d.filterTags()) Chip(label: Text(tag)),
            Chip(
              label: Text(mobileCatalogSortLabel(_d.preferences.sort)),
              backgroundColor: Colors.transparent,
              side: BorderSide(color: mono.outline),
            ),
          ],
        ),
      ],
    );
  }

  Widget _previewStep(MonoTokens mono) {
    final home = t.unifiedCatalog.homeRows;
    final content = _d.content;
    final isEmpty = content != null && content.isEmpty;
    final kindLabel = _d.kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(home.stepPreviewBody),
        Text(
          homeCustomRowLabel(_d.draft),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          [
            ?homeCustomRowCountLabel(content),
            kindLabel,
            ...homeCustomRowFilterParts(_d.draft),
            mobileCatalogSortLabel(_d.preferences.sort),
          ].join(' · '),
          // Amber when the filter yields nothing: C4's one colour change.
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: isEmpty ? mono.accentAlt : mono.textMuted),
        ),
        const SizedBox(height: 16),
        if (_d.isPreviewing || content == null)
          const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()))
        else if (isEmpty)
          Container(
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: mono.outline),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(home.emptyPreviewTitle, style: TextStyle(color: mono.textMuted)),
          )
        else
          _posters(content, mono),
        const SizedBox(height: 16),
        Text(
          isEmpty ? home.emptyPreviewBody : home.landsBelowContinue,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mono.textMuted),
        ),
      ],
    );
  }

  Widget _posters(HomeCustomRowContent content, MonoTokens mono) {
    const width = 74.0;
    const height = 111.0;
    final shown = content.groups.take(4).toList();
    final rest = content.loadedCount - shown.length;
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final group in shown)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: OptimizedMediaImage.poster(
                  client: widget.editing.clientFor(group.representativeSource.item.serverId ?? ''),
                  imagePath: discoveryPosterPath(group.representativeSource.item),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (rest > 0)
            Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: mono.surfaceElevated, borderRadius: BorderRadius.circular(8)),
              child: Text(
                t.unifiedCatalog.homeRows.morePosters(count: rest),
                style: TextStyle(color: mono.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final home = t.unifiedCatalog.homeRows;
    final first = _d.step == HomeRowWizardStep.nameAndKind;
    Widget label(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    final Widget primary;
    if (_d.step != HomeRowWizardStep.preview) {
      primary = FilledButton.icon(
        onPressed: () => _d.goTo(HomeRowWizardStep.values[_d.step.index + 1]),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Symbols.arrow_forward_rounded),
        label: label(home.next),
      );
    } else if (!_d.canSave) {
      // C4: an empty filter cannot be saved, and the way forward is the
      // filters step rather than a disabled button with nothing to say.
      primary = FilledButton.icon(
        onPressed: _d.isPreviewing ? null : () => _d.goTo(HomeRowWizardStep.filters),
        icon: const Icon(Symbols.tune_rounded),
        label: label(home.adjustFilters),
      );
    } else {
      primary = FilledButton.icon(
        onPressed: () => widget.onSave(_d.draft),
        icon: const Icon(Symbols.add_rounded),
        label: label(widget.initial == null ? home.addRow : home.saveRow),
      );
    }
    return Row(
      children: [
        AutomationNode(
          id: AutomationIds.homeCustomizeWizardAction,
          instance: 'back',
          role: 'button',
          child: TextButton.icon(
            onPressed: () => first ? widget.onCancel() : _d.goTo(HomeRowWizardStep.values[_d.step.index - 1]),
            icon: first ? null : const Icon(Symbols.arrow_back_rounded),
            label: label(first ? t.common.cancel : home.back),
          ),
        ),
        const SizedBox(width: 12),
        // Flexible, so a longer translation shrinks the button instead of
        // overflowing a small iPhone.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: AutomationNode(
              id: AutomationIds.homeCustomizeWizardAction,
              instance: 'next',
              role: 'button',
              child: primary,
            ),
          ),
        ),
      ],
    );
  }
}
