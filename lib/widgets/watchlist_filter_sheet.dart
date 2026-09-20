import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../i18n/strings.g.dart';
import '../media/watchlist_filter.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'focusable_list_tile.dart';
import 'overlay_sheet.dart';

Future<WatchlistFilterSelection?> showWatchlistFilterSheet(
  BuildContext context, {
  required WatchlistFilterSelection current,
  required bool showAvailable,
}) {
  return OverlaySheetController.showAdaptive<WatchlistFilterSelection>(
    context,
    builder: (_) => WatchlistFilterSheet(current: current, showAvailable: showAvailable),
  );
}

enum _WatchlistFilterSection { kind, availability }

class WatchlistFilterSheet extends StatefulWidget {
  const WatchlistFilterSheet({super.key, required this.current, required this.showAvailable});

  final WatchlistFilterSelection current;
  final bool showAvailable;

  @override
  State<WatchlistFilterSheet> createState() => _WatchlistFilterSheetState();
}

class _WatchlistFilterSheetState extends State<WatchlistFilterSheet> {
  late WatchlistFilterSelection _draft = widget.current;
  _WatchlistFilterSection _section = _WatchlistFilterSection.kind;

  int get _activeCount => (_draft.kind == WatchlistKindFilter.all ? 0 : 1) + (_draft.availableOnly ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final sections = [_WatchlistFilterSection.kind, if (widget.showAvailable) _WatchlistFilterSection.availability];

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
              Row(
                children: [
                  Text(
                    t.unifiedCatalog.filters.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (_activeCount > 0)
                    Text(
                      t.unifiedCatalog.filters.activeCount(count: _activeCount),
                      style: TextStyle(color: tk.textMuted),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [for (final section in sections) _category(section, tk)],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _options()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!_draft.isEmpty)
                    AutomationNode(
                      id: AutomationIds.sheetCatalogFiltersClear,
                      role: 'button',
                      child: TextButton(
                        onPressed: () => setState(() => _draft = WatchlistFilterSelection.none),
                        child: Text(t.unifiedCatalog.filters.clearAll),
                      ),
                    ),
                  const Spacer(),
                  AutomationNode(
                    id: AutomationIds.sheetCatalogFiltersApply,
                    role: 'button',
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      onPressed: () => OverlaySheetController.closeAdaptive(context, _draft),
                      child: Text(t.unifiedCatalog.filters.apply),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _category(_WatchlistFilterSection section, MonoTokens tk) {
    final selected = section == _section;
    final count = switch (section) {
      _WatchlistFilterSection.kind => _draft.kind == WatchlistKindFilter.all ? 0 : 1,
      _WatchlistFilterSection.availability => _draft.availableOnly ? 1 : 0,
    };
    final label = switch (section) {
      _WatchlistFilterSection.kind => t.watchlist.rail.kind,
      _WatchlistFilterSection.availability => t.watchlist.rail.availability,
    };

    return AutomationNode(
      id: AutomationIds.sheetCatalogFiltersCategory,
      instance: section.name,
      role: 'list.item',
      child: InkWell(
        onTap: () => setState(() => _section = section),
        borderRadius: BorderRadius.circular(tk.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? tk.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(tk.radiusSm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              if (count > 0) Text('$count', style: TextStyle(color: tk.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _options() {
    final options = switch (_section) {
      _WatchlistFilterSection.kind => <(String, bool, VoidCallback)>[
        (
          t.watchlist.filterAll,
          _draft.kind == WatchlistKindFilter.all,
          () => setState(() => _draft = _draft.copyWith(kind: WatchlistKindFilter.all)),
        ),
        (
          t.watchlist.filterMovies,
          _draft.kind == WatchlistKindFilter.movies,
          () => setState(() => _draft = _draft.copyWith(kind: WatchlistKindFilter.movies)),
        ),
        (
          t.watchlist.filterShows,
          _draft.kind == WatchlistKindFilter.shows,
          () => setState(() => _draft = _draft.copyWith(kind: WatchlistKindFilter.shows)),
        ),
      ],
      _WatchlistFilterSection.availability => <(String, bool, VoidCallback)>[
        (
          t.watchlist.filterAll,
          !_draft.availableOnly,
          () => setState(() => _draft = _draft.copyWith(availableOnly: false)),
        ),
        (
          t.watchlist.filterAvailable,
          _draft.availableOnly,
          () => setState(() => _draft = _draft.copyWith(availableOnly: true)),
        ),
      ],
    };

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final (label, selected, onTap) = options[index];
        return AutomationNode(
          id: AutomationIds.sheetCatalogFiltersOption,
          instance: '${_section.name}.$index',
          role: 'list.item',
          child: FocusableListTile(
            selected: selected,
            autofocus: selected,
            leading: AppIcon(
              selected ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded,
              fill: 1,
            ),
            title: Text(label),
            onTap: onTap,
          ),
        );
      },
    );
  }
}
