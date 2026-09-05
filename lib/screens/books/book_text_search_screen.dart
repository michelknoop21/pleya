import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../books/book.dart';
import '../../books/book_text_search.dart';
import '../../books/book_text_search_layout.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../widgets/app_icon.dart';
import 'widgets/book_text_search_row.dart';

/// Zoeken in boek, built against approved golden 09
/// (`docs/assets/ebooks/northstar/09a-books-search-in-book.png`).
///
/// One query through the publication that is open, and a list of places to jump
/// to. The golden's two frames are one screen: `09a` is the canonical state with
/// twelve results running on under the bottom edge, `09b` lifts the row out so
/// its six shapes can be judged next to each other.
///
/// **This is not golden 04.** That screen searches the shelf and returns books,
/// authors and series; this one searches one publication and returns places in
/// it. They share the header and the field and nothing else: there are no
/// category chips here, because there is one kind of result, and no tab bar,
/// because this is a page of the reader the way the inhoudsopgave is.
///
/// **Presentation and search engine are two contracts, and this is the first
/// one.** What a result looks like and what it says about itself is fixed here;
/// how matching works, where the index lives and whether anything is remembered
/// between queries all sit behind [BookTextSearch] and are free to move.
///
/// **What this screen stops at.** A row is drawn and opens nothing: it carries a
/// locator, and how the reader travels to it, whether the match stays marked on
/// arrival and whether there is a way back to where the search started are the
/// things golden 09 leaves open. The empty state is left open for the same
/// reason and is deliberately not invented here — see [_Count].
class BookTextSearchScreen extends StatefulWidget {
  const BookTextSearchScreen({super.key, required this.book, required this.search, this.initialQuery = ''});

  final Book book;

  /// Which places in this publication belong to a query. Injected for the
  /// reason golden 04's ranking is: golden 09 fixes the result, not the engine.
  final BookTextSearch search;

  /// What the field starts with. Empty for a reader, who came here to type.
  final String initialQuery;

  @override
  State<BookTextSearchScreen> createState() => _BookTextSearchScreenState();
}

class _BookTextSearchScreenState extends State<BookTextSearchScreen> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialQuery);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The reason to be here is to type, so the keyboard comes up on its own
    // rather than costing a tap on the only control on the screen. Unless the
    // field arrives with something in it: then there are results to look at, and
    // a keyboard over the lower half of them is the opposite of helpful. Same
    // rule golden 04's screen follows.
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

  @override
  Widget build(BuildContext context) {
    final query = _controller.text;
    // Searched on every keystroke, the way golden 04's screen searches the
    // shelf. Golden 09 leaves live-versus-on-submit open, and this follows the
    // sibling screen that is already approved and built rather than answering
    // the question here; a source that cannot answer that fast is what turns it
    // into a real decision.
    final hits = widget.search.search(bookId: widget.book.id, query: query);

    return AutomationScreen(
      id: AutomationIds.screenBookTextSearch,
      readiness: () => const AutomationReadiness.ready(),
      child: Scaffold(
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: _Header(controller: _controller, focus: _focus, onChanged: (_) => setState(() {})),
            ),
            SliverToBoxAdapter(
              child: _Count(query: query, count: hits.length, minQueryLength: widget.search.minQueryLength),
            ),
            if (hits.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: BookTextSearchLayout.pageMargin),
                  child: _Card(hits: hits),
                ),
              ),
            // The list runs on under the home indicator, the same allowance
            // golden 01b and 02 made for the tab bar: overlapping for a moment
            // is fine, permanently out of reach is not.
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 24)),
          ],
        ),
      ),
    );
  }
}

