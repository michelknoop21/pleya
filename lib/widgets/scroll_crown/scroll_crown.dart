import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/haptics.dart';
import '../../utils/platform_detector.dart';
import 'crown_ratchet.dart';
import 'scroll_crown_gear.dart';

/// The phone scroll crown for any vertical scroll view: wrap the scroll view
/// in it and that is all.
///
/// ```dart
/// ScrollCrown(child: CustomScrollView(slivers: ...))
/// ```
///
/// It is the CN09 gear without the letter bubble. It appears when the view
/// scrolls or the right edge is touched and fades [hideDelay] after the last
/// activity. A vertical drag that starts on the gear (or where it rests while
/// hidden) scrubs: it scrolls pixel for pixel over the scrollable range as it
/// was when the drag began (rail height maps onto scroll length), the gear
/// rides under the finger and its teeth turn with the drag, with a ratchet
/// tick per tooth through [CrownRatchet]. After a touch on the edge brought
/// the crown up, the whole edge is a rail until it hides or the content
/// scrolls; a crown that came up through scrolling leaves ordinary swipes
/// along the edge to the scroll view.
///
/// It stays out of the way: phones only (no tablet, desktop or TV), only for
/// the outermost vertical scrollable below it, and only when the content is
/// at least [minContentScreens] viewports long. The rail ends above the tab
/// bar and below the status bar (the `MediaQuery` padding) and only claims
/// vertical drags, so horizontal rails and swipe gestures keep working. Under
/// reduce motion the teeth stay still; scrubbing still works.
///
/// The library grid sorted by title uses the alphabet variant
/// (`AlphaScrollHandle`) instead.
class ScrollCrown extends StatefulWidget {
  const ScrollCrown({
    super.key,
    required this.child,
    this.controller,
    this.enabled,
    this.topInset = 0,
    this.onToothTick,
    this.clock,
  });

  final Widget child;

  /// The scroll view's controller. Without one the crown picks the position
  /// up from the scroll view's own notifications.
  final ScrollController? controller;

  /// Null shows the crown on phones only; tests force it with true.
  final bool? enabled;

  /// Extra space at the top of the rail, below the status bar, e.g. for a
  /// floating header.
  final double topInset;

  /// Ratchet tick per passing tooth. Defaults to [Haptics.selection].
  final VoidCallback? onToothTick;

  /// Monotonic time source for the tick rate limit; tests inject one.
  final Duration Function()? clock;

  /// Content shorter than this many viewports gets no crown.
  static const double minContentScreens = 2.0;

  static const double railWidth = 44;

  /// Extra touch room above and below the gear for grabbing it.
  static const double gearHitMargin = 22;
  static const Duration hideDelay = Duration(milliseconds: 850);
  static const Duration fade = Duration(milliseconds: 150);

  /// Whether [metrics] describe content long enough for a crown.
  static bool isLongEnough(ScrollMetrics metrics) {
    if (!metrics.hasContentDimensions || !metrics.hasViewportDimension) return false;
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (!range.isFinite || metrics.viewportDimension <= 0) return false;
    return range >= metrics.viewportDimension * (minContentScreens - 1);
  }

  /// The scroll offset for a drag of [dragDelta] on a rail of [railHeight]
  /// that started at [startPixels]: the rail maps onto the whole scrollable
  /// range, so a full-rail drag covers it end to end.
  static double offsetForDrag({
    required double startPixels,
    required double dragDelta,
    required double railHeight,
    required double minExtent,
    required double maxExtent,
  }) {
    if (railHeight <= 0 || maxExtent <= minExtent) return startPixels.clamp(minExtent, maxExtent);
    return (startPixels + dragDelta / railHeight * (maxExtent - minExtent)).clamp(minExtent, maxExtent);
  }

  @override
  State<ScrollCrown> createState() => _ScrollCrownState();
}

