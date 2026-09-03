import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../books/book_filter.dart';
import '../../../i18n/strings.g.dart';

/// Golden 03's measurements, in logical pixels at the viewport it was drawn on
/// (`docs/assets/ebooks/northstar/03a-filters-status.png`, 393 × 852).
///
/// Every number here was read off `04-filters-sheet.png` from the iOS Unified
/// set rather than chosen, so a books sheet and a films sheet are the same
/// object with different content in it.
class BookFilterSheetMetrics {
  BookFilterSheetMetrics._();

  /// The viewport the golden was drawn on, and the top edge of the sheet on
  /// it. The sheet keeps that ratio on other screen heights rather than a
  /// fixed 600, so it neither overflows a shorter phone nor floats on a taller
  /// one.
  static const double referenceHeight = 852;
  static const double referenceTopInset = 252;
  static const double heightFactor = (referenceHeight - referenceTopInset) / referenceHeight;

  static const double cornerRadius = 13;
  static const double handleWidth = 36;
  static const double handleHeight = 5;
  static const double handleTop = 8;

  /// Header band: 20 pt margins, its own 24 pt row starting 24 pt down.
  static const double pageMargin = 20;
  static const double headerTop = 24;
  static const double headerHeight = 24;

  /// Where both panes begin, measured from the top of the sheet.
  static const double paneTop = 61;

  static const double railWidth = 131;
  static const double groupRowHeight = 43.5;

  /// The white edge on the active group. A tint alone is invisible here: in
  /// `monoTheme` the container colours resolve to the same value as the
  /// surface behind them (DEC-053).
  static const double groupEdgeWidth = 3;

  static const double optionRowHeight = 37;
  static const double optionGap = 10.5;
  static const double optionMargin = 16;
  static const double optionRadius = 9;

  /// Action bar: a 40 pt row 15 pt down, then the home indicator's room. At
  /// the golden's 34 pt bottom inset that adds up to its measured 97.
  static const double actionRowTop = 15;
  static const double actionRowHeight = 40;
  static const double actionRowGap = 8;
  static const double applyWidth = 130;

  static const Color surface = Color(0xFF1F1F1F);
  static const Color divider = Color(0xFF303030);
  static const Color activeGroup = Color(0xFF2A2A2A);
  static const Color selectedOption = Color(0xFF3E3E3E);
  static const Color handle = Color(0xFF575757);
}

/// The reader-facing name of a status choice. Here rather than inside the
/// sheet because Alle boeken's result line names the same four values.
String bookStatusLabel(BookStatusFilter status) => switch (status) {
  BookStatusFilter.all => t.books.statusAll,
  BookStatusFilter.unread => t.books.statusUnread,
  BookStatusFilter.read => t.books.statusRead,
  BookStatusFilter.downloaded => t.books.statusDownloaded,
};

/// Opens the filter sheet and answers what the reader applied.
///
/// `null` means they left without applying: dismissing is not the same as
/// clearing, and a swipe down must not silently change the shelf.
///
/// Deliberately on the nearest navigator rather than the root one. The browse
/// UI hangs under `ProfileNavigationScope`'s own `Navigator`, and a route put
/// above that scope loses it (see the overlay gotcha in CLAUDE.md).
Future<BookFilter?> showBookFilterSheet(
  BuildContext context, {
  required BookFilter filter,
  required BookFilterOptions options,
}) {
  return showModalBottomSheet<BookFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Measured on the golden: one black layer at 60 % over the whole frame,
    // the status bar included.
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (context) => BookFilterSheet(filter: filter, options: options),
  );
}

/// The two-pane filter sheet from approved golden 03.
///
/// Groups on the left, their choices on the right, and nothing happens to the
/// shelf until `Toepassen`. The staged filter lives here; the applied one
/// lives on Alle boeken. That split is the golden's third decision, and it is
/// why the Filters pill behind the sheet stays at rest while choices are being
/// made.
class BookFilterSheet extends StatefulWidget {
  const BookFilterSheet({super.key, required this.filter, required this.options});

  final BookFilter filter;
  final BookFilterOptions options;

  @override
  State<BookFilterSheet> createState() => _BookFilterSheetState();
}

class _BookFilterSheetState extends State<BookFilterSheet> {
  late BookFilter _staged = widget.filter;
  BookFilterGroup _group = BookFilterGroup.status;

