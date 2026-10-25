import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Scroll the nearest scrollable ancestor so [context] is centered.
///
/// Uses [Scrollable.ensureVisible] with alignment 0.5 (center).
/// Runs in a post-frame callback to ensure layout is complete.
void scrollContextToCenter(BuildContext? context) {
  if (context == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  });
}

/// Jump a vertical [ListView] so that [currentIndex] is visible.
///
/// Measures the first item (via [firstItemKey]) to get the real item height,
/// then scrolls to `currentIndex * itemHeight`, clamped to max extent.
/// Call once after the first build; the callback is a no-op if the key or
/// controller aren't ready yet.
void scrollToCurrentItem(ScrollController controller, GlobalKey firstItemKey, int currentIndex) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    final itemHeight = (firstItemKey.currentContext?.findRenderObject() as RenderBox?)?.size.height;
    if (itemHeight == null) return;
    final maxExtent = controller.position.maxScrollExtent;
    if (!maxExtent.isFinite) return;
    final target = (currentIndex * itemHeight).clamp(0.0, maxExtent);
    controller.jumpTo(target);
  });
}

/// Owns the boilerplate for one-time initial scrolling in selectable lists.
class InitialItemScrollController {
  final GlobalKey firstItemKey = GlobalKey();
  final ScrollController controller = ScrollController();
  bool _didInitialScroll = false;

  void maybeScrollTo(int? selectedIndex) {
    if (_didInitialScroll || selectedIndex == null || selectedIndex <= 0) return;
    _didInitialScroll = true;
    scrollToCurrentItem(controller, firstItemKey, selectedIndex);
  }

  void dispose() => controller.dispose();
}

/// Scroll a horizontal list to center the item at the given index.
///
/// Assumes items are laid out with [leadingPadding] before the first item,
/// and each item occupies [itemExtent] pixels (including per-item padding).
void scrollListToIndex(
  ScrollController controller,
  int index, {
  required double itemExtent,
  double leadingPadding = 12.0,
  bool animate = true,
}) {
  if (controller.positions.length != 1 || itemExtent <= 0) return;

  final viewport = controller.position.viewportDimension;
  final maxExtent = controller.position.maxScrollExtent;
  if (!viewport.isFinite || !maxExtent.isFinite) return;
  final targetCenter = leadingPadding + (index * itemExtent) + (itemExtent / 2);
  final desiredOffset = (targetCenter - (viewport / 2)).clamp(0.0, maxExtent);

  if (animate) {
    unawaited(controller.animateTo(desiredOffset, duration: const Duration(milliseconds: 150), curve: Curves.easeOut));
  } else {
    controller.jumpTo(desiredOffset);
  }
}

/// Scroll a horizontal list so the keyed child is centered using its real layout
/// bounds. This corrects small per-item extent drift in long carousels.
void scrollKeyedChildToHorizontalCenter(
  ScrollController controller,
  GlobalKey key, {
  bool animate = true,
  int maxAttempts = 2,
  bool Function()? isCurrent,
}) {
  void schedule(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrent?.call() == false) return;

      final context = key.currentContext;
      if (context == null) {
        if (attempt < maxAttempts) schedule(attempt + 1);
        return;
      }

      final didResolve = _scrollContextToHorizontalCenterNow(controller, context, animate: animate);
      if (!didResolve && attempt < maxAttempts) schedule(attempt + 1);
    });
  }

  schedule(0);
}

bool _scrollContextToHorizontalCenterNow(ScrollController controller, BuildContext context, {required bool animate}) {
  if (!context.mounted || controller.positions.length != 1) return true;

  final position = controller.position;
  if (position.axis != Axis.horizontal) return true;

  final renderObject = context.findRenderObject();
  if (renderObject == null || !renderObject.attached) return false;

  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (viewport == null) return false;

  final target = viewport
      .getOffsetToReveal(renderObject, 0.5)
      .offset
      .clamp(position.minScrollExtent, position.maxScrollExtent)
      .toDouble();
  if ((target - position.pixels).abs() < 0.5) return true;

  if (animate) {
    unawaited(controller.animateTo(target, duration: const Duration(milliseconds: 150), curve: Curves.easeOut));
  } else {
    controller.jumpTo(target);
  }
  return true;
}

/// Non-focusable space after the last carousel card, so it can reach the lead.
double carouselTrailingSpace(double viewport, double leading, double lastItemExtent) =>
    (viewport - leading - lastItemExtent).clamp(0.0, double.infinity).toDouble();

/// Each TV carousel owns its card geometry; they share this leading-anchor motion.
void scrollCarouselToLeading(
  ScrollController controller,
  double itemOffset, {
  bool animate = true,
  Duration duration = const Duration(milliseconds: 150),
  BuildContext? childContext,
  double leadingInset = 0,
}) {
  if (controller.positions.length != 1) return;
  final position = controller.position;
  if (!position.hasContentDimensions || !itemOffset.isFinite) return;
  final child = childContext?.mounted == true ? childContext!.findRenderObject() : null;
  final viewport = child == null ? null : RenderAbstractViewport.maybeOf(child);
  final offset = child == null || viewport == null
      ? itemOffset
      : viewport.getOffsetToReveal(child, 0).offset - leadingInset;
  final target = offset.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
  if (!animate || duration == Duration.zero) {
    controller.jumpTo(target);
  } else {
    unawaited(controller.animateTo(target, duration: duration, curve: Curves.easeOutCubic));
  }
}
