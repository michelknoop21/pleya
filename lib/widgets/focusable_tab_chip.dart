import 'package:flutter/material.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import '../theme/mono_tokens.dart';
import 'focus_builders.dart';

/// How a [FocusableTabChip] draws itself.
enum TabChipStyle {
  /// Plain text with a rule under the active label. For section navigation
  /// (library tabs, Live TV tabs) where the row should read as a heading
  /// rather than a strip of buttons.
  underline,

  /// Filled pill, meant to sit inside a [SegmentedTabGroup]. For sets that
  /// behave like a filter or a picker: request states, season posters.
  segmented,
}

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

  /// Visual treatment. See [TabChipStyle].
  final TabChipStyle style;

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
    this.style = TabChipStyle.underline,
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
  /// Height of the accent bar under the open tab.
  static const double _indicatorHeight = 2;

  /// Clearance between that bar and the bottom edge of the tab. In a header the
  /// hairline sits on that edge, and the two must never share a row of pixels.
  static const double _indicatorGap = 5;

  /// Clearance between the label and the bar above it. Small on purpose: the
  /// bar belongs to the word, the gap below it belongs to the header.
  static const double _labelGap = 3;

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
    final useUnderline = widget.style == TabChipStyle.underline && widget.topImage == null;
    return useUnderline ? _buildUnderline(context, showFocus) : _buildSegmented(context, showFocus);
  }

  /// Text tab: no fill, no border, no box. Two states, two separate signals.
  ///
  /// The accent bar marks the open tab. It is as wide as the label, and it
  /// stops [_indicatorGap] short of the bottom edge, because in a header the
  /// bottom edge is exactly where the hairline runs and a bar touching that
  /// line makes the two read as one thick rule under the label.
  ///
  /// Focus never draws a line of its own. It brightens the label and lifts it
  /// a few percent, which paints rather than lays out, so the neighbouring
  /// tabs stay where they are.
  Widget _buildUnderline(BuildContext context, bool showFocus) {
    final tk = tokens(context);

    final label = Text(
      widget.label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: showFocus || widget.isSelected ? tk.text : tk.textMuted,
        // Weight tracks selection only. Bolding on focus as well would resize
        // the label under the cursor and nudge its neighbours.
        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
        letterSpacing: 0.1,
      ),
    );

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onSelect,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      borderRadius: 8,
      // Anchored to the bottom, not centred: centring would let the distance
      // between the label and its bar drift with the height of the row.
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Also the child that sizes the stack, so the bar below ends up
          // exactly as wide as the label.
          Padding(
            padding: const EdgeInsets.only(bottom: _indicatorGap + _indicatorHeight + _labelGap),
            child: AnimatedScale(duration: reduceMotion(context, tk.fast), scale: showFocus ? 1.05 : 1.0, child: label),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _indicatorGap,
            child: AnimatedContainer(
              duration: reduceMotion(context, tk.fast),
              height: _indicatorHeight,
              color: widget.isSelected ? tk.accent : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmented(BuildContext context, bool showFocus) {
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
