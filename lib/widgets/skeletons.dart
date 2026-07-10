import 'package:flutter/widgets.dart';

import 'media_card.dart';
import 'skeleton_media_card.dart';

/// Skeleton family built on [SkeletonLoader] (shimmer sweep on the full
/// effects tier, static fill on the reduced tier — handled inside
/// [SkeletonLoader] itself, no extra gating needed here).
///
/// Placeholder for a horizontal hub row: title shimmer + a run of
/// [SkeletonMediaCard]s. Mirrors the layout of a real hub section so content
/// doesn't jump when it lands.
class SkeletonHubRow extends StatelessWidget {
  final int cardCount;
  final double cardWidth;
  final double rowHeight;

  const SkeletonHubRow({super.key, this.cardCount = 5, this.cardWidth = 140, this.rowHeight = 200});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          const SkeletonLoader(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: SizedBox(width: 200, height: 24),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: rowHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cardCount,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(width: cardWidth, child: const SkeletonMediaCard()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for a list-mode media row: poster rect + title/meta/summary
/// shimmer lines, mirroring the list layout of a real media card.
class SkeletonListTile extends StatelessWidget {
  final double posterWidth;
  final double posterHeight;

  const SkeletonListTile({super.key, this.posterWidth = 60, this.posterHeight = 90});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          SkeletonLoader(
            child: SizedBox(width: posterWidth, height: posterHeight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: const [
                SkeletonLoader(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                  child: SizedBox(height: 14, width: double.infinity),
                ),
                SizedBox(height: 6),
                FractionallySizedBox(
                  alignment: .centerLeft,
                  widthFactor: 0.5,
                  child: SkeletonLoader(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    child: SizedBox(height: 11),
                  ),
                ),
                SizedBox(height: 6),
                FractionallySizedBox(
                  alignment: .centerLeft,
                  widthFactor: 0.8,
                  child: SkeletonLoader(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    child: SizedBox(height: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
