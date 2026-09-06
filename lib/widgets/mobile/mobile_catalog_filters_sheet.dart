/// The filter sheet for Alle films/Alle series (iOS Unified 2026 fase 3,
/// `docs/ios-unified-2026-fase3-plan.md`), against the frozen
/// `04-filters-sheet.png`.
///
/// Two zones, not five stacked sections with a heading each: a narrow rail of
/// categories on the left (Status, Genre, Jaar, Servers, Bibliotheken, each
/// present only when the participating backends can execute it), and the
/// active category's choices on the right. The TV sheet this is modelled on
/// (`tv_catalog_filter_panel.dart`, read via `git show origin/main:...`, it
/// does not exist on this branch) took the same two-zone shape for the same
/// reason a stacked list gives: on a 393pt-wide phone a heading-per-section
/// column is even more awkward than on a ten-foot screen, and an unavailable
/// category simply has no row rather than a greyed-out apology.
///
/// Nothing here is applied until Toepassen. A `_draft` copy of the caller's
/// selection is mutated by every tap; the catalog behind the sheet does not
/// restart its query until the caller receives this sheet's result. On touch
/// that is a UX choice rather than the remote-control necessity it is on TV
/// (hoofdstuk 10.6), but the effect the codebase already relies on (closing
/// without Toepassen leaves the previous query untouched) is the same
/// either way.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_filter_options.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/global_key_utils.dart';
import '../app_icon.dart';
import '../overlay_sheet.dart';

/// Which category the sheet opens on. [servers] is what "Alle bronnen"
/// promises; the other four are all reachable from "Filters".
enum MobileCatalogFilterSection { status, genre, year, servers, libraries }

const List<MobileCatalogFilterSection> _railOrder = [
  MobileCatalogFilterSection.status,
  MobileCatalogFilterSection.genre,
  MobileCatalogFilterSection.year,
  MobileCatalogFilterSection.servers,
  MobileCatalogFilterSection.libraries,
];

Future<UnifiedCatalogFilterSelection?> showMobileCatalogFiltersSheet(
  BuildContext context, {
  required UnifiedCatalogFilterSelection selection,
  required UnifiedFilterCapabilities capabilities,
  required List<CatalogLibrary> libraries,
  required MediaServerClient? Function(String serverId) clientFor,
  MobileCatalogFilterSection initialSection = MobileCatalogFilterSection.genre,
}) {
  return OverlaySheetController.of(context).show<UnifiedCatalogFilterSelection>(
    showDragHandle: true,
    builder: (sheetContext) => MobileCatalogFiltersSheet(
      selection: selection,
      capabilities: capabilities,
      libraries: libraries,
      clientFor: clientFor,
      initialSection: initialSection,
      onApply: (result) => OverlaySheetController.of(sheetContext).pop(result),
    ),
  );
}

class MobileCatalogFiltersSheet extends StatefulWidget {
  const MobileCatalogFiltersSheet({
    super.key,
    required this.selection,
    required this.capabilities,
    required this.libraries,
    required this.clientFor,
    required this.onApply,
    this.initialSection = MobileCatalogFilterSection.genre,
  });

  final UnifiedCatalogFilterSelection selection;
  final UnifiedFilterCapabilities capabilities;

  /// Every eligible library, restricted or not: a server the user has
  /// excluded still needs a row, or there is no way back to it.
  final List<CatalogLibrary> libraries;
  final MediaServerClient? Function(String serverId) clientFor;
  final ValueChanged<UnifiedCatalogFilterSelection> onApply;
  final MobileCatalogFilterSection initialSection;

  @override
  State<MobileCatalogFiltersSheet> createState() => _MobileCatalogFiltersSheetState();
}

class _MobileCatalogFiltersSheetState extends State<MobileCatalogFiltersSheet> {
  late UnifiedCatalogFilterSelection _draft = widget.selection;
  late MobileCatalogFilterSection _active = _resolveInitialSection();
  UnifiedFilterOptions _options = UnifiedFilterOptions.empty;
  bool _isLoadingOptions = false;

  @override
  void initState() {
    super.initState();
    if (widget.capabilities.supportsMetadataFilters) unawaited(_loadOptions());
  }

  MobileCatalogFilterSection _resolveInitialSection() {
    final available = _availableSections;
    return available.contains(widget.initialSection) ? widget.initialSection : available.first;
  }

