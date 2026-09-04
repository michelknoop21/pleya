import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_navigation_hooks.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../automation/pleya_verify.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile_avatar.dart';
import '../../books/book.dart';
import '../../providers/books_home_provider.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pleya_logo.dart';
import 'all_books_screen.dart';
import 'book_detail_screen.dart';
import 'books_search_screen.dart';
import 'widgets/book_rail.dart';
import 'widgets/continue_reading_card.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Boeken-home, built against approved golden 01b
/// (`docs/assets/ebooks/northstar/01b-books-home.png`).
///
/// The golden's two frames are one screen: the first is this page at rest, the
/// second is the same page scrolled far enough to show the Boekenseries
/// metadata. There is no second destination, and the bottom padding below is
/// what makes the second frame reachable.
class BooksHomeScreen extends StatefulWidget {
  const BooksHomeScreen({super.key});

  @override
  State<BooksHomeScreen> createState() => _BooksHomeScreenState();
}

class _BooksHomeScreenState extends State<BooksHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaitedLoad();
    });
    if (kPleyaVerify) {
      AutomationNavigationHooks.instance.registerRouteOpener(AutomationIds.screenAllBooks, _openAllBooks);
      AutomationNavigationHooks.instance.registerRouteOpener(AutomationIds.screenBooksSearch, _openSearch);
      AutomationNavigationHooks.instance.registerRouteOpener(AutomationIds.screenBookDetail, _openCanonicalDetail);
    }
  }

  @override
  void dispose() {
    if (kPleyaVerify) {
      AutomationNavigationHooks.instance.unregisterRouteOpener(AutomationIds.screenAllBooks, _openAllBooks);
      AutomationNavigationHooks.instance.unregisterRouteOpener(AutomationIds.screenBooksSearch, _openSearch);
      AutomationNavigationHooks.instance.unregisterRouteOpener(AutomationIds.screenBookDetail, _openCanonicalDetail);
    }
    super.dispose();
  }

  /// The same push the `Alle boeken ›` link performs, so a scenario and a
  /// reader take one route rather than two.
  void _openAllBooks() {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllBooksScreen()));
  }

  /// The same push the search glyph performs, so a scenario and a reader take
  /// one route rather than two, with one difference: the automation route
  /// lands on the canonical query of approved golden 04.
  ///
  /// That difference is not decoration. The iOS driver has no text-input
  /// endpoint (`typeText: no /v1/input/text endpoint exists yet`), so a
  /// scenario cannot type, and without a query there is no canonical state to
  /// photograph on hardware at all. The reader's own route, the search glyph,
  /// still opens an empty field; only the opener a scenario calls pre-fills
  /// it, and only in a `kPleyaVerify` build. What this buys is evidence that
  /// the three sections lay out on a device; what it does not cover is the
  /// typing itself, and the widget tests do that instead.
  void _openSearch() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BooksSearchScreen(initialQuery: _verifyCanonicalQuery)));
  }

  /// The query golden 04 is drawn with, and the one the fixed fixture answers
  /// with all three result kinds.
  static const String _verifyCanonicalQuery = 'dune';

  /// The book golden 05a is drawn with: the one state that carries a series
  /// line and reading progress, so a scenario photographs the canonical page
  /// rather than whichever book happens to be first on a rail.
  ///
  /// Same shape as [_openSearch]'s seeded query, and the same limit: a route
  /// opener is a `VoidCallback` keyed by screen id, so there is exactly one
  /// per screen and only one state of this page is reachable from a scenario.
  /// The unstarted state of `05b` is covered by widget tests instead.
  static const String _verifyCanonicalBookId = 'dune';

  void _openCanonicalDetail() {
    if (!mounted) return;
    final rows = context.read<BooksHomeProvider?>()?.rows ?? const BooksHomeRows();
    final book = rows.all.where((b) => b.id == _verifyCanonicalBookId).firstOrNull;
    if (book == null) return;
    _openDetail(book);
  }

  /// The push every cover on this page performs. On the nearest navigator, not
  /// the root: the browse UI hangs under `ProfileNavigationScope` and a route
  /// above it loses that scope.
  void _openDetail(Book book) {
    final series = context.read<BooksHomeProvider?>()?.rows.series ?? const <BookSeries>[];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(book: book, series: series),
      ),
    );
  }

  void unawaitedLoad() {
    final provider = context.read<BooksHomeProvider?>();
    if (provider != null && !provider.hasLoaded && !provider.isLoading) provider.load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BooksHomeProvider?>();
    final rows = provider?.rows ?? const BooksHomeRows();
    return AutomationScreen(
      id: AutomationIds.screenBooks,
      readiness: () => provider == null || provider.hasLoaded
          ? const AutomationReadiness.ready()
          : const AutomationReadiness.loading('books'),
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _BooksHeader()),
            SliverToBoxAdapter(child: _PageTitle(onSeeAll: rows.isEmpty ? null : _openAllBooks)),
            if (rows.continueReading.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: BookRailHeader(title: t.books.continueReading, onSeeAll: () {}),
              ),
              SliverToBoxAdapter(
                child: AutomationNode(
                  id: AutomationIds.booksRailContinue,
                  role: 'rail',
                  child: _ContinueReadingRail(rows: rows, onOpen: _openDetail),
                ),
              ),
            ],
            if (rows.recentlyAdded.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: BookRailHeader(title: t.books.recentlyAdded, onSeeAll: () {}),
              ),
              SliverToBoxAdapter(
                child: AutomationNode(
                  id: AutomationIds.booksRailRecent,
                  role: 'rail',
                  child: BookRail(
                    items: [
                      for (final book in rows.recentlyAdded)
                        BookRailItem.fromBook(book, onTap: () => _openDetail(book)),
                    ],
                  ),
                ),
              ),
            ],
            if (rows.series.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: BookRailHeader(title: t.books.bookSeries, onSeeAll: () {}),
              ),
              SliverToBoxAdapter(
                child: AutomationNode(
                  id: AutomationIds.booksRailSeries,
                  role: 'rail',
                  child: BookRail(
                    items: [for (final series in rows.series) BookRailItem.fromSeries(series)],
                    coverHeight: BookRailMetrics.seriesCoverHeight,
                  ),
                ),
              ),
            ],
            // The tab bar may cover content on the way past, never for good
            // (golden 01b's implementation requirement). This is the room the
            // last rail needs to clear it, plus the bar's own height, which
            // the shell draws over this scrollable rather than beside it.
            SliverToBoxAdapter(child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom)),
          ],
        ),
      ),
    );
  }
}

