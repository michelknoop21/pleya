/// The mobile card family's single card: a poster or a 16:9 still, its
/// markers, and a two-line caption underneath. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 4 — the northstar's card shape
/// for Home rails and Verder kijken, distinct from [MediaCard], which still
/// serves Bibliotheken and desktop and does not take a [UnifiedMediaGroup].
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/provider_extensions.dart';
import '../app_icon.dart';
import '../media_card_grid_layout.dart';
import '../media_markers.dart';
import '../new_content_badge.dart';
import '../optimized_media_image.dart';
import '../pressable.dart';

/// Which artwork a [MobileMediaCard] draws: a 2:3 poster for a Home/landing
/// rail, or a 16:9 still for Verder kijken.
enum MobileCardShape { portrait, wide }

class MobileMediaCard extends StatelessWidget {
  final UnifiedMediaGroup group;
  final MobileCardShape shape;
  final double width;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MobileMediaCard({
    super.key,
    required this.group,
    required this.shape,
    required this.width,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final item = group.representativeSource.item;
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final aspect = shape == MobileCardShape.portrait ? 2 / 3 : 16 / 9;
    final height = width / aspect;
    final resumeFraction = resumeFractionFor(group);
    final newLabel = newBadgeLabel(item);
    final fallbackIcon = item.isShow || item.isSeason || item.isEpisode ? Symbols.tv_rounded : Symbols.movie_rounded;

    final poster = shape == MobileCardShape.portrait
        ? OptimizedMediaImage.poster(
            client: client,
            imagePath: item.posterThumb(),
            width: width,
            height: height,
            fallbackIcon: fallbackIcon,
            blurHash: item.posterBlurHash,
          )
        : OptimizedMediaImage.thumb(
            client: client,
            imagePath: item.thumbPath,
            width: width,
            height: height,
            fallbackIcon: fallbackIcon,
            blurHash: item.posterBlurHash,
          );

    return GestureDetector(
      onLongPress: onLongPress,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: .start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      poster,
                      if (group.hasMultipleSources)
                        Positioned(top: 6, left: 6, child: SourceCountCapsule(count: group.sources.length)),
                      if (group.watchState.isWatched)
                        const Positioned(top: 6, right: 6, child: WatchedTick())
                      else if (newLabel == 'NEW EPISODE')
                        const Positioned(top: 6, right: 6, child: NewEpisodeDot()),
                      if (resumeFraction != null)
                        Positioned(left: 0, right: 0, bottom: 0, child: ResumeLine(fraction: resumeFraction)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: MediaCardGridLayout.posterCaptionGap),
              Text(
                item.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MediaCardGridLayout.titleStyle.copyWith(color: DefaultTextStyle.of(context).style.color),
              ),
              _CaptionSubtitle(item: item, shape: shape),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptionSubtitle extends StatelessWidget {
  final MediaItem item;
  final MobileCardShape shape;

  const _CaptionSubtitle({required this.item, required this.shape});

  @override
  Widget build(BuildContext context) {
    final muted = tokens(context).textMuted;
    if (shape == MobileCardShape.wide) {
      final season = item.parentIndex;
      final episode = item.index;
      final label = season != null && episode != null
          ? t.unifiedCatalog.discovery.episodeLabel(season: season, episode: episode)
          : null;
      return Row(
        mainAxisSize: .min,
        children: [
          if (label != null) ...[
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MediaCardGridLayout.subtitleStyleFrom(DefaultTextStyle.of(context).style, color: muted),
              ),
            ),
            const SizedBox(width: 4),
            AppIcon(Symbols.info_rounded, size: 12, color: muted),
          ],
        ],
      );
    }

    final isSeries = item.kind == MediaKind.show || item.kind == MediaKind.season;
    final seasonCount = item.childCount;
    final trailing = isSeries
        ? (seasonCount != null && seasonCount > 0
              ? (seasonCount == 1 ? t.unifiedCatalog.oneSeason : t.unifiedCatalog.seasons(count: seasonCount))
              : null)
        : item.genres?.firstOrNull;
    final parts = [?item.year?.toString(), ?trailing].join(' · ');

    return Text(
      parts,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: MediaCardGridLayout.subtitleStyleFrom(DefaultTextStyle.of(context).style, color: muted),
    );
  }
}
