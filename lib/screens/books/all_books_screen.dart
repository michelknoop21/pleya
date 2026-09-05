import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_navigation_hooks.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../automation/pleya_verify.dart';
import '../../books/book.dart';
import '../../books/book_filter.dart';
import '../../i18n/strings.g.dart';
import '../../providers/books_home_provider.dart';
import '../../widgets/app_icon.dart';
import 'book_detail_screen.dart';
import 'books_search_screen.dart';
import 'widgets/book_cover.dart';
import 'widgets/book_filter_sheet.dart';
import 'widgets/book_filter_sheet_metrics.dart';
import 'widgets/book_rail.dart';

/// Alle boeken, built against approved golden 02
/// (`docs/assets/ebooks/northstar/02a-all-books.png`).
///
/// The grid geometry is the Unified set's own, measured on `03-alle-films.png`:
/// three columns of 114 pt with 10 pt gutters inside a 16 pt page margin, so a
/// shelf of books and a shelf of films line up. Books get no film metadata —
/// no year, runtime, resolution or rating — because this is a bookshelf.
class AllBooksScreen extends StatefulWidget {
  const AllBooksScreen({super.key});

  /// Two title lines plus one author line, plus the leading each carries. The
  /// block is a fixed height so every row starts on the same line whatever the
  /// titles do; the slack falls at the bottom of the cell rather than between
  /// a short title and its author.
  static const double captionHeight = 62;

  static const double _rowGap = 18;

  /// The caption's own key, because a cover draws its title too and a test
  /// looking for the text alone finds both.
  static String captionKey(String bookId) => 'books.grid.caption.$bookId';

  @override
  State<AllBooksScreen> createState() => _AllBooksScreenState();
}

class _AllBooksScreenState extends State<AllBooksScreen> {
  /// What is applied to the shelf right now. The sheet edits a copy; this
  /// only changes when the reader taps Toepassen (approved golden 03).
  BookFilter _filter = BookFilter.none;

  @override
  void initState() {
    super.initState();
    if (kPleyaVerify) {
      AutomationNavigationHooks.instance.registerRouteOpener(AutomationIds.screenBooksFilters, _openFilters);
    }
  }

  @override
  void dispose() {
    if (kPleyaVerify) {
      AutomationNavigationHooks.instance.unregisterRouteOpener(AutomationIds.screenBooksFilters, _openFilters);
    }
    super.dispose();
  }

  /// The same route the Filters pill opens, so a scenario and a reader arrive
  /// the same way.
  ///
  /// Answers whether the sheet went up, because it is also the route opener
  /// `/v1/open` drives: a `false` from an unmounted screen means nothing was
  /// pushed and the caller may ask again. The pill ignores the answer.
  Future<bool> _openFilters() async {
    if (!mounted) return false;
    final rows = context.read<BooksHomeProvider?>()?.rows ?? const BooksHomeRows();
    // Not awaited, and that matters twice over. `showModalBottomSheet` pushes
    // its route synchronously and then hands back a future that only completes
    // when the sheet closes; awaiting that here would make this opener answer
    // on dismissal rather than on push, and `/v1/open` — which awaits the
    // opener — would hang until a reader closed the sheet by hand. It did:
    // `POST /v1/open did not answer within 0:00:10` on books.filters.layout.
    unawaited(
      showBookFilterSheet(
        context,
        filter: _filter,
        options: BookFilterOptions.from(books: rows.all, series: rows.series),
      ).then((applied) {
        // `null` is a dismissal, and dismissing is not clearing.
        if (applied != null && mounted) setState(() => _filter = applied);
      }),
    );
    return true;
  }

  /// A cell opens the book's own page (approved golden 05), on the nearest
  /// navigator so `ProfileNavigationScope` is not lost.
  void _openDetail(Book book, List<BookSeries> series) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(book: book, series: series),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BooksHomeProvider?>();
    final rows = provider?.rows ?? const BooksHomeRows();
    final books = _filter.apply(rows.allByTitle);
    final options = BookFilterOptions.from(books: rows.all, series: rows.series);
    return AutomationScreen(
      id: AutomationIds.screenAllBooks,
      readiness: () => provider == null || provider.hasLoaded
          ? const AutomationReadiness.ready()
          : const AutomationReadiness.loading('books'),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _AllBooksHeader()),
            SliverToBoxAdapter(
              child: _Controls(filter: _filter, onOpenFilters: () => unawaited(_openFilters())),
            ),
            SliverToBoxAdapter(
              child: _ResultLine(
                count: books.length,
                summary: _filter.summaryLabels(statusLabel: bookStatusLabel, options: options).join(' · '),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(BookRailMetrics.pageMargin, 16, BookRailMetrics.pageMargin, 0),
              // The node sits on each cell, not on the grid: a sliver has no
              // render box, so an id mounted there registers with no bounds
              // and every geometry assertion against it fails with nothing to
              // measure. One node per cell is also what `library.grid.item`
              // already does.
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: AllBooksScreen._rowGap,
                  // 114 wide at 2:3 is 171 tall, plus the caption block.
                  mainAxisExtent: BookRailMetrics.coverHeight + AllBooksScreen.captionHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => AutomationNode(
                    id: AutomationIds.booksGridItem,
                    instance: '$index',
                    role: 'grid.item',
                    child: _GridItem(book: books[index], onTap: () => _openDetail(books[index], rows.series)),
                  ),
                  childCount: books.length,
                ),
              ),
            ),
            // The tab bar may cover the last row on the way past, never for
            // good. Same requirement as Boeken-home (golden 01b/02).
            SliverToBoxAdapter(child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
      ),
    );
  }
}

