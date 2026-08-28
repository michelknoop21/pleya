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
    final opacity = isKeyboard && !_isFocused ? 0.6 : 1.0;

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
      child: AnimatedOpacity(opacity: showFocus ? 1.0 : opacity, duration: duration, child: widget.child),
    );
  }
}