  /// Groups with nothing to choose from are left out rather than shown empty.
  /// Status is always there: its four choices are fixed, not derived.
  List<BookFilterGroup> get _groups => [
    BookFilterGroup.status,
    for (final group in BookFilterGroup.values)
      if (group != BookFilterGroup.status && widget.options.forGroup(group).isNotEmpty) group,
  ];

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * BookFilterSheetMetrics.heightFactor;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return AutomationScreen(
      id: AutomationIds.screenBooksFilters,
      readiness: () => const AutomationReadiness.ready(),
      child: SizedBox(
        height: height,
        child: Material(
          color: BookFilterSheetMetrics.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(BookFilterSheetMetrics.cornerRadius)),
          child: Column(
            children: [
              const _Handle(),
              _Header(count: _staged.chosenCount),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: BookFilterSheetMetrics.railWidth,
                      child: _GroupRail(
                        groups: _groups,
                        selected: _group,
                        filter: _staged,
                        onSelect: (group) => setState(() => _group = group),
                      ),
                    ),
                    const VerticalDivider(width: 1, thickness: 1, color: BookFilterSheetMetrics.divider),
                    // The right pane scrolls on its own; the rail stays put, so
                    // a long group never scrolls its own heading off screen.
                    Expanded(
                      child: _OptionPane(
                        group: _group,
                        options: widget.options,
                        filter: _staged,
                        onToggle: (value) => setState(() => _staged = _staged.toggle(_group, value)),
                      ),
                    ),
                  ],
                ),
              ),
              _ActionBar(
                canClear: !_staged.isEmpty,
                bottomInset: bottomInset,
                onClear: () => setState(() => _staged = BookFilter.none),
                onApply: () => Navigator.of(context).pop(_staged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: BookFilterSheetMetrics.handleTop),
      child: Center(
        child: Container(
          width: BookFilterSheetMetrics.handleWidth,
          height: BookFilterSheetMetrics.handleHeight,
          decoration: BoxDecoration(
            color: BookFilterSheetMetrics.handle,
            borderRadius: BorderRadius.circular(BookFilterSheetMetrics.handleHeight / 2),
          ),
        ),
      ),
    );
  }
}

/// `Filters` on the left, how many choices stand on the right.
///
/// `gekozen` rather than the Unified set's `actief`: nothing is active until
/// Toepassen, and a word that claims otherwise would be the one lie on this
/// screen.
class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BookFilterSheetMetrics.pageMargin,
        // The handle already took `handleTop + handleHeight`.
        BookFilterSheetMetrics.headerTop - BookFilterSheetMetrics.handleTop - BookFilterSheetMetrics.handleHeight,
        BookFilterSheetMetrics.pageMargin,
        0,
      ),
      child: SizedBox(
        height: BookFilterSheetMetrics.headerHeight,
        child: Row(
          children: [
            Expanded(
              child: Text(
                t.books.filters,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3),
              ),
            ),
            if (count > 0)
              Text(
                t.books.filtersChosen(count: count),
                style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.62)),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupRail extends StatelessWidget {
  const _GroupRail({required this.groups, required this.selected, required this.filter, required this.onSelect});

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
            child: _GroupRow(
              group: group,
              isSelected: group == selected,
              count: filter.countFor(group),
              onTap: () => onSelect(group),
            ),
          ),
      ],
    );
  }

  /// Both panes start at [BookFilterSheetMetrics.paneTop] from the top of the
  /// sheet; the handle and the header have already used part of that.
  static const double _paneTopOffset =
      BookFilterSheetMetrics.paneTop - (BookFilterSheetMetrics.headerTop + BookFilterSheetMetrics.headerHeight);
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.isSelected, required this.count, required this.onTap});

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

class _OptionPane extends StatelessWidget {
  const _OptionPane({required this.group, required this.options, required this.filter, required this.onToggle});

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
        top: _GroupRail._paneTopOffset + BookFilterSheetMetrics.optionGap / 2,
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
          child: _OptionRow(
            option: option,
            isSelected: chosen.contains(option.value),
            onTap: () => onToggle(option.value),
          ),
        );
      },
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.isSelected, required this.onTap});

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

/// `Wissen` left, `Toepassen` right, on one line.
///
/// The golden puts them together rather than splitting them over the header
/// and the footer: they are the same kind of act, and a reader deciding to
/// give up should not have to look in a second place for it. With nothing
/// chosen, Wissen is still drawn but inert.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.canClear, required this.bottomInset, required this.onClear, required this.onApply});

  final bool canClear;
  final double bottomInset;
  final VoidCallback onClear;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BookFilterSheetMetrics.divider)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          BookFilterSheetMetrics.pageMargin,
          BookFilterSheetMetrics.actionRowTop,
          BookFilterSheetMetrics.pageMargin,
          BookFilterSheetMetrics.actionRowGap + bottomInset,
        ),
        child: SizedBox(
          height: BookFilterSheetMetrics.actionRowHeight,
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: canClear ? onClear : null,
                child: SizedBox(
                  height: BookFilterSheetMetrics.actionRowHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t.books.filtersClear,
                      style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: canClear ? 1 : 0.5)),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              AutomationNode(
                id: AutomationIds.booksFilterApply,
                role: 'button',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onApply,
                  child: Container(
                    width: BookFilterSheetMetrics.applyWidth,
                    height: BookFilterSheetMetrics.actionRowHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(BookFilterSheetMetrics.actionRowHeight / 2),
                    ),
                    child: Text(
                      t.books.filtersApply,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111111)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
