import 'package:flutter/material.dart';

import '../theme/mono_shapes.dart';
import 'focus_theme.dart';
import 'focusable_wrapper.dart';
import 'input_mode_tracker.dart';

class FocusableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Navigation callbacks for explicit focus control (e.g. horizontal button rows).
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onBack;

  /// Whether to scroll the widget into view when focused.
  final bool autoScroll;

  /// What the focus indicator does: draws a ring (default), draws a
  /// background fill, or is delegated to the child.
  final FocusIndicatorMode mode;

  /// The shape the focus indicator follows. Defaults to the CTA contract
  /// ([MonoShapes.cta]) because a [FocusableButton]'s child is usually a
  /// Material text button. Set explicitly for a child with its own shape
  /// (round icon, card).
  final OutlinedBorder shape;

  /// Whether an unfocused button recedes to 60% in D-pad mode.
  ///
  /// On by default, and right for almost everything: a wall of cards or a
  /// column of settings rows reads better when the one under the remote is the
  /// bright one. It is wrong for a control whose *resting* colour is part of a
  /// binding design — the TV Home's `Afspelen` capsule is specified white
  /// (hoofdstuk 33.1), and multiplying it by 0.6 renders it grey until it is
  /// focused, which is a state the north star never shows. Such a control
  /// already draws its own focus ([FocusIndicatorMode.delegated]) and can opt
  /// out of the dim as well.
  final bool dimWhenUnfocused;

  const FocusableButton({
    super.key,
    required this.child,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
    this.autoScroll = true,
    this.mode = FocusIndicatorMode.ring,
    this.shape = MonoShapes.cta,
    this.dimWhenUnfocused = true,
  });

  @override
  State<FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<FocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isKeyboard = InputModeTracker.isKeyboardMode(context);
    final showFocus = _isFocused && isKeyboard;
    final duration = FocusTheme.getAnimationDuration(context);
    // In dpad mode: focused = full opacity, unfocused = dimmed
    final opacity = widget.dimWhenUnfocused && isKeyboard && !_isFocused ? 0.6 : 1.0;
    // Always the same two wrappers, so the child keeps its place in the tree
    // when the dim comes and goes; only their data changes.
    final dimmed = opacity < 1;
    final outlined = OutlinedButtonTheme.of(context);
    final text = TextButtonTheme.of(context);
    final ink = _RestingInk(Theme.of(context).colorScheme.onSurface);

    return FocusableWrapper(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      disableScale: true,
      mode: widget.mode,
      focusShapeBorder: widget.shape,
      descendantsAreFocusable: false,
      onFocusChange: (f) => setState(() => _isFocused = f),
      autoScroll: widget.autoScroll,
      onSelect: widget.onPressed,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onBack: widget.onBack,
      child: AnimatedOpacity(
        opacity: showFocus ? 1.0 : opacity,
        duration: duration,
        child: OutlinedButtonTheme(
          data: dimmed ? OutlinedButtonThemeData(style: _resting(outlined.style, ink)) : outlined,
          child: TextButtonTheme(
            data: dimmed ? TextButtonThemeData(style: _resting(text.style, ink)) : text,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The label colour a dimmed, unfocused button paints with.
///
/// An outlined or text button without a colour of its own takes Material's
/// default label colour, `colorScheme.primary`, which here is the brand red.
/// That red reaches 4.4:1 on black at full strength and about 2:1 once the
/// resting dim above multiplies it by 0.6. At rest the label therefore uses
/// the text colour; the focused button keeps what it had. A button that sets
/// its own `foregroundColor` (an error action) still wins over this.
///
/// Only the two button themes are replaced, never the whole [Theme]: a
/// `Theme` widget also resets the inherited `IconTheme` and `CupertinoTheme`
/// for everything below it, in every input mode.
///
/// It compares by value, so the button theme of one build equals that of the
/// next and nothing below rebuilds for it.
class _RestingInk extends WidgetStateProperty<Color?> {
  _RestingInk(this.color);

  final Color color;

  @override
  Color? resolve(Set<WidgetState> states) => states.contains(WidgetState.disabled) ? null : color;

  @override
  bool operator ==(Object other) => other is _RestingInk && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

ButtonStyle _resting(ButtonStyle? style, _RestingInk ink) =>
    (style ?? const ButtonStyle()).copyWith(foregroundColor: ink);
