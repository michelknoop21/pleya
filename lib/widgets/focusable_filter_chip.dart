import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import 'focus_builders.dart';

/// A focusable filter chip that shows a color change when focused.
///
/// Unlike FocusableWrapper which uses scale + border, this widget
/// uses a background color change to indicate focus state.
class FocusableFilterChip extends StatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onPressed;

  /// When true, renders an accent-tinted "active" state (used for toggle
  /// filters like type/genre). Focus styling always takes precedence.
  final bool selected;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Called when the user presses DOWN from this chip.
  final VoidCallback? onNavigateDown;

  /// Called when the user presses UP from this chip.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses LEFT from this chip.
  final VoidCallback? onNavigateLeft;

  /// Called when the user presses RIGHT from this chip.
  final VoidCallback? onNavigateRight;

  /// Called when the user presses BACK from this chip.
  final VoidCallback? onBack;

  const FocusableFilterChip({
    super.key,
    this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.focusNode,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  @override
  State<FocusableFilterChip> createState() => _FocusableFilterChipState();
}

class _FocusableFilterChipState extends State<FocusableFilterChip> with FocusableChipStateMixin<FocusableFilterChip> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  String get debugLabel => 'filter_chip_${widget.label}';

  @override
  void initState() {
    super.initState();
    initFocusNode();
  }

  @override
  void didUpdateWidget(FocusableFilterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateFocusNode(oldWidget.focusNode);
  }

  @override
  void dispose() {
    disposeFocusNode();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    return handleChipKeyEvent(
      node,
      event,
      ChipKeyCallbacks(
        onSelect: widget.onPressed,
        onNavigateDown: widget.onNavigateDown,
        onNavigateUp: widget.onNavigateUp,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onBack: widget.onBack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);

    // Focus wins; otherwise an accent tint marks the selected/active state and
    // the neutral surface is the resting state.
    final Color backgroundColor;
    final Color foregroundColor;
    if (showFocus) {
      backgroundColor = colorScheme.primary;
      foregroundColor = colorScheme.onPrimary;
    } else if (widget.selected) {
      backgroundColor = colorScheme.primary.withValues(alpha: 0.16);
      foregroundColor = colorScheme.primary;
    } else {
      backgroundColor = colorScheme.surfaceContainerHighest;
      foregroundColor = colorScheme.onSurfaceVariant;
    }

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      backgroundColor: backgroundColor,
      child: Row(
        mainAxisSize: .min,
        children: [
          if (icon != null) ...[AppIcon(icon, fill: 1, size: 16, color: foregroundColor), const SizedBox(width: 6)],
          Text(widget.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foregroundColor)),
        ],
      ),
    );
  }

  IconData? get icon => widget.icon;
}