/// Back, title, field. Golden 06's pushed-page header and golden 04's field, at
/// the geometry both already carry: the title band on 62, the field on 109.
class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.focus, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top + 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: BookTextSearchLayout.headerHeight,
            child: Row(
              children: [
                // Golden 06's own back glyph rather than a Material
                // `IconButton`: the arrow sits on 16 and the title on 56, which
                // is where golden 09 says its header stands, and a 48 pt button
                // would put the title at 48 and outgrow the 32 pt band.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: SizedBox(
                    width: BookTextSearchLayout.pageMargin + 40,
                    height: BookTextSearchLayout.headerHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: BookTextSearchLayout.pageMargin),
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
                    t.books.searchInBook,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                  ),
                ),
                const SizedBox(width: BookTextSearchLayout.pageMargin),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BookTextSearchLayout.pageMargin),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: BookTextSearchLayout.surface,
                borderRadius: BorderRadius.circular(BookTextSearchLayout.fieldRadius),
              ),
              child: SizedBox(
                height: BookTextSearchLayout.fieldHeight,
                child: Row(
                  children: [
                    const SizedBox(width: BookTextSearchLayout.fieldPadding),
                    AppIcon(
                      Symbols.search_rounded,
                      size: BookTextSearchLayout.fieldGlyph,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: BookTextSearchLayout.fieldGap),
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
                          ? const SizedBox(width: BookTextSearchLayout.fieldPadding)
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                controller.clear();
                                onChanged('');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: BookTextSearchLayout.fieldPadding),
                                child: AppIcon(
                                  Symbols.close_rounded,
                                  size: BookTextSearchLayout.fieldGlyph,
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

/// `12 resultaten gevonden`, on the band golden 04 gives its chip row.
///
/// **It only speaks once a search has run.** An empty field and a query under
/// the source's own floor are not a query, and `Geen resultaten gevonden` under
/// either of them would be a claim about a search that never happened. The floor
/// is asked of the source rather than assumed here, because how short is too
/// short is a property of the engine.
///
/// A query that ran and found nothing gets that line and no card. That is the
/// approved furniture of this screen saying what is true, and deliberately not
/// an empty state: golden 09 leaves the empty state open on purpose, because one
/// book is a small corpus and a query that finds nothing there is not an edge
/// case. Inventing a composition for it here would be answering a question the
/// golden holds open.
class _Count extends StatelessWidget {
  const _Count({required this.query, required this.count, required this.minQueryLength});

  final String query;
  final int count;
  final int minQueryLength;

  bool get _ran => query.trim().length >= minQueryLength;

  @override
  Widget build(BuildContext context) {
    // The band the count would have occupied, so the card keeps its place under
    // the field whether or not there is anything to count.
    if (!_ran) {
      return const SizedBox(
        height: BookTextSearchLayout.cardTop - BookTextSearchLayout.fieldTop - BookTextSearchLayout.fieldHeight,
      );
    }
    final label = switch (count) {
      0 => t.books.searchInBookNoResults,
      1 => t.books.searchInBookOneResult,
      _ => t.books.searchInBookResults(count: count),
    };
    return Padding(
      // The count band sits 16 under the field and the card 12 under the count.
      padding: const EdgeInsets.fromLTRB(BookTextSearchLayout.pageMargin, 16, BookTextSearchLayout.pageMargin, 12),
      child: AutomationNode(
        id: AutomationIds.bookTextSearchCount,
        role: 'label',
        // Content-sized, not a box of 18. The line band *is* 18 at text scale
        // 1.0, which is the number the golden was measured with; a fixed box
        // would clip the line the moment the reader turns Larger Text on.
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: BookTextSearchLayout.countSize,
            height: BookTextSearchLayout.countHeight / BookTextSearchLayout.countSize,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// One rounded card with hairlines between the rows, the shape golden 04 chose
/// over the comp's card-per-row and golden 06 kept.
///
/// Twelve separate cards would be twelve heights that each want their own space
/// around them, on rows that already differ in height.
class _Card extends StatelessWidget {
  const _Card({required this.hits});

  final List<BookSearchHit> hits;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(BookTextSearchLayout.cardRadius),
      child: ColoredBox(
        color: BookTextSearchLayout.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The node sits on the row, not around the list: a node around a
            // sliver has no bounds, and then a geometry assertion has nothing to
            // measure. The instance is the locator, because two results can
            // share a chapter and a page label — golden 09a draws exactly that
            // pair — and an index would point at a different place as soon as
            // the query changes.
            //
            // The hairline belongs to the row and not between the rows: a
            // separator with a height of its own would push every row after the
            // first one point down the card, and the eighth would no longer
            // reach the bottom edge on 807.
            for (var i = 0; i < hits.length; i++)
              AutomationNode(
                id: AutomationIds.bookTextSearchResult,
                instance: hits[i].locator.value,
                role: 'list.item',
                child: BookTextSearchRow(hit: hits[i], showsHairline: i > 0),
              ),
          ],
        ),
      ),
    );
  }
}
