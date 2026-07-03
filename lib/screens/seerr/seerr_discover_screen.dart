import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../models/seerr/seerr_media.dart';
import '../../providers/seerr_provider.dart';
import '../../services/seerr/seerr_client.dart';
import '../../services/seerr/seerr_constants.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/seerr_request_sheet.dart';
import '../../widgets/seerr_status_badge.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/state_view.dart';

/// Jellyseerr / Overseerr ("seerr") discover browse screen.
///
/// Shows a stack of horizontal poster rows (Trending, Popular movies, Popular
/// TV, Upcoming movies). Each row owns its own pagination: reaching the trailing
/// "Load more" tile (via focus or tap) appends the next page. Availability
/// badges come straight from each [SeerrMedia.status] (no extra calls). Tapping
/// a poster opens the request flow via [SeerrRequestSheet.show].
///
/// Deliberately does *not* reuse [HubSection]/[FocusableMediaCard]: those are
/// bound to the app's own [MediaItem]/[MediaHub] types, whereas seerr results
/// are [SeerrMedia]. We reuse the lower-level focus + layout primitives
/// (`FocusableWrapper`, `FocusedScrollScaffold`, `TvLayoutConstants`,
/// `SkeletonHubRow`, `StateView`) instead.
class SeerrDiscoverScreen extends StatefulWidget {
  const SeerrDiscoverScreen({super.key});

  @override
  State<SeerrDiscoverScreen> createState() => _SeerrDiscoverScreenState();
}

class _SeerrDiscoverScreenState extends State<SeerrDiscoverScreen> {
  SeerrClient? _client;
  late final List<_SeerrRow> _rows;

  @override
  void initState() {
    super.initState();
    _client = context.read<SeerrProvider>().client;
    _rows = [
      _SeerrRow(title: t.seerr.trending, fetch: (c, p) => c.discoverTrending(page: p)),
      _SeerrRow(title: t.seerr.popularMovies, fetch: (c, p) => c.discoverMovies(page: p)),
      _SeerrRow(title: t.seerr.popularTv, fetch: (c, p) => c.discoverTv(page: p)),
      _SeerrRow(title: t.seerr.upcoming, fetch: (c, p) => c.discoverUpcomingMovies(page: p)),
    ];
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    final client = _client;
    if (client == null) return;
    await Future.wait(_rows.map((row) => _loadFirst(row, client)));
  }

  Future<void> _loadFirst(_SeerrRow row, SeerrClient client) async {
    try {
      final page = await row.fetch(client, 1);
      if (!mounted) return;
      setState(() {
        row.items = page.items;
        row.page = page.page;
        row.totalPages = page.totalPages;
        row.loadingFirst = false;
      });
    } catch (e) {
      // Broad catch so a non-Seerr parse error can't leave the row stuck on its
      // skeleton forever (which would also wedge the whole-screen empty state).
      if (!mounted) return;
      setState(() {
        row.loadingFirst = false;
        row.errored = true;
        row.network = e is SeerrException && e.isNetwork;
      });
    }
  }

  Future<void> _loadMore(_SeerrRow row) async {
    final client = _client;
    if (client == null || row.loadingMore || row.page >= row.totalPages) return;
    setState(() => row.loadingMore = true);
    try {
      final page = await row.fetch(client, row.page + 1);
      if (!mounted) return;
      setState(() {
        row.items = [...row.items, ...page.items];
        row.page = page.page;
        row.totalPages = page.totalPages;
        row.loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => row.loadingMore = false);
    }
  }

  Future<void> _retry() async {
    setState(() {
      for (final row in _rows) {
        row.reset();
      }
    });
    await _loadAll();
  }

  bool get _allLoaded => _rows.every((r) => !r.loadingFirst);
  bool get _allErrored => _rows.every((r) => r.errored);
  bool get _anyNetworkError => _rows.any((r) => r.errored && r.network);
  bool get _allEmpty => _rows.every((r) => r.items.isEmpty);

  @override
  Widget build(BuildContext context) {
    // React to the session being torn down (disconnect / profile switch).
    final client = context.watch<SeerrProvider>().client;
    if (client == null) {
      return FocusedScrollScaffold(
        title: Text(t.seerr.discoverTitle),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: StateView.empty(title: t.seerr.noResults, icon: Symbols.movie_rounded),
          ),
        ],
      );
    }

