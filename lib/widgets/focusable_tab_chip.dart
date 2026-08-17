import 'package:flutter/material.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import '../theme/mono_tokens.dart';
import 'focus_builders.dart';

/// A focusable tab chip that shows a color change when focused or selected.
///
/// Used for tab navigation in LibrariesScreen. Handles:
/// - SELECT key to activate the tab
/// - LEFT/RIGHT arrows to switch between tabs
/// - DOWN arrow to navigate to tab content
/// - BACK key to navigate to sidenav
class FocusableTabChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Called when the user presses LEFT from this chip.
  /// Should switch to the previous tab.
  final VoidCallback? onNavigateLeft;

  /// Called when the user presses RIGHT from this chip.
  /// Should switch to the next tab.
  final VoidCallback? onNavigateRight;

  /// Called when the user presses DOWN from this chip.
  final VoidCallback? onNavigateDown;

  /// Called when the user presses UP from this chip.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses BACK from this chip.
  final VoidCallback? onBack;

  /// Called when SELECT key is held (D-pad long press).
  final VoidCallback? onLongPress;

  /// Optional image to show above the label (e.g. a poster).
  /// When provided, the chip lays out vertically with image on top, label below.
  final Widget? topImage;

  const FocusableTabChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelect,
    this.focusNode,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onBack,
    this.onLongPress,
    this.topImage,
  });

  @override
  State<FocusableTabChip> createState() => _FocusableTabChipState();
}

class _FocusableTabChipState extends State<FocusableTabChip> with FocusableChipStateMixin<FocusableTabChip> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  String get debugLabel => 'tab_chip_${widget.label}';

  @override
  void initState() {
    super.initState();
    initFocusNode();
  }

  @override
  void didUpdateWidget(FocusableTabChip oldWidget) {
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
        onSelect: widget.onSelect,
        onLongPress: widget.onLongPress,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onNavigateDown: widget.onNavigateDown,
        onNavigateUp: widget.onNavigateUp,
        onBack: widget.onBack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);

    // Segmented-control look: the group draws the surface, a tab only marks
    // itself. Selected sits one step lighter with an accent underline; the rest
    // stays transparent so the row reads as one control instead of four buttons.
    final tk = tokens(context);
    final Color backgroundColor;
    final Color foregroundColor;
    Color? borderColor;

    if (widget.isSelected) {
      backgroundColor = tk.surfaceElevated;
      foregroundColor = tk.text;
      borderColor = tk.outline.withValues(alpha: 0.9);
    } else if (showFocus) {
      backgroundColor = tk.surfaceElevated.withValues(alpha: 0.6);
      foregroundColor = tk.text;
      borderColor = tk.text.withValues(alpha: 0.55);
    } else {
      backgroundColor = Colors.transparent;
      foregroundColor = tk.textMuted;
    }
    if (showFocus) borderColor = tk.text.withValues(alpha: 0.75);

    final isHighlighted = showFocus || widget.isSelected;

    final label = Text(
      widget.label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: foregroundColor,
        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
      ),
    );

    // Underline keeps the brand accent in play without a filled red slab, and
    // the zero-width twin keeps every tab the same height.
    final underline = AnimatedContainer(
      duration: reduceMotion(context, tk.fast),
      margin: const EdgeInsets.only(top: 5),
      height: 2,
      width: widget.isSelected ? 18 : 0,
      decoration: BoxDecoration(color: tk.accent, borderRadius: BorderRadius.circular(2)),
    );

    final hasImage = widget.topImage != null;
    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onSelect,
      padding: hasImage ? const EdgeInsets.all(8) : const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 5),
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderRadius: hasImage ? 12 : 10,
      child: hasImage
          ? Column(
              mainAxisSize: .min,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: widget.topImage!),
                const SizedBox(height: 6),
                label,
              ],
            )
          : Column(mainAxisSize: MainAxisSize.min, children: [label, underline]),
    );
  }
}
