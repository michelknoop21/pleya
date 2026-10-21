/// A-06b: the page half of a TV page whose heading and top navigation glide
/// away while the remote is past the first row. The bar half is in
/// `TvRootShell`; both run on [TvTopNavScrollAwayMotion], so the bar and the
/// heading leave and return as one piece.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../navigation/tv/tv_top_nav_scroll_away.dart';
import 'tv_unified_layout.dart';

/// A page heading over a body, on the whole window, where the heading and the
/// band above it fold away while [expanded] is false.
///
/// **Why the body never changes size.** The body is laid out once, at the
/// height it has with everything folded away (the window minus the overscan
/// inset), and only its *position* animates. A grid laid out again on every
/// animation frame would rebuild every card it holds, and a viewport that grows
/// and shrinks re-clamps its scroll offset, which is the jump this page must
/// not make. Expanded, the body simply starts lower and its last strip runs
/// past the bottom of the window; that is acceptable because the page is only
/// expanded while the remote is on the first row, in the bar or in the rail.
///
/// [fitBody] is the exception for a body that is not a scrolling grid (an
/// empty state, a skeleton): it gets the height that is actually visible
/// while expanded, so a centred message stays centred.
class TvScrollAwayPage extends StatefulWidget {
  const TvScrollAwayPage({
    super.key,
    required this.expanded,
    required this.topBand,
    required this.header,
    required this.body,
    this.fitBody = false,
  });

  final bool expanded;

  /// The shell's measured bar band: where the heading sits while expanded.
  final double topBand;

  final Widget header;
  final Widget body;
  final bool fitBody;

  /// Where the body starts while everything is folded away: the outer band
  /// of hoofdstuk 8.1 ("geen tekst of focusring binnen de buitenste 56
  /// pixels", [TvCatalogLayout.topSafeInset] of the 1080 reference), and never
  /// less than the inset the shell hands a whole-window route.
  ///
  /// The shell's inset alone is the bar's, 28 reference pixels, which is half
  /// that band. Folded, the grid parks a row flush against this line whenever
  /// the remote moves UP, ring included, so with the bar's inset the row the
  /// viewer moved to sat at four per cent of the screen and a set that
  /// overscans cut it off (Michel, build 391).
  static double foldedTopOf(BuildContext context) => math.max(
    MediaQuery.paddingOf(context).top,
    MediaQuery.sizeOf(context).height * (TvCatalogLayout.topSafeInset / 1080),
  );

  @override
  State<TvScrollAwayPage> createState() => _TvScrollAwayPageState();
}

class _TvScrollAwayPageState extends State<TvScrollAwayPage> with SingleTickerProviderStateMixin {
  /// 1 is expanded, 0 is folded away. Driven with `animateTo` so a change of
  /// direction mid-flight carries on from where it is instead of restarting.
  late final AnimationController _reveal = AnimationController(vsync: this, value: widget.expanded ? 1 : 0);

  @override
  void didUpdateWidget(TvScrollAwayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    final duration = TvTopNavScrollAwayMotion.durationFor(context, showing: widget.expanded);
    final target = widget.expanded ? 1.0 : 0.0;
    if (duration == Duration.zero) {
      _reveal.value = target;
    } else {
      // Scaled to the distance left, so a reversal halfway takes half the time
      // instead of crawling back at full length.
      final remaining = (target - _reveal.value).abs();
      _reveal.animateTo(target, duration: duration * remaining, curve: TvTopNavScrollAwayMotion.curve);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomMultiChildLayout(
        delegate: _ScrollAwayLayout(
          reveal: _reveal,
          topBand: widget.topBand,
          safeTop: TvScrollAwayPage.foldedTopOf(context),
          fitBody: widget.fitBody,
        ),
        children: [
          // Own layers: the slide repaints only the two offsets, never the
          // cards or the heading themselves.
          LayoutId(
            id: _Slot.body,
            child: RepaintBoundary(child: widget.body),
          ),
          LayoutId(
            id: _Slot.header,
            child: ExcludeSemantics(
              excluding: !widget.expanded,
              child: FadeTransition(
                opacity: _reveal,
                child: RepaintBoundary(child: widget.header),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Slot { header, body }

/// Positions the heading and the body for the current [reveal] value.
///
/// Relaid out on every animation tick, but cheaply: both children get the same
/// constraints every time, so their own layout is skipped and only the two
/// offsets move.
class _ScrollAwayLayout extends MultiChildLayoutDelegate {
  _ScrollAwayLayout({required this.reveal, required this.topBand, required this.safeTop, required this.fitBody})
    : super(relayout: reveal);

  final Animation<double> reveal;
  final double topBand;
  final double safeTop;
  final bool fitBody;

  @override
  void performLayout(Size size) {
    final header = layoutChild(_Slot.header, BoxConstraints(minWidth: size.width, maxWidth: size.width));
    // How far the body travels: from right under the heading (expanded) to
    // the overscan line at the top of the window (folded away).
    final travel = math.max(0.0, topBand + header.height - safeTop);
    final bodyHeight = math.max(0.0, size.height - safeTop - (fitBody ? travel : 0));
    layoutChild(_Slot.body, BoxConstraints.tightFor(width: size.width, height: bodyHeight));
    final bodyTop = safeTop + travel * reveal.value;
    positionChild(_Slot.body, Offset(0, bodyTop));
    positionChild(_Slot.header, Offset(0, bodyTop - header.height));
  }

  @override
  bool shouldRelayout(_ScrollAwayLayout oldDelegate) =>
      oldDelegate.reveal != reveal ||
      oldDelegate.topBand != topBand ||
      oldDelegate.safeTop != safeTop ||
      oldDelegate.fitBody != fitBody;
}
