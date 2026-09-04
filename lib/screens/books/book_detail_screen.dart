import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../books/book.dart';
import '../../books/book_detail_layout.dart';
import '../../books/book_detail_view.dart';
import '../../i18n/strings.g.dart';
import '../../providers/books_home_provider.dart';
import '../../widgets/app_icon.dart';
import 'book_reader_screen.dart';
import 'widgets/book_cover.dart';
import 'widgets/book_description.dart';
import 'widgets/book_detail_actions.dart';
import 'widgets/book_detail_ambience.dart';

/// Boekdetail, built against approved golden 05
/// (`docs/assets/ebooks/northstar/05a-book-detail.png`).
///
/// The page behind a cover, where a book introduces itself and the reading
/// starts. The golden's three frames are one screen: `05a` is the canonical
/// state, a book halfway read; `05b` is the same page for a book that has not
/// been started and is in no series; `05c` lifts the action block out of both
/// so the difference can be judged on its own.
///
/// **The reading button is the door to the reader.** Panel 7 has its own golden
/// and, since 4 September 2026, its own approval, so `Lees verder` opens
/// [BookReaderScreen] on the page the source hands it. It opens nothing for a
/// publication this build cannot open a page of, which keeps the button honest
/// rather than dead. `Downloaden` is still drawn and inert: what it means in
/// each of its states is PS-16. The overflow glyph top right is there because
/// the comp draws it; what is in it was not decided either.
///
/// The layout rule lives in [BookDetailLayout] and the content derivation in
/// [BookDetailView], so what this file does is hang the one on the other.
class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({super.key, required this.book, this.series = const []});

  final Book book;

  /// The series the profile knows about, so `Dune #1` can be named. Passed in
  /// rather than read from a provider: this screen is reached from four places
  /// and each of them already has the shelf in hand.
  final List<BookSeries> series;

  @override
  Widget build(BuildContext context) {
    final view = BookDetailView.of(book, series: series);
    final blocks = view.blocks;
    return AutomationScreen(
      id: AutomationIds.screenBookDetail,
      readiness: () => const AutomationReadiness.ready(),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Stack(
            children: [
              Positioned.fill(child: BookDetailAmbience(artwork: book.artwork)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: MediaQuery.viewPaddingOf(context).top + 3),
                  const _Header(),
                  const SizedBox(
                    height: BookDetailLayout.coverTop - BookDetailLayout.headerTop - BookDetailLayout.headerHeight,
                  ),
                  _Cover(book: book),
                  for (final block in BookDetailLayout.flow.keys)
                    if (blocks.contains(block)) ...[
                      SizedBox(height: BookDetailLayout.flow[block]!.gapAbove),
                      _block(context, block, view),
                    ],
                  SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).bottom),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the reader on the page the source has for this publication.
  ///
  /// Nothing happens when there is none. A page comes from a reader engine that
  /// lays a publication out, that engine is PS-15, and until it exists the fixed
  /// set carries one page for the one book approved golden 07 is drawn with.
  Future<void> _openReader(BuildContext context) async {
    final provider = context.read<BooksHomeProvider?>();
    if (provider == null) return;
    final page = await provider.readerPage(book.id);
    if (page == null || !context.mounted) return;
    final toc = await provider.tableOfContents(book.id);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookReaderScreen(book: book, page: page, toc: toc),
      ),
    );
  }

  /// One entry of the column, in golden 05's own order. Every one of them is
  /// horizontally inset by the page margin except the cover, which is centred.
  Widget _block(BuildContext context, BookDetailBlock block, BookDetailView view) {
    final child = switch (block) {
      BookDetailBlock.title => _Title(text: view.book.title),
      BookDetailBlock.author => _Author(text: view.book.author),
      BookDetailBlock.series => _Series(text: view.seriesLabel!),
      BookDetailBlock.progress => BookDetailProgress(progress: view.progress!),
      BookDetailBlock.primary => AutomationNode(
        id: AutomationIds.booksDetailAction,
        instance: 'primary',
        role: 'button',
        child: BookDetailAction(label: view.primaryActionLabel, isPrimary: true, onTap: () => _openReader(context)),
      ),
      BookDetailBlock.secondary => AutomationNode(
        id: AutomationIds.booksDetailAction,
        instance: 'secondary',
        role: 'button',
        // Books have their own word for it. The app-wide `downloads.downloadNow`
        // is `Download`, golden 05 says `Downloaden`, and changing the shared
        // string would reword every other surface that uses it.
        child: BookDetailAction(label: t.books.download, isPrimary: false),
      ),
      BookDetailBlock.stats => AutomationNode(
        id: AutomationIds.booksDetailStats,
        role: 'list',
        child: BookDetailStats(stats: view.stats),
      ),
      BookDetailBlock.description => BookDescription(text: view.book.description!),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookDetailLayout.pageMargin),
      child: child,
    );
  }
}

/// Back and overflow, and no title.
///
/// `06-film-detail.png` puts `Dune: Part Two` next to the back arrow. Panel 5
/// does not, and the title stands 270 pt lower in 30 pt bold; setting it twice
/// adds no information and costs the top edge its quiet. The comp wins here,
/// for the composition.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BookDetailLayout.headerHeight,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(
              width: BookDetailLayout.pageMargin + 42,
              height: BookDetailLayout.headerHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: BookDetailLayout.pageMargin),
                  child: Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).backButtonTooltip,
                    child: const AppIcon(Symbols.arrow_back_ios_new_rounded, size: 22, fill: 0, weight: 500),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Drawn, opens nothing: the comp puts a menu here, what is in it is
          // not part of golden 05.
          const Padding(
            padding: EdgeInsets.only(right: BookDetailLayout.pageMargin),
            child: Opacity(opacity: 0.92, child: AppIcon(Symbols.more_horiz_rounded, size: 24)),
          ),
        ],
      ),
    );
  }
}

/// 150 x 225 at 2:3, centred, and the one place the artwork is shown sharp.
class _Cover extends StatelessWidget {
  const _Cover({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final value = book;
    return Center(
      child: AutomationNode(
        id: AutomationIds.booksDetailCover,
        role: 'image',
        child: Container(
          width: BookDetailLayout.coverWidth,
          height: BookDetailLayout.coverHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BookDetailLayout.coverRadius),
            boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 44, offset: Offset(0, 20))],
          ),
          child: BookCover(
            artwork: value.artwork,
            title: value.title,
            author: value.author,
            borderRadius: BookDetailLayout.coverRadius,
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 36 / 30, letterSpacing: -0.5),
  );
}

class _Author extends StatelessWidget {
  const _Author({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 17, height: 22 / 17, color: Colors.white.withValues(alpha: 0.78)),
  );
}

/// `Dune #1`, a label and nothing more. Whether it navigates to the series is
/// an open question; golden 05 draws it and promises no destination.
class _Series extends StatelessWidget {
  const _Series({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 13.5, height: 18 / 13.5, color: Colors.white.withValues(alpha: 0.5)),
  );
}
