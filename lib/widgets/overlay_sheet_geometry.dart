import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../utils/layout_constants.dart';

/// How an overlay sheet presents itself.
///
/// The overlay host draws every kind of transient surface the app has: context
/// menus at the cursor, track pickers, and the filter/sort panels behind a
/// header action. Those want different placement, so the caller says which
/// kind it is opening and [resolveOverlaySheetGeometry] turns that into
/// numbers.
enum OverlaySheetPresentation {
  /// Bottom edge, full width on phones, anchored to the last mouse position on
  /// desktop. The long-standing behaviour, and the right one for context menus
  /// and quick pickers that belong to the spot the user clicked.
  sheet,

  /// Viewport-aware panel: a bottom sheet below [ScreenBreakpoints.mobile] and
  /// on TV, a centred modal above it. Never follows the pointer.
  panel,
}

/// Resolved placement for one overlay sheet. Pure data: the host reads it,
/// nothing here touches a widget tree.
@immutable
class OverlaySheetGeometry {
  /// Where the surface sits inside the viewport.
  final Alignment alignment;

  /// Size bounds for the sheet content, already clamped to the viewport.
  final BoxConstraints constraints;

  final BorderRadius borderRadius;

  /// Gap the layout delegate keeps between the sheet and the viewport edges.
  final double edgePadding;

  /// Whether the horizontal position may follow the last mouse position.
  /// False for a panel: a settings surface has no business tracking the cursor.
  final bool allowPointerAnchor;

  /// Whether a drag handle (and swipe-to-dismiss) may be drawn. Callers still
  /// opt in per sheet; this only says the presentation permits it.
  final bool allowDragHandle;

  /// Where the surface starts before it animates in, relative to its resting
  /// place. A bottom sheet travels a full viewport height; a centred panel
  /// only lifts a few pixels, because sliding it up from off-screen would read
  /// as a sheet that overshot.
  final Offset enterOffset;

  /// Whether the enter animation fades as well as moves.
  final bool fadeIn;

  const OverlaySheetGeometry({
    required this.alignment,
    required this.constraints,
    required this.borderRadius,
    required this.edgePadding,
    required this.allowPointerAnchor,
    required this.allowDragHandle,
    required this.enterOffset,
    required this.fadeIn,
  });

  /// Whether the surface floats in the middle rather than hanging off an edge.
  /// A floating panel needs no safe-area padding on the edge it does not touch.
  bool get isCentered => alignment.y == 0;

  @override
  bool operator ==(Object other) =>
      other is OverlaySheetGeometry &&
      other.alignment == alignment &&
      other.constraints == constraints &&
      other.borderRadius == borderRadius &&
      other.edgePadding == edgePadding &&
      other.allowPointerAnchor == allowPointerAnchor &&
      other.allowDragHandle == allowDragHandle &&
      other.enterOffset == enterOffset &&
      other.fadeIn == fadeIn;

  @override
  int get hashCode => Object.hash(
    alignment,
    constraints,
    borderRadius,
    edgePadding,
    allowPointerAnchor,
    allowDragHandle,
    enterOffset,
    fadeIn,
  );
}

/// Width above which the [OverlaySheetPresentation.sheet] path switches to its
/// desktop box. Deliberately its own number rather than a [ScreenBreakpoints]
/// one: context menus have been placed against this exact value for a long
/// time and must keep landing on the same pixels.
const double _sheetDesktopWidth = 600;

/// Widest a centred panel gets, however wide the window is. Past this a list of
/// filter rows stops reading as a column and starts reading as a table.
const double _panelMaxWidth = 560;

/// Gap between a centred panel and the viewport edge.
const double _panelEdgePadding = 24;

/// Vertical breathing room a centred panel leaves in total (split over top and
/// bottom), on top of the 80%-of-height ceiling.
const double _panelVerticalMargin = 96;

/// How far a centred panel travels while animating in.
const double _panelEnterDistance = 24;

/// Turn a presentation plus a viewport into concrete placement numbers.
///
/// [explicitConstraints] are the caller's wish. They win over the defaults, but
/// never over the viewport: a panel that would not fit is shrunk, because a
/// surface hanging off the screen has no close button.
OverlaySheetGeometry resolveOverlaySheetGeometry({
  required OverlaySheetPresentation presentation,
  required Size viewport,
  required Alignment alignment,
  required bool isTV,
  BoxConstraints? explicitConstraints,
}) {
  final usePanel =
      presentation == OverlaySheetPresentation.panel && !isTV && !ScreenBreakpoints.isMobile(viewport.width);
  return usePanel
      ? _panelGeometry(viewport: viewport, explicitConstraints: explicitConstraints)
      : _sheetGeometry(viewport: viewport, alignment: alignment, isTV: isTV, explicitConstraints: explicitConstraints);
}

OverlaySheetGeometry _sheetGeometry({
  required Size viewport,
  required Alignment alignment,
  required bool isTV,
  BoxConstraints? explicitConstraints,
}) {
  final isDesktop = viewport.width > _sheetDesktopWidth;
  final isTop = alignment.y < 0;
  return OverlaySheetGeometry(
    alignment: alignment,
    constraints:
        explicitConstraints ??
        BoxConstraints(
          maxWidth: isTV ? 400 : (isDesktop ? 700 : double.infinity),
          maxHeight: isTV ? 400 : (isDesktop ? 400 : viewport.height * 0.75),
        ),
    borderRadius: isTop
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : const BorderRadius.vertical(top: Radius.circular(16)),
    edgePadding: isDesktop ? 16 : 0,
    allowPointerAnchor: true,
    allowDragHandle: !isTV && !isTop,
    enterOffset: Offset(0, isTop ? -viewport.height : viewport.height),
    fadeIn: false,
  );
}

OverlaySheetGeometry _panelGeometry({required Size viewport, BoxConstraints? explicitConstraints}) {
  // Only a viewport at least [ScreenBreakpoints.mobile] wide reaches this
  // branch, so the margin always fits; the max() below is a guard against a
  // degenerate viewport (a zero-sized first frame), not a real layout case.
  const edgePadding = _panelEdgePadding;

  final availableWidth = math.max(0.0, viewport.width - edgePadding * 2);
  final availableHeight = math.max(0.0, viewport.height - edgePadding * 2);

  final desired =
      explicitConstraints ??
      BoxConstraints(
        maxWidth: math.min(_panelMaxWidth, availableWidth),
        maxHeight: math.min(math.max(0.0, viewport.height - _panelVerticalMargin), viewport.height * 0.8),
      );

  // The caller asks, the viewport decides. Intersecting rather than replacing
  // keeps an explicit `maxWidth: 320` at 320 while still capping a `maxWidth:
  // 900` on a 700px window.
  final constraints = BoxConstraints(
    minWidth: math.min(desired.minWidth, availableWidth),
    maxWidth: math.min(desired.maxWidth, availableWidth),
    minHeight: math.min(desired.minHeight, availableHeight),
    maxHeight: math.min(desired.maxHeight, availableHeight),
  );

  return OverlaySheetGeometry(
    alignment: Alignment.center,
    constraints: constraints,
    borderRadius: BorderRadius.circular(16),
    edgePadding: edgePadding,
    allowPointerAnchor: false,
    allowDragHandle: false,
    enterOffset: const Offset(0, _panelEnterDistance),
    fadeIn: true,
  );
}
