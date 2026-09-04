import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../books/book.dart';
import '../../books/book_toc.dart';
import '../../books/book_toc_layout.dart';
import '../../books/book_toc_view.dart';
import '../../i18n/strings.g.dart';
import '../../widgets/app_icon.dart';
import 'widgets/book_toc_rows.dart';

/// Inhoudsopgave, built against approved golden 06
/// (`docs/assets/ebooks/northstar/06a-books-toc.png`).
///
/// The map of a book: where you are, what lies behind you, and where you can go
/// without paging there. The golden's three frames are one screen: `06a` is the
/// canonical state with the tree open on the reader's own place, `06b` is the
/// same tree with every part collapsed, `06c` lifts the row kinds out so the
/// three positions can be judged on their own.
///
/// **The dimmed row is a statement about position, never about completion.**
/// That was the blocker that cost golden 06 two rounds, and it lives in
/// [BookTocPosition] rather than in this file: nothing here knows the words
/// `read` or `completed`, no row carries a check, and the one reading figure on
/// the screen is the publication-wide `totalProgression` in the footer.
///
/// **This screen draws the tree and opens nothing.** Choosing a chapter jumps
/// into the reader, and the reader is panel 7 with its own golden — exactly
/// where the Filters pill stood between golden 02 and golden 03. `Ga naar
/// pagina` is drawn for the same reason and opens nothing either: what it opens
/// is one of the things golden 06 explicitly leaves open.
///
/// **And it has no door.** Where a table of contents opens from belongs to the
/// reader's chrome, which is not designed, so golden 05 deliberately has no row
/// for it and no screen pushes this one. The route opener on Boeken-home exists
/// for the Verify scenario and is not a way in.
class BooksTocScreen extends StatefulWidget {
  const BooksTocScreen({super.key, required this.book, required this.toc});

  final Book book;

  /// The publication's navigation and the reader's place in it. Passed in
  /// rather than fetched: the screen renders a tree, it does not own one.
  final BookToc toc;

  @override
  State<BooksTocScreen> createState() => _BooksTocScreenState();
}

class _BooksTocScreenState extends State<BooksTocScreen> {
  /// The tree opens on the place you are: the part holding the locator stands
  /// open and the others stand closed. Collapsing everything is a state you can
  /// reach, not the state you arrive in.
  late Set<String> _expanded = widget.toc.initiallyExpanded;

  void _toggle(String partId) {
    setState(() {
      if (!_expanded.remove(partId)) _expanded.add(partId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = BookTocView(book: widget.book, toc: widget.toc, expanded: _expanded);
    final rows = view.rows;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return AutomationScreen(
      id: AutomationIds.screenBooksToc,
      readiness: () => const AutomationReadiness.ready(),
      child: Scaffold(
        body: Stack(
          // Expand, and not the default loose fit. A `Stack` sizes itself to
          // its largest child, and a scroll view under loose constraints sizes
          // itself to its content: with every part collapsed the tree is 647
          // tall, the stack would be 768, and `bottom: 0` would hang the fixed
          // bar in the middle of the screen. It only looks right in the state
          // whose content is taller than the viewport, which is exactly the
          // state the tests were written against.
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: MediaQuery.viewPaddingOf(context).top + 3),
                  const _Header(),
                  const SizedBox(height: BookTocLayout.cardTop - BookTocLayout.headerTop - BookTocLayout.headerHeight),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: BookTocLayout.pageMargin),
                    child: _Card(rows: rows, book: widget.book, onTogglePart: _toggle),
                  ),
                  // The list runs on under the bar and nothing is shortened to
                  // make it fit; this is the room it needs to be scrolled clear
                  // of it.
                  SizedBox(height: _ActionBar.heightFor(bottomInset) + 24),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ActionBar(
                progressLabel: view.progressLabel,
                showsGoToPage: view.showsGoToPage,
                bottomInset: bottomInset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One dismiss glyph and a left-aligned title.
///
/// The comp draws a back arrow **and** a cross in the same bar: two doors for
/// one action, unless the cross means leaving the book, which would be a
/// decision about the reader's chrome. With one glyph this reads as a pushed
/// page, and then the title stands next to the arrow the way it does on every
/// header in the set rather than centred.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BookTocLayout.headerHeight,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(
              width: BookTocLayout.pageMargin + 40,
              height: BookTocLayout.headerHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: BookTocLayout.pageMargin),
                  child: Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).backButtonTooltip,
                    child: const AppIcon(Symbols.arrow_back_ios_new_rounded, size: 22, fill: 0, weight: 500),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              t.books.tableOfContents,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ),
          const SizedBox(width: BookTocLayout.pageMargin),
        ],
      ),
    );
  }
}