/// Back, title, search. Not the wordmark header of Boeken-home: this is a page
/// you arrive at, so it says where back goes.
class _AllBooksHeader extends StatelessWidget {
  const _AllBooksHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, MediaQuery.viewPaddingOf(context).top, 16, 0),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              // The chevron, not the full arrow. Goldens 02a and 04a draw the
              // same iOS chevron every other header in the books set uses;
              // detail, inhoudsopgave and zoeken in boek were already built with
              // it, and these two were the odd pair out.
              icon: const AppIcon(Symbols.arrow_back_ios_new_rounded, size: 22, fill: 0, weight: 500),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
            Expanded(
              child: Text(
                t.books.allBooks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
              ),
            ),
            IconButton(
              // Boeken zoeken, not the whole-library search: approved golden
              // 04 scopes this glyph to books. `MainScreenFocusScope`'s
              // `openSearch` still belongs to the other surfaces.
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BooksSearchScreen())),
              icon: const AppIcon(Symbols.search_rounded),
              tooltip: t.common.search,
            ),
          ],
        ),
      ),
    );
  }
}

/// The filter and sort pills from golden 02.
///
/// Filters opens approved golden 03's sheet and carries its badge. Sorting
/// still does nothing: golden 02 approved a pill that shows its value, and
/// what a tap on it should open has no golden. The label is not a lie either
/// way, because the grid really is title A–Z.
class _Controls extends StatelessWidget {
  const _Controls({required this.filter, required this.onOpenFilters});

  final BookFilter filter;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    // Scrollable, though at the golden's two pills in Inter it never scrolls.
    // A pill exists to show its value, so the honest way out of a row that
    // does not fit — a long sort label, a large text scale, a badge arriving
    // next to both — is to let it slide, not to ellipsise the value away.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(BookRailMetrics.pageMargin, 16, BookRailMetrics.pageMargin, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(
            icon: Symbols.filter_list_rounded,
            label: t.books.filters,
            badge: filter.chosenCount,
            onTap: onOpenFilters,
          ),
          const SizedBox(width: 8),
          _Pill(icon: Symbols.swap_vert_rounded, label: t.books.sortTitleAsc),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.badge = 0, this.onTap});

  final IconData icon;
  final String label;

  /// How many choices stand behind this pill. Zero draws no badge and leaves
  /// the pill at rest.
  final int badge;

  final VoidCallback? onTap;

  static const Color _accent = Color(0xFFE5140F);

  @override
  Widget build(BuildContext context) {
    final isActive = badge > 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isActive ? _accent.withValues(alpha: 0.20) : const Color(0xFF2F2F2F),
          borderRadius: BorderRadius.circular(18),
          border: isActive ? Border.all(color: _accent.withValues(alpha: 0.75)) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 17),
                const SizedBox(width: 7),
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                if (isActive) ...[const SizedBox(width: 7), _Badge(count: badge)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 19),
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _Pill._accent, borderRadius: BorderRadius.circular(10)),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// How many, on its own line under the pills, where the Unified set puts
/// `126 titels geladen`. With a filter on, what it is sits on the right of the
/// same line (golden 02c). At rest that side stays empty rather than being
/// filled with something to look busy.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.count, required this.summary});

  final int count;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(BookRailMetrics.pageMargin, 14, BookRailMetrics.pageMargin, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            count == 1 ? t.books.oneBookLabel : t.books.bookCountLabel(count: count),
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.62)),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(width: 12),
            // Ellipsised rather than wrapped: a second line here would push
            // the whole grid down and break the row rhythm golden 02 fixed.
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.70)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  const _GridItem({required this.book, this.onTap});

  final Book book;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: BookRailMetrics.coverHeight,
            child: BookCover(artwork: book.artwork, title: book.title, author: book.author),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: AllBooksScreen.captionHeight - 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    key: Key(AllBooksScreen.captionKey(book.id)),
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.28),
                  ),
                ),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.28, color: Colors.white.withValues(alpha: 0.62)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
