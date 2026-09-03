import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../books/book.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/main_screen_scope.dart';
import '../../providers/books_home_provider.dart';
import '../../widgets/app_icon.dart';
import 'widgets/book_cover.dart';
import 'widgets/book_rail.dart';

/// Alle boeken, built against approved golden 02
/// (`docs/assets/ebooks/northstar/02a-all-books.png`).
///
/// The grid geometry is the Unified set's own, measured on `03-alle-films.png`:
/// three columns of 114 pt with 10 pt gutters inside a 16 pt page margin, so a
/// shelf of books and a shelf of films line up. Books get no film metadata —
/// no year, runtime, resolution or rating — because this is a bookshelf.
class AllBooksScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final provider = context.watch<BooksHomeProvider?>();
    final books = provider?.rows.allByTitle ?? const <Book>[];
    return AutomationScreen(
      id: AutomationIds.screenAllBooks,
      readiness: () => provider == null || provider.hasLoaded
          ? const AutomationReadiness.ready()
          : const AutomationReadiness.loading('books'),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _AllBooksHeader()),
            const SliverToBoxAdapter(child: _Controls()),
            SliverToBoxAdapter(child: _ResultLine(count: books.length)),
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
                  mainAxisSpacing: _rowGap,
                  // 114 wide at 2:3 is 171 tall, plus the caption block.
                  mainAxisExtent: BookRailMetrics.coverHeight + captionHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => AutomationNode(
                    id: AutomationIds.booksGridItem,
                    instance: '$index',
                    role: 'grid.item',
                    child: _GridItem(book: books[index]),
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
              icon: const AppIcon(Symbols.arrow_back_rounded),
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
              onPressed: () => MainScreenFocusScope.of(context, listen: false)?.openSearch?.call(),
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
/// They are drawn and they do nothing yet, on purpose. Golden 02 approves how
/// they look; what opens behind Filters is schermgolden 03 and has no approval,
/// so there is nothing honest to wire them to. Rendering them without a tap
/// target is the difference between "not built yet" and "built and broken".
/// The sort pill still tells the truth: the grid really is title A–Z.
class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(BookRailMetrics.pageMargin, 16, BookRailMetrics.pageMargin, 0),
      child: Row(
        children: [
          _Pill(icon: Symbols.filter_list_rounded, label: t.books.filters),
          const SizedBox(width: 8),
          _Pill(icon: Symbols.swap_vert_rounded, label: t.books.sortTitleAsc),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xFF2F2F2F), borderRadius: BorderRadius.circular(18)),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// How many, on its own line under the pills — where the Unified set puts
/// `126 titels geladen`. The filter summary sits on the right of this line once
/// filters exist; until then that side stays empty rather than being filled
/// with something to look busy.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(BookRailMetrics.pageMargin, 14, BookRailMetrics.pageMargin, 0),
      child: Text(
        count == 1 ? t.books.oneBookLabel : t.books.bookCountLabel(count: count),
        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.62)),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  const _GridItem({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}
