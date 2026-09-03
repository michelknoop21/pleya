import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../automation/automation_screen.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/main_screen_scope.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile_avatar.dart';
import '../../providers/books_home_provider.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/pleya_logo.dart';
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
            SliverToBoxAdapter(child: _PageTitle(onSeeAll: rows.isEmpty ? null : () {})),
            if (rows.continueReading.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: BookRailHeader(title: t.books.continueReading, onSeeAll: () {}),
              ),
              SliverToBoxAdapter(
                child: AutomationNode(
                  id: AutomationIds.booksRailContinue,
                  role: 'rail',
                  child: _ContinueReadingRail(rows: rows),
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
                  child: BookRail(items: [for (final book in rows.recentlyAdded) BookRailItem.fromBook(book)]),
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
/// golden 01b repeats. Search lives here because DEC-069 took it out of the
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
              onPressed: () => MainScreenFocusScope.of(context, listen: false)?.openSearch?.call(),
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
  const _ContinueReadingRail({required this.rows});

  final BooksHomeRows rows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ContinueReadingCard.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BookRailMetrics.pageMargin),
        itemCount: rows.continueReading.length,
        separatorBuilder: (_, _) => const SizedBox(width: BookRailMetrics.gap),
        itemBuilder: (context, index) => ContinueReadingCard(book: rows.continueReading[index]),
      ),
    );
  }
}
