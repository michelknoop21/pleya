import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/haptics.dart';
import '../../utils/platform_detector.dart';
import 'crown_ratchet.dart';
import 'crown_drag_motion.dart';
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
/// hidden) scrubs directly from the library start to its end in one stroke.
/// It has no speed or distance acceleration. The gear
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
/// The library grid supplies a passive [positionLabel] to this same wheel.
class ScrollCrown extends StatefulWidget {
  const ScrollCrown({
    super.key,
    required this.child,
    this.controller,
    this.enabled,
    this.topInset = 0,
    this.onToothTick,
    this.clock,
    this.onDragSample,
    this.positionLabel,
    this.onScrubStart,
  });

  final Widget child;

  /// Passive position readout, such as the first visible title letter.
  final String? positionLabel;
  final VoidCallback? onScrubStart;

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

  /// Diagnostic observer for calibration; never changes the drag calculation.
  final ValueChanged<Map<String, Object>>? onDragSample;

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
  bool _focused = false;

  /// The crown came up through a touch on the edge, not through scrolling:
  /// then the whole edge scrubs, not only the gear.
  bool _touchActivated = false;
  bool _dragging = false;
  double _railHeight = 0;
  double? _fingerY;
  Offset? _fingerGlobalPosition;
  BuildContext? _railContext;
  bool _fingerRefreshPending = false;
  double _phase = 0;
  double _dragStartY = 0;
  double _dragStartGlobalY = 0;
  double _dragTravel = 0;
  double _dragStartPixels = 0;
  double _dragStartPhase = 0;
  double _dragMinExtent = 0;
  double _dragMaxExtent = 0;
  CrownDragMotion? _motion;
  Drag? _scrollDrag;
  Duration _pointerDownTime = Duration.zero;
  Duration _motionTime = Duration.zero;
  bool _followingEnd = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollDrag?.cancel();
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

  ScrollPosition? get _outerPosition {
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    if (nested == null || !nested.innerController.positions.contains(_position) || !nested.outerController.hasClients)
      return null;
    return nested.outerController.position;
  }

  ScrollMetrics _combinedMetrics(ScrollMetrics inner) {
    final outer = _outerPosition;
    if (outer == null || !outer.hasContentDimensions || !inner.hasContentDimensions) return inner;
    return inner.copyWith(
      viewportDimension: outer.viewportDimension,
      pixels: inner.pixels + outer.pixels,
      minScrollExtent: inner.minScrollExtent + outer.minScrollExtent,
      maxScrollExtent: inner.maxScrollExtent + outer.maxScrollExtent,
    );
  }

  void _jumpTo(double target) {
    final position = _position!;
    final drag = _scrollDrag;
    final delta = target - _combinedMetrics(position).pixels;
    if (drag != null) {
      // One continuous activity for the entire crown drag. jumpTo emits an
      // idle/end notification on every pointer update, repeatedly waking
      // content loading and disrupting the scrolling image pipeline.
      if (delta != 0)
        drag.update(DragUpdateDetails(delta: Offset(0, -delta), primaryDelta: -delta, globalPosition: Offset.zero));
    } else if (_outerPosition == null) {
      position.jumpTo(target);
    } else {
      position.pointerScroll(delta);
    }
  }

