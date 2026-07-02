import 'package:flutter/material.dart';

import '../media/media_hub.dart';
import '../theme/mono_tokens.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/platform_detector.dart';
import 'horizontal_scroll_with_arrows.dart';
import 'media_card.dart';

/// Netflix-style "Top 10" row: each poster is preceded by a large outlined
/// rank numeral in the display font. Reuses [MediaCard] for the poster so
/// tap / context-menu / focus behaviour stays identical to every other row.
///
/// A heuristic in discover_screen picks which hubs render with this variant
/// (ids/titles containing "popular", "top" or "trending").
class TopTenRow extends StatelessWidget {
  final MediaHub hub;
  final void Function(String itemId)? onRefresh;

  const TopTenRow({super.key, required this.hub, this.onRefresh});

  /// Heuristic: does this hub look like a ranked "top / popular / trending" list?
  static bool matches(MediaHub hub) {
    final haystack = '${hub.id} ${hub.identifier ?? ''} ${hub.title}'.toLowerCase();
    return haystack.contains('top') ||
        haystack.contains('popular') ||
        haystack.contains('trending') ||
        haystack.contains('meest bekeken') ||
        haystack.contains('populair');
  }

  @override
  Widget build(BuildContext context) {
    final items = hub.items.take(10).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final isTv = PlatformDetector.isTV();
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize: isTv ? 26 : null,
      fontWeight: FontWeight.w700,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = GridSizeCalculator.getCellWidth(constraints.maxWidth, context, 1).clamp(96.0, 200.0);
        final cardHeight = cardWidth * 1.5;
        // Numeral column is a little narrower than the poster.
        final numeralWidth = cardWidth * 0.72;

        Widget entry(int index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RankNumeral(rank: index + 1, width: numeralWidth, height: cardHeight),
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: MediaCard(
                  item: items[index],
                  width: cardWidth,
                  height: cardHeight,
                  forceGridMode: true,
                  onRefresh: onRefresh,
                ),
              ),
            ],
          ),
        );

        ListView buildList([ScrollController? controller]) => ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: isTv ? 40 : 12),
          itemCount: items.length,
          itemBuilder: (context, index) => entry(index),
        );

        final list = PlatformDetector.isDesktop(context)
            ? HorizontalScrollWithArrows(builder: (controller) => buildList(controller))
            : buildList();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isTv ? 44 : 16, isTv ? 6 : 4, 8, 6),
              child: Text(hub.title, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            SizedBox(height: cardHeight, child: list),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _RankNumeral extends StatelessWidget {
  final int rank;
  final double width;
  final double height;

  const _RankNumeral({required this.rank, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    // Large hollow numeral in the display font: stroked outline, no fill.
    final stroke = tokens(context).textMuted.withValues(alpha: 0.55);
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.bottomLeft,
        child: Text(
          '$rank',
          style: TextStyle(
            fontFamily: 'ArchivoBlack',
            fontWeight: FontWeight.w900,
            height: 0.78,
            letterSpacing: -8,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = stroke,
          ),
        ),
      ),
    );
  }
}
