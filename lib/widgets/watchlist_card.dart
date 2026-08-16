import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_wrapper.dart';
import '../i18n/strings.g.dart';
import '../media/watchlist_entry.dart';
import '../theme/mono_tokens.dart';
import '../utils/media_image_helper.dart';
import '../focus/card_focus_scope.dart';
import 'pressable.dart';
import 'focusable_media_card.dart';

/// Vertical space a watchlist card reserves for its title and year block,
/// on top of the 2:3 poster. Shared with the grid so the cell height and the
/// card height cannot drift apart.
const double watchlistCardTextExtent = 46;

/// One title on the kijklijst.
///
/// A thin dispatcher rather than a new card. A playable title renders through
/// [FocusableMediaCard] with its real server item, so it behaves exactly like
/// the same title anywhere else in the app: same context menu, same tap
/// target, same focus treatment. Only a title with nothing to play falls
/// through to [WatchlistUnavailableCard].
///
/// [MediaCard] itself was deliberately not extended. It is a thousand lines
/// built around [MediaItem] and [MediaPlaylist], and a discover title is
/// neither. The repo's own precedent runs the other way: `SeerrPosterCard` is
/// a separate card for exactly this reason.
///
/// Both branches render at the same [width] and [height], because a card that
/// is wider than its grid cell gets its top clipped by the SliverGrid.
class WatchlistCard extends StatelessWidget {
  const WatchlistCard({
    super.key,
    required this.entry,
    required this.isPlayable,
    required this.onTap,
    required this.width,
    required this.height,
    this.focusNode,
  });

  final WatchlistEntry entry;

  /// Decided by `WatchlistProvider.isPlayable`, which weighs both an online
  /// server and a finished download.
  final bool isPlayable;

  /// Only used for the unavailable branch; a playable card opens the normal
  /// detail route through [FocusableMediaCard].
  final VoidCallback onTap;

  final double width;
  final double height;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final match = entry.lastKnownMatch;
    if (isPlayable && match != null) {
      return FocusableMediaCard(item: match, width: width, height: height, focusNode: focusNode);
    }
    return WatchlistUnavailableCard(entry: entry, onTap: onTap, width: width, height: height, focusNode: focusNode);
  }
}

/// A watchlist title that cannot be played from here, in one of three
/// treatments for four model states.
///
/// | state      | treatment                                          |
/// | ---------- | -------------------------------------------------- |
/// | unknown    | plain card, no indicator; nothing is scheduled yet  |
/// | checking   | plain card plus a small spinner; a lookup is live   |
/// | available  | never reaches here; it renders as a playable card   |
/// | notFound   | dimmed and desaturated, with a "Not available" badge|
///
/// There is no green tick on available titles. In a media app a check reads as
/// watched, finished or selected, and available is simply the normal state.
/// The dimming on notFound is deliberately light: it is still real content the
/// user can request, not a disabled control.
class WatchlistUnavailableCard extends StatelessWidget {
  const WatchlistUnavailableCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.width,
    required this.height,
    this.focusNode,
  });

  final WatchlistEntry entry;
  final VoidCallback onTap;
  final double width;
  final double height;
  final FocusNode? focusNode;

  /// Opacity for a title none of the reachable servers has.
  static const double notFoundOpacity = 0.82;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final notFound = entry.availability == WatchlistAvailability.notFound;
    final posterHeight = (height - watchlistCardTextExtent).clamp(0.0, height);

    Widget poster = _WatchlistPoster(entry: entry, width: width, height: posterHeight);
    if (notFound) {
      poster = Opacity(
        opacity: notFoundOpacity,
        child: ColorFiltered(
          // Pull roughly a third of the saturation out. Enough to read as set
          // apart in a grid, not enough to look broken.
          colorFilter: const ColorFilter.matrix(_desaturate),
          child: poster,
        ),
      );
    }

    return FocusableWrapper(
      onSelect: onTap,
      focusNode: focusNode,
      borderRadius: tk.radiusSm,
      delegateFocusBorder: true,
      semanticLabel: entry.item.title,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CardFocusBorder(
                borderRadius: tk.radiusSm,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tk.radiusSm),
                  child: Stack(
                    children: [
                      poster,
                      if (entry.availability == WatchlistAvailability.checking)
                        const Positioned(top: 6, right: 6, child: _CheckingSpinner()),
                      if (notFound) Positioned(left: 6, bottom: 6, right: 6, child: _NotAvailableBadge()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: watchlistCardTextExtent - 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.item.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                    if (entry.item.year != null)
                      Text(
                        '${entry.item.year}',
                        style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted, fontSize: 11, height: 1.1),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalogue poster, sized through the public proxy so no token is involved.
class _WatchlistPoster extends StatelessWidget {
  const _WatchlistPoster({required this.entry, required this.width, required this.height});

  final WatchlistEntry entry;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final url = MediaImageHelper.catalogPosterUrl(
      entry.posterRef,
      width: (width * dpr).round(),
      height: (height * dpr).round(),
    );

    return SizedBox(
      width: width,
      height: height,
      child: url.isEmpty
          ? const _PosterPlaceholder()
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (context, _) => const _PosterPlaceholder(),
              errorBuilder: (context, _, _) => const _PosterPlaceholder(),
            ),
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

/// Minimal progress ring, no text. A lookup that resolves in a few hundred
/// milliseconds does not deserve a label the eye has to read.
class _CheckingSpinner extends StatelessWidget {
  const _CheckingSpinner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
      child: const Padding(
        padding: EdgeInsets.all(5),
        child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _NotAvailableBadge extends StatelessWidget {
  const _NotAvailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(4)),
      child: Text(
        t.watchlist.notAvailable,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.2),
      ),
    );
  }
}

/// Saturation at roughly 0.65, in the 5x4 matrix ColorFilter wants.
const List<double> _desaturate = [
  0.7551, 0.2087, 0.0362, 0, 0, //
  0.1071, 0.8567, 0.0362, 0, 0, //
  0.1071, 0.2087, 0.6842, 0, 0, //
  0, 0, 0, 1, 0, //
];
