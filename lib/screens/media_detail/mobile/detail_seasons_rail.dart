import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_server_client.dart';
import '../../../theme/mono_theme.dart';
import '../../../widgets/optimized_media_image.dart';

/// The series' seasons as a poster rail (`.seas` in D-03, DEC-140): a tap
/// opens the season's own page. A partly watched season gets a progress bar,
/// an untouched one a badge with its episode count. Draws nothing for an
/// empty list. iPhone only.
class DetailSeasonsRail extends StatelessWidget {
  const DetailSeasonsRail({super.key, required this.seasons, required this.onOpen, this.client});

  final List<MediaItem> seasons;
  final void Function(MediaItem season) onOpen;
  final MediaServerClient? client;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          t.discover.seasonsHeading(n: seasons.length),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: .bold),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: .start,
            children: [
              for (var i = 0; i < seasons.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _SeasonPoster(
                  key: ValueKey('season-poster-${seasons[i].id}'),
                  season: seasons[i],
                  client: client,
                  onTap: () => onOpen(seasons[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SeasonPoster extends StatelessWidget {
  const _SeasonPoster({super.key, required this.season, required this.client, required this.onTap});

  final MediaItem season;
  final MediaServerClient? client;
  final VoidCallback onTap;

  static const _width = 130.0;
  static const _height = 195.0;

  @override
  Widget build(BuildContext context) {
    final total = season.leafCount ?? 0;
    final watched = (season.viewedLeafCount ?? 0).clamp(0, total);
    final left = total - watched;
    final partlyWatched = watched > 0 && left > 0;
    final subtitle = [
      if (total > 0) t.discover.seasonEpisodes(n: total),
      if (partlyWatched) t.discover.seasonEpisodesLeft(count: left),
    ].join(' · ');
    final muted = Colors.white.withValues(alpha: 0.7);

    return SizedBox(
      width: _width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: _width,
                height: _height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OptimizedMediaImage.poster(
                      client: client,
                      imagePath: season.thumbPath,
                      width: _width,
                      height: _height,
                    ),
                    if (partlyWatched)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        height: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: watched / total,
                            backgroundColor: Colors.white.withValues(alpha: 0.3),
                            color: kAccent,
                          ),
                        ),
                      ),
                    if (watched == 0 && total > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: const BoxDecoration(
                            color: Color(0xD1141414),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            '$left',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              season.title ?? '',
              maxLines: 1,
              overflow: .ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 2,
                overflow: .ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
          ],
        ),
      ),
    );
  }
}