/// One rounded card with hairlines between the rows of its top layer, the shape
/// golden 04 settled on for a result section.
///
/// Content-sized on purpose: eight collapsed rows are eight rows, and stretching
/// the card down to the bar would lie about how much is in it.
class _Card extends StatelessWidget {
  const _Card({required this.rows, required this.book, required this.onTogglePart});

  final List<BookTocRow> rows;
  final Book book;
  final ValueChanged<String> onTogglePart;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(BookTocLayout.cardRadius),
      child: ColoredBox(
        color: BookTocLayout.surface,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final row in rows) _row(row)]),
      ),
    );
  }

  /// The automation node sits on the row and not around the list: a node around
  /// a sliver has no bounds, and then a geometry assertion has nothing to
  /// measure. That cost golden 02 a round.
  Widget _row(BookTocRow row) {
    final widget = BookTocRowWidget(
      row: row,
      book: book,
      // A part is the one row that does something: it opens and closes. Every
      // other row is drawn and inert, because what it would open is the reader.
      onTap: row.kind == BookTocRowKind.part ? () => onTogglePart(row.id) : null,
    );
    return switch (row.kind) {
      BookTocRowKind.book => AutomationNode(id: AutomationIds.booksTocBook, role: 'list.item', child: widget),
      BookTocRowKind.part => AutomationNode(
        id: AutomationIds.booksTocPart,
        instance: row.id,
        role: 'list.item',
        child: widget,
      ),
      BookTocRowKind.chapter => AutomationNode(
        id: AutomationIds.booksTocChapter,
        instance: row.id,
        role: 'list.item',
        child: widget,
      ),
      BookTocRowKind.entry => widget,
    };
  }
}

/// The bar golden 03 approved for the filter sheet, to the point, and fixed for
/// the same reason: a jump control that scrolls away with a long list is one you
/// cannot reach from where you need it.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.progressLabel, required this.showsGoToPage, required this.bottomInset});

  final String? progressLabel;
  final bool showsGoToPage;
  final double bottomInset;

  static double heightFor(double bottomInset) =>
      BookTocLayout.hairlineThickness +
      BookTocLayout.actionRowTop +
      BookTocLayout.actionRowHeight +
      BookTocLayout.actionRowGap +
      bottomInset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: const Border(top: BorderSide(color: BookTocLayout.hairline)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          BookTocLayout.pageMargin,
          BookTocLayout.actionRowTop,
          BookTocLayout.pageMargin,
          BookTocLayout.actionRowGap + bottomInset,
        ),
        child: SizedBox(
          height: BookTocLayout.actionRowHeight,
          child: Row(
            children: [
              if (progressLabel != null)
                Text(
                  progressLabel!,
                  style: TextStyle(fontSize: 14, height: 18 / 14, color: Colors.white.withValues(alpha: 0.62)),
                ),
              const Spacer(),
              // Drawn and inert. What it opens — a field, a slider, a sheet of
              // its own — is one of the things golden 06 leaves open, so there
              // is nothing here to open it with.
              if (showsGoToPage)
                AutomationNode(
                  id: AutomationIds.booksTocGoto,
                  role: 'button',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(
                      height: BookTocLayout.actionRowHeight,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: BookTocLayout.pill,
                        borderRadius: BorderRadius.circular(BookTocLayout.actionPillRadius),
                      ),
                      child: Text(
                        t.books.tocGoToPage,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