  /// Status/Genre/Jaar depend on the participating backends; Servers and
  /// Bibliotheken are always offered, because they are executed by leaving a
  /// cursor out of the merge rather than by asking a backend to filter.
  List<MobileCatalogFilterSection> get _availableSections => [
    for (final section in _railOrder)
      if (_supports(section)) section,
  ];

  bool _supports(MobileCatalogFilterSection section) => switch (section) {
    MobileCatalogFilterSection.status => widget.capabilities.supportsWatchFilter,
    MobileCatalogFilterSection.genre || MobileCatalogFilterSection.year => widget.capabilities.supportsMetadataFilters,
    MobileCatalogFilterSection.servers || MobileCatalogFilterSection.libraries => true,
  };

  Future<void> _loadOptions() async {
    setState(() => _isLoadingOptions = true);
    final options = await loadUnifiedFilterOptions(
      libraries: widget.libraries,
      clientFor: (serverId) => widget.clientFor(serverId.value),
    );
    if (!mounted) return;
    setState(() {
      _options = options;
      _isLoadingOptions = false;
    });
  }

  void _showSection(MobileCatalogFilterSection section) {
    if (_active == section) return;
    setState(() => _active = section);
  }

  void _toggleGenre(String genre) => setState(() => _draft = _draft.copyWith(genres: _toggled(_draft.genres, genre)));

  void _toggleYear(int year) => setState(() => _draft = _draft.copyWith(years: _toggled(_draft.years, year)));

  void _toggleServer(String serverId) =>
      setState(() => _draft = _draft.copyWith(serverIds: _toggled(_draft.serverIds, serverId)));

  void _toggleLibrary(String key) =>
      setState(() => _draft = _draft.copyWith(libraryKeys: _toggled(_draft.libraryKeys, key)));

  void _setWatchState(UnifiedWatchFilter value) => setState(() => _draft = _draft.copyWith(watchState: value));

  static Set<T> _toggled<T>(Set<T> current, T value) =>
      current.contains(value) ? ({...current}..remove(value)) : {...current, value};

  /// Distinct servers behind the eligible libraries, ordered by name then id
  /// so two servers sharing a display name cannot swap rows between openings.
  List<({String id, String name})> get _servers {
    final byId = <String, String>{};
    for (final library in widget.libraries) {
      byId.putIfAbsent(library.serverId.value, () => library.serverName);
    }
    final servers = [for (final entry in byId.entries) (id: entry.key, name: entry.value)];
    servers.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return servers;
  }

  List<_OptionRowSpec> _rowsFor(MobileCatalogFilterSection section) => switch (section) {
    MobileCatalogFilterSection.status => [
      _OptionRowSpec(
        label: t.unifiedCatalog.filters.all,
        isSelected: _draft.watchState == UnifiedWatchFilter.all,
        onPressed: () => _setWatchState(UnifiedWatchFilter.all),
      ),
      _OptionRowSpec(
        label: t.unifiedCatalog.filters.unwatched,
        isSelected: _draft.watchState == UnifiedWatchFilter.unwatched,
        onPressed: () => _setWatchState(UnifiedWatchFilter.unwatched),
      ),
    ],
    MobileCatalogFilterSection.genre => [
      for (final genre in _options.genres)
        _OptionRowSpec(label: genre, isSelected: _draft.genres.contains(genre), onPressed: () => _toggleGenre(genre)),
    ],
    MobileCatalogFilterSection.year => [
      for (final year in _options.years)
        _OptionRowSpec(label: '$year', isSelected: _draft.years.contains(year), onPressed: () => _toggleYear(year)),
    ],
    MobileCatalogFilterSection.servers => [
      for (final server in _servers)
        _OptionRowSpec(
          label: server.name,
          isSelected: _draft.serverIds.contains(server.id),
          onPressed: () => _toggleServer(server.id),
        ),
    ],
    MobileCatalogFilterSection.libraries => [
      for (final library in widget.libraries)
        _OptionRowSpec(
          label: library.libraryTitle,
          secondary: library.serverName,
          isSelected: _draft.libraryKeys.contains(buildGlobalKey(library.serverId, library.libraryId)),
          onPressed: () => _toggleLibrary(buildGlobalKey(library.serverId, library.libraryId)),
        ),
    ],
  };

