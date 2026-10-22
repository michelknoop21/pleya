import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../media/library_first_character.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/haptics.dart';
import '../../widgets/scroll_crown/crown_ratchet.dart';
import '../../widgets/scroll_crown/scroll_crown_gear.dart';
import 'alpha_jump_helper.dart';

/// Phone alphabet scrubber after the CN09 prototype: the whole right edge is
/// a touch rail. At rest only a thin hint line shows; touching the edge brings
/// up a machined gear under the finger and a letter bubble beside it. The rail
/// maps onto the whole scrollable range, so the grid follows the finger, and
/// the gear's teeth turn with the drag (not under reduce motion).
///
/// You feel it: a fine ratchet tick per tooth that passes ([toothPitch] of
/// drag), capped at one tick per [minTickInterval], and a firmer tick when
/// the letter changes.
///
/// Desktop/tablet/TV use [AlphaJumpBar] instead.
class AlphaScrollHandle extends StatefulWidget {
  final List<LibraryFirstCharacter> firstCharacters;

  /// Jump to the first item of a letter (keyboard and accessibility steps).
  final void Function(int targetIndex) onJump;

  /// Scroll to a fraction (0 to 1) of the scrollable range while dragging.
  final ValueChanged<double> onScrub;

  /// Current scroll position as a fraction of the scrollable range.
  final double Function() readScrollFraction;

  /// The letter at the top of the grid, derived from the scroll position by
  /// the parent.
  final String currentLetter;
  final bool descending;

  /// Ratchet tick per passing tooth. Defaults to [Haptics.selection].
  final VoidCallback? onToothTick;

  /// Firmer tick on a letter change. Defaults to [Haptics.light].
  final VoidCallback? onLetterTick;

  /// Monotonic time source for the tick rate limit; tests inject one.
  final Duration Function()? clock;

  /// Drag distance per tooth: one ratchet tick and one tooth of rotation.
  static const double toothPitch = CrownRatchet.toothPitch;

  /// Fastest ratchet rate (about 28 ticks a second); faster drags drop teeth.
  static const Duration minTickInterval = CrownRatchet.minTickInterval;

  const AlphaScrollHandle({
    super.key,
    required this.firstCharacters,
    required this.onJump,
    required this.onScrub,
    required this.readScrollFraction,
    required this.currentLetter,
    this.descending = false,
    this.onToothTick,
    this.onLetterTick,
    this.clock,
  });

  @override
  State<AlphaScrollHandle> createState() => _AlphaScrollHandleState();
}

class _AlphaScrollHandleState extends State<AlphaScrollHandle> {
  late AlphaJumpHelper _helper;
  final FocusNode _focusNode = FocusNode(debugLabel: 'alpha_scroll_handle');
  final Stopwatch _stopwatch = Stopwatch()..start();
  late final CrownRatchet _ratchetState = CrownRatchet(now: _now);
  Timer? _hideTimer;

  bool _active = false;
  bool _dragging = false;
  bool _focused = false;
  double _railHeight = 0;
  double? _gearTop;
  double _phase = 0;
  double _dragStartY = 0;
  double _dragStartFraction = 0;
  double _dragStartPhase = 0;

