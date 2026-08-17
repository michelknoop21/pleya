import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import 'focus_builders.dart';
import '../theme/mono_tokens.dart';

/// How a [FocusableFilterChip] draws itself.
enum FilterChipVariant {
  /// Outlined pill with an icon. For chip rows that stand on their own, like
  /// the search filters.
  outlined,

  /// Muted label plus its current value in full colour, no outline. For a
  /// header line where the chips have to sit beside a page title without
  /// turning it into a toolbar.
  text,
}

/// A focusable filter chip that shows a color change when focused.
///
/// Unlike FocusableWrapper which uses scale + border, this widget
/// uses a background color change to indicate focus state.
class FocusableFilterChip extends StatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onPressed;

  /// Visual treatment. See [FilterChipVariant].
  final FilterChipVariant variant;

  /// Current value, shown after [label] in the [FilterChipVariant.text]
  /// variant ("Sort · Title"). Ignored by the outlined variant, which folds
  /// the value into [label].
  final String? value;

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
    this.variant = FilterChipVariant.outlined,
    this.value,
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
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);
    if (widget.variant == FilterChipVariant.text) return _buildText(context, showFocus);

    // Outlined instead of filled: these sit next to the segmented tab control,
    // and two competing filled shapes made the header look like a toolbar of
    // grey slabs. Active state keeps a soft accent tint so it still reads.
    final tk = tokens(context);
    final Color backgroundColor;
    final Color foregroundColor;
    final Color borderColor;
    if (showFocus) {
      backgroundColor = tk.surfaceElevated;
      foregroundColor = tk.text;
      borderColor = tk.text.withValues(alpha: 0.75);
    } else if (widget.selected) {
      backgroundColor = tk.accent.withValues(alpha: 0.14);
      foregroundColor = tk.accent;
      borderColor = tk.accent.withValues(alpha: 0.55);
    } else {
      backgroundColor = Colors.transparent;
      foregroundColor = tk.textMuted;
      borderColor = tk.outline.withValues(alpha: 0.8);
    }

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      borderRadius: 10,
      borderColor: borderColor,
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

  /// Label in muted ink, current value in full ink, and nothing drawn around it.
  /// Focus lifts and brightens the text rather than adding a surface or a rule:
  /// this variant shares its line with the tab labels and their accent bar, and
  /// a second marker there would compete with the one that says which tab is
  /// open.
  Widget _buildText(BuildContext context, bool showFocus) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final labelColor = showFocus ? tk.text : tk.textMuted;
    final valueColor = widget.selected ? tk.accent : tk.text;

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: 8,
      backgroundColor: Colors.transparent,
      child: AnimatedScale(
        duration: reduceMotion(context, tk.fast),
        scale: showFocus ? 1.05 : 1.0,
        child: Row(
          mainAxisSize: .min,
          children: [
            Text(widget.label, style: theme.textTheme.labelMedium?.copyWith(color: labelColor)),
            if (widget.value != null) ...[
              const SizedBox(width: 6),
              Text(
                widget.value!,
                style: theme.textTheme.labelMedium?.copyWith(color: valueColor, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