    return FocusedScrollScaffold(
      title: Text(t.seerr.discoverTitle),
      slivers: _buildSlivers(),
    );
  }

  List<Widget> _buildSlivers() {
    // Fatal: every row failed to load its first page.
    if (_allLoaded && _allErrored) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.error(
            title: _anyNetworkError ? t.seerr.errorNetwork : t.seerr.errorGeneric,
            icon: Symbols.cloud_off_rounded,
            onRetry: _retry,
            retryLabel: t.common.retry,
          ),
        ),
      ];
    }

    // All rows loaded successfully but empty.
    if (_allLoaded && !_allErrored && _allEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StateView.empty(title: t.seerr.noResults, icon: Symbols.movie_rounded),
        ),
      ];
    }

    final slivers = <Widget>[];
    for (final row in _rows) {
      if (row.loadingFirst) {
        slivers.add(SliverToBoxAdapter(child: _RowHeaderSkeleton(title: row.title)));
        continue;
      }
      // Skip a row that finished empty (errored or genuinely no results) while
      // other rows still have content.
      if (row.items.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: _SeerrRowView(
            row: row,
            onTapItem: _openRequest,
            onLoadMore: () => _loadMore(row),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    return slivers;
  }

  Future<void> _openRequest(SeerrMedia media) => SeerrRequestSheet.show(context, media: media);
}

/// Mutable per-row pagination state.
class _SeerrRow {
  _SeerrRow({required this.title, required this.fetch});

  final String title;
  final Future<SeerrMediaPage> Function(SeerrClient client, int page) fetch;

  List<SeerrMedia> items = const [];
  int page = 0;
  int totalPages = 1;
  bool loadingFirst = true;
  bool loadingMore = false;
  bool errored = false;
  bool network = false;

  bool get hasMore => page < totalPages;

  void reset() {
    items = const [];
    page = 0;
    totalPages = 1;
    loadingFirst = true;
    loadingMore = false;
    errored = false;
    network = false;
  }
}

// -----------------------------------------------------------------------------
// Row view
// -----------------------------------------------------------------------------

double get _posterWidth => PlatformDetector.isTV() ? 150 : 120;
double get _posterHeight => _posterWidth * 3 / 2; // TMDB posters are 2:3.
double get _rowInset => PlatformDetector.isTV() ? TvLayoutConstants.horizontalInset : 16;

/// A single horizontal poster row with a header and an optional trailing
/// "Load more" tile.
class _SeerrRowView extends StatelessWidget {
  const _SeerrRowView({required this.row, required this.onTapItem, required this.onLoadMore});

  final _SeerrRow row;
  final ValueChanged<SeerrMedia> onTapItem;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // poster + gap + two title lines + year.
    final rowHeight = _posterHeight + 56;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _rowInset),
            child: Text(
              row.title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: _rowInset),
              itemCount: row.items.length + (row.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index >= row.items.length) {
                  return _LoadMoreTile(loading: row.loadingMore, onActivate: onLoadMore);
                }
                final media = row.items[index];
                return _SeerrPosterCard(media: media, onTap: () => onTapItem(media));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A focusable poster card: image + availability badge + title/year.
class _SeerrPosterCard extends StatelessWidget {
  const _SeerrPosterCard({required this.media, required this.onTap});

  final SeerrMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableWrapper(
      onSelect: onTap,
      borderRadius: 8,
      semanticLabel: media.title,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _posterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    SizedBox(
                      width: _posterWidth,
                      height: _posterHeight,
                      child: _PosterImage(url: media.posterUrl),
                    ),
                    if (media.status != SeerrMediaStatus.unknown)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: SeerrStatusBadge(status: media.status, compact: true),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (media.year != null)
                Text(
                  media.year!,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _PosterPlaceholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, _) => const _PosterPlaceholder(),
      errorWidget: (context, _, _) => const _PosterPlaceholder(),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(Symbols.movie_rounded, color: scheme.onSurfaceVariant, size: 32)),
    );
  }
}

/// Trailing focusable tile that loads the next page. Loads on activation and
/// also opportunistically when it gains focus (d-pad reaches the row's end).
class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({required this.loading, required this.onActivate});

  final bool loading;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FocusableWrapper(
      onSelect: onActivate,
      onFocusChange: (focused) {
        if (focused) onActivate();
      },
      borderRadius: 8,
      semanticLabel: t.seerr.loadMore,
      child: GestureDetector(
        onTap: onActivate,
        child: SizedBox(
          width: _posterWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _posterWidth,
                height: _posterHeight,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: loading
                      ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Symbols.add_circle_rounded, color: scheme.onSurfaceVariant, size: 36),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.seerr.loadMore,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header + skeleton posters shown while a row loads its first page.
class _RowHeaderSkeleton extends StatelessWidget {
  const _RowHeaderSkeleton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _rowInset),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          SkeletonHubRow(cardWidth: _posterWidth, rowHeight: _posterHeight + 16),
        ],
      ),
    );
  }
}