  static const double _railWidth = 44;
  static const double _gearHeight = ScrollCrownGear.height;
  static const double _bubbleSize = 43;
  static const double _bubbleRight = 34;
  static const double _hintHeight = 30;
  static const Duration _hideDelay = Duration(milliseconds: 850);
  static const Duration _fade = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _helper = AlphaJumpHelper(widget.firstCharacters, descending: widget.descending);
  }

  @override
  void didUpdateWidget(AlphaScrollHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstCharacters != widget.firstCharacters || oldWidget.descending != widget.descending) {
      _helper = AlphaJumpHelper(widget.firstCharacters, descending: widget.descending);
    }
    if (_dragging && widget.currentLetter.isNotEmpty && widget.currentLetter != oldWidget.currentLetter) {
      _letterTick();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Duration _now() => widget.clock?.call() ?? _stopwatch.elapsed;

  void _letterTick() {
    _ratchetState.markTick();
    (widget.onLetterTick ?? Haptics.light)();
  }

  /// One tick per [AlphaScrollHandle.toothPitch] of travel, rate limited by
  /// the shared [CrownRatchet].
  void _ratchet(double distance) {
    if (_ratchetState.advance(distance)) (widget.onToothTick ?? Haptics.selection)();
  }

  double _clampGearTop(double centerY) =>
      (centerY - _gearHeight / 2).clamp(0.0, (_railHeight - _gearHeight).clamp(0.0, double.infinity));

  void _show({bool autoHide = true}) {
    _hideTimer?.cancel();
    if (!_active) setState(() => _active = true);
    if (autoHide) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && !_dragging && !_focused) setState(() => _active = false);
    });
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _dragStartY = details.localPosition.dy;
    _dragStartFraction = widget.readScrollFraction();
    _dragStartPhase = _phase;
    _ratchetState.reset();
    setState(() => _gearTop = _clampGearTop(details.localPosition.dy));
    _show(autoHide: false);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_railHeight <= 0) return;
    final delta = details.localPosition.dy - _dragStartY;
    widget.onScrub((_dragStartFraction + delta / _railHeight).clamp(0.0, 1.0));
    setState(() {
      _gearTop = _clampGearTop(details.localPosition.dy);
      if (!prefersReducedMotion(context)) {
        _phase = _dragStartPhase + CrownRatchet.phaseFor(delta);
      }
    });
    _ratchet(details.delta.dy.abs());
  }

  void _onDragEnd() {
    _dragging = false;
    _scheduleHide();
  }

  /// Step [by] letters through the list (keyboard and accessibility).
  void _step(int by) => _stepTo(_helper.letters.indexOf(widget.currentLetter) + by);

  void _stepTo(int target) {
    final letters = _helper.letters;
    if (letters.isEmpty) return;
    final next = target.clamp(0, letters.length - 1);
    final letter = letters[next];
    if (letter == widget.currentLetter) return;
    _letterTick();
    widget.onJump(_helper.indexForLetter(letter) ?? 0);
    if (!prefersReducedMotion(context)) _phase += (next - letters.indexOf(widget.currentLetter)) * 0.24;
    setState(
      () => _gearTop = _helper.fractionForLetter(letter) * (_railHeight - _gearHeight).clamp(0.0, double.infinity),
    );
    _show(autoHide: !_focused);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
      _step(1);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.home) {
      _stepTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _stepTo(_helper.letters.length - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String? _neighbour(int by) {
    final letters = _helper.letters;
    final i = letters.indexOf(widget.currentLetter) + by;
    return i >= 0 && i < letters.length ? letters[i] : null;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = prefersReducedMotion(context);
    final fade = reduced ? Duration.zero : _fade;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final visible = _active || _focused;
    final next = _neighbour(1);
    final previous = _neighbour(-1);

    return Semantics(
      slider: true,
      label: t.libraries.alphabetScrubber,
      value: widget.currentLetter,
      increasedValue: next,
      decreasedValue: previous,
      onIncrease: next == null ? null : () => _step(1),
      onDecrease: previous == null ? null : () => _step(-1),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) {
            _show(autoHide: false);
          } else {
            _scheduleHide();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            _railHeight = constraints.maxHeight;
            final gearTop = _gearTop ?? _clampGearTop(_railHeight / 2);
            return SizedBox(
              width: _railWidth,
              height: _railHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('alpha_scroll_rail'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onTapDown: (d) {
                        setState(() => _gearTop = _clampGearTop(d.localPosition.dy));
                        _show();
                      },
                      onVerticalDragStart: _onDragStart,
                      onVerticalDragUpdate: _onDragUpdate,
                      onVerticalDragEnd: (_) => _onDragEnd(),
                      onVerticalDragCancel: _onDragEnd,
                    ),
                  ),
                  // Hint line at rest, so the edge reads as a control.
                  Positioned(
                    right: 2,
                    top: (_railHeight - _hintHeight) / 2,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: visible ? 0 : 1,
                        duration: fade,
                        child: Container(
                          width: 2,
                          height: _hintHeight,
                          decoration: BoxDecoration(
                            color: dark ? const Color(0x55D3CEC7) : const Color(0x66595550),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: ScrollCrownGear.right,
                    top: gearTop,
                    child: ScrollCrownGear(
                      paintKey: const ValueKey('alpha_scroll_crown'),
                      phase: _phase,
                      visible: visible,
                      focused: _focused,
                      fade: fade,
                    ),
                  ),
                  Positioned(
                    right: _bubbleRight,
                    top: gearTop + 14,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: visible && widget.currentLetter.isNotEmpty ? 1 : 0,
                        duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
                        child: AnimatedSlide(
                          offset: visible ? Offset.zero : const Offset(8 / _bubbleSize, 0),
                          duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
                          child: Container(
                            key: const ValueKey('alpha_scroll_bubble'),
                            width: _bubbleSize,
                            height: _bubbleSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDFDDD8),
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: const [
                                BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 3)),
                              ],
                            ),
                            child: Text(
                              widget.currentLetter,
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
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
