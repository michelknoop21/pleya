import 'package:flutter/material.dart';

import '../../media/media_item.dart';
import '../../widgets/focus_builders.dart';
import '../../widgets/horizontal_scroll_with_arrows.dart';
import '../../widgets/media_card.dart';

/// Horizontal extras (trailers/clips) row for the media detail screen, with
/// the locked-focus pattern for D-pad navigation. Extracted from
/// `MediaDetailScreen`; the screen keeps owning focus/scroll/index state and
/// passes it in, so behaviour is unchanged.
class ExtrasSection extends StatelessWidget {
  final List<MediaItem> extras;
  final double cardWidth;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final ScrollController scrollController;
  final int focusedIndex;
  final GlobalKey<MediaCardState> Function(int index) cardKeyFor;
  final void Function(MediaItem extra) onExtraTap;

  const ExtrasSection({
    super.key,
    required this.extras,
    required this.cardWidth,
    required this.focusNode,
    required this.onKeyEvent,
    required this.scrollController,
    required this.focusedIndex,
    required this.cardKeyFor,
    required this.onExtraTap,
  });

  @override
  Widget build(BuildContext context) {
    // 16:9 aspect ratio for clip thumbnails (cardWidth includes 8px padding on each side)
    final posterHeight = (cardWidth - 16) * (9 / 16);
    final containerHeight = posterHeight + 52;

    return Focus(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final hasFocus = focusNode.hasFocus;

          return SizedBox(
            height: containerHeight,
            child: HorizontalScrollWithArrows(
              controller: scrollController,
              builder: (scrollController) => ListView.builder(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(vertical: 5),
                itemCount: extras.length,
                itemBuilder: (context, index) {
                  final extra = extras[index];
                  final isFocused = hasFocus && index == focusedIndex;
                  final cardKey = cardKeyFor(index);

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FocusBuilders.buildLockedFocusWrapper(
                      context: context,
                      isFocused: isFocused,
                      onTap: () => onExtraTap(extra),
                      delegateFocusBorder: true,
                      child: MediaCard(
                        key: cardKey,
                        item: extra,
                        width: cardWidth,
                        height: posterHeight,
                        forceGridMode: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
