import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../media/media_server_client.dart';
import '../../../utils/media_image_helper.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/tv/tv_catalog_card_grid.dart';
import 'tv_detail_cards.dart';
import 'tv_detail_layout.dart';

const double _spoilerBlur = 30;

/// A wide card on the season row: the still, and in the corner what it is.
/// There is no text under it, the hero above names what has the focus.
class TvDetailEpisodeCard extends StatelessWidget {
  const TvDetailEpisodeCard({
    super.key,
    required this.cell,
    required this.imagePath,
    required this.client,
    required this.badge,
    required this.semanticLabel,
    required this.onSelect,
    this.watched = false,
    this.progress,
    this.blurred = false,
    this.onContextMenu,
    this.onFocused,
  });

  final TvCatalogGridCell cell;
  final String? imagePath;
  final MediaServerClient? client;

  /// `A1`, or the season's name on the card that stands for the whole season.
  final String badge;
  final bool watched;

  /// How far through the episode this is.
  final double? progress;

  /// Spoiler protection: an unwatched still under the setting that hides them.
  final bool blurred;
  final String semanticLabel;
  final VoidCallback onSelect;
  final VoidCallback? onContextMenu;
  final VoidCallback? onFocused;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final radius = TvDetailLayout.reviewCardRadius * pt;
    final fraction = progress;
    return TvDetailFocusCard(
      cell: cell,
      semanticLabel: semanticLabel,
      onSelect: onSelect,
      onContextMenu: onContextMenu,
      onFocused: onFocused,
      radius: radius,
      artwork: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: TvDetailLayout.wideCardHeight * pt,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                enabled: blurred,
                imageFilter: ImageFilter.blur(sigmaX: _spoilerBlur, sigmaY: _spoilerBlur),
                child: OptimizedMediaImage(
                  client: client,
                  imagePath: imagePath,
                  fit: BoxFit.cover,
                  imageType: ImageType.thumb,
                  fallbackIcon: Symbols.movie_rounded,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: _Badge(label: badge, watched: watched, pt: pt),
              ),
              if (fraction != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6 * pt,
                    color: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.watched, required this.pt});

  final String label;
  final bool watched;
  final double pt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * pt, vertical: 6 * pt),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12 * pt)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (watched) ...[
            AppIcon(Symbols.check_rounded, fill: 1, size: TvHig.caption2 * pt, color: Colors.white),
            SizedBox(width: 8 * pt),
          ],
          Text(
            label,
            maxLines: 1,
            style: TextStyle(color: Colors.white, fontSize: TvHig.caption2 * pt, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
