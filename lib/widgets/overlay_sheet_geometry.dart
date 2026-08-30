import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
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

  /// Viewport-aware panel: a bottom sheet below [ScreenBreakpoints.mobile], a
  /// centred modal above it, and a centred 10-foot modal on TV. Never follows
  /// the pointer.
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

  /// Cast behind the surface, outside its clip. Empty for every presentation
  /// that hangs off a viewport edge — a sheet flush against the bottom has no
  /// gap to cast into — and populated only for the centred 10-foot panel, which
  /// floats over content and has to read as lifted rather than as a hole cut in
  /// the page. See [_tvPanelShadows].
  final List<BoxShadow> shadows;

  const OverlaySheetGeometry({
    required this.alignment,
    required this.constraints,
    required this.borderRadius,
    required this.edgePadding,
    required this.allowPointerAnchor,
    required this.allowDragHandle,
    required this.enterOffset,
    required this.fadeIn,
    this.shadows = const [],
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
      other.fadeIn == fadeIn &&
      listEquals(other.shadows, shadows);

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
    Object.hashAll(shadows),
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

// ---------------------------------------------------------------------------
// TV panel (hoofdstuk 8 and 14.1 of docs/tvos-unified-experience.md)
// ---------------------------------------------------------------------------
//
// Every number the design contract states — "breedte circa 900–1040",
// "hoekradius 20–24", the 72px safe inset of hoofdstuk 8.1 — is a *reference*
// measurement on a 1920x1080 TV output surface, not a Flutter logical pixel.
// [DEC-028] renders Apple TV at scale 1.85, so the logical canvas the widget
// tree actually sees is roughly 1038x584. Reading 1040 as a logical width there
// would produce a panel covering the whole screen: exactly the failure hoofdstuk
// 8 warns about ("geen losse magic numbers per widget").
//
// So the reference numbers are stored as *fractions of the 1920x1080 surface*
// and multiplied by the live viewport. On the canonical canvas that is
// arithmetically identical to `reference / 1.85` — the whole canvas is upscaled
// by the same factor — while degrading correctly on any other surface size (a
// simulator window, a 720p output, the Linux golden harness).
//
// Note this is deliberately *not* [TvLayoutConstants.scaleForHeight]. That scale
// is clamped to [0.85, 1.35] because 10-foot *typography* must not shrink
// linearly with the canvas; box composition must. Type inside the panel keeps
// using the clamped scale; the panel's own box uses these fractions.

/// Reference width of a centred TV panel on the 1920x1080 design surface.
/// Hoofdstuk 14.1 gives a 900–1040 band; the source picker sits at the roomy
/// end because its rows carry server, library, quality and progress on one line.
const double _tvPanelReferenceWidth = 1000;

/// Reference corner radius, from hoofdstuk 14.1's "hoekradius 20–24".
const double _tvPanelReferenceRadius = 22;

/// Reference gap between the panel and the viewport edge — hoofdstuk 8.1's
/// horizontal safe inset. A floor, not the real margin: a 1000-wide panel on a
/// 1920-wide surface already leaves 460 either side.
const double _tvPanelReferenceEdge = 72;

/// Reference travel of the panel's enter animation (hoofdstuk 8.4 keeps it a
/// lift, not a slide).
const double _tvPanelReferenceEnter = 24;

const double _tvReferenceWidth = 1920;
const double _tvReferenceHeight = 1080;

/// Share of the viewport height a TV panel may occupy — hoofdstuk 14.1's
/// "hoogte dynamisch, maximaal veilige viewport". The remainder is the vertical
/// overscan margin, split top and bottom.
const double _tvPanelMaxHeightFraction = 0.84;

/// Floor for the panel width on a degenerate or very small surface, so the
/// fraction can never collapse the panel to nothing.
const double _tvPanelMinWidth = 320;

/// Reference blur/offset of the panel's cast shadow, in the same 1920x1080
/// units as everything else here.
///
/// The numbers are not invented: `tv_info_panel.dart` already floats a 10-foot
/// surface on `blurRadius: 40, offset: (0, 12)`, and `media_card`'s hover
/// preview on `40 / (0, 18)`. This is that same language, stated as a fraction
/// so it survives a different output resolution.
///
/// Two layers, because one does two jobs badly: the ambient layer separates the
/// panel from a busy poster wall several rows deep, and the tight contact layer
/// puts an edge under it. Note `monoTheme` sets `ColorScheme.shadow` to
/// transparent on purpose — Material elevation paints nothing in this app — so
/// a surface that should cast says so explicitly, here.
const double _tvPanelShadowAmbientBlur = 72;
const double _tvPanelShadowAmbientOffset = 26;
const double _tvPanelShadowContactBlur = 20;
const double _tvPanelShadowContactOffset = 6;

/// The corner radius a TV panel gets on [viewport].
///
/// Exported so panel *content* can draw a hairline that lands exactly on the
/// host's clipped edge instead of guessing at the number. One source of truth,
/// which is the whole point of putting the reference conversion in this file.
double tvPanelBorderRadius(Size viewport) => viewport.width * (_tvPanelReferenceRadius / _tvReferenceWidth);

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
  if (presentation == OverlaySheetPresentation.panel && isTV) {
    return _tvPanelGeometry(viewport: viewport, explicitConstraints: explicitConstraints);
  }
  final usePanel = presentation == OverlaySheetPresentation.panel && !ScreenBreakpoints.isMobile(viewport.width);
  return usePanel
      ? _panelGeometry(viewport: viewport, explicitConstraints: explicitConstraints)
      : _sheetGeometry(viewport: viewport, alignment: alignment, isTV: isTV, explicitConstraints: explicitConstraints);
}

/// The centred 10-foot modal of hoofdstuk 14.1.
///
/// Separate from [_panelGeometry] rather than a branch inside it: the desktop
/// panel is capped at a fixed 560 because a wider column of filter rows stops
/// reading as a list, while a TV panel is sized as a *proportion of the screen*
/// and read from three metres away. Sharing one function would mean one of the
/// two silently inheriting the other's constant.
OverlaySheetGeometry _tvPanelGeometry({required Size viewport, BoxConstraints? explicitConstraints}) {
  double fromWidth(double reference) => viewport.width * (reference / _tvReferenceWidth);
  double fromHeight(double reference) => viewport.height * (reference / _tvReferenceHeight);

  final edgePadding = math.max(0.0, fromWidth(_tvPanelReferenceEdge));
  final availableWidth = math.max(0.0, viewport.width - edgePadding * 2);
  final availableHeight = math.max(0.0, viewport.height - edgePadding * 2);

  final desired =
      explicitConstraints ??
      BoxConstraints(
        maxWidth: math.min(math.max(_tvPanelMinWidth, fromWidth(_tvPanelReferenceWidth)), availableWidth),
        maxHeight: viewport.height * _tvPanelMaxHeightFraction,
      );

  final constraints = BoxConstraints(
    minWidth: math.min(desired.minWidth, availableWidth),
    maxWidth: math.min(desired.maxWidth, availableWidth),
    minHeight: math.min(desired.minHeight, availableHeight),
    maxHeight: math.min(desired.maxHeight, availableHeight),
  );

  return OverlaySheetGeometry(
    alignment: Alignment.center,
    constraints: constraints,
    borderRadius: BorderRadius.circular(fromWidth(_tvPanelReferenceRadius)),
    edgePadding: edgePadding,
    // No pointer on a remote, and no drag handle to grab with one.
    allowPointerAnchor: false,
    allowDragHandle: false,
    enterOffset: Offset(0, fromHeight(_tvPanelReferenceEnter)),
    fadeIn: true,
    shadows: _tvPanelShadows(fromWidth: fromWidth, fromHeight: fromHeight),
  );
}

List<BoxShadow> _tvPanelShadows({
  required double Function(double) fromWidth,
  required double Function(double) fromHeight,
}) => [
  BoxShadow(
    color: const Color(0xFF000000).withValues(alpha: 0.55),
    blurRadius: fromWidth(_tvPanelShadowAmbientBlur),
    offset: Offset(0, fromHeight(_tvPanelShadowAmbientOffset)),
  ),
  BoxShadow(
    color: const Color(0xFF000000).withValues(alpha: 0.42),
    blurRadius: fromWidth(_tvPanelShadowContactBlur),
    offset: Offset(0, fromHeight(_tvPanelShadowContactOffset)),
  ),
];

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
