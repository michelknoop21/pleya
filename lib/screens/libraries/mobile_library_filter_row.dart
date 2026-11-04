/// The filter row of the iPhone library look: the browse tab's own actions as
/// pills, three dots for what used to be the toolbar's pencil and refresh, and
/// the item count on the right.
///
/// The row belongs to the screen and is there on every tab, because the dots
/// are the only way to manage or refresh. The pills and the count come from
/// [LibraryHeaderInfo], which the browse tab publishes while it is open.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/focusable_filter_chip.dart';
import '../../widgets/library_header_bar.dart';
import '../../widgets/mobile/library_phone_look.dart';
import '../../widgets/mobile/library_sort_glyph.dart';

enum _LibraryMoreAction { manage, refresh }

class MobileLibraryFilterRow extends StatelessWidget {
  const MobileLibraryFilterRow({super.key, required this.info, required this.onManage, required this.onRefresh});

  final LibraryHeaderInfo info;

  /// Null hides the entry: there is nothing to manage without libraries.
  final VoidCallback? onManage;
  final VoidCallback onRefresh;

  void _handleMore(_LibraryMoreAction action) => switch (action) {
    _LibraryMoreAction.manage => onManage?.call(),
    _LibraryMoreAction.refresh => onRefresh(),
  };

  List<AppMenuEntry<_LibraryMoreAction>> _moreEntries() => [
    if (onManage != null)
      AppMenuItem(value: _LibraryMoreAction.manage, icon: Symbols.edit_rounded, label: t.libraries.manageLibraries),
    AppMenuItem(value: _LibraryMoreAction.refresh, icon: Symbols.refresh_rounded, label: t.common.refresh),
  ];

  @override
  Widget build(BuildContext context) {
    final count = info.itemCount;
    return SizedBox(
      height: LibraryPhoneMetrics.filterRowHeight,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: LibraryPhoneMetrics.gridInsetStart),
              child: Row(
                children: [
                  for (final action in info.actions) ...[
                    _LibraryPill(action: action),
                    const SizedBox(width: LibraryPhoneMetrics.pillGap),
                  ],
                  AutomationNode(
                    id: AutomationIds.libraryFilterMore,
                    role: 'button',
                    child: AppMenuButton<_LibraryMoreAction>(
                      tooltip: t.libraries.libraryOptions,
                      entriesBuilder: (_) => _moreEntries(),
                      onSelected: _handleMore,
                      child: const _MoreDots(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (count != null) _CountBadge(count: count),
        ],
      ),
    );
  }
}

class _LibraryPill extends StatelessWidget {
  const _LibraryPill({required this.action});

  final LibraryHeaderAction action;

  @override
  Widget build(BuildContext context) {
    final descending = action.sortDescending;
    final chip = FocusableFilterChip(
      variant: FilterChipVariant.libraryPill,
      icon: action.icon,
      leading: descending == null
          ? null
          : LibrarySortGlyph(
              descending: descending,
              color: tokens(context).text,
              size: LibraryPhoneMetrics.pillIconSize,
            ),
      label: action.pillLabel ?? action.value ?? action.label,
      focusNode: action.focusNode,
      onPressed: action.onPressed,
      onNavigateDown: action.onNavigateDown,
      onNavigateUp: action.onNavigateUp,
      onNavigateLeft: action.onNavigateLeft,
      onNavigateRight: action.onNavigateRight,
      onBack: action.onBack,
    );
    final id = action.automationId;
    return id == null ? chip : AutomationNode(id: id, role: 'filter', child: chip);
  }
}

class _MoreDots extends StatelessWidget {
  const _MoreDots();

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return SizedBox(
      height: 44,
      child: Center(
        child: Container(
          width: LibraryPhoneMetrics.pillHeight,
          height: LibraryPhoneMetrics.pillHeight,
          decoration: BoxDecoration(color: tk.surfaceElevated, shape: BoxShape.circle),
          child: AppIcon(Symbols.more_vert_rounded, size: LibraryPhoneMetrics.pillIconSize, color: tk.text),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: LibraryPhoneMetrics.gridInsetStart),
      child: AutomationNode(
        id: AutomationIds.libraryFilterCount,
        role: 'region',
        child: Container(
          height: LibraryPhoneMetrics.pillHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: LibraryPhoneMetrics.countBadgeHorizontalPadding),
          decoration: BoxDecoration(
            color: tk.surface,
            borderRadius: BorderRadius.circular(LibraryPhoneMetrics.pillHeight / 2),
          ),
          child: Text(
            '$count',
            style: TextStyle(color: tk.text, fontSize: LibraryPhoneMetrics.pillFontSize, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
