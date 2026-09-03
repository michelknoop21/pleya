import 'package:flutter/material.dart';

import '../services/device_performance.dart';
import '../theme/mono_tokens.dart';
import 'skeleton_media_card.dart';

/// Skeleton placeholder with a subtle shimmer sweep on the full effects tier;
/// static semi-transparent fill on the reduced tier.
class SkeletonLoader extends StatefulWidget {
  final Widget? child;
  final BorderRadius? borderRadius;

  const SkeletonLoader({super.key, this.child, this.borderRadius});

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!DevicePerformance.isReduced) {
      _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.075);
    final radius = widget.borderRadius ?? BorderRadius.circular(tokens(context).radiusSm);
    final controller = _controller;

    if (controller == null) {
      return Container(
        decoration: BoxDecoration(color: base, borderRadius: radius),
        child: widget.child,
      );
    }

    final highlight = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Sweep center travels -0.3 → 1.3 so the band fully enters and exits.
        final t = -0.3 + controller.value * 1.6;
        return Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: .centerLeft,
              end: .centerRight,
              colors: [base, highlight, base],
              stops: [(t - 0.25).clamp(0.0, 1.0), t.clamp(0.0, 1.0), (t + 0.25).clamp(0.0, 1.0)],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

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