  int _activeCountFor(MobileCatalogFilterSection section) => switch (section) {
    MobileCatalogFilterSection.status => _draft.watchState == UnifiedWatchFilter.all ? 0 : 1,
    MobileCatalogFilterSection.genre => _draft.genres.length,
    MobileCatalogFilterSection.year => _draft.years.length,
    MobileCatalogFilterSection.servers => _draft.serverIds.length,
    MobileCatalogFilterSection.libraries => _draft.libraryKeys.length,
  };

  String _labelFor(MobileCatalogFilterSection section) => switch (section) {
    MobileCatalogFilterSection.status => t.unifiedCatalog.filters.status,
    MobileCatalogFilterSection.genre => t.unifiedCatalog.filters.genre,
    MobileCatalogFilterSection.year => t.unifiedCatalog.filters.year,
    MobileCatalogFilterSection.servers => t.unifiedCatalog.filters.servers,
    MobileCatalogFilterSection.libraries => t.unifiedCatalog.filters.libraries,
  };

  @override
  Widget build(BuildContext context) {
    final sections = _availableSections;
    final rows = _rowsFor(_active);
    final tk = tokens(context);

    return AutomationNode(
      id: AutomationIds.sheetCatalogFilters,
      role: 'sheet',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(tk),
              const SizedBox(height: 16),
              SizedBox(
                height: 320,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 112, child: _buildRail(sections, tk)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildOptions(rows, tk)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(MonoTokens tk) {
    final activeCount = _draft.activeCount;
    return Row(
      children: [
        Text(t.unifiedCatalog.filters.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (activeCount > 0)
          Text(
            t.unifiedCatalog.filters.activeCount(count: activeCount),
            style: TextStyle(color: tk.textMuted),
          ),
      ],
    );
  }

  Widget _buildRail(List<MobileCatalogFilterSection> sections, MonoTokens tk) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in sections)
          AutomationNode(
            id: AutomationIds.sheetCatalogFiltersCategory,
            instance: section.name,
            role: 'list.item',
            child: _CategoryRow(
              label: _labelFor(section),
              count: _activeCountFor(section),
              isActive: section == _active,
              onTap: () => _showSection(section),
            ),
          ),
      ],
    );
  }

  Widget _buildOptions(List<_OptionRowSpec> rows, MonoTokens tk) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _isLoadingOptions ? t.common.loading : t.unifiedCatalog.filters.noValues,
          style: TextStyle(color: tk.textMuted),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final row = rows[index];
        return AutomationNode(
          id: AutomationIds.sheetCatalogFiltersOption,
          instance: '${_active.name}.$index',
          role: 'list.item',
          child: _OptionRow(spec: row),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        if (!_draft.isEmpty)
          AutomationNode(
            id: AutomationIds.sheetCatalogFiltersClear,
            role: 'button',
            child: TextButton(
              onPressed: () => setState(() => _draft = UnifiedCatalogFilterSelection.empty),
              child: Text(t.unifiedCatalog.filters.clearAll),
            ),
          ),
        const Spacer(),
        AutomationNode(
          id: AutomationIds.sheetCatalogFiltersApply,
          role: 'button',
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
            onPressed: () => widget.onApply(_draft),
            child: Text(t.unifiedCatalog.filters.apply),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.label, required this.count, required this.isActive, required this.onTap});

  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tk.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? tk.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(tk.radiusSm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: tk.text),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text('$count', style: TextStyle(color: tk.textMuted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionRowSpec {
  const _OptionRowSpec({required this.label, required this.isSelected, required this.onPressed, this.secondary});

  final String label;
  final String? secondary;
  final bool isSelected;
  final VoidCallback onPressed;
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.spec});

  final _OptionRowSpec spec;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return InkWell(
      onTap: spec.onPressed,
      borderRadius: BorderRadius.circular(tk.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: spec.isSelected ? tk.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(tk.radiusSm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: spec.isSelected ? FontWeight.w700 : FontWeight.w400, color: tk.text),
                  ),
                  if (spec.secondary != null)
                    Text(
                      spec.secondary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tk.textMuted),
                    ),
                ],
              ),
            ),
            if (spec.isSelected) AppIcon(Symbols.check_rounded, fill: 1, size: 20, color: tk.text),
          ],
        ),
      ),
    );
  }
}