  bool _isOurs(int depth, ScrollMetrics metrics) => depth == 0 && metrics.axis == Axis.vertical;

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (!_isOurs(notification.depth, notification.metrics)) return false;
    final wasEligible = _eligible;
    _position = _positionFrom(notification.context) ?? _position;
    _metrics = _combinedMetrics(notification.metrics);
    if (_dragging &&
        _followingEnd &&
        _fingerY != null &&
        _fingerY! >= _railHeight - ScrollCrownGear.height / 2 &&
        _metrics!.extentAfter > 0.5) {
      // A lazy list can discover its final extent only after the edge jump.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final position = _position;
        if (mounted &&
            _dragging &&
            _followingEnd &&
            _fingerY != null &&
            _fingerY! >= _railHeight - ScrollCrownGear.height / 2 &&
            position != null &&
            position.hasContentDimensions) {
          _jumpTo(_combinedMetrics(position).maxScrollExtent);
        }
      });
    }
    if (wasEligible != _eligible) _update(() {});
    _refreshFingerAfterLayout();
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_isOurs(notification.depth, notification.metrics)) return false;
    _position = _positionFrom(notification.context) ?? _position;
    _metrics = _combinedMetrics(notification.metrics);
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

  void _refreshFingerAfterLayout() {
    if (_fingerRefreshPending || !_dragging || _outerPosition == null) return;
    _fingerRefreshPending = true;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      SchedulerBinding.instance.scheduleFrame();
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _fingerRefreshPending = false;
      final railContext = _railContext;
      final finger = _fingerGlobalPosition;
      if (!mounted || !_dragging || finger == null || railContext == null || !railContext.mounted) return;
      final rail = railContext.findRenderObject();
      if (rail is! RenderBox || !rail.hasSize) return;
      final y = rail.globalToLocal(finger).dy;
      if (_fingerY == null || (y - _fingerY!).abs() > .01) setState(() => _fingerY = y);
    });
  }

  void _show({bool autoHide = true}) {
    _hideTimer?.cancel();
    if (!_active) _update(() => _active = true);
    if (autoHide) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(ScrollCrown.hideDelay, () {
      if (mounted && !_dragging && !_focused) {
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
    if (!_active || _touchActivated) return true;
    final top = _gearTop();
    return y >= top - ScrollCrown.gearHitMargin && y <= top + ScrollCrownGear.height + ScrollCrown.gearHitMargin;
  }

  void _onEdgeDown(PointerDownEvent event) {
    _pointerDownTime = event.timeStamp;
    if (!_active) _touchActivated = true;
    _show();
  }

  void _onDragStart(DragStartDetails details) {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    widget.onScrubStart?.call();
    _motionTime = _pointerDownTime;
    _motion = CrownDragMotion(y: details.localPosition.dy - ScrollCrownGear.height / 2, time: _pointerDownTime);
    _followingEnd = false;
    _dragging = true;
    _scrollDrag = position.drag(details, () => _scrollDrag = null);
    _dragStartY = details.localPosition.dy;
    _dragStartGlobalY = details.globalPosition.dy;
    _fingerGlobalPosition = details.globalPosition;
    _dragTravel = _railHeight - ScrollCrownGear.height;
    final metrics = _combinedMetrics(position);
    _dragStartPixels = metrics.pixels;
    // Pinned for the whole drag: a page that loads more items mid-drag would
    // otherwise stretch the mapping and jump the view.
    _dragMinExtent = metrics.minScrollExtent;
    _dragMaxExtent = metrics.maxScrollExtent;
    _dragStartPhase = _phase;
    _ratchet.reset();
    setState(() => _fingerY = details.localPosition.dy);
    _show(autoHide: false);
    _sample('start', details.localPosition.dy);
  }

  void _sample(String event, double y) {
    final metrics = _combinedMetrics(_position!);
    widget.onDragSample?.call({
      'event': event,
      't_us': (widget.clock?.call() ?? _stopwatch.elapsed).inMicroseconds,
      'y': y,
      'start_y': _dragStartY,
      'start_pixels': _dragStartPixels,
      'min': _dragMinExtent,
      'max': y >= _railHeight - ScrollCrownGear.height / 2 ? metrics.maxScrollExtent : _dragMaxExtent,
      'rail_height': _railHeight,
      'pixels': metrics.pixels,
      'mapping': CrownDragMotion.model,
      'input_down_us': _pointerDownTime.inMicroseconds,
      'input_time_us': _motionTime.inMicroseconds,
      'range_extent': _dragMaxExtent - _dragMinExtent,
      'live_min': metrics.minScrollExtent,
      'live_max': metrics.maxScrollExtent,
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final position = _position;
    if (!_dragging || position == null || !position.hasContentDimensions || _railHeight <= 0) return;
    _fingerGlobalPosition = details.globalPosition;
    final delta = details.globalPosition.dy - _dragStartGlobalY;
    final metrics = _combinedMetrics(position);
    _motionTime = details.sourceTimeStamp ?? _motionTime;
    final target = _motion!.move(
      y: _dragStartY + delta - ScrollCrownGear.height / 2,
      time: _motionTime,
      pixels: metrics.pixels,
      travel: _dragTravel,
      rangeExtent: _dragMaxExtent - _dragMinExtent,
      minExtent: metrics.minScrollExtent,
      maxExtent: metrics.maxScrollExtent,
    );
    _jumpTo(target);
    _followingEnd = _combinedMetrics(position).extentAfter <= 0.5;
    final rail = _railContext?.findRenderObject();
    setState(() {
      _fingerY = rail is RenderBox ? rail.globalToLocal(details.globalPosition).dy : details.localPosition.dy;
      if (!prefersReducedMotion(context)) _phase = _dragStartPhase + CrownRatchet.phaseFor(delta);
    });
    if (_ratchet.advance(details.delta.dy.abs())) (widget.onToothTick ?? Haptics.selection)();
    _sample('update', details.localPosition.dy);
    _refreshFingerAfterLayout();
  }

  void _onDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    _fingerGlobalPosition = null;
    _scrollDrag?.end(DragEndDetails(primaryVelocity: 0));
    _scrollDrag = null;
    _motion = null;
    _followingEnd = false;
    _sample('end', _fingerY ?? _dragStartY);
    setState(() => _fingerY = null);
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
    widget.onScrubStart?.call();
    final target = _pageTarget(_combinedMetrics(position), direction);
    if (_outerPosition != null || prefersReducedMotion(context)) {
      _jumpTo(target);
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
          _railContext = context;
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
                right: 2,
                top: (_railHeight - 30) / 2,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _active ? 0 : 1,
                    duration: fade,
                    child: Container(
                      width: 2,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0x55D3CEC7)
                            : const Color(0x66595550),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.positionLabel case final label? when label.isNotEmpty)
                Positioned(
                  right: 34,
                  top: _gearTop() + (ScrollCrownGear.height - 43) / 2,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _active ? 1 : 0,
                      duration: fade,
                      child: Container(
                        width: 43,
                        height: 43,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDFDDD8),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 3))],
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF252527),
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                            height: 1,
                          ),
                        ),
                      ),
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
                  focused: _focused,
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
                child: AutomationNode(
                  id: AutomationIds.overlayScrollCrown,
                  role: 'slider',
                  state: () => {
                    'at_start': _metrics!.extentBefore <= 0.5,
                    'at_end': _metrics!.extentAfter <= 0.5,
                    'visible': _active,
                    'gear_height': ScrollCrownGear.height,
                    'motion_model': CrownDragMotion.model,
                    'position_label': widget.positionLabel,
                    'dragging': _dragging,
                  },
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
                        _page(1);
                      } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
                        _page(-1);
                      } else if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
                        final metrics = _combinedMetrics(_position!);
                        widget.onScrubStart?.call();
                        _jumpTo(key == LogicalKeyboardKey.home ? metrics.minScrollExtent : metrics.maxScrollExtent);
                      } else {
                        return KeyEventResult.ignored;
                      }
                      _show();
                      return KeyEventResult.handled;
                    },
                    onFocusChange: (focused) {
                      _update(() => _focused = focused);
                      if (focused) {
                        _show(autoHide: false);
                      } else {
                        _scheduleHide();
                      }
                    },
                    child: _rail(context),
                  ),
                ),
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
  Offset? _start;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _start ??= event.position;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind kind, double? deviceTouchSlop) {
    final start = _start;
    if (start == null) return super.hasSufficientGlobalDistanceToAccept(kind, deviceTouchSlop);
    final delta = lastPosition.global - start;
    // Fine crown motion must win before a card's long press; horizontal swipes still pass.
    return delta.dy.abs() > delta.dx.abs();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _start = null;
  }

  @override
  bool isPointerAllowed(PointerEvent event) => claims(event.localPosition.dy) && super.isPointerAllowed(event);
}