class _ScrollCrownState extends State<ScrollCrown> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  late final CrownRatchet _ratchet = CrownRatchet(now: () => widget.clock?.call() ?? _stopwatch.elapsed);
  Timer? _hideTimer;

  ScrollPosition? _position;
  ScrollMetrics? _metrics;
  bool _active = false;

  /// The crown came up through a touch on the edge, not through scrolling:
  /// then the whole edge scrubs, not only the gear.
  bool _touchActivated = false;
  bool _dragging = false;
  double _railHeight = 0;
  double? _fingerY;
  double _phase = 0;
  double _dragStartY = 0;
  double _dragStartPixels = 0;
  double _dragStartPhase = 0;
  double _dragMinExtent = 0;
  double _dragMaxExtent = 0;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  bool get _eligible {
    final metrics = _metrics;
    return metrics != null && ScrollCrown.isLongEnough(metrics);
  }

  /// setState, or after the frame when a notification arrives mid-layout.
  void _update(VoidCallback change) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      change();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(change);
    }
  }

  ScrollPosition? _positionFrom(BuildContext? context) {
    final controller = widget.controller;
    if (controller != null && controller.positions.length == 1) return controller.position;
    return context == null ? null : Scrollable.maybeOf(context)?.position;
  }

  bool _isOurs(int depth, ScrollMetrics metrics) => depth == 0 && metrics.axis == Axis.vertical;

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (!_isOurs(notification.depth, notification.metrics)) return false;
    final wasEligible = _eligible;
    _metrics = notification.metrics;
    _position = _positionFrom(notification.context) ?? _position;
    if (wasEligible != _eligible) _update(() {});
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_isOurs(notification.depth, notification.metrics)) return false;
    _metrics = notification.metrics;
    _position = _positionFrom(notification.context) ?? _position;
    if (_dragging || notification is! ScrollUpdateNotification) return false;
    if (!_eligible) {
      if (_active) _update(() => _active = false);
      return false;
    }
    _touchActivated = false;
    _update(() => _fingerY = null);
    _show();
    return false;
  }

  void _show({bool autoHide = true}) {
    _hideTimer?.cancel();
    if (!_active) _update(() => _active = true);
    if (autoHide) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(ScrollCrown.hideDelay, () {
      if (mounted && !_dragging) {
        setState(() {
          _active = false;
          _touchActivated = false;
          _fingerY = null;
        });
      }
    });
  }

  /// Whether a touch at rail height [y] takes a vertical drag: on the gear's
  /// spot (also while hidden, so the first drag after it faded still grabs
  /// it), or anywhere on the edge once a touch on the edge brought it up.
  bool _claims(double y) {
    if (_active && _touchActivated) return true;
    final top = _gearTop();
    return y >= top - ScrollCrown.gearHitMargin && y <= top + ScrollCrownGear.height + ScrollCrown.gearHitMargin;
  }

  void _onEdgeDown(PointerDownEvent _) {
    if (!_active) _touchActivated = true;
    _show();
  }

  void _onDragStart(DragStartDetails details) {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    _dragging = true;
    _dragStartY = details.localPosition.dy;
    _dragStartPixels = position.pixels;
    // Pinned for the whole drag: a page that loads more items mid-drag would
    // otherwise stretch the mapping and jump the view.
    _dragMinExtent = position.minScrollExtent;
    _dragMaxExtent = position.maxScrollExtent;
    _dragStartPhase = _phase;
    _ratchet.reset();
    setState(() => _fingerY = details.localPosition.dy);
    _show(autoHide: false);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final position = _position;
    if (!_dragging || position == null || !position.hasContentDimensions || _railHeight <= 0) return;
    final delta = details.localPosition.dy - _dragStartY;
    final target = ScrollCrown.offsetForDrag(
      startPixels: _dragStartPixels,
      dragDelta: delta,
      railHeight: _railHeight,
      minExtent: _dragMinExtent,
      maxExtent: _dragMaxExtent,
    );
    position.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    setState(() {
      _fingerY = details.localPosition.dy;
      if (!prefersReducedMotion(context)) _phase = _dragStartPhase + CrownRatchet.phaseFor(delta);
    });
    if (_ratchet.advance(details.delta.dy.abs())) (widget.onToothTick ?? Haptics.selection)();
  }

  void _onDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    _scheduleHide();
  }

  double get _fraction {
    final metrics = _metrics;
    if (metrics == null || !metrics.hasContentDimensions) return 0;
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (range <= 0) return 0;
    return ((metrics.pixels - metrics.minScrollExtent) / range).clamp(0.0, 1.0);
  }

  double _gearTop() {
    final room = (_railHeight - ScrollCrownGear.height).clamp(0.0, double.infinity);
    final finger = _fingerY;
    if (finger == null) return _fraction * room;
    return (finger - ScrollCrownGear.height / 2).clamp(0.0, room);
  }

  /// Where a page up or down for VoiceOver's slider gestures lands.
  static double _pageTarget(ScrollMetrics metrics, int direction) =>
      (metrics.pixels + direction * metrics.viewportDimension * 0.8).clamp(
        metrics.minScrollExtent,
        metrics.maxScrollExtent,
      );

  static String _percentOf(ScrollMetrics metrics, double pixels) {
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (range <= 0) return '0%';
    return '${((pixels - metrics.minScrollExtent) / range * 100).clamp(0, 100).round()}%';
  }

  void _page(int direction) {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    final target = _pageTarget(position, direction);
    if (prefersReducedMotion(context)) {
      position.jumpTo(target);
    } else {
      unawaited(position.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
    }
  }

  Widget _rail(BuildContext context) {
    final fade = prefersReducedMotion(context) ? Duration.zero : ScrollCrown.fade;
    final metrics = _metrics!;
    final atStart = metrics.pixels <= metrics.minScrollExtent;
    final atEnd = metrics.pixels >= metrics.maxScrollExtent;
    return Semantics(
      container: true,
      slider: true,
      label: t.accessibility.scrollCrown,
      value: _percentOf(metrics, metrics.pixels),
      increasedValue: _percentOf(metrics, _pageTarget(metrics, 1)),
      decreasedValue: _percentOf(metrics, _pageTarget(metrics, -1)),
      onIncrease: atEnd ? null : () => _page(1),
      onDecrease: atStart ? null : () => _page(-1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _railHeight = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                // Touching the edge brings the crown up. The drag recognizer is
                // always there, so the first touch already counts, but it only
                // joins the arena when [_claims] says so; other vertical drags,
                // taps and horizontal drags reach the content underneath
                // (translucent, no tap handler).
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onEdgeDown,
                  child: RawGestureDetector(
                    key: const ValueKey('scroll_crown_rail'),
                    behavior: HitTestBehavior.translucent,
                    gestures: {
                      _RailDragRecognizer: GestureRecognizerFactoryWithHandlers<_RailDragRecognizer>(
                        () => _RailDragRecognizer(claims: _claims),
                        (recognizer) => recognizer
                          ..claims = _claims
                          ..dragStartBehavior = DragStartBehavior.down
                          ..onStart = _onDragStart
                          ..onUpdate = _onDragUpdate
                          ..onCancel = _onDragEnd
                          ..onEnd = ((_) => _onDragEnd()),
                      ),
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                right: ScrollCrownGear.right,
                top: _gearTop(),
                child: ScrollCrownGear(
                  paintKey: const ValueKey('scroll_crown_gear'),
                  phase: _phase,
                  visible: _active,
                  fade: fade,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled ?? PlatformDetector.isPhone(context);
    if (!enabled) return widget.child;
    final padding = MediaQuery.paddingOf(context);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_eligible)
              Positioned(
                top: padding.top + widget.topInset,
                bottom: padding.bottom,
                right: 0,
                width: ScrollCrown.railWidth,
                child: _rail(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// A vertical drag recognizer that only takes pointers [claims] accepts,
/// judged at pointer down in rail coordinates.
class _RailDragRecognizer extends VerticalDragGestureRecognizer {
  _RailDragRecognizer({required this.claims});

  bool Function(double y) claims;

  @override
  bool isPointerAllowed(PointerEvent event) => claims(event.localPosition.dy) && super.isPointerAllowed(event);
}
