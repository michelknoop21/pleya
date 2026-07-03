import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/card_focus_scope.dart';
import '../../media/media_item.dart';
import '../../media/media_role.dart';
import '../../media/media_server_client.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_image_helper.dart';
import '../../widgets/focus_builders.dart';
import '../../widgets/horizontal_scroll_with_arrows.dart';
import '../../widgets/optimized_media_image.dart';

/// Horizontal cast row for the media detail screen, with the locked-focus
/// pattern for D-pad navigation. Extracted from `MediaDetailScreen`; the
/// screen keeps owning focus/scroll/index state and passes it in, so
/// behaviour is unchanged. Uses the same layout pattern as seasons/extras.
class CastSection extends StatelessWidget {
  final MediaItem metadata;
  final double cardWidth;
  final MediaServerClient? client;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final ScrollController scrollController;
  final int focusedIndex;
  final void Function(MediaRole actor) onActorTap;

  const CastSection({
    super.key,
    required this.metadata,
    required this.cardWidth,
    required this.client,
    required this.focusNode,
    required this.onKeyEvent,
    required this.scrollController,
    required this.focusedIndex,
    required this.onActorTap,
  });

  @override
  Widget build(BuildContext context) {
    const innerPadding = 3.0;
    final imageSize = cardWidth;
    // image + inner padding + text area + outer list padding + focus scale headroom
    final containerHeight = imageSize + innerPadding * 2 + 58 + 10;

    final theme = Theme.of(context);
    final actorNameStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: .w600);
    final actorRoleStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

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
                itemCount: metadata.roles!.length,
                itemBuilder: (context, index) {
                  final actor = metadata.roles![index];
                  final isFocused = hasFocus && index == focusedIndex;

                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FocusBuilders.buildLockedFocusWrapper(
                      context: context,
                      isFocused: isFocused,
                      borderRadius: tokens(context).radiusSm,
                      onTap: () => onActorTap(actor),
                      delegateFocusBorder: true,
                      child: Padding(
                        padding: const EdgeInsets.all(innerPadding),
                        child: SizedBox(
                          width: cardWidth,
                          child: Column(
                            crossAxisAlignment: .start,
                            children: [
                              CardFocusBorder(
                                borderRadius: tokens(context).radiusSm,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                                  child: OptimizedMediaImage(
                                    client: client,
                                    imagePath: actor.thumbPath,
                                    width: imageSize,
                                    height: imageSize,
                                    fit: BoxFit.cover,
                                    imageType: ImageType.avatar,
                                    fallbackIcon: Symbols.person_rounded,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: .start,
                                  children: [
                                    Text(actor.tag, style: actorNameStyle, maxLines: 2, overflow: .ellipsis),
                                    if (actor.role != null) ...[
                                      const SizedBox(height: 2),
                                      Text(actor.role!, style: actorRoleStyle, maxLines: 1, overflow: .ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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