/// Wordmark left, search and profile right — the header golden 00 approved and
/// golden 01b repeats. Search lives here because DEC-094 took it out of the
/// bottom bar.
class _BooksHeader extends StatelessWidget {
  const _BooksHeader();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ActiveProfileProvider?>()?.active;
    return Padding(
      // Measured against approved golden 01b, not guessed: with `+ 12` the
      // wordmark landed 12.7 pt low and every row below it inherited the
      // offset, so the Boekenseries rail showed less than the golden does.
      padding: EdgeInsets.fromLTRB(16, MediaQuery.viewPaddingOf(context).top, 16, 0),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const PleyaLogo(size: 28),
            const SizedBox(width: 10),
            const Text('PLEYA', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 3.6)),
            const Spacer(),
            IconButton(
              // Boeken zoeken, not the whole-library search: approved golden
              // 04 scopes this glyph to books. `MainScreenFocusScope`'s
              // `openSearch` still belongs to the other surfaces.
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BooksSearchScreen())),
              icon: const AppIcon(Symbols.search_rounded),
              tooltip: t.common.search,
            ),
            const SizedBox(width: 4),
            if (profile != null) ProfileAvatar(profile: profile, size: 38, showLockBadge: false),
          ],
        ),
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              t.navigation.books,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.2),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Text(
                '${t.books.allBooks} ›',
                style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.62)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContinueReadingRail extends StatelessWidget {
  const _ContinueReadingRail({required this.rows, required this.onOpen});

  final BooksHomeRows rows;
  final void Function(Book book) onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ContinueReadingCard.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BookRailMetrics.pageMargin),
        itemCount: rows.continueReading.length,
        separatorBuilder: (_, _) => const SizedBox(width: BookRailMetrics.gap),
        itemBuilder: (context, index) {
          final book = rows.continueReading[index];
          return ContinueReadingCard(book: book, onTap: () => onOpen(book));
        },
      ),
    );
  }
}
