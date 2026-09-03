/// One tappable cell in a mobile rail or grid: [MobileMediaCard] under
/// [MediaContextMenu].
///
/// Extracted from `MobileMediaRail`'s private `_RailCardCell` when fase 3
/// added the catalogue grid, which needs the same wiring. Behaviour-preserving:
/// the same widget in the same order with the same arguments, only the name
/// and the file changed.
///
/// Tap opens detail on the group's representative source (a read); long-press
/// opens today's context menu on that same item, unimproved until fase 5.
library;

import 'package:flutter/material.dart';

import '../../media/unified/unified_media_group.dart';
import '../../mixins/context_menu_tap_mixin.dart';
import '../media_context_menu.dart';
import 'mobile_media_card.dart';

class MobileMediaCardCell extends StatefulWidget {
  final UnifiedMediaGroup group;
  final MobileCardShape shape;
  final double width;

  /// Continue Watching's cells offer "Remove from Continue Watching" in the
  /// long-press menu; other cells do not.
  final bool isContinueWatching;

  final VoidCallback? onTap;

  const MobileMediaCardCell({
    super.key,
    required this.group,
    required this.shape,
    required this.width,
    this.isContinueWatching = false,
    required this.onTap,
  });

  @override
  State<MobileMediaCardCell> createState() => _MobileMediaCardCellState();
}

class _MobileMediaCardCellState extends State<MobileMediaCardCell> with ContextMenuTapMixin<MobileMediaCardCell> {
  @override
  Widget build(BuildContext context) {
    // `MobileMediaCard`'s own onTap/onLongPress, not a second wrapping
    // GestureDetector: `Pressable` always registers onTapUp/onTapCancel
    // (unconditionally, regardless of whether onTap is null), so an outer
    // detector never sees the tap win the gesture arena over that inner one.
    return MediaContextMenu(
      key: contextMenuKey,
      item: widget.group.representativeSource.item,
      isInContinueWatching: widget.isContinueWatching,
      onTap: widget.onTap,
      child: MobileMediaCard(
        group: widget.group,
        shape: widget.shape,
        width: widget.width,
        onTap: widget.onTap,
        onLongPress: showContextMenu,
      ),
    );
  }
}
