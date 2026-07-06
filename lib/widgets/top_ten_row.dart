import 'package:flutter/material.dart';

import '../media/media_hub.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/platform_detector.dart';
import 'horizontal_scroll_with_arrows.dart';
import 'media_card.dart';

/// Netflix-style "Top 10" row: each poster is preceded by a large outlined
/// rank numeral in the display font. Reuses [MediaCard] in full-bleed mode
/// (poster only, no caption) so tap / context-menu / focus stay identical to
/// every other row and there is no vertical overflow.
class TopTenRow extends StatelessWidget {
  final MediaHub hub;
  final void Function(String itemId)? onRefresh;

  const TopTenRow({super.key, required this.hub, this.onRefresh});

  /// Tight heuristic: only genuine ranked "Top 10 / trending" hubs, never a
  /// generic "Top films in `<genre>`" shelf.
  static bool matches(MediaHub hub) {
    final h = '${hub.id} ${hub.identifier ?? ''} ${hub.title}'.toLowerCase();
    return h.contains('top 10') || h.contains('top10') || h.contains('trending');
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
        // Poster width from the grid calculator, following the size slider
        // (libraryDensity) like the rest of the app; clamped so the ranked row
        // stays compact. Height is a fixed 2:3 so the row never overflows.
        final density = SettingsService.instance.read(SettingsService.libraryDensity);
        final cardWidth = GridSizeCalculator.getCellWidth(
          constraints.maxWidth,
          context,
          density,
        ).clamp(92.0, 190.0);
        final cardHeight = cardWidth * 1.5;
        final numeralWidth = cardWidth * 0.7;
        final rowHeight = cardHeight;

        Widget entry(int index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _RankNumeral(rank: index + 1, width: numeralWidth, height: rowHeight),
                SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: MediaCard(
                    item: items[index],
                    width: cardWidth,
                    height: cardHeight,
                    forceGridMode: true,
                    fullBleedImage: true,
                    onRefresh: onRefresh,
                  ),
                ),
              ],
            ),
          );
        }

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
            SizedBox(height: rowHeight, child: list),
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
            height: 0.9,
            letterSpacing: -8,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = stroke,
          ),
        ),
      ),
    );
  }
}
