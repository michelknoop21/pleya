import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../books/book.dart';
import '../../books/book_search.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../providers/books_home_provider.dart';
import '../../widgets/app_icon.dart';
import 'book_detail_screen.dart';
import 'widgets/book_search_row.dart';

/// Boeken zoeken, built against approved golden 04
/// (`docs/assets/ebooks/northstar/04a-books-search.png`).
///
/// This screen brings no search UI of its own. The header, the field and the
/// chip row are `05-zoeken.png` from the iOS Unified set, measured and reused,
/// and `search_screen.dart` already draws a chip per result kind that only
/// appears when that kind has results. Books adds a fourth category and three
/// result shapes under it.
///
/// It is books-scoped on purpose: golden 04's chips are Alles, Boeken,
/// Auteurs and Boekenseries with no Films or Afleveringen among them, and the
/// tab bar under it has Boeken active. Searching the whole library stays with
/// `search_screen.dart`.
///
/// Library search, not in-book search. Finding a word inside an open book is
/// a reader screen and has nothing to do with this one.
class BooksSearchScreen extends StatefulWidget {
  const BooksSearchScreen({super.key, this.initialQuery = '', this.ranking = const LocalBookSearchRanking()});

  /// What the field starts with. Empty for a reader, who came here to type.
  final String initialQuery;

  /// Injected so the ranking can be swapped without touching a widget. What a
  /// query matches is a contract of its own: golden 04 fixes what a result
  /// looks like, not which results a query has.
  final BookSearchRanking ranking;

  @override
  State<BooksSearchScreen> createState() => _BooksSearchScreenState();
}

