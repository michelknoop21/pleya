import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../books/book_filter.dart';
import '../../../i18n/strings.g.dart';
import 'book_filter_sheet_metrics.dart';

/// The two panes of golden 03's filter sheet: the group rail on the left and
/// the choices for the selected group on the right. Lifted out of
/// `book_filter_sheet.dart` unchanged when that file went over 500 lines; the
/// sheet itself, its handle, header and action bar stayed behind.
///
/// Both panes start at [BookFilterSheetMetrics.paneTop] from the top of the
/// sheet; the handle and the header have already used part of that. It was a
/// private static on the rail, which the option pane reached into by name;
/// out here it belongs to neither and reads the same for both.
const double _paneTopOffset =
    BookFilterSheetMetrics.paneTop - (BookFilterSheetMetrics.headerTop + BookFilterSheetMetrics.headerHeight);

class BookFilterGroupRail extends StatelessWidget {
  const BookFilterGroupRail({
    super.key,
    required this.groups,
    required this.selected,
    required this.filter,
    required this.onSelect,
  });

  final List<BookFilterGroup> groups;
  final BookFilterGroup selected;
  final BookFilter filter;
  final ValueChanged<BookFilterGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: _paneTopOffset),
      children: [
        for (final group in groups)
          AutomationNode(
            id: AutomationIds.booksFilterGroup,
            instance: group.name,
            role: 'filter.group',
            child: BookFilterGroupRow(
              group: group,
              isSelected: group == selected,
              count: filter.countFor(group),
              onTap: () => onSelect(group),
            ),
          ),
      ],
    );
  }
}

class BookFilterGroupRow extends StatelessWidget {
  const BookFilterGroupRow({
    super.key,
    required this.group,
    required this.isSelected,
    required this.count,
    required this.onTap,
  });

  final BookFilterGroup group;
  final bool isSelected;
  final int count;
  final VoidCallback onTap;

  static String label(BookFilterGroup group) => switch (group) {
    BookFilterGroup.status => t.books.filterStatus,
    BookFilterGroup.genre => t.books.filterGenre,
    BookFilterGroup.series => t.books.filterSeries,
    BookFilterGroup.author => t.books.filterAuthor,
    BookFilterGroup.language => t.books.filterLanguage,
  };

  @override
  Widget build(BuildContext context) {
    final ink = isSelected ? Colors.white : Colors.white.withValues(alpha: 0.62);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: BookFilterSheetMetrics.groupRowHeight,
        // `expand`, because a Stack hands its non-positioned children loose
        // constraints: without it the label sized itself to one line of text
        // and sat against the top of a 43.5 pt row instead of in the middle
        // of it. Nothing in the widget tree complains; it only shows up
        // against the golden.
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isSelected) const ColoredBox(color: BookFilterSheetMetrics.activeGroup),
            if (isSelected)
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: BookFilterSheetMetrics.groupEdgeWidth,
                child: ColoredBox(color: Colors.white),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(BookFilterSheetMetrics.pageMargin, 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label(group),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: ink,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 13,
                        color: ink,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookFilterOptionPane extends StatelessWidget {
  const BookFilterOptionPane({
    super.key,
    required this.group,
    required this.options,
    required this.filter,
    required this.onToggle,
  });

  final BookFilterGroup group;
  final BookFilterOptions options;
  final BookFilter filter;
  final ValueChanged<String> onToggle;

  /// Status renders from its enum: its four choices are the golden's, not the
  /// shelf's.
  List<BookFilterOption> get _options => group == BookFilterGroup.status
      ? [
          for (final status in BookStatusFilter.values)
            BookFilterOption(value: status.name, label: bookStatusLabel(status)),
        ]
      : options.forGroup(group);

  @override
  Widget build(BuildContext context) {
    final chosen = filter.valuesFor(group);
    final items = _options;
    return ListView.separated(
      padding: const EdgeInsets.only(
        top: _paneTopOffset + BookFilterSheetMetrics.optionGap / 2,
        bottom: BookFilterSheetMetrics.optionGap,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: BookFilterSheetMetrics.optionGap),
      itemBuilder: (context, index) {
        final option = items[index];
        return AutomationNode(
          id: AutomationIds.booksFilterOption,
          instance: option.value,
          role: 'filter.option',
          child: BookFilterOptionRow(
            option: option,
            isSelected: chosen.contains(option.value),
            onTap: () => onToggle(option.value),
          ),
        );
      },
    );
  }
}

class BookFilterOptionRow extends StatelessWidget {
  const BookFilterOptionRow({super.key, required this.option, required this.isSelected, required this.onTap});

  final BookFilterOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookFilterSheetMetrics.optionMargin),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: BookFilterSheetMetrics.optionRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: BookFilterSheetMetrics.optionMargin),
          decoration: BoxDecoration(
            color: isSelected ? BookFilterSheetMetrics.selectedOption : Colors.transparent,
            borderRadius: BorderRadius.circular(BookFilterSheetMetrics.optionRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5),
                ),
              ),
              if (isSelected) const Icon(Icons.check_rounded, size: 19, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
