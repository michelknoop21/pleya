import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_wrapper.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_constants.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';
import 'pressable.dart';
import 'seerr_status_badge.dart';

/// Poster dimensions shared by every seerr surface (discover rows, grid, search
/// fallback, recommendations). TV gets slightly larger touch/focus targets.
double get seerrPosterWidth => PlatformDetector.isTV() ? 150 : 120;
double get seerrPosterHeight => seerrPosterWidth * 3 / 2; // TMDB posters are 2:3.

/// Fixed height of the text block under every poster (gap + two title lines +
/// year). One shared constant so rows and grids budget identical space and all
/// cards line up — nothing overflows, nothing clips. Add this to
/// [seerrPosterHeight] for the total card height / row height.
const double seerrCardTextExtent = 54;

/// A focusable seerr poster: artwork + availability badge + title/year.
///
/// Extracted from the discover screen so discover, search and the media detail
/// recommendations row all render identical cards. Tapping is left to the
/// caller (usually: open [SeerrMediaDetailScreen]).
class SeerrPosterCard extends StatelessWidget {
  const SeerrPosterCard({super.key, required this.media, required this.onTap, this.width});

  final SeerrMedia media;
  final VoidCallback onTap;

  /// Override the shared [seerrPosterWidth] (e.g. inside a fixed-size grid).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final w = width ?? seerrPosterWidth;
    final h = w * 3 / 2;
    return FocusableWrapper(
      onSelect: onTap,
      borderRadius: t.radiusSm,
      semanticLabel: media.title,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(t.radiusSm),
                child: Stack(
                  children: [
                    SizedBox(width: w, height: h, child: SeerrPosterImage(url: media.posterUrl)),
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
              // Fixed-height text block so every card lines up regardless of a
              // one- or two-line title / present-or-absent year.
              SizedBox(
                height: seerrCardTextExtent - 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.1),
                    ),
                    if (media.year != null)
                      Text(
                        media.year!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: t.textMuted,
                          fontSize: 11,
                          height: 1.1,
                        ),
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

/// A poster image with a graceful placeholder for empty/failed URLs.
class SeerrPosterImage extends StatelessWidget {
  const SeerrPosterImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SeerrPosterPlaceholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, _) => const SeerrPosterPlaceholder(),
      errorWidget: (context, _, _) => const SeerrPosterPlaceholder(),
    );
  }
}

class SeerrPosterPlaceholder extends StatelessWidget {
  const SeerrPosterPlaceholder({super.key});

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
class SeerrLoadMoreTile extends StatelessWidget {
  const SeerrLoadMoreTile({super.key, required this.loading, required this.onActivate, this.width});

  final bool loading;
  final VoidCallback onActivate;

  /// Override the shared [seerrPosterWidth] (e.g. inside a fixed-size grid).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = tokens(context).radiusSm;
    final w = width ?? seerrPosterWidth;
    return FocusableWrapper(
      onSelect: onActivate,
      onFocusChange: (focused) {
        if (focused) onActivate();
      },
      borderRadius: radius,
      semanticLabel: t.seerr.loadMore,
      child: Pressable(
        onTap: onActivate,
        child: SizedBox(
          width: w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: w,
                height: w * 3 / 2,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(radius),
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