class _BooksSearchScreenState extends State<BooksSearchScreen> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialQuery);
  final FocusNode _focus = FocusNode();
  BookSearchCategory _category = BookSearchCategory.all;

  @override
  void initState() {
    super.initState();
    // The reason to be here is to type, so the keyboard comes up on its own
    // rather than costing a tap on a field that is already the only control.
    // Unless the field arrives with something in it: then there are results
    // to look at, and a keyboard over two of the three sections is the
    // opposite of helpful.
    if (widget.initialQuery.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A new query, and with it a fresh look at whether the chosen chip still
  /// means anything.
  ///
  /// The choice is **dropped**, not parked. Falling back only for the frame
  /// being drawn used to leave `_category` on a chip the reader could no longer
  /// see: search `dune`, choose Boekenseries, type `sapiens` (no series, so the
  /// screen showed Alles), then type `hobbit` — De Hobbit is in `midden-aarde`,
  /// the Boekenseries chip came back, the old choice took hold again, and the
  /// book the reader was looking for sat behind a filter they never applied to
  /// this query.
  void _onQueryChanged(String query) {
    setState(() {
      if (_category == BookSearchCategory.all) return;
      final rows = context.read<BooksHomeProvider?>()?.rows ?? const BooksHomeRows();
      final categories = widget.ranking.search(query: query, books: rows.all, series: rows.series).availableCategories;
      if (!categories.contains(_category)) _category = BookSearchCategory.all;
    });
  }

  /// A book result opens its own page (approved golden 05). Author and series
  /// rows do not: where those lead is not part of golden 04 or 05, so they stay
  /// drawn without a destination.
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
    final all = widget.ranking.search(query: _controller.text, books: rows.all, series: rows.series);
    final categories = all.availableCategories;
    // A rendering guard, and only that. [_onQueryChanged] is what actually
    // drops a choice the query no longer offers; this covers the other way the
    // chips can change under a standing choice — the provider finishing its
    // load after this screen mounted — so a frame is never drawn empty behind
    // a chip that is not there.
    final category = categories.contains(_category) ? _category : BookSearchCategory.all;
    final shown = all.within(category);

    return AutomationScreen(
      id: AutomationIds.screenBooksSearch,
      readiness: () => provider == null || provider.hasLoaded
          ? const AutomationReadiness.ready()
          : const AutomationReadiness.loading('books'),
      child: Scaffold(
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: _Header(controller: _controller, focus: _focus, onChanged: _onQueryChanged),
            ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: _Categories(
                  categories: categories,
                  selected: category,
                  onSelect: (value) => setState(() => _category = value),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 19),
                child: Column(
                  children: [
                    BookSearchSection(
                      title: t.navigation.books,
                      children: [
                        for (final book in shown.books)
                          AutomationNode(
                            id: AutomationIds.booksSearchResult,
                            instance: book.id,
                            role: 'list.item',
                            child: BookResultRow(book: book, onTap: () => _openDetail(book, rows.series)),
                          ),
                      ],
                    ),
                    BookSearchSection(
                      title: t.books.searchAuthors,
                      children: [
                        for (final name in shown.authors)
                          AutomationNode(
                            id: AutomationIds.booksSearchResultAuthor,
                            instance: name,
                            role: 'list.item',
                            child: AuthorResultRow(name: name),
                          ),
                      ],
                    ),
                    BookSearchSection(
                      title: t.books.bookSeries,
                      children: [
                        for (final series in shown.series)
                          AutomationNode(
                            id: AutomationIds.booksSearchResultSeries,
                            instance: series.id,
                            role: 'list.item',
                            child: SeriesResultRow(series: series),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
      ),
    );
  }
}

/// Back, title, field. The geometry is golden 04's: title row at 62, field at
/// 109 with a height of 36 and its glyph at 32.
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.focus, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Golden 04's own numbers: title row 3 pt under the safe area and 32
      // tall, field 15 pt under that. On the 59 pt inset of the frame the
      // golden was drawn on, that puts the title on 78 and the field on 109.
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top + 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  // The chevron, not the full arrow. Goldens 02a and 04a draw the
                  // same iOS chevron every other header in the books set uses;
                  // detail, inhoudsopgave and zoeken in boek were already built
                  // with it, and these two were the odd pair out.
                  icon: const AppIcon(Symbols.arrow_back_ios_new_rounded, size: 22, fill: 0, weight: 500),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                ),
                Text(
                  t.common.search,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BookSearchRowMetrics.pageMargin),
            child: DecoratedBox(
              decoration: BoxDecoration(color: BookSearchRowMetrics.surface, borderRadius: BorderRadius.circular(10)),
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    AppIcon(Symbols.search_rounded, size: 17, color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 12),
                    Expanded(
                      // `FocusableTextField`, not a bare `TextField`: the
                      // wrapper is what makes a field usable from a TV remote,
                      // and `test/no_bare_text_field_test.dart` enforces it.
                      child: FocusableTextField(
                        controller: controller,
                        focusNode: focus,
                        onChanged: onChanged,
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 16),
                        // `filled: false`, because a dark InputDecorationTheme
                        // fills a field by default and that second surface sat
                        // a shade lighter inside the one the golden draws.
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox(width: 16)
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                controller.clear();
                                onChanged('');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: AppIcon(
                                  Symbols.close_rounded,
                                  size: 17,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chip row. Outlined, and the chosen one is an accent outline with
/// accent ink rather than a filled accent capsule: a solid accent block here
/// would be the only one on a screen where accent otherwise means playing or
/// selected.
class _Categories extends StatelessWidget {
  const _Categories({required this.categories, required this.selected, required this.onSelect});

  final List<BookSearchCategory> categories;
  final BookSearchCategory selected;
  final ValueChanged<BookSearchCategory> onSelect;

  static const Color _accent = Color(0xFFE5140F);
  static const Color _accentInk = Color(0xFFFF6A63);

  static String label(BookSearchCategory category) => switch (category) {
    BookSearchCategory.all => t.books.statusAll,
    BookSearchCategory.books => t.navigation.books,
    BookSearchCategory.authors => t.books.searchAuthors,
    BookSearchCategory.series => t.books.bookSeries,
  };

  @override
  Widget build(BuildContext context) {
    // Scrollable for the same reason Alle boeken's pill row is: four chips in
    // a longer language, or at a larger text scale, stop fitting, and a
    // category is not something to ellipsise.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(BookSearchRowMetrics.pageMargin, 16, BookSearchRowMetrics.pageMargin, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final category in categories) ...[
            if (category != categories.first) const SizedBox(width: 7),
            AutomationNode(
              id: AutomationIds.booksSearchCategory,
              instance: category.name,
              role: 'filter',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(category),
                child: Container(
                  height: 33,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: category == selected ? _accent.withValues(alpha: 0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: category == selected ? _accent : Colors.white.withValues(alpha: 0.30)),
                  ),
                  child: Text(
                    label(category),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: category == selected ? _accentInk : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
