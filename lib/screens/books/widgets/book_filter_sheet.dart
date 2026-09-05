import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../books/book_filter.dart';
import '../../../i18n/strings.g.dart';
import 'book_filter_sheet_metrics.dart';
import 'book_filter_sheet_panes.dart';

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
                      child: BookFilterGroupRail(
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
                      child: BookFilterOptionPane(
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
